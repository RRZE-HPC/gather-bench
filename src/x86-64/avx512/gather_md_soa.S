.intel_syntax noprefix
.data
.align 64
SCALAR:
.double 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0

.section .rodata, "a"
.align 64
.align 64
.ymm_reg_mask_soa:
	.long	0x00000000,0x00000001,0x00000002,0x00000003,0x00000004,0x00000005,0x00000006,0x00000007
	.type	.ymm_reg_mask_soa,@object
	.size	.ymm_reg_mask_soa,32
	.align 8

# rdi -> a (double*, SoA planar layout, component d at a[d*n + i])
# rsi -> neighbors
# rdx -> numneighs[i]
# rcx -> &t[t_idx]
# r8  -> ntest
# r9  -> n (elements per component, i.e. the stride between components)
.text
.globl gather_md_soa
.type gather_md_soa, @function
gather_md_soa :
push rbp
mov rbp, rsp
push rbx
push r10
push r11
push r12
push r13
push r14
push r15

mov r14, r9                    # save n (r9 is caller-saved, will be reused below)
lea r12, [rdi + r14 * 8]       # &a[1*n]  (y component base)
lea r13, [r12 + r14 * 8]       # &a[2*n]  (z component base)

vmovdqu ymm7, YMMWORD PTR .ymm_reg_mask_soa[rip]
mov r15, rdx
xor rax, rax
cmpq r15, 8
jl .remainder_only
.align 16
1:

vmovdqu ymm3, YMMWORD PTR [rsi + rax * 4]

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

vgatherdpd zmm0{k1}, [rdi + ymm3 * 8]
#ifndef ONLY_FIRST_DIMENSION
vgatherdpd zmm1{k2}, [r12 + ymm3 * 8]
vgatherdpd zmm2{k3}, [r13 + ymm3 * 8]
#endif

#ifdef TEST
vmovupd  [rcx + rax * 8], zmm0
lea rbx, [rcx + r8  * 8]
vmovupd  [rbx + rax * 8], zmm1
lea r10, [rbx + r8  * 8]
vmovupd  [r10 + rax * 8], zmm2
#endif

addq rax, 8
subq r15, 8
cmpq r15, 8
jge 1b

.remainder_only:
cmpq r15, 0
jle .end_func

vpbroadcastd ymm6, r15d
vpcmpgtd k1, ymm6, ymm7
vmovdqu32 ymm3{k1}{z}, YMMWORD PTR [rsi + rax * 4]

vpxord    zmm0, zmm0, zmm0
#ifndef ONLY_FIRST_DIMENSION
kmovw     k2, k1
kmovw     k3, k1
vpxord    zmm1, zmm1, zmm1
vpxord    zmm2, zmm2, zmm2
#endif

vgatherdpd zmm0{k1}, [rdi + ymm3 * 8]
#ifndef ONLY_FIRST_DIMENSION
vgatherdpd zmm1{k2}, [r12 + ymm3 * 8]
vgatherdpd zmm2{k3}, [r13 + ymm3 * 8]
#endif

#ifdef TEST
vmovupd  [rcx + rax * 8], zmm0
lea rbx, [rcx + r8  * 8]
vmovupd  [rbx + rax * 8], zmm1
lea r10, [rbx + r8  * 8]
vmovupd  [r10  + rax * 8], zmm2
#endif

addq rax, r15

.end_func:
pop r15
pop r14
pop r13
pop r12
pop r11
pop r10
pop rbx
mov  rsp, rbp
pop rbp
ret
.size gather_md_soa, .-gather_md_soa
