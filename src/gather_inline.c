#include <stdio.h>
#include <stdlib.h>
//---
#include "timer.h"

void gather(double *a, int *idx, int N) {
    int n = N;
    double sum = 0.0;

#if defined(__AVX512F__)
    for(long long int offs = 0; offs < n; offs += 8 * 4) {
        __asm__ __volatile__(
            "vpcmpeqb %%xmm0, %%xmm0, %%k1\n\t"
            "vpcmpeqb %%xmm0, %%xmm0, %%k2\n\t"
            "vpcmpeqb %%xmm0, %%xmm0, %%k3\n\t"
            "vpcmpeqb %%xmm0, %%xmm0, %%k4\n\t;"
            "vmovdqu (%0,%1,4), %%ymm0\n\t"
            "vmovdqu 32(%0,%1,4), %%ymm1\n\t"
            "vmovdqu 64(%0,%1,4), %%ymm2\n\t"
            "vmovdqu 96(%0,%1,4), %%ymm3\n\t"
            "vpxord %%zmm4, %%zmm4, %%zmm4\n\t"
            "vpxord %%zmm5, %%zmm5, %%zmm5\n\t"
            "vpxord %%zmm6, %%zmm6, %%zmm6\n\t"
            "vpxord %%zmm7, %%zmm7, %%zmm7\n\t"
            "vgatherdpd (%2,%%ymm0,8), %%zmm4%{%%k1%}\n\t"
            "vgatherdpd (%2,%%ymm1,8), %%zmm5%{%%k2%}\n\t"
            "vgatherdpd (%2,%%ymm2,8), %%zmm6%{%%k3%}\n\t"
            "vgatherdpd (%2,%%ymm3,8), %%zmm7%{%%k4%}"
            :
            : "r" (idx), "r" (offs), "r" (a)
        );
    }

    /*
    for(int offs = 0; offs < n; offs += 8) {
        asm("vpcmpeqb %%xmm0, %%xmm0, %%k1\n\t"
            "vmovdqu (%%rsi,%0,4), %%ymm0\n\t"
            "vpxord %%zmm0, %%zmm0, %%zmm0\n\t"
            "vgatherdpd (%%rdi,%%ymm0,8), %%zmm0{%%k1}" : : "r" (offs));
    }
    */
#endif
}

int round_up_div(int a, int b) {
    if(a % b) { return a / b + 1; }
    return a / b;
}

// Cost of gather (cycles per gather op)
// Impact of number of cache lines
// AVX512
// Avg cycles per element
int main(int argc, char** argv) {
    if(argc < 3) {
        printf("Please provide stride and frequency\n");
        printf("%s <stride> <freq (GHz)>\n", argv[0]);
        return -1;
    }

    int stride = atoi(argv[1]);
    double freq = atof(argv[2]);
    const int cache_line_size = 64;
    const int cache_line_elements = cache_line_size / sizeof(double);

    printf("stride = %d, freq = %f GHz\n", stride, freq);
    printf("cache_line_size = %d, CLU = %.2f\n", cache_line_size, ((double)cache_line_elements / (stride * cache_line_elements)));

    freq = freq * 1e9;
    printf("#%13s, %14s, %14s, %14s, %14s, %14s, %14s\n", "N", "Size(kB)", "tot. time", "time/LUP(ms)", "cy/LUP", "cy/CL", "tCL(10^6)");
    for(int N=500; N<480000; N=1.2*N) {
        double *a;
        int *idx;
        int N_alloc = N*2; //little extra alloc for avoiding extra predicates
        //double *a = (double*) malloc(sizeof(double)*N_alloc);
        //int *idx = (int*) malloc(sizeof(int)*N_alloc);
        posix_memalign((void **) &a, 4096, sizeof(double) * N_alloc);
        posix_memalign((void **) &idx, 4096, sizeof(int) * N_alloc);

        for(int i=0; i<N_alloc; ++i) {
            a[i] = i;
            idx[i] = (i*stride)%N;
        }

        INIT_TIMER(load_warm);
        START_TIMER(load_warm);
        for(int r=0; r<100; ++r)
        {
            gather(a,idx,N);
        }
        STOP_TIMER(load_warm);
        double warm_time = GET_TIMER(load_warm);
        int rep = 100*(0.5/warm_time);
        INIT_TIMER(load);
        START_TIMER(load);
        for(int r=0; r<rep; ++r)
        {
            gather(a,idx,N);
        }
        STOP_TIMER(load);

        double time =  GET_TIMER(load);
        const int cache_lines_touched = N * (round_up_div(cache_line_elements, stride) - 1);
        printf("%14d, %14.2f, %14.10f, %14.10f, %14.6f, %14.6f, %14.6f\n", N, N*(sizeof(double)+sizeof(int))/(1000.0), time, time*1e6/((double)N*rep), time*freq/((double)N*rep), time*freq*8.0/((double)N*rep), (double)(cache_lines_touched) / 1e6);
        //free(a);
        //free(idx);
    }
    return 0;
}
