.arch armv8-a+sve2
.text
.global gather
.type gather, %function

// x0 -> a (double*)
// x1 -> idx (int*)
// w2 -> N
// x3 -> t (double*, only used if TEST)
gather:
    mov     w2, w2              // zero-extend N into x2
    ptrue   p0.d, all
    mov     x9, #0
.align 4
1:
    ld1sw   {z1.d}, p0/z, [x1, x9, lsl #2]
    ld1d    {z0.d}, p0/z, [x0, z1.d, lsl #3]

#ifdef TEST
    st1d    {z0.d}, p0, [x3, x9, lsl #3]
#endif

    incd    x9
    cmp     x9, x2
    b.lt    1b
    ret
.size gather, .-gather
