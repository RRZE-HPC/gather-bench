# gather-bench
A gather instruction performance benchmark for x86-64 (AVX2/AVX-512), ARM
SVE2, and GPUs (CUDA/HIP).

## Directory layout

```
src/
  x86-64/avx2/     hand-written AVX2 gather kernels (.S)
  x86-64/avx512/   hand-written AVX-512 gather kernels (.S)
  sve2/            hand-written ARM SVE2 gather kernels (.S) - UNVERIFIED,
                   no SVE hardware or cross-compiler was available to build
                   or run these; treat with extra scrutiny before relying on
                   the numbers.
  cuda/            GPU (CUDA/HIP) benchmark, see below
  gather_intrinsic.cc   portable C++ intrinsics kernel (KERNEL=intrinsic)
  main.c, main-md.c, main-md-trace.c, allocate.c, timing.c, includes/
```

## Building and running (CPU)

```
make TAG=GCC ISA=avx2            # or ISA=avx512, ISA=sve
./gather-bench-GCC -s 8 -f 2.5
make TAG=GCC ISA=avx2 VARIANT=md
./gather-bench-GCC-md -s 8 -f 2.5
```

Key `config.mk` / command-line knobs:

- `ISA` - `avx2`, `avx512`, or `sve`.
- `KERNEL` - `asm` (default: hand-written per-ISA assembly, double-precision
  only, fixed unroll factor, no masking) or `intrinsic` (portable C++
  kernel that additionally supports `DATA_TYPE=SP`, `UNROLL`, and masked
  gathers).
- `DATA_TYPE` - `DP` (default) or `SP`; `SP` requires `KERNEL=intrinsic`.
- `UNROLL` - unroll factor for `KERNEL=intrinsic` (1, 2, 4, or 8).
- `DATA_LAYOUT` - `AOS` or `SOA` (main-md/main-md-trace only).
- `TEST=true` - verify gathered values against the expected pattern.
- `--unique=K` (`main.c`/`main-md.c` runtime flag) - number of distinct
  indices per vector-width lane group (1..VL, default VL = fully distinct).
  Setting `K` < VL makes some gathered elements in the same instruction
  reference the same address, letting you evaluate the effect of address
  conflicts within a gather.

When `KERNEL=intrinsic`, both `main.c` and `main-md.c` automatically sweep
every mask value from 1 to VL active lanes per gather (an extra `Mask`
column in the CSV output), using each ISA's native masked-gather support
(AVX-512 k-registers, AVX2's vector gather mask, SVE predicates) built once
outside the timed loop. `KERNEL=asm` has no masking support and reports a
single, fully-active row.

`PADDING`, `ONLY_FIRST_DIMENSION`, `MEASURE_GATHER_CYCLES`, and
`MEM_TRACER` are `KERNEL=asm`-only diagnostic/variant options.

## GPU (CUDA/HIP) variant

`src/cuda/main.cu` ports the same idea to GPUs: a permutation index array
`idx[i] = (i * stride) % N` is used to gather either a single value
(`--dims 1`) or a 3-component "particle" (`--dims 3`, AoS or SoA layout,
mirroring `src/main-md.c`) per element, sweeping the problem size `N` and
reporting achieved bandwidth, time/element and cycles/element.

Build (single source, following the same nvcc/hipify-perl/hipcc flow used by
the `gpu-benches` repo):

```
cd src/cuda
make cuda-gather-bench   # requires nvcc
make hip-gather-bench    # requires hipify-perl + hipcc
```

Run, e.g.:

```
./cuda-gather-bench --stride=8 --dims=3 --layout=aos --test
```

See `./cuda-gather-bench --help` for all options (stride, dims, layout,
precision, block size, N sweep bounds, correctness test).
