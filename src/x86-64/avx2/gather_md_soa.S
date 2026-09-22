.intel_syntax noprefix
.data
.align 32
SCALAR:
.double 1.0, 1.0, 1.0, 1.0

.section .rodata, "a"
.align 16
.iota_mask_soa:
	.long	0,1,2,3
	.type	.iota_mask_soa,@object
	.size	.iota_mask_soa,16

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

mov r14, r9                     # save n (r9 is caller-saved, reused below as scratch)
lea r12, [rdi + r14 * 8]        # &a[1*n]  (y component base)
lea r13, [r12 + r14 * 8]        # &a[2*n]  (z component base)

vmovdqu xmm9, XMMWORD PTR .iota_mask_soa[rip]
vpcmpeqd ymm8, ymm8, ymm8
mov r15, rdx
xor rax, rax
cmpq r15, 4
jl .remainder_only
.align 16
1:

vmovups xmm3, XMMWORD PTR [rsi + rax * 4]

vmovdqa ymm5, ymm8
#ifndef ONLY_FIRST_DIMENSION
vmovdqa ymm6, ymm8
vmovdqa ymm7, ymm8
#endif
vxorpd ymm0, ymm0, ymm0
#ifndef ONLY_FIRST_DIMENSION
vxorpd ymm1, ymm1, ymm1
vxorpd ymm2, ymm2, ymm2
#endif
vgatherdpd ymm0, [rdi + xmm3 * 8], ymm5
#ifndef ONLY_FIRST_DIMENSION
vgatherdpd ymm1, [r12 + xmm3 * 8], ymm6
vgatherdpd ymm2, [r13 + xmm3 * 8], ymm7
#endif

#ifdef TEST
vmovupd  [rcx + rax * 8], ymm0
lea rbx, [rcx + r8  * 8]
vmovupd  [rbx + rax * 8], ymm1
lea r10, [rbx + r8  * 8]
vmovupd  [r10 + rax * 8], ymm2
#endif

addq rax, 4
subq r15, 4
cmpq r15, 4
jge 1b

.remainder_only:
cmpq r15, 0
jle .end_func

vmovd xmm10, r15d
vpbroadcastd xmm10, xmm10
vpcmpgtd xmm10, xmm10, xmm9       # xmm10 = (r15 > iota): first r15 lanes active
vpmaskmovd xmm3, xmm10, XMMWORD PTR [rsi + rax * 4]

vpmovsxdq ymm5, xmm10             # widen 32-bit lane mask to 64-bit lane mask for the double gather
#ifndef ONLY_FIRST_DIMENSION
vmovdqa ymm6, ymm5
vmovdqa ymm7, ymm5
#endif
vxorpd ymm0, ymm0, ymm0
#ifndef ONLY_FIRST_DIMENSION
vxorpd ymm1, ymm1, ymm1
vxorpd ymm2, ymm2, ymm2
#endif
vgatherdpd ymm0, [rdi + xmm3 * 8], ymm5
#ifndef ONLY_FIRST_DIMENSION
vgatherdpd ymm1, [r12 + xmm3 * 8], ymm6
vgatherdpd ymm2, [r13 + xmm3 * 8], ymm7
#endif

#ifdef TEST
vmovupd  [rcx + rax * 8], ymm0
lea rbx, [rcx + r8  * 8]
vmovupd  [rbx + rax * 8], ymm1
lea r10, [rbx + r8  * 8]
vmovupd  [r10 + rax * 8], ymm2
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
