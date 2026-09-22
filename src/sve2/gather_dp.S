.arch armv8-a+sve2
.text
.global gather_dp
.type gather_dp, %function

// UNVERIFIED: no SVE hardware or cross-compiler was available to build/run this.
// UNROLL is not honored here: SVE already scales to the hardware's native
// vector width per iteration, so additional software unrolling was judged
// not worth the extra unverifiable risk in this environment.
//
// x0 -> a (double*)
// x1 -> idx (int*)
// w2 -> N
// x3 -> t (double*, only written if TEST)
// w4 -> active_lanes: first `active_lanes` (of the hardware's native vector
//       width) elements of every gather are gathered
gather_dp:
    mov     w2, w2              // zero-extend N into x2
    mov     w4, w4              // zero-extend active_lanes into x4
    whilelt p0.d, xzr, x4       // p0 = first active_lanes lanes active
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
.size gather_dp, .-gather_dp
