.intel_syntax noprefix
.altmacro

#ifndef UNROLL
#define UNROLL 4
#endif

.data
.align 64
SCALAR:
.double 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0

# One VL(=16)-wide masked AoS gather (3 components), cycling through 4
# register slots. zmm31 is transient scratch for the idx*dims multiply.
.macro GATHER_AOS512_SP_ONE slot, off
.if \slot == 0
    vmovdqu32 zmm0, ZMMWORD PTR [rsi + rax * 4 + (\off*64)]
    vpaddd  zmm31, zmm0, zmm0
#ifdef PADDING
    vpaddd  zmm0, zmm31, zmm31
#else
    vpaddd  zmm0, zmm0, zmm31
#endif
    kmovw   k1, r10d
    vpxord  zmm4, zmm4, zmm4
    vgatherdps zmm4{k1}, [rdi + zmm0 * 4]
#ifndef ONLY_FIRST_DIMENSION
    kmovw   k2, r10d
    kmovw   k3, r10d
    vpxord  zmm5, zmm5, zmm5
    vpxord  zmm6, zmm6, zmm6
    vgatherdps zmm5{k2}, [4 + rdi + zmm0 * 4]
    vgatherdps zmm6{k3}, [8 + rdi + zmm0 * 4]
#endif
#ifdef TEST
    vmovups [rcx + rax * 4 + (\off*64)], zmm4
#ifndef ONLY_FIRST_DIMENSION
    vmovups [r11 + rax * 4 + (\off*64)], zmm5
    vmovups [r9  + rax * 4 + (\off*64)], zmm6
#endif
#endif
.elseif \slot == 1
    vmovdqu32 zmm1, ZMMWORD PTR [rsi + rax * 4 + (\off*64)]
    vpaddd  zmm31, zmm1, zmm1
#ifdef PADDING
    vpaddd  zmm1, zmm31, zmm31
#else
    vpaddd  zmm1, zmm1, zmm31
#endif
    kmovw   k1, r10d
    vpxord  zmm7, zmm7, zmm7
    vgatherdps zmm7{k1}, [rdi + zmm1 * 4]
#ifndef ONLY_FIRST_DIMENSION
    kmovw   k2, r10d
    kmovw   k3, r10d
    vpxord  zmm8, zmm8, zmm8
    vpxord  zmm9, zmm9, zmm9
    vgatherdps zmm8{k2}, [4 + rdi + zmm1 * 4]
    vgatherdps zmm9{k3}, [8 + rdi + zmm1 * 4]
#endif
#ifdef TEST
    vmovups [rcx + rax * 4 + (\off*64)], zmm7
#ifndef ONLY_FIRST_DIMENSION
    vmovups [r11 + rax * 4 + (\off*64)], zmm8
    vmovups [r9  + rax * 4 + (\off*64)], zmm9
#endif
#endif
.elseif \slot == 2
    vmovdqu32 zmm2, ZMMWORD PTR [rsi + rax * 4 + (\off*64)]
    vpaddd  zmm31, zmm2, zmm2
#ifdef PADDING
    vpaddd  zmm2, zmm31, zmm31
#else
    vpaddd  zmm2, zmm2, zmm31
#endif
    kmovw   k1, r10d
    vpxord  zmm10, zmm10, zmm10
    vgatherdps zmm10{k1}, [rdi + zmm2 * 4]
#ifndef ONLY_FIRST_DIMENSION
    kmovw   k2, r10d
    kmovw   k3, r10d
    vpxord  zmm11, zmm11, zmm11
    vpxord  zmm12, zmm12, zmm12
    vgatherdps zmm11{k2}, [4 + rdi + zmm2 * 4]
    vgatherdps zmm12{k3}, [8 + rdi + zmm2 * 4]
#endif
#ifdef TEST
    vmovups [rcx + rax * 4 + (\off*64)], zmm10
#ifndef ONLY_FIRST_DIMENSION
    vmovups [r11 + rax * 4 + (\off*64)], zmm11
    vmovups [r9  + rax * 4 + (\off*64)], zmm12
#endif
#endif
.else
    vmovdqu32 zmm3, ZMMWORD PTR [rsi + rax * 4 + (\off*64)]
    vpaddd  zmm31, zmm3, zmm3
#ifdef PADDING
    vpaddd  zmm3, zmm31, zmm31
#else
    vpaddd  zmm3, zmm3, zmm31
#endif
    kmovw   k1, r10d
    vpxord  zmm13, zmm13, zmm13
    vgatherdps zmm13{k1}, [rdi + zmm3 * 4]
#ifndef ONLY_FIRST_DIMENSION
    kmovw   k2, r10d
    kmovw   k3, r10d
    vpxord  zmm14, zmm14, zmm14
    vpxord  zmm15, zmm15, zmm15
    vgatherdps zmm14{k2}, [4 + rdi + zmm3 * 4]
    vgatherdps zmm15{k3}, [8 + rdi + zmm3 * 4]
#endif
#ifdef TEST
    vmovups [rcx + rax * 4 + (\off*64)], zmm13
#ifndef ONLY_FIRST_DIMENSION
    vmovups [r11 + rax * 4 + (\off*64)], zmm14
    vmovups [r9  + rax * 4 + (\off*64)], zmm15
#endif
#endif
.endif
.endm

# rdi -> a (float*)
# rsi -> idx
# rdx -> N
# rcx -> t (float*, only written if TEST)
# r8  -> cycles (unused by this kernel)
# r9d -> active_lanes (1..16): first `active_lanes` of every 16-wide gather group are gathered
.text
.globl gather_aos_sp
.type gather_aos_sp, @function
gather_aos_sp :
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

mov r9d, r9d
mov r10d, -1
bzhi r10d, r10d, r9d

#ifdef TEST
lea r11, [rcx + rdx * 4]     # &t[N]   (y component base, float stride)
lea r9,  [r11 + rdx * 4]     # &t[2*N] (z component base); r9 (active_lanes) is free now
#endif

xor   rax, rax
.align 16
1:
counter = 0
.rept UNROLL
    slot = counter % 4
    off = counter
    GATHER_AOS512_SP_ONE %slot, %off
    counter = counter + 1
.endr

addq rax, (16 * UNROLL)
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
.size gather_aos_sp, .-gather_aos_sp
