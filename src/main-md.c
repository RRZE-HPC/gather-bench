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
#include <limits.h>
#include <float.h>

#include <timing.h>
#include <allocate.h>

#if !defined(ISA_avx2) && !defined (ISA_avx512)
#error "Invalid ISA macro, possible values are: avx2 and avx512"
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
#define SIZE  20000

#ifdef ISA_avx512
#define _VL_  8
#define ISA_STRING "avx512"
#else
#define _VL_  4
#define ISA_STRING "avx2"
#endif

#ifdef AOS
#define GATHER gather_aos
#define LAYOUT_STRING "AoS"
#else
#define GATHER gather_soa
#define LAYOUT_STRING "SoA"
#endif

#ifdef TEST
extern void gather_aos(double*, int*, int, double*);
extern void gather_soa(double*, int*, int, double*);
#else
extern void gather_aos(double*, int*, int);
extern void gather_soa(double*, int*, int);
#endif

int main (int argc, char** argv) {
    if (argc < 3) {
        printf("Please provide stride and frequency\n");
        printf("%s <stride> <freq (GHz)> [cache line size (B)]\n", argv[0]);
        return -1;
    }

    int stride = atoi(argv[1]);
    const int dims = 3;
    double freq = atof(argv[2]);
    int cl_size = (argc == 3) ? 64 : atoi(argv[3]);
    size_t bytesPerWord = sizeof(double);
    #ifdef AOS
    size_t cacheLinesPerGather = MIN(MAX(stride * _VL_ * dims / (cl_size / sizeof(double)), 1), _VL_);
    #else
    size_t cacheLinesPerGather = MIN(MAX(stride * _VL_ / (cl_size / sizeof(double)), 1), _VL_) * dims;
    #endif
    size_t N = SIZE;
    double E, S;

    printf("ISA,Layout,Stride,Dims,Frequency (GHz),Cache Line Size (B),Vector Width (e),Cache Lines/Gather\n");
    printf("%s,%s,%d,%d,%f,%d,%d,%lu\n\n", ISA_STRING, LAYOUT_STRING, stride, dims, freq, cl_size, _VL_, cacheLinesPerGather);
    printf("%14s,%14s,%14s,%14s,%14s,%14s,%14s\n", "N", "Size(kB)", "tot. time", "time/LUP(ms)", "cy/it", "cy/gather", "cy/elem");

    freq = freq * 1e9;
    for(int N = 512; N < 200000; N = 1.5 * N) {
        // Currently this only works when the array size (in elements) is multiple of the vector length (no preamble and prelude)
        if(N % _VL_ != 0) {
            N += _VL_ - (N % _VL_);
        }

        int N_alloc = N * 2;
        double* a = (double*) allocate( ARRAY_ALIGNMENT, N_alloc * dims * sizeof(double) );
        int* idx = (int*) allocate( ARRAY_ALIGNMENT, N_alloc * sizeof(int) );
        int rep;
        double time;

#ifdef TEST
        double* t = (double*) allocate( ARRAY_ALIGNMENT, N_alloc * dims * sizeof(double) );
#endif

        for(int i = 0; i < N_alloc; ++i) {
#ifdef AOS
            a[i * dims + 0] = i * dims + 0;
            a[i * dims + 1] = i * dims + 1;
            a[i * dims + 2] = i * dims + 2;
#else
            a[N * 0 + i] = N * 0 + i;
            a[N * 1 + i] = N * 1 + i;
            a[N * 2 + i] = N * 2 + i;
#endif
            idx[i] = (i * stride) % N;
        }

        S = getTimeStamp();
        for(int r = 0; r < 100; ++r) {
#ifdef TEST
            GATHER(a, idx, N, t);
#else
            GATHER(a, idx, N);
#endif
        }
        E = getTimeStamp();

        rep = 100 * (0.5 / (E - S));
        S = getTimeStamp();
        for(int r = 0; r < rep; ++r) {
#ifdef TEST
            GATHER(a, idx, N, t);
#else
            GATHER(a, idx, N);
#endif
        }
        E = getTimeStamp();

        time = E - S;

#ifdef TEST
        int test_failed = 0;
        for(int i = 0; i < N; ++i) {
            for(int d = 0; d < dims; ++d) {
#ifdef AOS
                if(t[d * N + i] != ((i * stride) % N) * dims + d) {
#else
                if(t[d * N + i] != d * N + ((i * stride) % N)) {
#endif
                    test_failed = 1;
                    break;
                }
            }
        }

        if(test_failed) {
            printf("Test failed!\n");
            return EXIT_FAILURE;
        } else {
            printf("Test passed!\n");
        }
#endif

        const double size = N * (3 * sizeof(double) + sizeof(int)) / 1000.0;
        const double time_per_it = time * 1e6 / ((double) N * rep);
        const double cy_per_it = time * freq * _VL_ / ((double) N * rep);
        const double cy_per_gather = time * freq * _VL_ / ((double) N * rep * dims);
        const double cy_per_elem = time * freq / ((double) N * rep * dims);
        printf("%14d,%14.2f,%14.10f,%14.10f,%14.6f,%14.6f,%14.6f\n", N, size, time, time_per_it, cy_per_it, cy_per_gather, cy_per_elem);
        free(a);
        free(idx);
#ifdef TEST
        free(t);
#endif
    }

    return EXIT_SUCCESS;
}
