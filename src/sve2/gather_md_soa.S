.arch armv8-a+sve2
.text
.global gather_md_soa
.type gather_md_soa, %function

// UNVERIFIED: no SVE hardware or cross-compiler was available to build/run this.
// See gather_md_aos.S for the whilelt-based looping idiom this mirrors.
//
// x0 -> a (double*, SoA planar layout, component d at a[d*n + i])
// x1 -> neighbors
// w2 -> numneighs[i]
// x3 -> &t[t_idx]
// w4 -> ntest
// w5 -> n (elements per component, i.e. the stride between components)
gather_md_soa:
    mov     w2, w2              // zero-extend numneighs[i] into x2
    mov     w4, w4              // zero-extend ntest into x4
    mov     w5, w5              // zero-extend n into x5
    add     x6, x0, x5, lsl #3  // &a[1*n]  (y component base)
    add     x7, x6, x5, lsl #3  // &a[2*n]  (z component base)
    mov     x9, #0
.align 4
1:
    whilelt p0.d, x9, x2
    b.none  2f

    ld1sw   {z3.d}, p0/z, [x1, x9, lsl #2]   // neighbors[i..i+VL-1], widened to 64-bit
    ld1d    {z0.d}, p0/z, [x0, z3.d, lsl #3]
#ifndef ONLY_FIRST_DIMENSION
    ld1d    {z1.d}, p0/z, [x6, z3.d, lsl #3]
    ld1d    {z2.d}, p0/z, [x7, z3.d, lsl #3]
#endif

#ifdef TEST
    st1d    {z0.d}, p0, [x3, x9, lsl #3]
    add     x10, x3, x4, lsl #3              // &t[ntest]
#ifndef ONLY_FIRST_DIMENSION
    st1d    {z1.d}, p0, [x10, x9, lsl #3]
    add     x11, x10, x4, lsl #3             // &t[2*ntest]
    st1d    {z2.d}, p0, [x11, x9, lsl #3]
#endif
#endif

    incd    x9
    b       1b

2:
    mov     w0, w2                           // return numneighs[i] (matches x86 ABI convention)
    ret
.size gather_md_soa, .-gather_md_soa
