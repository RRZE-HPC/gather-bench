.intel_syntax noprefix
.data
.align 32
SCALAR:
.double 1.0, 1.0, 1.0, 1.0

# rdi -> a (double*, SoA planar layout, component d at a[d*n + i])
# esi -> i (atom index)
# edx -> n (elements per component, i.e. the stride between components)

.text
.globl load_soa
.type load_soa, @function
load_soa :

movsxd rax, esi
movsxd rcx, edx

vmovsd xmm0, QWORD PTR [rdi + rax * 8]
lea r8, [rdi + rcx * 8]
vmovsd xmm1, QWORD PTR [r8 + rax * 8]
lea r9, [r8 + rcx * 8]
vmovsd xmm2, QWORD PTR [r9 + rax * 8]

vbroadcastsd ymm3, xmm0
vbroadcastsd ymm4, xmm1
vbroadcastsd ymm5, xmm2

ret
.size load_soa, .-load_soa
