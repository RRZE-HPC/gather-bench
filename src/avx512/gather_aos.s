.intel_syntax noprefix
.data
.align 64
SCALAR:
.double 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0

# rdi -> a
# rsi -> idx
# rdx -> N
# rcx -> t
.text
.globl gather_aos
.type gather_aos, @function
gather_aos :
push rbp
mov rbp, rsp
push rbx
push r9
push r10
push r11
push r12
push r13
push r14
push r15

xor   rax, rax
.align 16
1:

vmovdqu ymm3, YMMWORD PTR [rsi + rax * 4]
vpaddd ymm4, ymm3, ymm3
vpaddd ymm3, ymm3, ymm4

# Prefetching instructions
#mov ebx, DWORD PTR[rsi + rax*4]
#mov r9d, DWORD PTR[4 + rsi + rax*4]
#mov r10d, DWORD PTR[8 + rsi + rax*4]
#mov r11d, DWORD PTR[12 + rsi + rax*4]
#mov r12d, DWORD PTR[16 + rsi + rax*4]
#mov r13d, DWORD PTR[20 + rsi + rax*4]
#mov r14d, DWORD PTR[24 + rsi + rax*4]
#mov r15d, DWORD PTR[28 + rsi + rax*4]
#lea ebx, DWORD PTR[rbx]
#lea r9d, DWORD PTR[r9]
#lea r10d, DWORD PTR[r10]
#lea r11d, DWORD PTR[r11]
#lea r12d, DWORD PTR[r12]
#lea r13d, DWORD PTR[r13]
#lea r14d, DWORD PTR[r14]
#lea r15d, DWORD PTR[r15]

vpcmpeqb k1, xmm5, xmm5
vpcmpeqb k2, xmm5, xmm5
vpcmpeqb k3, xmm5, xmm5
vpxord zmm0, zmm0, zmm0
vpxord zmm1, zmm1, zmm1
vpxord zmm2, zmm2, zmm2
vgatherdpd zmm0{k1}, [rdi + ymm3*8]
vgatherdpd zmm1{k2}, [8 + rdi + ymm3*8]
vgatherdpd zmm2{k3}, [16 + rdi + ymm3*8]

# Required for test
#vmovupd [rcx + rax*8], zmm0
#lea rbx, [rcx + rdx*8]
#vmovupd [rbx + rax*8], zmm1
#lea r9, [rbx + rdx*8]
#vmovupd [r9 + rax*8], zmm2

addq rax, 8
cmpq rax, rdx
jl 1b

pop r15
pop r14
pop r13
pop r12
pop r11
pop r10
pop r9
pop rbx
mov  rsp, rbp
pop rbp
ret
.size gather_aos, .-gather_aos
