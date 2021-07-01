# Supported: GCC, CLANG, ICC
TAG ?= ICC
# Supported: avx2, avx512
ISA ?= avx512

# SP or DP
DATA_TYPE ?= DP
# AOS or SOA
DATA_LAYOUT ?= AOS
# Padding byte for AoS
PADDING ?= false

# Test correctness of gather kernels
TEST ?= false
