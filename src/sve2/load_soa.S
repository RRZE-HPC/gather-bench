.arch armv8-a+sve2
.text
.global load_soa
.type load_soa, %function

// UNVERIFIED: no SVE hardware or cross-compiler was available to build/run this.
//
// x0 -> a (double*, SoA planar layout, component d at a[d*n + i])
// w1 -> i (atom index)
// w2 -> n (elements per component, i.e. the stride between components)
load_soa:
    mov     w1, w1              // zero-extend i
    mov     w2, w2              // zero-extend n
    add     x4, x0, x1, lsl #3  // &a[i]
    add     x6, x4, x2, lsl #3  // &a[n+i]
    add     x7, x6, x2, lsl #3  // &a[2n+i]
    ptrue   p0.d, all
    ld1rd   {z3.d}, p0/z, [x4]
    ld1rd   {z4.d}, p0/z, [x6]
    ld1rd   {z5.d}, p0/z, [x7]
    ret
.size load_soa, .-load_soa
