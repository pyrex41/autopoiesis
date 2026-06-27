-- serve/access.lua — the read-tier EDGE handler (spec/04, spec/05; agentzh review
-- docs 27/31). Runs in `access_by_lua_block` on the client-facing /read location.
--
-- THE LOAD-BEARING RULE: bytes never enter the Lua VM. This handler only DECIDES
-- (resolve + authorize + mint token), then hands off to nginx via `ngx.exec` to an
-- INTERNAL /cas location that sendfile()s the blob — kernel zero-copy. The blob
-- hash is derived SERVER-SIDE from the authorized (commit,path); a client-supplied
-- hash is never trusted (a hash is a read capability — agentzh F7).
--
-- This is the deployment artifact (requires OpenResty/mlcache/lua-resty-lock). The
-- DECISION logic it calls is the shen-lua brain (test/read.sh) and the token verify
-- is serve/verify.lua (test/read-edge.sh). Pseudostructured to the real APIs.

local mlcache      = require "resty.mlcache"
local lock         = require "resty.lock"
local brain        = require "mvfs.brain"   -- thin FFI/embedding shim over the shen-lua read-decide

-- Two-level cache (agentzh F2): L1 = per-worker lrucache of LIVE decoded tables
-- (no lock, no serialization, ~tens of ns); L2 = lua_shared_dict (cross-worker,
-- serialized, in shmem NOT the Lua GC heap). Big set lives in L2; L1 element count
-- is capped so the Lua GC heap stays small (F5). Content-addressed keys never go
-- stale -> effectively infinite TTL.
local resolve_cache = assert(mlcache.new("resolve", "mvfs_resolve_dict", {
  lru_size = 50000, ttl = 0, neg_ttl = 5,           -- ttl=0: never expire (immutable per commit)
}))
local acl_cache = assert(mlcache.new("acl", "mvfs_acl_dict", {
  lru_size = 50000, ttl = 30, neg_ttl = 5,          -- short ttl; bumped by acl-version in the key
}))

local SERVE_KEY = os.getenv("MVFS_SERVE_KEY")       -- rotated per operator policy

local function fail_closed()                         -- uniform 403; never leak existence
  return ngx.exit(ngx.HTTP_FORBIDDEN)
end

local function handle()
  -- ---- inputs (commit/seq + path; basis carried by the client, I8) ----
  local args   = ngx.req.get_uri_args()
  local commit = args.commit            -- a landed-log seq / commit, NEVER a raw blob hash
  local path   = args.path
  local req_seq = tonumber(ngx.var.http_x_mvfs_as_of_seq or 0)
  local req_acl = tonumber(ngx.var.http_x_mvfs_as_of_acl or 0)
  local princ   = ngx.ctx.principal     -- set by the upstream auth phase; NEVER a client header
  if not (commit and path and princ) then return fail_closed() end

  -- ---- I8: as-of basis gate. The node's applied basis must be >= the request's.
  -- If behind, block up to T_ryw then redirect to a caught-up peer / fail closed.
  local applied_seq, applied_acl = brain.applied_basis()
  if applied_seq < req_seq or applied_acl < req_acl then
    -- (block <= T_ryw via a short semaphore wait on basis advance, omitted here)
    return ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)   -- or 307 redirect to a peer; never serve stale
  end

  -- ---- §5.2 resolve (commit,path)->blob, cached per immutable commit (F8) ----
  -- single-flight via mlcache's L3 lua-resty-lock so a cold-popular path does not
  -- fan out N origin resolves (agentzh F4).
  local blob = resolve_cache:get(commit .. "\31" .. path, nil, brain.resolve, commit, path)
  if not blob or blob == "" then return fail_closed() end   -- authorize-then-resolve; uniform deny

  -- ---- I9/I6: authorize at the applied acl-version (per-principal, per-version key) ----
  local allow = acl_cache:get(princ .. "\31" .. path .. "\31" .. applied_acl, nil,
                              brain.acl_allow, princ, path, applied_acl)
  if not allow then return fail_closed() end

  -- ---- §5.3 mint the single-use, expiring, per-principal serve token ----
  local token = brain.mint_token(SERVE_KEY, blob, princ, applied_acl)   -- FFI HMAC, off the GC

  -- ---- hand off to nginx: INTERNAL jump, no socket, no byte in Lua ----
  ngx.req.set_header("X-Mvfs-Serve-Token", token)     -- internal-only; stripped at the edge
  ngx.header["X-Mvfs-Applied-Seq"] = applied_seq      -- so the client can advance its HWM (I8)
  ngx.header["X-Mvfs-Applied-Acl"] = applied_acl
  return ngx.exec("/cas/serve", { h = blob })          -- nginx verifies the token then sendfile()s
end

return handle
