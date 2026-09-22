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
.iota32_gather_soa_sp:
.long 0, 1, 2, 3, 4, 5, 6, 7
.size .iota32_gather_soa_sp, 32

# One VL(=8)-wide masked SoA gather (3 components), cycling through 2
# register slots. r8/r9 hold the precomputed y/z component bases into a;
# r11/r12 hold the same for t (TEST only).
.macro GATHER_SOA_SP_ONE slot, off
.if \slot == 0
    vmovdqu ymm0, YMMWORD PTR [rsi + rax * 4 + (\off*32)]
    vmovdqa ymm1, ymm14
    vmovdqa ymm2, ymm14
    vmovdqa ymm3, ymm14
    vxorps  ymm4, ymm4, ymm4
    vxorps  ymm5, ymm5, ymm5
    vxorps  ymm6, ymm6, ymm6
    vgatherdps ymm4, [rdi + ymm0 * 4], ymm1
    vgatherdps ymm5, [r8  + ymm0 * 4], ymm2
    vgatherdps ymm6, [r9  + ymm0 * 4], ymm3
#ifdef TEST
    vmovups [rcx + rax * 4 + (\off*32)], ymm4
    vmovups [r11 + rax * 4 + (\off*32)], ymm5
    vmovups [r12 + rax * 4 + (\off*32)], ymm6
#endif
.else
    vmovdqu ymm7, YMMWORD PTR [rsi + rax * 4 + (\off*32)]
    vmovdqa ymm8,  ymm14
    vmovdqa ymm9,  ymm14
    vmovdqa ymm10, ymm14
    vxorps  ymm11, ymm11, ymm11
    vxorps  ymm12, ymm12, ymm12
    vxorps  ymm13, ymm13, ymm13
    vgatherdps ymm11, [rdi + ymm7 * 4], ymm8
    vgatherdps ymm12, [r8  + ymm7 * 4], ymm9
    vgatherdps ymm13, [r9  + ymm7 * 4], ymm10
#ifdef TEST
    vmovups [rcx + rax * 4 + (\off*32)], ymm11
    vmovups [r11 + rax * 4 + (\off*32)], ymm12
    vmovups [r12 + rax * 4 + (\off*32)], ymm13
#endif
.endif
.endm

# rdi -> a (float*)
# rsi -> idx
# rdx -> N
# rcx -> t (float*, only written if TEST)
# r8  -> cycles (unused by this ISA)
# r9d -> active_lanes (1..8): first `active_lanes` of every 8-wide gather group are gathered
.text
.globl gather_soa_sp
.type gather_soa_sp, @function
gather_soa_sp :
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
vmovd   xmm1, r9d
vpbroadcastd ymm1, xmm1
vmovdqu ymm2, YMMWORD PTR .iota32_gather_soa_sp[rip]
vpcmpgtd ymm14, ymm1, ymm2         # ymm14 = mask template: first active_lanes lanes active

lea r8, [rdi + rdx * 4]            # &a[1*N] (y component base, float stride)
lea r9, [r8  + rdx * 4]            # &a[2*N] (z component base); r9 (active_lanes) is free now
#ifdef TEST
lea r11, [rcx + rdx * 4]           # &t[N]
lea r12, [r11 + rdx * 4]           # &t[2*N]
#endif

xor   rax, rax
.align 16
1:
counter = 0
.rept UNROLL
    slot = counter % 2
    off = counter
    GATHER_SOA_SP_ONE %slot, %off
    counter = counter + 1
.endr

addq rax, (8 * UNROLL)
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
.size gather_soa_sp, .-gather_soa_sp
