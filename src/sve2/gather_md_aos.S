.arch armv8-a+sve2
.text
.global gather_md_aos
.type gather_md_aos, %function

// UNVERIFIED: no SVE hardware or cross-compiler was available to build/run this.
// Unlike the x86 AVX2/AVX-512 ports, this uses SVE's native predicated
// while-loop idiom (whilelt) instead of a separate full-vector loop plus a
// hand-rolled masked remainder tail - whilelt naturally produces an
// all-false predicate once the count is exhausted, terminating the loop.
//
// x0 -> a
// x1 -> neighbors
// w2 -> numneighs[i]
// x3 -> &t[t_idx]
// w4 -> ntest
gather_md_aos:
    mov     w2, w2              // zero-extend numneighs[i] into x2
    mov     w4, w4              // zero-extend ntest into x4
    mov     x9, #0
.align 4
1:
    whilelt p0.d, x9, x2
    b.none  2f

    ld1sw   {z3.d}, p0/z, [x1, x9, lsl #2]   // neighbors[i..i+VL-1], widened to 64-bit
    add     z4.d, z3.d, z3.d                 // z4 = 2*idx
#ifdef PADDING
    add     z3.d, z4.d, z4.d                 // z3 = 4*idx (dims=3 + 1 padding byte)
#else
    add     z3.d, z3.d, z4.d                 // z3 = 3*idx
#endif

    ld1d    {z0.d}, p0/z, [x0, z3.d, lsl #3] // a[idx*snbytes + 0]  (x component)

#ifndef ONLY_FIRST_DIMENSION
    mov     z5.d, z3.d
    add     z5.d, z5.d, #1                   // idx*snbytes + 1
    mov     z6.d, z3.d
    add     z6.d, z6.d, #2                   // idx*snbytes + 2
    ld1d    {z1.d}, p0/z, [x0, z5.d, lsl #3] // y component
    ld1d    {z2.d}, p0/z, [x0, z6.d, lsl #3] // z component
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
.size gather_md_aos, .-gather_md_aos
