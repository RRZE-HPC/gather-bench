.arch armv8-a+sve2
.text
.global gather_sp
.type gather_sp, %function

// UNVERIFIED: no SVE hardware or cross-compiler was available to build/run this.
//
// x0 -> a (float*)
// x1 -> idx (int*)
// w2 -> N
// x3 -> t (float*, only written if TEST)
// w4 -> active_lanes: first `active_lanes` (of the hardware's native vector
//       width) elements of every gather are gathered
gather_sp:
    mov     w2, w2              // zero-extend N into x2
    mov     w4, w4              // zero-extend active_lanes into x4
    whilelt p0.s, xzr, x4       // p0 = first active_lanes lanes active
    mov     x9, #0
.align 4
1:
    ld1w    {z1.s}, p0/z, [x1, x9, lsl #2]
    ld1w    {z0.s}, p0/z, [x0, z1.s, sxtw #2]

#ifdef TEST
    st1w    {z0.s}, p0, [x3, x9, lsl #2]
#endif

    incw    x9
    cmp     x9, x2
    b.lt    1b
    ret
.size gather_sp, .-gather_sp
