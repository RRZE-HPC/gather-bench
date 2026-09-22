.intel_syntax noprefix
.altmacro

#ifndef UNROLL
#define UNROLL 4
#endif

.data
.align 64
SCALAR:
.double 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0

# One VL(=8)-wide masked SoA gather (3 components), cycling through 4
# register slots. r8/r9 hold the precomputed y/z component bases into a;
# r11/r12 hold the same for t (TEST only). k1/k2/k3 are rebuilt (via kmovw
# from r10d) before every gather since AVX-512 gather clears consumed mask bits.
.macro GATHER_SOA512_ONE slot, off
.if \slot == 0
    vmovdqu ymm0, YMMWORD PTR [rsi + rax * 4 + (\off*32)]
    kmovw   k1, r10d
    kmovw   k2, r10d
    kmovw   k3, r10d
    vpxord  zmm4, zmm4, zmm4
    vpxord  zmm5, zmm5, zmm5
    vpxord  zmm6, zmm6, zmm6
    vgatherdpd zmm4{k1}, [rdi + ymm0 * 8]
    vgatherdpd zmm5{k2}, [r8  + ymm0 * 8]
    vgatherdpd zmm6{k3}, [r9  + ymm0 * 8]
#ifdef TEST
    vmovupd [rcx + rax * 8 + (\off*64)], zmm4
    vmovupd [r11 + rax * 8 + (\off*64)], zmm5
    vmovupd [r12 + rax * 8 + (\off*64)], zmm6
#endif
.elseif \slot == 1
    vmovdqu ymm1, YMMWORD PTR [rsi + rax * 4 + (\off*32)]
    kmovw   k1, r10d
    kmovw   k2, r10d
    kmovw   k3, r10d
    vpxord  zmm7, zmm7, zmm7
    vpxord  zmm8, zmm8, zmm8
    vpxord  zmm9, zmm9, zmm9
    vgatherdpd zmm7{k1}, [rdi + ymm1 * 8]
    vgatherdpd zmm8{k2}, [r8  + ymm1 * 8]
    vgatherdpd zmm9{k3}, [r9  + ymm1 * 8]
#ifdef TEST
    vmovupd [rcx + rax * 8 + (\off*64)], zmm7
    vmovupd [r11 + rax * 8 + (\off*64)], zmm8
    vmovupd [r12 + rax * 8 + (\off*64)], zmm9
#endif
.elseif \slot == 2
    vmovdqu ymm2, YMMWORD PTR [rsi + rax * 4 + (\off*32)]
    kmovw   k1, r10d
    kmovw   k2, r10d
    kmovw   k3, r10d
    vpxord  zmm10, zmm10, zmm10
    vpxord  zmm11, zmm11, zmm11
    vpxord  zmm12, zmm12, zmm12
    vgatherdpd zmm10{k1}, [rdi + ymm2 * 8]
    vgatherdpd zmm11{k2}, [r8  + ymm2 * 8]
    vgatherdpd zmm12{k3}, [r9  + ymm2 * 8]
#ifdef TEST
    vmovupd [rcx + rax * 8 + (\off*64)], zmm10
    vmovupd [r11 + rax * 8 + (\off*64)], zmm11
    vmovupd [r12 + rax * 8 + (\off*64)], zmm12
#endif
.else
    vmovdqu ymm3, YMMWORD PTR [rsi + rax * 4 + (\off*32)]
    kmovw   k1, r10d
    kmovw   k2, r10d
    kmovw   k3, r10d
    vpxord  zmm13, zmm13, zmm13
    vpxord  zmm14, zmm14, zmm14
    vpxord  zmm15, zmm15, zmm15
    vgatherdpd zmm13{k1}, [rdi + ymm3 * 8]
    vgatherdpd zmm14{k2}, [r8  + ymm3 * 8]
    vgatherdpd zmm15{k3}, [r9  + ymm3 * 8]
#ifdef TEST
    vmovupd [rcx + rax * 8 + (\off*64)], zmm13
    vmovupd [r11 + rax * 8 + (\off*64)], zmm14
    vmovupd [r12 + rax * 8 + (\off*64)], zmm15
#endif
.endif
.endm

# rdi -> a
# rsi -> idx
# rdx -> N
# rcx -> t (only written if TEST)
# r8  -> cycles (unused by this kernel)
# r9d -> active_lanes (1..8): first `active_lanes` of every 8-wide gather group are gathered
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

mov r9d, r9d                # zero-extend active_lanes into r9
mov r10d, -1
bzhi r10d, r10d, r9d          # r10d = (1 << active_lanes) - 1, the mask template value

lea r8, [rdi + rdx * 8]       # &a[1*N] (y component base)
lea r9, [r8 + rdx * 8]        # &a[2*N] (z component base); r9 (active_lanes) is free now
#ifdef TEST
lea r11, [rcx + rdx * 8]      # &t[N]
lea r12, [r11 + rdx * 8]      # &t[2*N]
#endif

xor   rax, rax
.align 16
1:
counter = 0
.rept UNROLL
    slot = counter % 4
    off = counter
    GATHER_SOA512_ONE %slot, %off
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
.size gather_soa_dp, .-gather_soa_dp
