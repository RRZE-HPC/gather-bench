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
#include <float.h>
#include <getopt.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
//---
#include <likwid-marker.h>
//---
#include <allocate.h>
#include <timing.h>

#if !defined(ISA_avx2) && !defined (ISA_avx512)
#error "Invalid ISA macro, possible values are: avx2 and avx512"
#endif

#if defined(TEST) && defined(ONLY_FIRST_DIMENSION)
#error "TEST and ONLY_FIRST_DIMENSION options are mutually exclusive!"
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

#ifdef ISA_avx512
#define _VL_  8
#define ISA_STRING "avx512"
#else
#define _VL_  4
#define ISA_STRING "avx2"
#endif

#ifdef AOS
#define GATHER gather_md_aos
#define LAYOUT_STRING "AoS"
#else
#define GATHER gather_md_soa
#define LAYOUT_STRING "SoA"
#endif

#if defined(PADDING) && defined(AOS)
#define PADDING_BYTES 1
#else
#define PADDING_BYTES 0
#endif

#ifdef MEM_TRACER
#   define MEM_TRACER_INIT(trace_file)    FILE *mem_tracer_fp = fopen(get_mem_tracer_filename(trace_file), "w");
#   define MEM_TRACER_END                 fclose(mem_tracer_fp);
#   define MEM_TRACE(addr, op)            fprintf(mem_tracer_fp, "%c: %p\n", op, (void *)(&(addr)));
#else
#   define MEM_TRACER_INIT
#   define MEM_TRACER_END
#   define MEM_TRACE(addr, op)
#endif

extern int gather_md_aos(double*, int*, int, double*, int);
extern int gather_md_soa(double*, int*, int, double*, int);

const char *get_mem_tracer_filename(const char *trace_file) {
    static char fname[64];
    snprintf(fname, sizeof fname, "mem_tracer_%s.txt", trace_file);
    return fname;
}

int log2_uint(unsigned int x) {
    int ans = 0;
    while(x >>= 1) { ans++; }
    return ans;
}

