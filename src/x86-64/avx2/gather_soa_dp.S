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
.iota64_gather_soa:
.quad 0, 1, 2, 3
.size .iota64_gather_soa, 32

# One VL(=4)-wide masked SoA gather (3 components), cycling through 2
# register slots. See gather_aos_dp.S for the register-budget rationale.
# r8/r9 hold the precomputed y/z component bases into a; r11/r12 hold the
# same for t (TEST only).
.macro GATHER_SOA_ONE slot, off
.if \slot == 0
    vmovups xmm0, XMMWORD PTR [rsi + rax * 4 + (\off*16)]
    vmovdqa ymm1, ymm14
    vmovdqa ymm2, ymm14
    vmovdqa ymm3, ymm14
    vxorpd  ymm4, ymm4, ymm4
    vxorpd  ymm5, ymm5, ymm5
    vxorpd  ymm6, ymm6, ymm6
    vgatherdpd ymm4, [rdi + xmm0 * 8], ymm1
    vgatherdpd ymm5, [r8  + xmm0 * 8], ymm2
    vgatherdpd ymm6, [r9  + xmm0 * 8], ymm3
#ifdef TEST
    vmovupd [rcx + rax * 8 + (\off*32)], ymm4
    vmovupd [r11 + rax * 8 + (\off*32)], ymm5
    vmovupd [r12 + rax * 8 + (\off*32)], ymm6
#endif
.else
    vmovups xmm7, XMMWORD PTR [rsi + rax * 4 + (\off*16)]
    vmovdqa ymm8,  ymm14
    vmovdqa ymm9,  ymm14
    vmovdqa ymm10, ymm14
    vxorpd  ymm11, ymm11, ymm11
    vxorpd  ymm12, ymm12, ymm12
    vxorpd  ymm13, ymm13, ymm13
    vgatherdpd ymm11, [rdi + xmm7 * 8], ymm8
    vgatherdpd ymm12, [r8  + xmm7 * 8], ymm9
    vgatherdpd ymm13, [r9  + xmm7 * 8], ymm10
#ifdef TEST
    vmovupd [rcx + rax * 8 + (\off*32)], ymm11
    vmovupd [r11 + rax * 8 + (\off*32)], ymm12
    vmovupd [r12 + rax * 8 + (\off*32)], ymm13
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
.globl gather_soa_dp
.type gather_soa_dp, @function
gather_soa_dp :
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
vmovdqu ymm2, YMMWORD PTR .iota64_gather_soa[rip]
vpcmpgtq ymm14, ymm1, ymm2         # ymm14 = mask template: first active_lanes lanes active

lea r8, [rdi + rdx * 8]            # &a[1*N] (y component base)
lea r9, [r8  + rdx * 8]            # &a[2*N] (z component base); r9 (active_lanes) is free now
#ifdef TEST
lea r11, [rcx + rdx * 8]           # &t[N]
lea r12, [r11 + rdx * 8]           # &t[2*N]
#endif

xor   rax, rax
.align 16
1:
counter = 0
.rept UNROLL
    slot = counter % 2
    off = counter
    GATHER_SOA_ONE %slot, %off
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
.size gather_soa_dp, .-gather_soa_dp
