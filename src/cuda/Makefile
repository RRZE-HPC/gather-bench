NVCC := nvcc

TEMP_NVCC := $(shell which nvcc)
CUDA_HOME := $(shell echo $(TEMP_NVCC) | rev | cut -d'/' -f3- | rev)

HIP_HOME := /opt/rocm

NAME    := gather-bench

# NVIDIA architectures to build for; override on the command line, e.g.
# `make ARCHS="80 90" cuda-gather-bench`.
ARCHS   ?= 70 80 90
GENCODE := $(foreach arch,$(ARCHS),-gencode=arch=compute_$(arch),code=sm_$(arch))

NVCCFLAGS := -std=c++17 -O3 $(GENCODE) --compiler-options="-O2 -pipe -Wall" -Xcompiler -rdynamic --generate-line-info
LDFLAGS   := -L$(CUDA_HOME)/lib64 -lcuda

cuda-$(NAME): main.cu Makefile gpu-error.h
	$(NVCC) $(NVCCFLAGS) -o $@ $< $(LDFLAGS)

main.hip: main.cu
	hipify-perl main.cu > main.hip

hip-$(NAME): main.hip Makefile gpu-error.h
	hipcc -std=c++17 -O3 -o $@ main.hip

.PHONY: clean
clean:
	rm -f cuda-$(NAME) hip-$(NAME) main.hip
