.intel_syntax noprefix
.altmacro

#ifndef UNROLL
#define UNROLL 4
#endif

.data
.align 64
SCALAR:
.double 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0

# One VL(=8)-wide masked gather, cycling through 4 register slots so this
# works unmodified for any UNROLL value. AVX-512 gather clears the k-mask
# bits it consumes, so it must be rebuilt (cheaply, via kmovw from the
# precomputed r10d value) before every gather, not just once.
.macro GATHER_ONE_DP512 slot, off
.if \slot == 0
    vmovdqu ymm0, YMMWORD PTR [rsi + rax * 4 + (\off*32)]
    kmovw   k1, r10d
    vpxord  zmm4, zmm4, zmm4
    vgatherdpd zmm4{k1}, [rdi + ymm0 * 8]
#ifdef TEST
    vmovupd [rcx + rax * 8 + (\off*64)], zmm4
#endif
.elseif \slot == 1
    vmovdqu ymm1, YMMWORD PTR [rsi + rax * 4 + (\off*32)]
    kmovw   k2, r10d
    vpxord  zmm5, zmm5, zmm5
    vgatherdpd zmm5{k2}, [rdi + ymm1 * 8]
#ifdef TEST
    vmovupd [rcx + rax * 8 + (\off*64)], zmm5
#endif
.elseif \slot == 2
    vmovdqu ymm2, YMMWORD PTR [rsi + rax * 4 + (\off*32)]
    kmovw   k3, r10d
    vpxord  zmm6, zmm6, zmm6
    vgatherdpd zmm6{k3}, [rdi + ymm2 * 8]
#ifdef TEST
    vmovupd [rcx + rax * 8 + (\off*64)], zmm6
#endif
.else
    vmovdqu ymm3, YMMWORD PTR [rsi + rax * 4 + (\off*32)]
    kmovw   k4, r10d
    vpxord  zmm7, zmm7, zmm7
    vgatherdpd zmm7{k4}, [rdi + ymm3 * 8]
#ifdef TEST
    vmovupd [rcx + rax * 8 + (\off*64)], zmm7
#endif
.endif
.endm

# rdi -> a
# rsi -> idx
# rdx -> N
# rcx -> t (only written if TEST)
# r8d -> active_lanes (1..8): first `active_lanes` of every 8-wide gather group are gathered
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
    GATHER_ONE_DP512 %slot, %off
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
.size gather_dp, .-gather_dp
