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
.iota64_gather_aos:
.quad 0, 1, 2, 3
.size .iota64_gather_aos, 32

# One VL(=4)-wide masked AoS gather (3 components), cycling through 2
# register slots (AVX2 has only 16 YMM registers and each slot needs an
# idx register + 3 mask copies + 3 accumulators = 7 registers).
# Registers: ymm14 = mask template (persistent). Slot 0 uses
# ymm0-6 (idx, 3 mask copies, 3 accumulators); slot 1 uses ymm7-13.
# r9/r11 hold the precomputed y/z component bases into t (TEST only).
.macro GATHER_AOS_ONE slot, off
.if \slot == 0
    vmovups xmm0, XMMWORD PTR [rsi + rax * 4 + (\off*16)]
    vpaddd  xmm1, xmm0, xmm0
#ifdef PADDING
    vpaddd  xmm0, xmm1, xmm1
#else
    vpaddd  xmm0, xmm0, xmm1
#endif
    vmovdqa ymm1, ymm14
    vmovdqa ymm2, ymm14
    vmovdqa ymm3, ymm14
    vxorpd  ymm4, ymm4, ymm4
    vxorpd  ymm5, ymm5, ymm5
    vxorpd  ymm6, ymm6, ymm6
    vgatherdpd ymm4, [     rdi + xmm0 * 8], ymm1
    vgatherdpd ymm5, [8  + rdi + xmm0 * 8], ymm2
    vgatherdpd ymm6, [16 + rdi + xmm0 * 8], ymm3
#ifdef TEST
    vmovupd [rcx + rax * 8 + (\off*32)], ymm4
    vmovupd [r11 + rax * 8 + (\off*32)], ymm5
    vmovupd [r9  + rax * 8 + (\off*32)], ymm6
#endif
.else
    vmovups xmm7, XMMWORD PTR [rsi + rax * 4 + (\off*16)]
    vpaddd  xmm8, xmm7, xmm7
#ifdef PADDING
    vpaddd  xmm7, xmm8, xmm8
#else
    vpaddd  xmm7, xmm7, xmm8
#endif
    vmovdqa ymm8,  ymm14
    vmovdqa ymm9,  ymm14
    vmovdqa ymm10, ymm14
    vxorpd  ymm11, ymm11, ymm11
    vxorpd  ymm12, ymm12, ymm12
    vxorpd  ymm13, ymm13, ymm13
    vgatherdpd ymm11, [     rdi + xmm7 * 8], ymm8
    vgatherdpd ymm12, [8  + rdi + xmm7 * 8], ymm9
    vgatherdpd ymm13, [16 + rdi + xmm7 * 8], ymm10
#ifdef TEST
    vmovupd [rcx + rax * 8 + (\off*32)], ymm11
    vmovupd [r11 + rax * 8 + (\off*32)], ymm12
    vmovupd [r9  + rax * 8 + (\off*32)], ymm13
#endif
.endif
.endm

# rdi -> a
# rsi -> idx
# rdx -> N
# rcx -> t (only written if TEST)
# r8  -> cycles (unused by this ISA)
# r9d -> active_lanes (1..4): first `active_lanes` of every 4-wide gather group are gathered
.text
.globl gather_aos_dp
.type gather_aos_dp, @function
gather_aos_dp :
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

mov r9d, r9d                      # zero-extend active_lanes into r9
vmovq   xmm1, r9
vpbroadcastq ymm1, xmm1
vmovdqu ymm2, YMMWORD PTR .iota64_gather_aos[rip]
vpcmpgtq ymm14, ymm1, ymm2         # ymm14 = mask template: first active_lanes lanes active

#ifdef TEST
lea r11, [rcx + rdx * 8]          # &t[N]   (y component base)
lea r9,  [r11 + rdx * 8]          # &t[2*N] (z component base); r9 (active_lanes) is free now
#endif

xor   rax, rax
.align 16
1:
counter = 0
.rept UNROLL
    slot = counter % 2
    off = counter
    GATHER_AOS_ONE %slot, %off
    counter = counter + 1
.endr

addq rax, (4 * UNROLL)
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
.size gather_aos_dp, .-gather_aos_dp
