/*
 * Intrinsics-based gather kernel (KERNEL=intrinsic).
 *
 * Unlike the hand-written per-ISA assembly kernels (src/avx2, src/avx512,
 * src/sve), this is a single portable C++ source compiled once per ISA via
 * -DISA_avx2 / -DISA_avx512 / -DISA_sve. It exists as a second, independently
 * selectable kernel implementation (KERNEL=asm vs. KERNEL=intrinsic) so the
 * two can be compared, and it is the only kernel that supports:
 *   - DATA_TYPE=SP (single precision), via -DDATA_TYPE_SP
 *   - a configurable unroll factor, via -DUNROLL=<1|2|4|8>
 *   - masked gathers: the `active_lanes` parameter (1..VL) enables only the
 *     first `active_lanes` lanes of each VL-wide gather, using each ISA's
 *     native masked-gather support (AVX-512 k-registers, AVX2's vector gather
 *     mask, SVE predicates), built once outside the hot loop.
 *
 * Duplicate-index generation (--unique) is a data-generation concern, not a
 * kernel concern, so it needs no support here - it works with this kernel
 * unchanged, same as with the asm kernels.
 *
 * SVE path is UNVERIFIED: no SVE hardware or cross-compiler was available to
 * build/run it.
 */
#include <cstddef>
#include <cstdint>

#if defined(ISA_avx2) || defined(ISA_avx512)
#include <immintrin.h>
#elif defined(ISA_sve)
#include <arm_sve.h>
#endif

#if !defined(ISA_avx2) && !defined(ISA_avx512) && !defined(ISA_sve)
#error "Invalid ISA macro, possible values are: avx2, avx512 and sve"
#endif

#if defined(DATA_TYPE_SP)
typedef float real_t;
#else
typedef double real_t;
#endif

#ifndef UNROLL
#define UNROLL 4
#endif

// ---------------------------------------------------------------------------
// AVX2 / AVX-512: vector length, mask construction and masked gather, per T.
// ---------------------------------------------------------------------------
#if defined(ISA_avx2) || defined(ISA_avx512)

template <typename T> struct vec_traits;

