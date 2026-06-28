-- mvfs/host/host-composefs.lua — the composefs/overlay DEPLOYMENT backend (spec/08
-- §1, §9). The REUSE half of P-D0: it runs ONLY on a real Linux kernel with
-- composefs (mkcomposefs/composefs-info), EROFS, overlayfs, and privileged mounts
-- (CAP_SYS_ADMIN). It is NOT exercised in CI (the sandbox lacks these); the portable
-- model lives in src/dx.shen (git + plain dirs).
--
-- Why this file exists: capturing a REAL overlayfs upper is the actual engineering
-- the design doc glossed (panel doc 42 / Torvalds). An overlay upper is NOT a plain
-- file tree — it carries:
--   * char-device whiteouts (rdev 0,0) marking DELETIONS,
--   * opaque-dir markers (xattr trusted.overlay.opaque="y"),
--   * redirect xattrs (trusted.overlay.redirect) for renames,
--   * metadata copy-ups.
-- Plain-file capture (src/vfs.shen checkout!/switch!) would silently lose deletions.
-- This backend translates kernel overlay semantics into the same content-addressed
-- {set,del,opaque,redirect} delta the checkpoint kernel lands, so checkpoint! /
-- restore-checkpoint! / the fenced log are unchanged across backends.
--
-- Reuses host.lua's git CAS verbs (git hash-object -w / cat-file) for content blobs.
local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]+$")) or "."
local function load_host()
  if _G.mvfs then return _G.mvfs end
  for _, p in ipairs({ os.getenv("MVFS_HOST"), "host/host.lua", here .. "/host.lua" }) do
    if p then local f = io.open(p, "r"); if f then f:close(); dofile(p); return _G.mvfs end end
  end
  error("host-composefs: cannot locate host/host.lua")
end
local mvfs = load_host()
local C = {}
_G.mvfs_cfs = C

local function sh(cmd) local out, rc = mvfs.shell_run("sh", { "-c", cmd }); return out, rc end
local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

-- composefs-build!: materialize a tree to a staging dir, then mkcomposefs into a
-- content-addressed EROFS image whose digest is the base identity (fs-verity).
-- (Caller materializes the tree via dx/vfs first; here we assume STAGE holds it.)
function C.build(tree, stage)
  -- digest stability requires normalized metadata (panel: determinism is a discipline)
  sh("find " .. q(stage) .. " -exec touch -h -d @0 {} + 2>/dev/null")
  local img = stage .. ".cfs"
  local _, rc = sh("mkcomposefs --digest-store=objects " .. q(stage) .. " " .. q(img))
  if rc ~= 0 then error("mkcomposefs failed") end
  return (mvfs.shell_run("composefs-info", { "--digest", img }):gsub("%s+$", ""))
end

-- overlay-mount!: mount the EROFS base read-only, put a writable overlay upper on
-- top, return the merged mountpoint. In-kernel; no FUSE in the I/O path.
function C.mount(image_path, workdir)
  sh("mkdir -p " .. q(workdir) .. "/{base,upper,work,merged}")
  if select(2, sh("mount -t erofs -o ro,loop " .. q(image_path) .. " " .. q(workdir) .. "/base")) ~= 0 then
    error("erofs mount failed (need CAP_SYS_ADMIN)")
  end
  local m = ("mount -t overlay overlay -o lowerdir=%s/base,upperdir=%s/upper,workdir=%s/work %s/merged")
    :format(workdir, workdir, workdir, workdir)
  if select(2, sh(m)) ~= 0 then error("overlay mount failed") end
  return workdir .. "/merged"
end

-- overlay-capture!: walk the REAL overlay UPPER and emit the content-addressed delta.
-- This is the load-bearing translation of kernel overlay semantics -> delta nodes.
function C.capture(upperdir, _base)
  local rows = {}
  -- 1. regular files -> set nodes (content stored via git hash-object -w = durable CAS)
  local files = mvfs.shell_run("find", { upperdir, "-type", "f", "-printf", "%P\n" })
  for p in (files .. "\n"):gmatch("(.-)\n") do
    if #p > 0 then
      local h = (mvfs.shell_run("git", { "hash-object", "-w", upperdir .. "/" .. p }):gsub("%s+$", ""))
      rows[#rows + 1] = { "set", p, h }
    end
  end
  -- 2. char-device whiteouts (rdev 0,0) -> del nodes (THE deletion case)
  local whites = mvfs.shell_run("find", { upperdir, "-type", "c", "-printf", "%P %t\n" })
  for line in (whites .. "\n"):gmatch("(.-)\n") do
    local p = line:match("^(%S+)")
    if p then
      -- confirm it is a 0/0 whiteout, not a real device node
      local maj = mvfs.shell_run("stat", { "-c", "%Hr", upperdir .. "/" .. p }):gsub("%s+$", "")
      local min = mvfs.shell_run("stat", { "-c", "%Lr", upperdir .. "/" .. p }):gsub("%s+$", "")
      if maj == "0" and min == "0" then rows[#rows + 1] = { "del", p, "" } end
    end
  end
  -- 3. opaque dirs (xattr trusted.overlay.opaque="y") and 4. redirect xattrs
  local dirs = mvfs.shell_run("find", { upperdir, "-type", "d", "-printf", "%P\n" })
  for d in (dirs .. "\n"):gmatch("(.-)\n") do
    if #d > 0 then
      local op = mvfs.shell_run("sh", { "-c",
        "getfattr -n trusted.overlay.opaque --only-values " .. q(upperdir .. "/" .. d) .. " 2>/dev/null" })
      if op == "y" then rows[#rows + 1] = { "opaque", d, "" } end
      local rd = mvfs.shell_run("sh", { "-c",
        "getfattr -n trusted.overlay.redirect --only-values " .. q(upperdir .. "/" .. d) .. " 2>/dev/null" })
      if rd ~= "" then rows[#rows + 1] = { "redirect", d, rd } end
    end
  end
  return rows  -- same {kind,path,hash} shape dx.shen lands; superset kinds for overlay
end

-- overlay-apply!: reconstruct an overlay upper from a delta. set -> write file;
-- del -> mknod a 0/0 char-device whiteout; opaque/redirect -> set the xattr.
function C.apply(delta, upperdir)
  for _, r in ipairs(delta) do
    local kind, p, h = r[1], r[2], r[3]
    local dst = upperdir .. "/" .. p
    sh("mkdir -p " .. q(dst:match("^(.*)/[^/]+$") or upperdir))
    if kind == "set" then
      sh("git cat-file blob " .. q(h) .. " > " .. q(dst))
    elseif kind == "del" then
      sh("mknod " .. q(dst) .. " c 0 0")                       -- kernel overlay whiteout
    elseif kind == "opaque" then
      sh("setfattr -n trusted.overlay.opaque -v y " .. q(dst))
    elseif kind == "redirect" then
      sh("setfattr -n trusted.overlay.redirect -v " .. q(h) .. " " .. q(dst))
    end
  end
  return true
end

return C
