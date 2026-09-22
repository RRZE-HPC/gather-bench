.arch armv8-a+sve2
.text
.global gather_soa_sp
.type gather_soa_sp, %function

// UNVERIFIED: no SVE hardware or cross-compiler was available to build/run this.
// UNROLL is not honored here; see gather_dp.S for why.
//
// x0 -> a (float*), SoA layout, component d at a[d*N + i]
// x1 -> idx (int*)
// w2 -> N
// x3 -> t (float*, only used if TEST)
// x4 -> cycles (unused by this kernel)
// w5 -> active_lanes: first `active_lanes` (of the hardware's native vector
//       width) elements of every gather are gathered
gather_soa_sp:
    mov     w2, w2              // zero-extend N into x2
    mov     w5, w5              // zero-extend active_lanes into x5
    whilelt p0.s, xzr, x5       // p0 = first active_lanes lanes active
    add     x6, x0, x2, lsl #2  // &a[1*N]
    add     x7, x6, x2, lsl #2  // &a[2*N]
    mov     x9, #0
.align 4
1:
    ld1w    {z3.s}, p0/z, [x1, x9, lsl #2]   // idx[i..i+VL-1]
    ld1w    {z0.s}, p0/z, [x0, z3.s, sxtw #2]

#ifndef ONLY_FIRST_DIMENSION
    ld1w    {z1.s}, p0/z, [x6, z3.s, sxtw #2]
    ld1w    {z2.s}, p0/z, [x7, z3.s, sxtw #2]
#endif

#ifdef TEST
    st1w    {z0.s}, p0, [x3, x9, lsl #2]
    add     x10, x3, x2, lsl #2              // &t[N]
#ifndef ONLY_FIRST_DIMENSION
    st1w    {z1.s}, p0, [x10, x9, lsl #2]
    add     x11, x10, x2, lsl #2             // &t[2*N]
    st1w    {z2.s}, p0, [x11, x9, lsl #2]
#endif
#endif

    incw    x9
    cmp     x9, x2
    b.lt    1b
    ret
.size gather_soa_sp, .-gather_soa_sp
