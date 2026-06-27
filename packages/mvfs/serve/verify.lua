-- serve/verify.lua — the EDGE serve-token verifier (spec/04 §B.6.2).
-- In production this runs in `access_by_lua` on the INTERNAL /cas location,
-- BEFORE sendfile, and fails closed. It mirrors the Shen `verify-token` contract
-- byte-for-byte (same wire token: b64url(msg) "." HMAC-SHA256-hex(key,msg), where
-- msg = US-join(hash, principal, acl-version, expiry, nonce)), so a token minted
-- by the shen-lua brain verifies here unchanged (proven by test/read-edge.sh).
-- Reuses the audited host primitives (FFI HMAC, constant-time compare, nonce store).
-- Locate host/host.lua robustly (works whether verify.lua is the main script,
-- dofile'd, or `require`d): try $MVFS_HOST, then cwd, then arg[0]-relative.
local function load_host()
  if _G.mvfs then return _G.mvfs end
  local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]+$")) or "."
  local cands = {}
  if os.getenv("MVFS_HOST") then cands[#cands + 1] = os.getenv("MVFS_HOST") end
  cands[#cands + 1] = "host/host.lua"
  cands[#cands + 1] = here .. "/../host/host.lua"
  for _, p in ipairs(cands) do
    local f = io.open(p, "r"); if f then f:close(); dofile(p); return _G.mvfs end
  end
  error("verify.lua: cannot locate host/host.lua (set MVFS_HOST)")
end
local mvfs = load_host()
local US = string.char(31)

local V = {}

-- Returns true (allow sendfile) or false (deny -> 403, fail closed). Never throws
-- on a malformed token; never reveals WHY it failed (uniform deny at the edge).
function V.verify(key, token, expected_hash, principal, required_acl, store)
  if type(token) ~= "string" then return false end
  local dot = token:find(".", 1, true)
  if not dot then return false end
  local msg = mvfs.unb64url(token:sub(1, dot - 1))
  local tag = token:sub(dot + 1)
  -- 1. integrity: constant-time MAC check (forged/tampered -> deny)
  if not mvfs.consttime_eq(tag, mvfs.hmac_sha256(key, msg)) then return false end
  local f = mvfs.split(US, msg)              -- {hash, principal, acl-version, expiry, nonce}
  if #f < 5 then return false end
  -- 2. token is for THIS hash, bound to THIS principal
  if f[1] ~= expected_hash then return false end
  if f[2] ~= principal then return false end
  -- 3. minted at acl-version >= currently required (no stale-policy allow, I6)
  if (tonumber(f[3]) or -1) < required_acl then return false end
  -- 4. not expired
  if mvfs.now_secs() > (tonumber(f[4]) or 0) then return false end
  -- 5. single-use nonce (I9): replay -> deny
  if mvfs.nonce_seen(store, f[5]) then return false end
  mvfs.nonce_record(store, f[5])
  return true
end

return V
