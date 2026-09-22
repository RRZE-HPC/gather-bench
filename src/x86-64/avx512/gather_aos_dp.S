.intel_syntax noprefix
.altmacro

#ifndef UNROLL
#define UNROLL 4
#endif

.data
.align 64
SCALAR:
.double 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0

#ifndef MEASURE_GATHER_CYCLES
# One VL(=8)-wide masked AoS gather (3 components), cycling through 4
# register slots (AVX-512 has 32 vector registers, so no register-pressure
# constraint like AVX2). ymm31 is transient scratch for the idx*dims
# multiply. k1/k2/k3 are rebuilt (cheaply, via kmovw from r10d) before every
# gather since AVX-512 gather clears the mask bits it consumes.
.macro GATHER_AOS512_ONE slot, off
.if \slot == 0
    vmovdqu ymm0, YMMWORD PTR [rsi + rax * 4 + (\off*32)]
    vpaddd  ymm31, ymm0, ymm0
#ifdef PADDING
    vpaddd  ymm0, ymm31, ymm31
#else
    vpaddd  ymm0, ymm0, ymm31
#endif
    kmovw   k1, r10d
    vpxord  zmm4, zmm4, zmm4
    vgatherdpd zmm4{k1}, [rdi + ymm0 * 8]
#ifndef ONLY_FIRST_DIMENSION
    kmovw   k2, r10d
    kmovw   k3, r10d
    vpxord  zmm5, zmm5, zmm5
    vpxord  zmm6, zmm6, zmm6
    vgatherdpd zmm5{k2}, [8  + rdi + ymm0 * 8]
    vgatherdpd zmm6{k3}, [16 + rdi + ymm0 * 8]
#endif
#ifdef TEST
    vmovupd [rcx + rax * 8 + (\off*64)], zmm4
#ifndef ONLY_FIRST_DIMENSION
    vmovupd [r11 + rax * 8 + (\off*64)], zmm5
    vmovupd [r9  + rax * 8 + (\off*64)], zmm6
#endif
#endif
.elseif \slot == 1
    vmovdqu ymm1, YMMWORD PTR [rsi + rax * 4 + (\off*32)]
    vpaddd  ymm31, ymm1, ymm1
#ifdef PADDING
    vpaddd  ymm1, ymm31, ymm31
#else
    vpaddd  ymm1, ymm1, ymm31
#endif
    kmovw   k1, r10d
    vpxord  zmm7, zmm7, zmm7
    vgatherdpd zmm7{k1}, [rdi + ymm1 * 8]
#ifndef ONLY_FIRST_DIMENSION
    kmovw   k2, r10d
    kmovw   k3, r10d
    vpxord  zmm8, zmm8, zmm8
    vpxord  zmm9, zmm9, zmm9
    vgatherdpd zmm8{k2}, [8  + rdi + ymm1 * 8]
    vgatherdpd zmm9{k3}, [16 + rdi + ymm1 * 8]
#endif
#ifdef TEST
    vmovupd [rcx + rax * 8 + (\off*64)], zmm7
#ifndef ONLY_FIRST_DIMENSION
    vmovupd [r11 + rax * 8 + (\off*64)], zmm8
    vmovupd [r9  + rax * 8 + (\off*64)], zmm9
#endif
#endif
.elseif \slot == 2
    vmovdqu ymm2, YMMWORD PTR [rsi + rax * 4 + (\off*32)]
    vpaddd  ymm31, ymm2, ymm2
#ifdef PADDING
    vpaddd  ymm2, ymm31, ymm31
#else
    vpaddd  ymm2, ymm2, ymm31
#endif
    kmovw   k1, r10d
    vpxord  zmm10, zmm10, zmm10
    vgatherdpd zmm10{k1}, [rdi + ymm2 * 8]
#ifndef ONLY_FIRST_DIMENSION
    kmovw   k2, r10d
    kmovw   k3, r10d
    vpxord  zmm11, zmm11, zmm11
    vpxord  zmm12, zmm12, zmm12
    vgatherdpd zmm11{k2}, [8  + rdi + ymm2 * 8]
    vgatherdpd zmm12{k3}, [16 + rdi + ymm2 * 8]
#endif
#ifdef TEST
    vmovupd [rcx + rax * 8 + (\off*64)], zmm10
#ifndef ONLY_FIRST_DIMENSION
    vmovupd [r11 + rax * 8 + (\off*64)], zmm11
    vmovupd [r9  + rax * 8 + (\off*64)], zmm12
#endif
#endif
.else
    vmovdqu ymm3, YMMWORD PTR [rsi + rax * 4 + (\off*32)]
    vpaddd  ymm31, ymm3, ymm3
