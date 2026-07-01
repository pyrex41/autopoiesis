\* mvfs/host-composefs.shen — binds the composefs/overlay deployment backend
   (spec/08 §9). OPTIONAL: loaded only on a real kernel with composefs + privileged
   mounts; the portable P-D0 lives in dx.shen (git + plain dirs). Overrides the
   boundary's erroring composefs/overlay stubs with calls into host-composefs.lua.
   Loaded under tc- after the core, from packages/mvfs. *\
(package mvfs [lua.call]

(lua.call "dofile" ["host/host.lua"])
(lua.call "dofile" ["host/host-composefs.lua"])

(define composefs-build! { hash --> hash } Tree -> (lua.call "mvfs_cfs.build" [Tree Tree]))
(define overlay-mount! { hash --> string --> string } Img Wd -> (lua.call "mvfs_cfs.mount" [Img Wd]))
(define overlay-capture! { string --> hash --> (list (list string)) } Upper Base -> (lua.call "mvfs_cfs.capture" [Upper Base]))
(define overlay-apply! { (list (list string)) --> string --> boolean } Delta Upper -> (lua.call "mvfs_cfs.apply" [Delta Upper]))
)
