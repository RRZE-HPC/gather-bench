/*
 * =======================================================================================
 *
 *      Author:   Jan Eitzinger (je), jan.eitzinger@fau.de
 *      Copyright (c) 2021 RRZE, University Erlangen-Nuremberg
 *
 *      Permission is hereby granted, free of charge, to any person obtaining a copy
 *      of this software and associated documentation files (the "Software"), to deal
 *      in the Software without restriction, including without limitation the rights
 *      to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 *      copies of the Software, and to permit persons to whom the Software is
 *      furnished to do so, subject to the following conditions:
 *
 *      The above copyright notice and this permission notice shall be included in all
 *      copies or substantial portions of the Software.
 *
 *      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *      IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *      FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 *      AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *      LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 *      OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 *      SOFTWARE.
 *
 * =======================================================================================
 */
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <getopt.h>
#include <limits.h>
#include <float.h>
//---
#include <likwid-marker.h>
//---
#include <timing.h>
#include <allocate.h>

#if !defined(ISA_avx2) && !defined (ISA_avx512) && !defined(ISA_sve)
#error "Invalid ISA macro, possible values are: avx2, avx512 and sve"
#endif

#define HLINE "----------------------------------------------------------------------------\n"

#ifndef MIN
#define MIN(x,y) ((x)<(y)?(x):(y))
#endif
#ifndef MAX
#define MAX(x,y) ((x)>(y)?(x):(y))
#endif
#ifndef ABS
#define ABS(a) ((a) >= 0 ? (a) : -(a))
#endif

#define ARRAY_ALIGNMENT  64

#if defined(DATA_TYPE_SP)
typedef float real_t;
#define REAL_STRING "SP"
#else
typedef double real_t;
#define REAL_STRING "DP"
#endif

// Vector length depends on both ISA and DATA_TYPE for both kernel backends.
#if defined(DATA_TYPE_SP)
#if defined(ISA_avx512)
#define _VL_  16
#define ISA_STRING "avx512"
#elif defined(ISA_sve)
#define _VL_  4
#define ISA_STRING "sve"
#else
#define _VL_  8
#define ISA_STRING "avx2"
#endif
#else
#if defined(ISA_avx512)
#define _VL_  8
#define ISA_STRING "avx512"
#elif defined(ISA_sve)
#define _VL_  2
#define ISA_STRING "sve"
#else
#define _VL_  4
#define ISA_STRING "avx2"
#endif
#endif

#ifdef KERNEL_INTRINSIC
extern void gather_intrinsic(real_t*, int*, int, real_t*, int);
#define GATHER(a, idx, n, t, active) gather_intrinsic(a, idx, n, t, active)
#define KERNEL_STRING "intrinsic"
#else
#ifdef DATA_TYPE_SP
extern void gather_sp(real_t*, int*, int, real_t*, int);
#define GATHER(a, idx, n, t, active) gather_sp(a, idx, n, t, active)
#else
extern void gather_dp(real_t*, int*, int, real_t*, int);
#define GATHER(a, idx, n, t, active) gather_dp(a, idx, n, t, active)
#endif
#define KERNEL_STRING "asm"
#endif

static void usage(const char* prog) {
    printf("X86/ARM gather instruction performance benchmark.\n\n");
    printf("Usage: %s -s NUMBER -f REAL [OPTION]...\n\n", prog);
    printf("\t-s, --stride=NUMBER    stride between two successive indices (required).\n");
    printf("\t-f, --freq=REAL        CPU frequency in GHz (required).\n");
    printf("\t-l, --line=NUMBER      cache line size in bytes (default 64).\n");
    printf("\t-u, --unique=NUMBER    number of distinct indices per %d-wide lane group\n", _VL_);
    printf("\t                       (1..%d, default %d = fully distinct/no duplicates).\n", _VL_, _VL_);
    printf("\t-h, --help             display this help message.\n");
}

