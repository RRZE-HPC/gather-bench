.arch armv8-a+sve2
.text
.global gather_aos
.type gather_aos, %function

// x0 -> a (double*), AoS layout, dims doubles per element (+1 if PADDING)
// x1 -> idx (int*)
// w2 -> N
// x3 -> t (double*, only used if TEST; planar t[d*N+i] layout)
// x4 -> cycles (unused, no per-gather cycle counting on this ISA)
gather_aos:
    mov     w2, w2              // zero-extend N into x2
    ptrue   p0.d, all
    mov     x9, #0
.align 4
1:
    ld1sw   {z3.d}, p0/z, [x1, x9, lsl #2]   // idx[i..i+VL-1], widened to 64-bit
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
    add     x10, x3, x2, lsl #3              // &t[N]
#ifndef ONLY_FIRST_DIMENSION
    st1d    {z1.d}, p0, [x10, x9, lsl #3]
    add     x11, x10, x2, lsl #3             // &t[2*N]
    st1d    {z2.d}, p0, [x11, x9, lsl #3]
#endif
#endif

    incd    x9
    cmp     x9, x2
    b.lt    1b
    ret
.size gather_aos, .-gather_aos