#if defined(ISA_avx512)
template <> struct vec_traits<double> {
    static constexpr int VL = 8;
    using vidx_t = __m256i;
    using mask_t = __mmask8;
    using acc_t  = __m512d;
    static vidx_t load_idx(const int* p) { return _mm256_loadu_si256((const __m256i*)p); }
    static vidx_t mul_dims(vidx_t v, int dims) {
        return (dims == 1) ? v : _mm256_add_epi32(v, _mm256_add_epi32(v, v));
    }
    static mask_t make_mask(int active) { return (mask_t)((1u << active) - 1); }
    static __m512d gather(const double* base, vidx_t vidx, mask_t mask) {
        return _mm512_mask_i32gather_pd(_mm512_setzero_pd(), mask, vidx, base, 8);
    }
    static acc_t zero_acc() { return _mm512_setzero_pd(); }
    static acc_t add_acc(acc_t a, __m512d v) { return _mm512_add_pd(a, v); }
    static double hsum(acc_t a) { return _mm512_reduce_add_pd(a); }
    static void store(double* t, __m512d v) { _mm512_storeu_pd(t, v); }
};
template <> struct vec_traits<float> {
    static constexpr int VL = 16;
    using vidx_t = __m512i;
    using mask_t = __mmask16;
    using acc_t  = __m512;
    static vidx_t load_idx(const int* p) { return _mm512_loadu_si512((const void*)p); }
    static vidx_t mul_dims(vidx_t v, int dims) {
        return (dims == 1) ? v : _mm512_add_epi32(v, _mm512_add_epi32(v, v));
    }
    static mask_t make_mask(int active) { return (mask_t)((1u << active) - 1); }
    static __m512 gather(const float* base, vidx_t vidx, mask_t mask) {
        return _mm512_mask_i32gather_ps(_mm512_setzero_ps(), mask, vidx, base, 4);
    }
    static acc_t zero_acc() { return _mm512_setzero_ps(); }
    static acc_t add_acc(acc_t a, __m512 v) { return _mm512_add_ps(a, v); }
    static float hsum(acc_t a) { return _mm512_reduce_add_ps(a); }
    static void store(float* t, __m512 v) { _mm512_storeu_ps(t, v); }
};
#else // ISA_avx2
template <> struct vec_traits<double> {
    static constexpr int VL = 4;
    using vidx_t = __m128i;
    using mask_t = __m256d;
    using acc_t  = __m256d;
    static vidx_t load_idx(const int* p) { return _mm_loadu_si128((const __m128i*)p); }
    static vidx_t mul_dims(vidx_t v, int dims) {
        return (dims == 1) ? v : _mm_add_epi32(v, _mm_add_epi32(v, v));
    }
    static mask_t make_mask(int active) {
        __m256i iota = _mm256_set_epi64x(3, 2, 1, 0);
        __m256i k = _mm256_set1_epi64x(active);
        return _mm256_castsi256_pd(_mm256_cmpgt_epi64(k, iota));
    }
    static __m256d gather(const double* base, vidx_t vidx, mask_t mask) {
        return _mm256_mask_i32gather_pd(_mm256_setzero_pd(), base, vidx, mask, 8);
    }
    static acc_t zero_acc() { return _mm256_setzero_pd(); }
    static acc_t add_acc(acc_t a, __m256d v) { return _mm256_add_pd(a, v); }
    static double hsum(acc_t a) {
        __m128d lo = _mm256_castpd256_pd128(a);
        __m128d hi = _mm256_extractf128_pd(a, 1);
        __m128d s = _mm_add_pd(lo, hi);
        __m128d h = _mm_unpackhi_pd(s, s);
        return _mm_cvtsd_f64(_mm_add_sd(s, h));
    }
    static void store(double* t, __m256d v) { _mm256_storeu_pd(t, v); }
};
template <> struct vec_traits<float> {
    static constexpr int VL = 8;
    using vidx_t = __m256i;
    using mask_t = __m256;
    using acc_t  = __m256;
    static vidx_t load_idx(const int* p) { return _mm256_loadu_si256((const __m256i*)p); }
    static vidx_t mul_dims(vidx_t v, int dims) {
        return (dims == 1) ? v : _mm256_add_epi32(v, _mm256_add_epi32(v, v));
    }
    static mask_t make_mask(int active) {
        __m256i iota = _mm256_setr_epi32(0, 1, 2, 3, 4, 5, 6, 7);
        __m256i k = _mm256_set1_epi32(active);
        return _mm256_castsi256_ps(_mm256_cmpgt_epi32(k, iota));
    }
    static __m256 gather(const float* base, vidx_t vidx, mask_t mask) {
        return _mm256_mask_i32gather_ps(_mm256_setzero_ps(), base, vidx, mask, 4);
    }
    static acc_t zero_acc() { return _mm256_setzero_ps(); }
    static acc_t add_acc(acc_t a, __m256 v) { return _mm256_add_ps(a, v); }
    static float hsum(acc_t a) {
        __m128 lo = _mm256_castps256_ps128(a);
        __m128 hi = _mm256_extractf128_ps(a, 1);
        __m128 s = _mm_add_ps(lo, hi);
        s = _mm_add_ps(s, _mm_movehl_ps(s, s));
        s = _mm_add_ss(s, _mm_shuffle_ps(s, s, 1));
        return _mm_cvtss_f32(s);
    }
    static void store(float* t, __m256 v) { _mm256_storeu_ps(t, v); }
};
#endif

template <typename T, int DIMS, bool IS_AOS>
static void gather_core(const T* a, const int* idx, int N, T* t, int active_lanes) {
    using VT = vec_traits<T>;
    constexpr int VL = VT::VL;
    const typename VT::mask_t mask = VT::make_mask(active_lanes);
    typename VT::acc_t acc = VT::zero_acc();

    // UNROLL and DIMS are compile-time constants (small, <=8), so -Ofast's
    // optimizer fully unrolls both loops on its own; GCC's #pragma GCC unroll
    // does not macro-expand its argument, so it can't take UNROLL/DIMS directly.
    for (int i = 0; i < N; i += VL * UNROLL) {
        for (int u = 0; u < UNROLL; ++u) {
            const int base_i = i + u * VL;
            const typename VT::vidx_t vidx_raw = VT::load_idx(&idx[base_i]);
            for (int d = 0; d < DIMS; ++d) {
                const T* base = IS_AOS ? (a + d) : (a + (size_t)d * N);
                const typename VT::vidx_t vidx = IS_AOS ? VT::mul_dims(vidx_raw, DIMS) : vidx_raw;
                const auto v = VT::gather(base, vidx, mask);
                acc = VT::add_acc(acc, v);
#ifdef TEST
                if (base_i < N) VT::store(&t[(size_t)d * N + base_i], v);
#endif
            }
        }
    }

    // Prevent the compiler from eliminating the gather loop as dead code;
    // `sum` is never actually -1, so this store never fires at runtime.
    const T sum = VT::hsum(acc);
    if (sum == (T)(-1.0) && t != nullptr) { t[0] = sum; }
}

