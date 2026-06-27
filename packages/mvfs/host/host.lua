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

-- ---- best-effort fsync + self-SIGKILL via FFI (LuaJIT) ---------------------
local fsync_fd, ffi_kill
do
  local ok, ffi = pcall(require, "ffi")
  if ok then
    pcall(ffi.cdef, "int open(const char*, int); int close(int); int fsync(int); int getpid(void); int kill(int,int);")
    fsync_fd = function(path)
      local fd = ffi.C.open(path, 2)        -- O_RDWR
      if fd >= 0 then ffi.C.fsync(fd); ffi.C.close(fd) end
    end
    ffi_kill = function() io.flush(); ffi.C.kill(ffi.C.getpid(), 9) end
  else
    fsync_fd = function(_) end
    ffi_kill = function() os.exit(137) end
  end
end

-- fault-injection seam (T1): SIGKILL self iff env CRASH_AT == name. Inert in
-- production (CRASH_AT unset). pland! calls this at the post-append window.
function M.crash_point(name)
  if os.getenv("CRASH_AT") == name then ffi_kill() end
  return true
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
-- MF-1: are ALL of a candidate's pijul dependencies already in the trunk channel?
-- Parse the "# Dependencies" section of `pijul change <cand>` (lines "[n] <hash>
-- # name") and check each hash is present in `pijul log --channel CH --hash-only`.
-- If a dep is missing, applying the candidate would silently pull un-seq'd
-- changes into the trunk — an I1/I2 violation. Returns true iff all deps present.
function M.pijul_deps_in_trunk(cand, channel)
  local chg = M.shell_run("pijul", { "change", cand })
  local deps = {}
  local in_deps = false
  for line in (chg .. "\n"):gmatch("(.-)\n") do
    if line:find("# Dependencies", 1, true) then in_deps = true
    elseif line:find("# Hunks", 1, true) then in_deps = false
    elseif in_deps then
      local h = line:match("%[%d+%]%s+([A-Z0-9]+)")
      if h then deps[#deps + 1] = h end
    end
  end
  local trunk = M.shell_run("pijul", { "log", "--channel", channel, "--hash-only" })
  for _, d in ipairs(deps) do
    if not trunk:find(d, 1, true) then return false end
  end
  return true
end

-- non-base change hashes currently in a channel's pristine (for the orphan sweep).
function M.pijul_trunk_changes(channel, base)
  local out = M.shell_run("pijul", { "log", "--channel", channel, "--hash-only" })
  local hs = {}
  for h in out:gmatch("[A-Z0-9]+") do
    if h ~= base and #h > 40 then hs[#hs + 1] = h end
  end
  return hs
end

-- ---- fenced blob store (MF-4a): off-pijul byte backup of raw change bodies ---
-- A change body lives in pijul's content-addressed change store at
-- .pijul/changes/<h[0:2]>/<h[2:]>.change. We mirror it into OUR durable store
-- (<logpath>.blobs/<hash>) BEFORE the log append, so the body survives even if
-- pijul's store is lost — the log + this blob store are the durable truth.
local function change_path(hash)
  return ".pijul/changes/" .. hash:sub(1, 2) .. "/" .. hash:sub(3) .. ".change"
end
local function blob_path(hash, logpath) return logpath .. ".blobs/" .. hash end
local function copy_file(src, dst)
  local f = io.open(src, "rb"); if not f then return false end
  local data = f:read("*a"); f:close()
  os.execute("mkdir -p " .. shquote(dst:match("^(.*)/[^/]+$") or "."))
  local g = assert(io.open(dst, "wb")); g:write(data); g:flush(); g:close()
  fsync_fd(dst)
  return true
end

function M.blob_put(hash, logpath)   -- mirror the raw change body into the blob store
  return copy_file(change_path(hash), blob_path(hash, logpath))
end
function M.blob_has(hash, logpath)
  local f = io.open(blob_path(hash, logpath), "rb"); if f then f:close(); return true end
  return false
end
-- faithful-backup check: blob bytes == the live change body.
function M.blob_matches(hash, logpath)
  local a = read_file(blob_path(hash, logpath)); local b = read_file(change_path(hash))
  return a ~= nil and a == b
end
-- best-effort restore of a missing change body from the blob store (recovery).
function M.blob_restore(hash, logpath)
  if io.open(change_path(hash), "rb") then return true end   -- already present
  return copy_file(blob_path(hash, logpath), change_path(hash))
end

-- ---- MF-4c: best-effort fsync of the pijul pristine after a land apply ------
-- pijul beta.15 exposes no fsync-on-commit knob (the `--sync-data` flag belongs
-- to lore, not pijul), and Sanakirja's commit durability is not CLI-controllable.
-- Our correctness does NOT depend on it (the log is truth; recovery re-applies
-- any logged change missing from the pristine). As defense-in-depth we fsync the
-- pristine files at OUR layer after the land-path apply, so a crash is less likely
-- to leave recovery work. Coarse but real.
function M.sync_pristine()
  local p = io.popen("find .pijul/pristine -type f 2>/dev/null", "r")
  if p then
    for path in p:lines() do fsync_fd(path) end
    p:close()
  end
  return true
end

-- ---- MF-5: pin the pijul hash-algo/version in the log's meta sidecar --------
-- The order-independent state hash (entry Root) is in the audit chain and depends
-- on pijul's (pre-1.0) hash construction. We record the producing pijul version
-- in <logpath>.meta at genesis; a different pijul's state hashes would not match,
-- so we refuse to operate on a log written by an incompatible version.
function M.pijul_version()
  return (M.shell_run("pijul", { "--version" }):gsub("%s+$", ""))
end
function M.version_pin(logpath)   -- record current version if not already pinned
  local meta = logpath .. ".meta"
  if not read_file(meta) then
    local f = assert(io.open(meta, "wb")); f:write(M.pijul_version()); f:close()
  end
  return true
end
function M.version_ok(logpath)    -- meta absent (fresh) OR meta == current version
  local pinned = read_file(logpath .. ".meta")
  if not pinned then return true end
  return pinned == M.pijul_version()
end

-- ---- recovery-before-writes gate (MF-4b) ----------------------------------
-- A leader must run recovery before accepting writes. recover! marks the token;
-- pland! refuses to land until it is set. Keyed on the logpath (the land domain).
function M.mark_recovered(logpath)
  local f = assert(io.open(logpath .. ".recovered", "wb")); f:write("1"); f:close(); return true
end
function M.is_recovered(logpath)
  local f = io.open(logpath .. ".recovered", "rb"); if f then f:close(); return true end
  return false
end

-- ---- read tier (spec/04, spec/05) -----------------------------------------
-- §5.2 resolve: (root-tree, path) -> blob hash, via git's tree walk. "" if absent.
function M.resolve_path(root, path)
  local out, rc = run("git rev-parse " .. shquote(root .. ":" .. path) .. " 2>/dev/null")
  if rc ~= 0 then return "" end
  return (out:gsub("%s+$", ""))
end

-- §5.3 HMAC-SHA256 (hex) via libcrypto FFI (agentzh: keep crypto off the Lua GC).
local hmac_sha256
do
  local ok, ffi = pcall(require, "ffi")
  local okc, crypto = pcall(ffi.load, "crypto")
  if ok and okc then
    pcall(ffi.cdef, "unsigned char *HMAC(const void*, const void*, int, const unsigned char*, size_t, unsigned char*, unsigned int*); const void *EVP_sha256(void);")
    local md = ffi.new("unsigned char[32]"); local mlen = ffi.new("unsigned int[1]")
    local hex = ffi.new("char[65]")
    hmac_sha256 = function(key, msg)
      crypto.HMAC(crypto.EVP_sha256(), key, #key, msg, #msg, md, mlen)
      local t = {}
      for i = 0, 31 do t[i + 1] = string.format("%02x", md[i]) end
      return table.concat(t)
    end
  else
    hmac_sha256 = function() error("mvfs: libcrypto (HMAC) unavailable") end
  end
end
M.hmac_sha256 = function(key, msg) return hmac_sha256(key, msg) end

-- base64url (no padding).
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
function M.b64url(s)
  local out, i = {}, 1
  while i <= #s do
    local a, b, c = s:byte(i), s:byte(i + 1), s:byte(i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1 = math.floor(n / 262144) % 64
    local c2 = math.floor(n / 4096) % 64
    local c3 = math.floor(n / 64) % 64
    local c4 = n % 64
    out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
    if b then out[#out + 1] = B64:sub(c3 + 1, c3 + 1) else out[#out + 1] = "" end
    if c then out[#out + 1] = B64:sub(c4 + 1, c4 + 1) else out[#out + 1] = "" end
    i = i + 3
  end
  return table.concat(out)
end
local B64R = {}; for i = 1, #B64 do B64R[B64:byte(i)] = i - 1 end
function M.unb64url(s)
  local out, i = {}, 1
  while i <= #s do
    local c1 = B64R[s:byte(i)] or 0
    local c2 = B64R[s:byte(i + 1)] or 0
    local c3 = B64R[s:byte(i + 2)]
    local c4 = B64R[s:byte(i + 3)]
    local n = c1 * 262144 + c2 * 4096 + (c3 or 0) * 64 + (c4 or 0)
    out[#out + 1] = string.char(math.floor(n / 65536) % 256)
    if c3 then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
    if c4 then out[#out + 1] = string.char(n % 256) end
    i = i + 4
  end
  return table.concat(out)
end

-- constant-time string compare (no early exit; length-independent within equal len).
function M.consttime_eq(a, b)
  if #a ~= #b then return false end
  local diff = 0
  for i = 1, #a do diff = bit.bor(diff, bit.bxor(a:byte(i), b:byte(i))) end
  return diff == 0
end

function M.now_secs() return os.time() end

-- 128-bit random nonce (hex) from /dev/urandom (falls back to time+pid if absent).
function M.random_nonce()
  local f = io.open("/dev/urandom", "rb")
  if f then
    local r = f:read(16); f:close()
    local t = {}; for i = 1, #r do t[i] = string.format("%02x", r:byte(i)) end
    return table.concat(t)
  end
  return string.format("%x%x", os.time(), os.clock() * 1e6)
end

-- single-use nonce store (I9): a directory of touched files, one per seen nonce.
function M.nonce_seen(store, nonce)
  local f = io.open(store .. "/" .. nonce, "rb"); if f then f:close(); return true end
  return false
end
function M.nonce_record(store, nonce)
  os.execute("mkdir -p " .. shquote(store))
  local f = assert(io.open(store .. "/" .. nonce, "wb")); f:write("1"); f:close()
  return true
end

return M
