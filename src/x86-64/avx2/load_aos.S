.intel_syntax noprefix
.data
.align 32
SCALAR:
.double 1.0, 1.0, 1.0, 1.0

# rdi -> &a[i * snbytes]

.text
.globl load_aos
.type load_aos, @function
load_aos :

vmovsd xmm0, QWORD PTR [rdi]
vmovsd xmm1, QWORD PTR [8  + rdi]
vmovsd xmm2, QWORD PTR [16 + rdi]

vbroadcastsd ymm3, xmm0
vbroadcastsd ymm4, xmm1
vbroadcastsd ymm5, xmm2

ret
.size load_aos, .-load_aos