// ---------------------------------------------------------------------------
// SVE: UNVERIFIED - no SVE hardware or cross-compiler was available here.
// ---------------------------------------------------------------------------
#elif defined(ISA_sve)

template <typename T> struct vec_traits;

template <> struct vec_traits<double> {
    static svbool_t make_mask(int active) { return svwhilelt_b64(0, active); }
    static svint64_t load_idx(svbool_t p, const int* q) { return svld1sw_s64(p, q); }
    static svint64_t mul_dims(svbool_t p, svint64_t v, int dims) {
        return (dims == 1) ? v : svmad_n_s64_x(p, v, 2, v);
    }
    static svfloat64_t gather(svbool_t p, const double* base, svint64_t vidx) {
        return svld1_gather_index_f64(p, base, vidx);
    }
    static double hsum(svbool_t p, svfloat64_t acc) { return svaddv_f64(p, acc); }
};
template <> struct vec_traits<float> {
    static svbool_t make_mask(int active) { return svwhilelt_b32(0, active); }
    static svint32_t load_idx(svbool_t p, const int* q) { return svld1_s32(p, q); }
    static svint32_t mul_dims(svbool_t p, svint32_t v, int dims) {
        return (dims == 1) ? v : svmad_n_s32_x(p, v, 2, v);
    }
    static svfloat32_t gather(svbool_t p, const float* base, svint32_t vidx) {
        return svld1_gather_index_f32(p, base, vidx);
    }
    static float hsum(svbool_t p, svfloat32_t acc) { return svaddv_f32(p, acc); }
};

template <typename T, int DIMS, bool IS_AOS>
static void gather_core(const T* a, const int* idx, int N, T* t, int active_lanes) {
    using VT = vec_traits<T>;
    const svbool_t mask = VT::make_mask(active_lanes);
    auto acc = svdup_n<T>(T(0)); // NOTE: relies on ACLE overload resolution by T

    for (int i = 0; i < N; i += (int)svcntw()) {
        const svbool_t all = svwhilelt_b32(0, N - i); // conservative full-VL iteration predicate
        const auto vidx_raw = VT::load_idx(all, &idx[i]);
        for (int d = 0; d < DIMS; ++d) {
            const T* base = IS_AOS ? (a + d) : (a + (size_t)d * N);
            const auto vidx = IS_AOS ? VT::mul_dims(all, vidx_raw, DIMS) : vidx_raw;
            const auto v = VT::gather(mask, base, vidx);
            acc = svadd_x(all, acc, v);
#ifdef TEST
            svst1(all, &t[(size_t)d * N + i], v);
#endif
        }
    }

    const T sum = VT::hsum(svptrue_b32(), acc);
    if (sum == (T)(-1.0) && t != nullptr) { t[0] = sum; }
}

#endif // ISA dispatch

// ---------------------------------------------------------------------------
// Exported entry points (matching the asm kernels' naming, plus a mask arg).
// ---------------------------------------------------------------------------
extern "C" void gather_intrinsic(real_t* a, int* idx, int N, real_t* t, int active_lanes) {
    gather_core<real_t, 1, true>(a, idx, N, t, active_lanes);
}
extern "C" void gather_aos_intrinsic(real_t* a, int* idx, int N, real_t* t, int active_lanes) {
    gather_core<real_t, 3, true>(a, idx, N, t, active_lanes);
}
extern "C" void gather_soa_intrinsic(real_t* a, int* idx, int N, real_t* t, int active_lanes) {
    gather_core<real_t, 3, false>(a, idx, N, t, active_lanes);
}