int main (int argc, char** argv) {
    LIKWID_MARKER_INIT;
    LIKWID_MARKER_REGISTER("gather");
    char *trace_file = NULL;
    int cl_size = 64;
    int opt = 0;
    double freq = 2.5;
    struct option long_opts[] = {
        {"trace" , required_argument,   NULL,   't'},
        {"freq",   required_argument,   NULL,   'f'},
        {"line",   required_argument,   NULL,   'l'},
        {"help",   required_argument,   NULL,   'h'}
    };

    while((opt = getopt_long(argc, argv, "t:f:l:h", long_opts, NULL)) != -1) {
        switch(opt) {
            case 't':
                trace_file = strdup(optarg);
                break;

            case 'f':
                freq = atof(optarg);
                break;

            case 'l':
                cl_size = atoi(optarg);
                break;

            case 'h':
            case '?':
            default:
                printf("Usage: %s [OPTION]...\n", argv[0]);
                printf("MD variant for gather benchmark.\n\n");
                printf("Mandatory arguments to long options are also mandatory for short options.\n");
                printf("\t-t, --trace-file=STRING   input file with traced indexes from MD-Bench.\n");
                printf("\t-f, --freq=REAL           CPU frequency in GHz (default 2.5).\n");
                printf("\t-l, --line=NUMBER         cache line size in bytes (default 64).\n");
                printf("\t-h, --help                display this help message.\n");
                printf("\n\n");
                return EXIT_FAILURE;
        }
    }

    if(trace_file == NULL) {
        fprintf(stderr, "Trace file not specified!\n");
        return EXIT_FAILURE;
    }

    FILE *fp;
    char *line = NULL;
    int *neighborlists = NULL;
    int *numneighs = NULL;
    int atom = -1;
    int nlocal, nghost, nall, maxneighs;
    const int dims = 3;
    const int snbytes = dims + PADDING_BYTES; // bytes per element (struct), includes padding
    size_t llen;
    ssize_t read;
    double time, E, S;

    if((fp = fopen(trace_file, "r")) == NULL) {
        fprintf(stderr, "Error: could not open trace file!\n");
        return EXIT_FAILURE;
    }

    while((read = getline(&line, &llen, fp)) != -1) {
        int i = 2;
        if(strncmp(line, "N:", 2) == 0) {
            while(line[i] == ' ') { i++; }
            nlocal = atoi(strtok(&line[i], " "));
            nghost = atoi(strtok(NULL, " "));
            maxneighs = atoi(strtok(NULL, " "));
            nall = nlocal + nghost;

            if(neighborlists != NULL || numneighs != NULL) {
                fprintf(stderr, "Number of atoms and neighbor lists capacity defined more than once!");
                return EXIT_FAILURE;
            }

            if(nlocal <= 0 || maxneighs <= 0) {
                fprintf(stderr, "Number of local atoms and neighbor lists capacity cannot be less or equal than zero!");
                return EXIT_FAILURE;
            }

            neighborlists = (int *) allocate( ARRAY_ALIGNMENT, nlocal * maxneighs * sizeof(int) );
            numneighs = (int *) allocate( ARRAY_ALIGNMENT, nlocal * sizeof(int) );
        }

        if(strncmp(line, "A:", 2) == 0) {
            while(line[i] == ' ') { i++; }
            atom = atoi(strtok(&line[i], " "));
            numneighs[atom] = 0;
        }

        if(strncmp(line, "I:", 2) == 0) {
            while(line[i] == ' ') { i++; }
            char *neigh_idx = strtok(&line[i], " ");

            while(neigh_idx != NULL) {
                int j = numneighs[atom];
                neighborlists[atom * maxneighs + j] = atoi(neigh_idx);
                numneighs[atom]++;
                neigh_idx = strtok(NULL, " ");
            }
        }
    }

    fclose(fp);
    printf("ISA,Layout,Dims,Frequency (GHz),Cache Line Size (B),Vector Width (e)\n");
    printf("%s,%s,%d,%f,%d,%d\n\n", ISA_STRING, LAYOUT_STRING, dims, freq, cl_size, _VL_);
    printf("%14s,%14s,%14s,%14s,%14s", "tot. time", "time/LUP(ms)", "cy/it", "cy/gather", "cy/elem");
    printf("\n");
    freq = freq * 1e9;

    int N_alloc = nall * 2;
    double* a = (double*) allocate( ARRAY_ALIGNMENT, N_alloc * snbytes * sizeof(double) );

#ifdef TEST
    double* t = (double*) allocate( ARRAY_ALIGNMENT, N_alloc * dims * sizeof(double) );
#else
    double* t = (double*) NULL;
#endif
    for(int i = 0; i < N_alloc; ++i) {
#ifdef AOS
        a[i * snbytes + 0] = i * dims + 0;
        a[i * snbytes + 1] = i * dims + 1;
        a[i * snbytes + 2] = i * dims + 2;
#else
        a[N * 0 + i] = N * 0 + i;
        a[N * 1 + i] = N * 1 + i;
        a[N * 2 + i] = N * 2 + i;
#endif
    }

    int t_idx = 0;
    MEM_TRACER_INIT(trace_file);
    S = getTimeStamp();
    LIKWID_MARKER_START("gather");
    for(int i = 0; i < nlocal; i++) {
        int *neighbors = &neighborlists[i * maxneighs];
        t_idx += GATHER(a, neighbors, numneighs[i], &t[t_idx], N_alloc);
    }
    LIKWID_MARKER_STOP("gather");
    E = getTimeStamp();
    time = E - S;

#ifdef TEST
    int test_failed = 0;
    t_idx = 0;
    for(int i = 0; i < nlocal; ++i) {
        int *neighbors = &neighborlists[i * maxneighs];
        for(int j = 0; j < numneighs[i]; ++j) {
            int k = neighbors[j];
            for(int d = 0; d < dims; ++d) {
#ifdef AOS
                if(t[d * N_alloc + t_idx] != k * dims + d) {
#else
                if(t[d * N_alloc + t_idx] != d * N + ((i * stride) % N)) {
#endif
                    test_failed = 1;
                    break;
                }
            }

            t_idx++;
        }
    }

    if(test_failed) {
        printf("Test failed!\n");
        return EXIT_FAILURE;
    } else {
        printf("Test passed!\n");
    }
#endif

    MEM_TRACER_END;
    LIKWID_MARKER_CLOSE;
    return EXIT_SUCCESS;
}