int main (int argc, char** argv) {
    LIKWID_MARKER_INIT;
    LIKWID_MARKER_REGISTER("gather");

    int stride = 0;
    double freq = 0.0;
    int cl_size = 64;
    int unique = _VL_;
    int have_stride = 0, have_freq = 0;
    int opt;
    struct option long_opts[] = {
        {"stride", required_argument, NULL, 's'},
        {"freq",   required_argument, NULL, 'f'},
        {"line",   required_argument, NULL, 'l'},
        {"unique", required_argument, NULL, 'u'},
        {"help",   no_argument,       NULL, 'h'},
        {NULL, 0, NULL, 0}
    };

    while ((opt = getopt_long(argc, argv, "s:f:l:u:h", long_opts, NULL)) != -1) {
        switch (opt) {
            case 's': stride = atoi(optarg); have_stride = 1; break;
            case 'f': freq = atof(optarg); have_freq = 1; break;
            case 'l': cl_size = atoi(optarg); break;
            case 'u': unique = atoi(optarg); break;
            case 'h': usage(argv[0]); return EXIT_SUCCESS;
            default: usage(argv[0]); return EXIT_FAILURE;
        }
    }

    if (!have_stride || !have_freq) {
        fprintf(stderr, "Error: --stride and --freq are required\n\n");
        usage(argv[0]);
        return EXIT_FAILURE;
    }
    if (unique < 1 || unique > _VL_) {
        fprintf(stderr, "Error: --unique must be between 1 and %d\n", _VL_);
        return EXIT_FAILURE;
    }

    size_t bytesPerWord = sizeof(real_t);
    size_t cacheLinesPerGather = MIN(MAX(stride * _VL_ / (cl_size / bytesPerWord), 1), _VL_);
    double E, S;

    printf("ISA,Kernel,DataType,Stride (elems),Frequency (GHz),Cache Line Size (B),Vector Width (elems),Cache Lines/Gather,Unique idx/group\n");
    printf("%s,%s,%s,%d,%f,%d,%d,%lu,%d\n\n", ISA_STRING, KERNEL_STRING, REAL_STRING, stride, freq, cl_size, _VL_, cacheLinesPerGather, unique);
    printf("%14s,%14s,%14s,%14s,%14s,%14s,%14s,%14s\n", "N", "Mask", "Size(kB)", "tot. time", "time/LUP(ms)", "GB/s", "cy/gather", "cy/elem");

    freq = freq * 1e9;
    const int mask_lo = 1, mask_hi = _VL_;

    for(int N = 1024; N < 400000; N = 1.5 * N) {
        int N_alloc = N * 2;
        real_t* a = (real_t*) allocate( ARRAY_ALIGNMENT, N_alloc * sizeof(real_t) );
        int* idx = (int*) allocate( ARRAY_ALIGNMENT, N_alloc * sizeof(int) );
        int rep;
        double time;

#ifdef TEST
        real_t* t = (real_t*) allocate( ARRAY_ALIGNMENT, N_alloc * sizeof(real_t) );
#else
        real_t* t = NULL;
#endif

        for(int i = 0; i < N_alloc; ++i) {
            a[i] = (real_t) i;
            const int group_base = (i / _VL_) * _VL_;
            const int lane = i % _VL_;
            const int li = group_base + (lane % unique);
            idx[i] = (int)(((long) li * stride) % N);
        }

        // Warmup, not timed (mirrors the GPU benchmark's explicit warmup call).
        GATHER(a, idx, N, t, _VL_);

        // Sweeping every mask value multiplies the number of measurements per N
        // by up to _VL_; shorten the per-measurement target so a full mask sweep
        // doesn't take _VL_ times as long in wall-clock terms as a single run.
        const double target_s = (mask_hi > mask_lo) ? (0.5 / _VL_) : 0.5;

        for(int active = mask_lo; active <= mask_hi; ++active) {
            S = getTimeStamp();
            for(int r = 0; r < 100; ++r) {
                GATHER(a, idx, N, t, active);
            }
            E = getTimeStamp();

            rep = 100 * (target_s / (E - S));
            S = getTimeStamp();
            LIKWID_MARKER_START("gather");
            for(int r = 0; r < rep; ++r) {
                GATHER(a, idx, N, t, active);
            }
            LIKWID_MARKER_STOP("gather");
            E = getTimeStamp();

            time = E - S;

#ifdef TEST
            int test_failed = 0;
            for(int i = 0; i < N; ++i) {
                const int group_base = (i / _VL_) * _VL_;
                const int lane = i % _VL_;
                if (lane >= active) continue; // masked-off lanes are not gathered, skip verification
                const int li = group_base + (lane % unique);
                const int expected_idx = (int)(((long) li * stride) % N);
                if(t[i] != (real_t) expected_idx) {
                    test_failed = 1;
                    break;
                }
            }

            if(test_failed) {
                printf("Test failed!\n");
                return EXIT_FAILURE;
            } else {
                printf("Test passed!\n");
            }
#endif

            const double size = N * (sizeof(real_t) + sizeof(int)) / 1000.0;
            const double time_per_it = time * 1e6 / ((double) N * rep);
            const double bytes_per_call = (double) N * (sizeof(real_t) + sizeof(int));
            const double gbps = bytes_per_call / (time / rep) / 1e9;
            const double cy_per_gather = time * freq * _VL_ / ((double) N * rep);
            const double cy_per_elem = time * freq / ((double) N * rep);
            printf("%14d,%14d,%14.2f,%14.10f,%14.10f,%14.4f,%14.6f,%14.6f\n", N, active, size, time, time_per_it, gbps, cy_per_gather, cy_per_elem);
        }

        free(a);
        free(idx);
#ifdef TEST
        free(t);
#endif
    }

    LIKWID_MARKER_CLOSE;
    return EXIT_SUCCESS;
}
