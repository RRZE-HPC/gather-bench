.intel_syntax noprefix
.altmacro

#ifndef UNROLL
#define UNROLL 4
#endif

.data
.align 64
SCALAR:
.double 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0

.section .rodata, "a"
.align 32
.iota64_gather:
.quad 0, 1, 2, 3
.size .iota64_gather, 32

# One VL(=4)-wide masked gather_dp, cycling through 4 register slots so this
# works unmodified for any UNROLL value. Slot N uses xmm(1+N)/ymm(5+N)/ymm(9+N).
.macro GATHER_ONE slot, off
.if \slot == 0
    vmovups xmm1, XMMWORD PTR [rsi + rax * 4 + (\off*16)]
    vmovdqa ymm5, ymm0
    vxorpd  ymm9, ymm9, ymm9
    vgatherdpd ymm9, [rdi + xmm1 * 8], ymm5
#ifdef TEST
    vmovupd [rcx + rax * 8 + (\off*32)], ymm9
#endif
.elseif \slot == 1
    vmovups xmm2, XMMWORD PTR [rsi + rax * 4 + (\off*16)]
    vmovdqa ymm6, ymm0
    vxorpd  ymm10, ymm10, ymm10
    vgatherdpd ymm10, [rdi + xmm2 * 8], ymm6
#ifdef TEST
    vmovupd [rcx + rax * 8 + (\off*32)], ymm10
#endif
.elseif \slot == 2
    vmovups xmm3, XMMWORD PTR [rsi + rax * 4 + (\off*16)]
    vmovdqa ymm7, ymm0
    vxorpd  ymm11, ymm11, ymm11
    vgatherdpd ymm11, [rdi + xmm3 * 8], ymm7
#ifdef TEST
    vmovupd [rcx + rax * 8 + (\off*32)], ymm11
#endif
.else
    vmovups xmm4, XMMWORD PTR [rsi + rax * 4 + (\off*16)]
    vmovdqa ymm8, ymm0
    vxorpd  ymm12, ymm12, ymm12
    vgatherdpd ymm12, [rdi + xmm4 * 8], ymm8
#ifdef TEST
    vmovupd [rcx + rax * 8 + (\off*32)], ymm12
#endif
.endif
.endm

# rdi -> a
# rsi -> idx
# rdx -> N
# rcx -> t (only written if TEST)
# r8d -> active_lanes (1..4): first `active_lanes` of every 4-wide gather_dp group are gathered
.text
.globl gather_dp
.type gather_dp, @function
gather_dp :
push rbp
mov rbp, rsp
push rbx
push r12
push r13
push r14
push r15

mov r8d, r8d                    # zero-extend active_lanes into r8
vmovq   xmm1, r8
vpbroadcastq ymm1, xmm1
vmovdqu ymm2, YMMWORD PTR .iota64_gather[rip]
vpcmpgtq ymm0, ymm1, ymm2        # ymm0 = mask template: first active_lanes lanes active

xor   rax, rax
.align 16
1:
counter = 0
.rept UNROLL
    slot = counter % 4
    off = counter
    GATHER_ONE %slot, %off
    counter = counter + 1
.endr

addq rax, (4 * UNROLL)
cmpq rax, rdx
jl 1b

pop r15
pop r14
pop r13
pop r12
pop rbx
mov  rsp, rbp
pop rbp
ret
.size gather_dp, .-gather_dp
