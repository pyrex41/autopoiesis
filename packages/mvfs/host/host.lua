-- mvfs/host/host.lua — the REAL host backend for the mvfs boundary (spec/00 §5.4).
-- Loaded by src/host-lua.shen via (lua.call "dofile" ["host/host.lua"]), then the
-- boundary's erroring host stubs are redefined to delegate here. Implements the
-- ONLY side-effecting primitives: shell-out to git/pijul, the durable fenced log,
-- checksums, and the structural pijul conflict probe. Pure Lua/LuaJIT.
--
-- Notes:
--  * crc64/xor64 use a 32-bit CRC normalized to [0,2^32) so values round-trip
--    exactly through Shen numbers (doubles, <2^53). The chain invariant only
--    needs determinism; a production host uses true CRC-64 via FFI. Documented.
--  * shell errors only on exit code > 1: git uses rc=1 for "differences/conflict"
--    (merge-tree), which must NOT raise; rc>1 is a real failure.
--  * durable append: flush+close (durable to the OS) + best-effort FFI fsync.

local M = {}
_G.mvfs = M

local US = string.char(31)   -- \x1f field separator
local RS = string.char(30)   -- \x1e record terminator

-- ---- best-effort fsync via FFI (LuaJIT) ------------------------------------
local fsync_fd
do
  local ok, ffi = pcall(require, "ffi")
  if ok then
    pcall(ffi.cdef, "int open(const char*, int); int close(int); int fsync(int);")
    fsync_fd = function(path)
      local fd = ffi.C.open(path, 2)        -- O_RDWR
      if fd >= 0 then ffi.C.fsync(fd); ffi.C.close(fd) end
    end
  else
    fsync_fd = function(_) end
  end
end

local function read_file(path)
  local f = io.open(path, "rb"); if not f then return nil end
  local c = f:read("*a"); f:close(); return c
end

-- ---- shell ----------------------------------------------------------------
local function shquote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function run(cmdline)
  -- returns stdout(string), rc(number). rc parsed from a sentinel so it works
  -- regardless of io.popen:close() semantics across Lua versions.
  local p = assert(io.popen(cmdline .. "; printf '" .. RS .. "RC:%d' \"$?\"", "r"))
  local out = p:read("*a") or ""
  p:close()
  local body, rc = out:match("^(.*)" .. RS .. "RC:(%d+)$")
  if rc == nil then return out, 0 end
  return body, tonumber(rc)
end

