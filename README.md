# gather-bench
A gather instruction performance benchmark for x86-64 (AVX2/AVX-512), ARM
SVE2, and GPUs (CUDA/HIP).

## Directory layout

```
src/
  x86-64/avx2/     hand-written AVX2 gather kernels (.S)
  x86-64/avx512/   hand-written AVX-512 gather kernels (.S)
  aarch64/sve2/    hand-written ARM SVE2 gather kernels (.S) - UNVERIFIED,
                   no SVE hardware or cross-compiler was available to build
                   or run these; treat with extra scrutiny before relying on
                   the numbers.
  cuda/            GPU (CUDA/HIP) benchmark, see below
  gather_intrinsic.cc   portable C++ intrinsics kernel (KERNEL=intrinsic)
  main.c, main-md.c, main-md-trace.c, allocate.c, timing.c, includes/
make/
  include_<TAG>.mk   per-toolchain compiler/flags (GCC, CLANG, ICX, ICC)
  include_LIKWID.mk  LIKWID marker API settings (ENABLE_LIKWID=true)
config.mk          default build knobs (all overridable on the command line)
build/             object files, one directory per TAG/ISA/KERNEL/OP combination
```

## Building and running (CPU)

```
make ISA=avx2                         # TAG=GCC KERNEL=asm by default
./gather-bench-GCC-avx2-asm -s 8
make ISA=avx2 VARIANT=md
./gather-bench-GCC-avx2-asm-md -s 8
make TAG=ICX ISA=avx512 KERNEL=intrinsic OP=rmw   # Intel oneAPI icx/icpx (x86-64 only)
./gather-bench-ICX-avx512-intrinsic-rmw -s 8
```

Binaries are named `gather-bench-<TAG>-<ISA>-<KERNEL>[-<OP>][-<VARIANT>]`
(the `-<OP>` part is omitted for the default `OP=gather`) and are placed in
the repository root; objects go to the matching `build/<TAG>-<ISA>-<KERNEL>[-<OP>]/`.
Only the selected kernel backend is compiled (`src/gather_intrinsic.cc` for
`KERNEL=intrinsic`, the per-ISA `.S` files for `KERNEL=asm`). Knobs that are
not part of the name (`DATA_TYPE`, `UNROLL`, `DATA_LAYOUT`, `TEST`, ...)
still share a binary name, but changing any of them automatically recompiles
the objects and relinks the binary, so a build never mixes stale kernels.

`make clean` removes the current configuration's build directory, `make
distclean` also its binary, and `make cleanall` removes the whole `build/`
directory and every `gather-bench-*` binary.

Key `config.mk` / command-line knobs:

- `TAG` - toolchain: `GCC`, `CLANG`, `ICX` (Intel oneAPI), or `ICC`
  (Intel classic, discontinued in oneAPI 2024+).
- `ISA` - `avx2`, `avx512`, or `sve`.
- `KERNEL` - `asm` (hand-written per-ISA assembly, default) or `intrinsic`
  (portable C++ kernel). Both support `DATA_TYPE=SP`, `UNROLL`, and masked
  gathers for `main.c`/`main-md.c` (the plain and AoS/SoA kernels); the
  md-trace kernels remain `KERNEL=asm`-only, double-precision, and
  fixed-unroll. This lets the two implementations be compared directly.
- `DATA_TYPE` - `DP` (default) or `SP`.
- `UNROLL` - unroll factor (1, 2, 4, or 8) for `main.c`/`main-md.c` with
  either kernel; ignored (fixed) by the md-trace variant. Implemented via
  the GNU assembler's `.rept` for `KERNEL=asm`.
- `DATA_LAYOUT` - `AOS` or `SOA` (main-md/main-md-trace only).
- `TEST=true` - verify gathered values against the expected pattern.
- `--unique=K` (`main.c`/`main-md.c` runtime flag) - number of distinct
  indices per vector-width lane group (1..VL, default VL = fully distinct).
  Setting `K` < VL makes some gathered elements in the same instruction
  reference the same address, letting you evaluate the effect of address
  conflicts within a gather. Works identically with either `KERNEL`, since
  it's a data-generation concern, not a kernel concern.

`main.c` and `main-md.c` report `GHz(meas)` and `cy/it(meas)` (plus
`cy/gath(meas)` for `main-md.c`), computed from unhalted core cycles counted
with `perf_event_open` around the timed loop. One "it" is one SIMD iteration,
i.e. VL elements (one gather in `main.c`, `dims` gathers in `main-md.c`).
These columns stay correct under turbo, AVX-512 downclocking or a CPU still
ramping up from a low power state. They require `perf_event_paranoid <= 2`
and print `nan` otherwise; do not combine with `likwid-perfctr`.

`-f GHz` is optional. Only when it is given are the wall-time-based cycle
columns added (`cy/gather`, `cy/elem` in `main.c`; `cy/it`, `cy/gather`,
`cy/elem` in `main-md.c`), computed as wall time x the given frequency. They
match the measured columns only if the core actually runs at that frequency,
so prefer the `(meas)` columns. `time/LUP(us)` is wall time per element in
microseconds.

Both `main.c` and `main-md.c` automatically sweep every mask value from 1 to
VL active lanes per gather (an extra `Mask` column in the CSV output), using
each ISA's native masked-gather support (AVX-512 k-registers rebuilt via
`kmovw`, AVX2's vector gather mask rebuilt via a lane-index compare, SVE
predicates via `whilelt`) built once (or, for AVX-512/AVX2 where the
gather instruction consumes its mask, cheaply rebuilt) outside the hot loop.

`PADDING`, `ONLY_FIRST_DIMENSION`, and `MEM_TRACER` are `KERNEL=asm`-only
diagnostic/variant options for `main-md.c`. `MEASURE_GATHER_CYCLES` is also
`KERNEL=asm`-only and, on AVX-512, always uses the full (unmasked) width
regardless of the mask sweep - it's an orthogonal per-gather cycle-counting
diagnostic, not re-verified against masking.

SVE2's `UNROLL` is always effectively 1: SVE already scales to the
hardware's native vector width per iteration, so additional software
unrolling was judged not worth the added unverifiable risk in this
environment (see below).

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
