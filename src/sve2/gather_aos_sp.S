.arch armv8-a+sve2
.text
.global gather_aos_sp
.type gather_aos_sp, %function

// UNVERIFIED: no SVE hardware or cross-compiler was available to build/run this.
// UNROLL is not honored here; see gather_dp.S for why.
//
// x0 -> a (float*), AoS layout, dims floats per element (+1 if PADDING)
// x1 -> idx (int*)
// w2 -> N
// x3 -> t (float*, only used if TEST; planar t[d*N+i] layout)
// x4 -> cycles (unused, no per-gather cycle counting on this ISA)
// w5 -> active_lanes: first `active_lanes` (of the hardware's native vector
//       width) elements of every gather are gathered
gather_aos_sp:
    mov     w2, w2              // zero-extend N into x2
    mov     w5, w5              // zero-extend active_lanes into x5
    whilelt p0.s, xzr, x5       // p0 = first active_lanes lanes active
    mov     x9, #0
.align 4
1:
    ld1w    {z3.s}, p0/z, [x1, x9, lsl #2]   // idx[i..i+VL-1]
    add     z4.s, z3.s, z3.s                 // z4 = 2*idx
#ifdef PADDING
    add     z3.s, z4.s, z4.s                 // z3 = 4*idx (dims=3 + 1 padding byte)
#else
    add     z3.s, z3.s, z4.s                 // z3 = 3*idx
#endif

    ld1w    {z0.s}, p0/z, [x0, z3.s, sxtw #2] // a[idx*snbytes + 0]  (x component)

#ifndef ONLY_FIRST_DIMENSION
    mov     z5.s, z3.s
    add     z5.s, z5.s, #1                   // idx*snbytes + 1
    mov     z6.s, z3.s
    add     z6.s, z6.s, #2                   // idx*snbytes + 2
    ld1w    {z1.s}, p0/z, [x0, z5.s, sxtw #2] // y component
    ld1w    {z2.s}, p0/z, [x0, z6.s, sxtw #2] // z component
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
.size gather_aos_sp, .-gather_aos_sp