function M.shell_run(cmd, args)
  local parts = { shquote(cmd) }
  for _, a in ipairs(args or {}) do parts[#parts + 1] = shquote(a) end
  local out, rc = run(table.concat(parts, " ") .. " 2>/dev/null")
  if rc > 1 then error("mvfs shell-run: `" .. cmd .. "` exited " .. rc) end
  return out
end

function M.shell_run_stdin(cmd, args, stdin)
  local tmp = os.tmpname()
  local f = assert(io.open(tmp, "wb")); f:write(stdin or ""); f:close()
  local parts = { shquote(cmd) }
  for _, a in ipairs(args or {}) do parts[#parts + 1] = shquote(a) end
  local out, rc = run(table.concat(parts, " ") .. " < " .. shquote(tmp) .. " 2>/dev/null")
  os.remove(tmp)
  if rc > 1 then error("mvfs shell-run-stdin: `" .. cmd .. "` exited " .. rc) end
  return out
end

-- ---- checksums ------------------------------------------------------------
local bit = require("bit")
local crc_table
local function build_crc_table()
  crc_table = {}
  for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
      if bit.band(c, 1) == 1 then c = bit.bxor(0xEDB88320, bit.rshift(c, 1))
      else c = bit.rshift(c, 1) end
    end
    crc_table[i] = c
  end
end
build_crc_table()

function M.crc64(s)
  local c = 0xFFFFFFFF
  for i = 1, #s do
    c = bit.bxor(bit.rshift(c, 8), crc_table[bit.band(bit.bxor(c, s:byte(i)), 0xFF)])
  end
  c = bit.bxor(c, 0xFFFFFFFF)
  return c % 4294967296          -- normalize to [0, 2^32) — exact as a double
end

function M.xor64(a, b)
  return bit.bxor(a, b) % 4294967296
end

-- ---- string helpers -------------------------------------------------------
function M.strlen(s) return #s end
function M.substr(s, a, b) return s:sub(a + 1, b) end      -- [a, b) 0-indexed
function M.has_substr(hay, needle) return hay:find(needle, 1, true) ~= nil end
function M.first_line(s) return (s:match("^[^\n]*")) or "" end
function M.after_tag(tag, s)
  local i = s:find(tag, 1, true)
  if not i then return "" end
  local rest = s:sub(i + #tag)
  return (rest:match("^[^\n]*")) or ""
end
function M.str_to_num(s) return tonumber(s) or 0 end

function M.split(sep, s)
  local out = {}
  if s == "" then return out end
  for part in (s .. sep):gmatch("(.-)" .. sep:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")) do
    out[#out + 1] = part
  end
  return out
end

-- monotone lease epoch: read counter file, default 1 (the test bumps it to
-- simulate a new leader; release is a no-op).
function M.acquire_epoch(lease)
  local c = read_file(lease .. ".epoch")
  return tonumber(c) or 1
end

-- ---- durable fenced log ---------------------------------------------------
local function records(path)
  local c = read_file(path); if not c or c == "" then return {} end
  local recs = {}
  for rec in (c .. RS):gmatch("(.-)" .. RS) do
    if #rec > 0 then recs[#recs + 1] = rec end
  end
  return recs
end

function M.log_records(path) return records(path) end

function M.log_head(path)
  local r = records(path)
  return r[#r] or ""
end

-- the fence cell of the head record (cell index 10, 1-based; "" log => 0)
local function head_fence(path)
  local h = M.log_head(path)
  if h == "" then return 0 end
  local cells = {}
  for cell in (h .. US):gmatch("(.-)" .. US) do cells[#cells + 1] = cell end
  return tonumber(cells[10]) or 0
end

-- atomic-ish CAS append: succeed iff the on-disk head fence == expected AND
-- new >= expected; then append the (already RS-terminated) framed bytes durably.
-- Single-writer model: the re-read is the linearization check (post-fsync lease
-- re-check is the leader's job above this).
function M.cas_append(path, expected_fence, new_fence, framed)
  if new_fence < expected_fence then return false end
  if head_fence(path) ~= expected_fence then return false end
  local f = assert(io.open(path, "ab"))
  f:write(framed); f:flush(); f:close()
  fsync_fd(path)
  return true
end

-- ---- pijul structural conflict probe (Aphyr MF-2) -------------------------
-- A channel is conflicted iff its pristine carries any conflict class. We ask
-- PIJUL ITSELF: `pijul archive` of a conflicted channel reports, on stderr,
-- "There were conflicts: - <class> conflict in ..." — pijul's own structural
-- conflict detector naming the class (order/zombie/...). This is NOT a
-- working-copy marker grep and does NOT touch the working copy. The archive
-- output file is discarded. Isolated here so the Shen contract stays a clean
-- boolean.
function M.pijul_conflicted(channel)
  local tmp = os.tmpname()
  local p = assert(io.popen(
    "pijul archive --channel " .. shquote(channel) .. " -o " .. shquote(tmp) .. " 2>&1", "r"))
  local out = p:read("*a") or ""
  p:close()
  os.remove(tmp); os.remove(tmp .. ".gz"); os.remove(tmp .. ".tar.gz")
  return out:find("There were conflicts", 1, true) ~= nil
end

-- the order-independent trunk state/version hash of a channel (the "State: ..."
-- line of `pijul log --state`). "" if the channel has no changes.
function M.pijul_state(channel)
  local out = M.shell_run("pijul", { "log", "--channel", channel, "--state", "--limit", "1" })
  return (out:match("State:%s*([A-Z0-9]+)")) or ""
end

-- ---- recovery helpers (Aphyr: log is truth, pristine is a rebuildable cache) --
-- non-base change hashes currently in a channel's pristine (for the orphan sweep).
function M.pijul_trunk_changes(channel, base)
  local out = M.shell_run("pijul", { "log", "--channel", channel, "--hash-only" })
  local hs = {}
  for h in out:gmatch("[A-Z0-9]+") do
    if h ~= base and #h > 40 then hs[#hs + 1] = h end
  end
  return hs
end

return M
