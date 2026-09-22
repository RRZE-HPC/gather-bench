.intel_syntax noprefix
.altmacro

#ifndef UNROLL
#define UNROLL 4
#endif

.data
.align 64
SCALAR:
.double 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0

# One VL(=16)-wide masked SoA gather (3 components), cycling through 4
# register slots. r8/r9 hold the precomputed y/z component bases into a;
# r11/r12 hold the same for t (TEST only).
.macro GATHER_SOA512_SP_ONE slot, off
.if \slot == 0
    vmovdqu32 zmm0, ZMMWORD PTR [rsi + rax * 4 + (\off*64)]
    kmovw   k1, r10d
    kmovw   k2, r10d
    kmovw   k3, r10d
    vpxord  zmm4, zmm4, zmm4
    vpxord  zmm5, zmm5, zmm5
    vpxord  zmm6, zmm6, zmm6
    vgatherdps zmm4{k1}, [rdi + zmm0 * 4]
    vgatherdps zmm5{k2}, [r8  + zmm0 * 4]
    vgatherdps zmm6{k3}, [r9  + zmm0 * 4]
#ifdef TEST
    vmovups [rcx + rax * 4 + (\off*64)], zmm4
    vmovups [r11 + rax * 4 + (\off*64)], zmm5
    vmovups [r12 + rax * 4 + (\off*64)], zmm6
#endif
.elseif \slot == 1
    vmovdqu32 zmm1, ZMMWORD PTR [rsi + rax * 4 + (\off*64)]
    kmovw   k1, r10d
    kmovw   k2, r10d
    kmovw   k3, r10d
    vpxord  zmm7, zmm7, zmm7
    vpxord  zmm8, zmm8, zmm8
    vpxord  zmm9, zmm9, zmm9
    vgatherdps zmm7{k1}, [rdi + zmm1 * 4]
    vgatherdps zmm8{k2}, [r8  + zmm1 * 4]
    vgatherdps zmm9{k3}, [r9  + zmm1 * 4]
#ifdef TEST
    vmovups [rcx + rax * 4 + (\off*64)], zmm7
    vmovups [r11 + rax * 4 + (\off*64)], zmm8
    vmovups [r12 + rax * 4 + (\off*64)], zmm9
#endif
.elseif \slot == 2
    vmovdqu32 zmm2, ZMMWORD PTR [rsi + rax * 4 + (\off*64)]
    kmovw   k1, r10d
    kmovw   k2, r10d
    kmovw   k3, r10d
    vpxord  zmm10, zmm10, zmm10
    vpxord  zmm11, zmm11, zmm11
    vpxord  zmm12, zmm12, zmm12
    vgatherdps zmm10{k1}, [rdi + zmm2 * 4]
    vgatherdps zmm11{k2}, [r8  + zmm2 * 4]
    vgatherdps zmm12{k3}, [r9  + zmm2 * 4]
#ifdef TEST
    vmovups [rcx + rax * 4 + (\off*64)], zmm10
    vmovups [r11 + rax * 4 + (\off*64)], zmm11
    vmovups [r12 + rax * 4 + (\off*64)], zmm12
#endif
.else
    vmovdqu32 zmm3, ZMMWORD PTR [rsi + rax * 4 + (\off*64)]
    kmovw   k1, r10d
    kmovw   k2, r10d
    kmovw   k3, r10d
    vpxord  zmm13, zmm13, zmm13
    vpxord  zmm14, zmm14, zmm14
    vpxord  zmm15, zmm15, zmm15
    vgatherdps zmm13{k1}, [rdi + zmm3 * 4]
    vgatherdps zmm14{k2}, [r8  + zmm3 * 4]
    vgatherdps zmm15{k3}, [r9  + zmm3 * 4]
#ifdef TEST
    vmovups [rcx + rax * 4 + (\off*64)], zmm13
    vmovups [r11 + rax * 4 + (\off*64)], zmm14
    vmovups [r12 + rax * 4 + (\off*64)], zmm15
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

mov r9d, r9d
mov r10d, -1
bzhi r10d, r10d, r9d

lea r8, [rdi + rdx * 4]       # &a[1*N] (y component base, float stride)
lea r9, [r8 + rdx * 4]        # &a[2*N] (z component base); r9 (active_lanes) is free now
#ifdef TEST
lea r11, [rcx + rdx * 4]      # &t[N]
lea r12, [r11 + rdx * 4]      # &t[2*N]
#endif

xor   rax, rax
.align 16
1:
counter = 0
.rept UNROLL
    slot = counter % 4
    off = counter
    GATHER_SOA512_SP_ONE %slot, %off
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
.size gather_soa_sp, .-gather_soa_sp
