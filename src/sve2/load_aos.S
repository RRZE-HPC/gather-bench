.arch armv8-a+sve2
.text
.global load_aos
.type load_aos, %function

// UNVERIFIED: no SVE hardware or cross-compiler was available to build/run this.
//
// x0 -> &a[i * snbytes]
load_aos:
    ptrue   p0.d, all
    ld1rd   {z3.d}, p0/z, [x0]
    ld1rd   {z4.d}, p0/z, [x0, #8]
    ld1rd   {z5.d}, p0/z, [x0, #16]
    ret
.size load_aos, .-load_aos
