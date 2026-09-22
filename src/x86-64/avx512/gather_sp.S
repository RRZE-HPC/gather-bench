.intel_syntax noprefix
.altmacro

#ifndef UNROLL
#define UNROLL 4
#endif

.data
.align 64
SCALAR:
.double 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0

# One VL(=16)-wide masked gather, cycling through 4 register slots so this
# works unmodified for any UNROLL value. See gather_dp.S for why the k-mask
# is rebuilt (via kmovw) before every gather rather than once outside the loop.
.macro GATHER_ONE_SP512 slot, off
.if \slot == 0
    vmovdqu32 zmm0, ZMMWORD PTR [rsi + rax * 4 + (\off*64)]
    kmovw   k1, r10d
    vpxord  zmm4, zmm4, zmm4
    vgatherdps zmm4{k1}, [rdi + zmm0 * 4]
#ifdef TEST
    vmovups [rcx + rax * 4 + (\off*64)], zmm4
#endif
.elseif \slot == 1
    vmovdqu32 zmm1, ZMMWORD PTR [rsi + rax * 4 + (\off*64)]
    kmovw   k2, r10d
    vpxord  zmm5, zmm5, zmm5
    vgatherdps zmm5{k2}, [rdi + zmm1 * 4]
#ifdef TEST
    vmovups [rcx + rax * 4 + (\off*64)], zmm5
#endif
.elseif \slot == 2
    vmovdqu32 zmm2, ZMMWORD PTR [rsi + rax * 4 + (\off*64)]
    kmovw   k3, r10d
    vpxord  zmm6, zmm6, zmm6
    vgatherdps zmm6{k3}, [rdi + zmm2 * 4]
#ifdef TEST
    vmovups [rcx + rax * 4 + (\off*64)], zmm6
#endif
.else
    vmovdqu32 zmm3, ZMMWORD PTR [rsi + rax * 4 + (\off*64)]
    kmovw   k4, r10d
    vpxord  zmm7, zmm7, zmm7
    vgatherdps zmm7{k4}, [rdi + zmm3 * 4]
#ifdef TEST
    vmovups [rcx + rax * 4 + (\off*64)], zmm7
#endif
.endif
.endm

# rdi -> a (float*)
# rsi -> idx
# rdx -> N
# rcx -> t (float*, only written if TEST)
# r8d -> active_lanes (1..16): first `active_lanes` of every 16-wide gather group are gathered
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

mov r8d, r8d              # zero-extend active_lanes into r8
mov r10d, -1
bzhi r10d, r10d, r8d       # r10d = (1 << active_lanes) - 1, the mask template value

xor   rax, rax
.align 16
1:
counter = 0
.rept UNROLL
    slot = counter % 4
    off = counter
    GATHER_ONE_SP512 %slot, %off
    counter = counter + 1
.endr

addq rax, (16 * UNROLL)
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
