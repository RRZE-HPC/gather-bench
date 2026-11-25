# Supported: GCC, CLANG, ICX, ICC (toolchain files in make/include_<TAG>.mk)
TAG ?= GCC
# Supported: avx2, avx512, sve
ISA ?= avx512
# Use likwid?
ENABLE_LIKWID ?= false

# asm: hand-written per-ISA assembly kernels (src/x86-64/<isa>, src/aarch64/sve2).
# intrinsic: portable C++ intrinsics kernel (src/gather_intrinsic.cc); the only
#            one supporting OP=scatter/rmw. Both support DATA_TYPE, UNROLL and the
#            mask sweep for main.c/main-md.c; VARIANT=md-trace needs KERNEL=asm.
KERNEL ?= asm
# gather (default), scatter, or rmw (gather + add + scatter); scatter/rmw need KERNEL=intrinsic and avx512/sve.
OP ?= gather
# Unroll factor (1, 2, 4 or 8) for main.c/main-md.c; md-trace kernels use a fixed unroll.
UNROLL ?= 4

# SP or DP
DATA_TYPE ?= DP
# AOS or SOA
DATA_LAYOUT ?= AOS
# Padding byte for AoS
PADDING ?= false
# Measure cycles for each gather separately
MEASURE_GATHER_CYCLES ?= false
# Gather data only for first dimension (one gather per iteration)
ONLY_FIRST_DIMENSION ?= false

# Trace memory addresses for cache simulator
MEM_TRACER ?= false
# Test correctness of gather kernels
TEST ?= false
