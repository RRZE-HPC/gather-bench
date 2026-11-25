# Intel classic compiler (icc/icpc). Discontinued in oneAPI 2024+; use TAG=ICX
# with newer toolchains.
CC  = icc
CXX = icpc
AS  = as
LINKER = $(CC)

OPENMP   = -qopenmp

# Use -march rather than -x<code>: -x inserts a startup check that refuses to run
# on non-Intel CPUs (e.g. AMD EPYC), -march does not.
ifeq ($(strip $(ISA)),sve)
$(error TAG=ICC targets x86-64 only; use TAG=GCC or TAG=CLANG for ISA=sve)
else ifeq ($(strip $(ISA)),avx512)
ARCHFLAGS = -march=skylake-avx512 -qopt-zmm-usage=high
else
ARCHFLAGS = -march=core-avx2
endif

CFLAGS   = -Ofast -std=c11 $(ARCHFLAGS) $(OPENMP)
CXXFLAGS = -Ofast -std=c++17 $(ARCHFLAGS) $(OPENMP)
ASFLAGS  =
LFLAGS   = $(OPENMP) $(ARCHFLAGS)
DEFINES  = -D_GNU_SOURCE
INCLUDES =
LIBS     =
