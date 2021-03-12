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
#define _VL_  4

extern void gather(double*, int*, int);


int main (int argc, char** argv)
{
    size_t bytesPerWord = sizeof(double);
    size_t N = SIZE;
    double E, S;

    if (argc < 3) {
        printf("Please provide stride and frequency\n");
        printf("%s <stride> <freq (GHz)>\n", argv[0]);
        return -1;
    }
    int stride = atoi(argv[1]);
    double freq = atof(argv[2]);
    printf("stride = %d, freq = %f GHz\n", stride, freq);
    freq = freq * 1e9;

    printf("Vector length of %d assumed\n", _VL_);
    double* a = (double*) allocate( ARRAY_ALIGNMENT, N * sizeof(double) );
    int* idx = (int*) allocate( ARRAY_ALIGNMENT, N * sizeof(int) );

    S = getTimeStamp();
    gather(a, idx, N);
    E = getTimeStamp();

    printf("Runtime %f\n",E-S);

    return EXIT_SUCCESS;
}
