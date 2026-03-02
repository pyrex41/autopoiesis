# GPU Acceleration Interface Contract

## Overview
Future Rust+Metal GPU acceleration for swarm fitness evaluation. This document defines the interface contract; no implementation exists yet.

## Decision Criteria
GPU path should only be activated when ALL of:
- Population size > 1000 genomes
- Per-generation evaluation takes > 10 seconds on lparallel CPU path
- Fitness evaluation is primarily numeric (vector math)

## C ABI Surface
Three functions exposed from the Rust `ap-metabolism` crate:

### `ap_metabolism_init`
```c
void* ap_metabolism_init(uint32_t population_size, uint32_t genome_dim);
```
Initialize Metal compute pipeline. Returns opaque context pointer.

### `ap_reduce_batch`
```c
int32_t ap_reduce_batch(
    void* ctx,
    const uint8_t* genomes_msgpack,  // MessagePack-encoded genome vectors
    uint32_t genomes_len,
    uint8_t* results_out,            // MessagePack-encoded fitness scores
    uint32_t results_cap
);
```
Evaluate fitness for entire population in one GPU dispatch. Returns number of results written, or negative error code.

### `ap_metabolism_free`
```c
void ap_metabolism_free(void* ctx);
```
Release GPU resources.

## Buffer Format
- Input: MessagePack array of float vectors (one per genome)
- Output: MessagePack array of float scores
- MessagePack chosen for: compact binary, schema-free, easy FFI

## CFFI Binding Definitions (Lisp Side)
```lisp
;; Future CFFI definitions (not yet active)
(cffi:defcfun ("ap_metabolism_init" %metabolism-init) :pointer
  (population-size :uint32)
  (genome-dim :uint32))

(cffi:defcfun ("ap_reduce_batch" %reduce-batch) :int32
  (ctx :pointer)
  (genomes :pointer)
  (genomes-len :uint32)
  (results :pointer)
  (results-cap :uint32))

(cffi:defcfun ("ap_metabolism_free" %metabolism-free) :void
  (ctx :pointer))
```

## Rust Crate Structure
```
ap-metabolism/
  Cargo.toml
  src/
    lib.rs          # C ABI exports
    metal.rs        # Metal compute pipeline
    msgpack.rs      # Serialization helpers
    kernels/
      fitness.metal # Metal shader for fitness eval
```

## Integration Path
1. Build `ap-metabolism` as `libap_metabolism.dylib` (macOS) / `.so` (Linux)
2. Add `#:cffi` to autopoiesis.asd `:depends-on`
3. Load library via `(cffi:load-foreign-library "libap_metabolism")`
4. Replace `evaluate-population` GPU path in swarm module

## Fallback Behavior
When GPU is unavailable, `evaluate-fitness-gpu` falls back to `evaluate-population` with `:parallel t` (lparallel CPU path).
