# Intel oneAPI DPC++/C++ compiler (icx/icpx, LLVM-based successor of icc).
CC  = icx
CXX = icpx
AS  = as
LINKER = $(CC)

OPENMP   = -qopenmp

# Use -march rather than -x<code>: -x inserts a startup check that refuses to run
# on non-Intel CPUs (e.g. AMD EPYC), -march does not.
ifeq ($(strip $(ISA)),sve)
$(error TAG=ICX targets x86-64 only; use TAG=GCC or TAG=CLANG for ISA=sve)
else ifeq ($(strip $(ISA)),avx512)
# -qopt-zmm-usage=high: without it icx prefers 256-bit vectors for
# compiler-generated code on AVX-512 targets.
ARCHFLAGS = -march=skylake-avx512 -qopt-zmm-usage=high
else
ARCHFLAGS = -march=core-avx2
endif

CFLAGS   = -O3 -ffast-math -std=c11 $(ARCHFLAGS) $(OPENMP)
CXXFLAGS = -O3 -ffast-math -std=c++17 $(ARCHFLAGS) $(OPENMP)
ASFLAGS  =
LFLAGS   = $(OPENMP) $(ARCHFLAGS)
DEFINES  = -D_GNU_SOURCE
INCLUDES =
LIBS     =