#ifdef PADDING
    vpaddd  ymm3, ymm31, ymm31
#else
    vpaddd  ymm3, ymm3, ymm31
#endif
    kmovw   k1, r10d
    vpxord  zmm13, zmm13, zmm13
    vgatherdpd zmm13{k1}, [rdi + ymm3 * 8]
#ifndef ONLY_FIRST_DIMENSION
    kmovw   k2, r10d
    kmovw   k3, r10d
    vpxord  zmm14, zmm14, zmm14
    vpxord  zmm15, zmm15, zmm15
    vgatherdpd zmm14{k2}, [8  + rdi + ymm3 * 8]
    vgatherdpd zmm15{k3}, [16 + rdi + ymm3 * 8]
#endif
#ifdef TEST
    vmovupd [rcx + rax * 8 + (\off*64)], zmm13
#ifndef ONLY_FIRST_DIMENSION
    vmovupd [r11 + rax * 8 + (\off*64)], zmm14
    vmovupd [r9  + rax * 8 + (\off*64)], zmm15
#endif
#endif
.endif
.endm
#endif // !MEASURE_GATHER_CYCLES

# rdi -> a
# rsi -> idx
# rdx -> N
# rcx -> t (only written if TEST)
# r8  -> cycles (only used if MEASURE_GATHER_CYCLES)
# r9d -> active_lanes (1..8): first `active_lanes` of every 8-wide gather group are gathered
#        (ignored by the MEASURE_GATHER_CYCLES path, which always uses the full mask)
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

#ifndef MEASURE_GATHER_CYCLES
mov r9d, r9d               # zero-extend active_lanes into r9
mov r10d, -1
bzhi r10d, r10d, r9d        # r10d = (1 << active_lanes) - 1, the mask template value

#ifdef TEST
lea r11, [rcx + rdx * 8]   # &t[N]   (y component base)
lea r9,  [r11 + rdx * 8]   # &t[2*N] (z component base); r9 (active_lanes) is free now
#endif

xor   rax, rax
.align 16
1:
counter = 0
.rept UNROLL
    slot = counter % 4
    off = counter
    GATHER_AOS512_ONE %slot, %off
    counter = counter + 1
.endr

addq rax, (8 * UNROLL)
cmpq rax, rdx
jl 1b

#else // MEASURE_GATHER_CYCLES: unchanged single-chunk-per-iteration path, always full mask

xor   rax, rax
.align 16
2:

vmovdqu ymm3, YMMWORD PTR [rsi + rax * 4]
vpaddd ymm4, ymm3, ymm3
#ifdef PADDING
vpaddd ymm3, ymm4, ymm4
#else
vpaddd ymm3, ymm3, ymm4
#endif

vpcmpeqb k1, xmm5, xmm5
#ifndef ONLY_FIRST_DIMENSION
vpcmpeqb k2, xmm5, xmm5
vpcmpeqb k3, xmm5, xmm5
#endif

vpxord zmm0, zmm0, zmm0
#ifndef ONLY_FIRST_DIMENSION
vpxord zmm1, zmm1, zmm1
vpxord zmm2, zmm2, zmm2
#endif

mov r9, rax
mov r10, rdx
xor r11, r11
add r11, rax
add r11, rax
add r11, rax

xor rbx, rbx
lfence
rdtsc
add ebx, eax
vgatherdpd zmm0{k1}, [rdi + ymm3 * 8]
lfence
rdtsc
sub eax, ebx
movnti [r8 + r11], rax

#ifndef ONLY_FIRST_DIMENSION
xor rbx, rbx
lfence
rdtsc
add ebx, eax
vgatherdpd zmm1{k2}, [8 + rdi + ymm3 * 8]
lfence
rdtsc
sub eax, ebx
movnti [8 + r8 + r11], rax

xor rbx, rbx
lfence
rdtsc
add ebx, eax
vgatherdpd zmm2{k3}, [16 + rdi + ymm3 * 8]
lfence
rdtsc
sub eax, ebx
movnti [16 + r8 + r11], rax
#endif // ONLY_FIRST_DIMENSION

mov rax, r9
mov rdx, r10

#ifdef TEST
vmovupd  [rcx + rax * 8], zmm0
lea rbx, [rcx + rdx * 8]
vmovupd  [rbx + rax * 8], zmm1
lea r9,  [rbx + rdx * 8]
vmovupd  [r9  + rax * 8], zmm2
#endif

addq rax, 8
cmpq rax, rdx
jl 2b

#endif // MEASURE_GATHER_CYCLES

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
