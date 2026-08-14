CC  = gcc
AS  = as
LINKER = $(CC)

OPENMP   = -fopenmp

ifeq ($(strip $(ISA)),sve)
ARCHFLAGS = -march=armv8-a+sve2
else
ARCHFLAGS = -mavx2 -mfma
endif

CFLAGS   = -Ofast -std=c11 $(ARCHFLAGS) $(OPENMP)
ASFLAGS  =
LFLAGS   = $(OPENMP) $(ARCHFLAGS)
DEFINES  = -D_GNU_SOURCE
INCLUDES =
LIBS     =
