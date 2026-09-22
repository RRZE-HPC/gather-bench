.intel_syntax noprefix
.altmacro

#ifndef UNROLL
#define UNROLL 4
#endif

.section .rodata, "a"
.align 32
.iota32_gather_sp:
.long 0, 1, 2, 3, 4, 5, 6, 7
.size .iota32_gather_sp, 32

# One VL(=8)-wide masked gather, cycling through 4 register slots so this
# works unmodified for any UNROLL value.
.macro GATHER_ONE_SP slot, off
.if \slot == 0
    vmovdqu ymm1, YMMWORD PTR [rsi + rax * 4 + (\off*32)]
    vmovdqa ymm5, ymm0
    vxorps  ymm9, ymm9, ymm9
    vgatherdps ymm9, [rdi + ymm1 * 4], ymm5
#ifdef TEST
    vmovups [rcx + rax * 4 + (\off*32)], ymm9
#endif
.elseif \slot == 1
    vmovdqu ymm2, YMMWORD PTR [rsi + rax * 4 + (\off*32)]
    vmovdqa ymm6, ymm0
    vxorps  ymm10, ymm10, ymm10
    vgatherdps ymm10, [rdi + ymm2 * 4], ymm6
#ifdef TEST
    vmovups [rcx + rax * 4 + (\off*32)], ymm10
#endif
.elseif \slot == 2
    vmovdqu ymm3, YMMWORD PTR [rsi + rax * 4 + (\off*32)]
    vmovdqa ymm7, ymm0
    vxorps  ymm11, ymm11, ymm11
    vgatherdps ymm11, [rdi + ymm3 * 4], ymm7
#ifdef TEST
    vmovups [rcx + rax * 4 + (\off*32)], ymm11
#endif
.else
    vmovdqu ymm4, YMMWORD PTR [rsi + rax * 4 + (\off*32)]
    vmovdqa ymm8, ymm0
    vxorps  ymm12, ymm12, ymm12
    vgatherdps ymm12, [rdi + ymm4 * 4], ymm8
#ifdef TEST
    vmovups [rcx + rax * 4 + (\off*32)], ymm12
#endif
.endif
.endm

# rdi -> a (float*)
# rsi -> idx
# rdx -> N
# rcx -> t (float*, only written if TEST)
# r8d -> active_lanes (1..8): first `active_lanes` of every 8-wide gather group are gathered
.text
.globl gather_sp
.type gather_sp, @function
gather_sp :
push rbp
mov rbp, rsp
push rbx
push r12
push r13
push r14
push r15

mov r8d, r8d                     # zero-extend active_lanes into r8
vmovd   xmm1, r8d
vpbroadcastd ymm1, xmm1
vmovdqu ymm2, YMMWORD PTR .iota32_gather_sp[rip]
vpcmpgtd ymm0, ymm1, ymm2         # ymm0 = mask template: first active_lanes lanes active

xor   rax, rax
.align 16
1:
counter = 0
.rept UNROLL
    slot = counter % 4
    off = counter
    GATHER_ONE_SP %slot, %off
    counter = counter + 1
.endr

addq rax, (8 * UNROLL)
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
.size gather_sp, .-gather_sp
