CC  = gcc
CXX = g++
AS  = as
LINKER = $(CC)

OPENMP   = -fopenmp

ifeq ($(strip $(ISA)),sve)
ARCHFLAGS = -march=armv8-a+sve2
else ifeq ($(strip $(ISA)),avx512)
ARCHFLAGS = -march=skylake-avx512
else
ARCHFLAGS = -mavx2 -mfma
endif

CFLAGS   = -Ofast -std=c11 $(ARCHFLAGS) $(OPENMP)
CXXFLAGS = -Ofast -std=c++17 $(ARCHFLAGS) $(OPENMP)
ASFLAGS  =
LFLAGS   = $(OPENMP) $(ARCHFLAGS)
DEFINES  = -D_GNU_SOURCE
INCLUDES =
LIBS     = -lstdc++
