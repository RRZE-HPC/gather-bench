/*
 * =======================================================================================
 *
 *      GPU (CUDA/HIP) port of the gather-bench indexed-load microbenchmark.
 *
 *      Mimics the x86 AVX2/AVX512 gather kernels (src/main.c, src/main-md.c):
 *      for a permutation index array idx[] with idx[i] = (i * stride) % N,
 *      gather either a single value per element (--dims 1) or a 3-component
 *      "particle" (--dims 3, AoS or SoA layout) per element.
 *
 * =======================================================================================
 */
#include "gpu-error.h"
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <getopt.h>
#include <iomanip>
#include <iostream>
#include <string>
#include <vector>

using namespace std;

#ifndef MIN
#define MIN(x, y) ((x) < (y) ? (x) : (y))
#endif
#ifndef MAX
#define MAX(x, y) ((x) > (y) ? (x) : (y))
#endif

// ---------------------------------------------------------------------------
// Device kernels
// ---------------------------------------------------------------------------

template <typename T, int DIMS, bool AOS>
__global__ void initDataKernel(T *__restrict__ a, int N) {
  int tid = blockIdx.x * blockDim.x + threadIdx.x;
  for (int i = tid; i < N; i += blockDim.x * gridDim.x) {
#pragma unroll
    for (int d = 0; d < DIMS; d++) {
      if constexpr (AOS) {
        a[(size_t)i * DIMS + d] = (T)((size_t)i * DIMS + d);
      } else {
        a[(size_t)d * N + i] = (T)((size_t)d * N + i);
      }
    }
  }
}

__global__ void initIdxKernel(int *__restrict__ idx, int N, int stride) {
  int tid = blockIdx.x * blockDim.x + threadIdx.x;
  for (int i = tid; i < N; i += blockDim.x * gridDim.x) {
    idx[i] = (int)(((long long)i * stride) % (long long)N);
  }
}

// STORE == false: gathered values are accumulated and only conditionally
// written back (via a sentinel that is never true for our data), so the
// compiler cannot dead-code-eliminate the loads while we still avoid paying
// for the stores during the timed measurement.
// STORE == true: gathered values are always written back - used for the
// correctness test only.
template <typename T, int DIMS, bool AOS, bool STORE>
__global__ void gatherKernel(const T *__restrict__ a,
                              const int *__restrict__ idx,
                              T *__restrict__ out, int N) {
  int tid = blockIdx.x * blockDim.x + threadIdx.x;
  for (int i = tid; i < N; i += blockDim.x * gridDim.x) {
    int id = idx[i];
    T sum = T(0);
#pragma unroll
    for (int d = 0; d < DIMS; d++) {
      T v;
      if constexpr (AOS) {
        v = a[(size_t)id * DIMS + d];
      } else {
        v = a[(size_t)d * N + id];
      }
      if constexpr (STORE) {
        out[(size_t)d * N + i] = v;
      } else {
        sum += v;
      }
    }
    if constexpr (!STORE) {
      if (sum == T(-1.0)) {
        out[i] = sum;
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Host side
// ---------------------------------------------------------------------------

struct Config {
  int stride = 1;
  int dims = 3;
  bool aos = true;
  bool sp = false;
  double freqGHz = 0.0; // 0 => use device clockRate
  bool test = false;
  int blockSize = 256;
  long minElems = 1024;
  long maxElems = 64L * 1024 * 1024;
  int clSize = 128; // bytes, informational only
};

static int smCount = 0;

static int gridSizeFor(long N, int blockSize) {
  long blocks = (N + blockSize - 1) / blockSize;
  long cap = (long)smCount * 32;
  return (int)MAX(1, MIN(blocks, cap));
}

// Returns the number of unique `clSize`-byte segments touched by the data
// gathers of one warp, averaged over all warps - purely an analytical,
// host-side measure of how well the stride/layout coalesces (mirrors the
// "cut cache lines" analysis in the CPU main-md.c benchmark).
static double avgSegmentsPerWarp(const vector<int> &idx, int N, int dims,
                                  bool aos, int elemBytes, int clSize) {
  const int WARP = 32;
  long nWarps = 0;
  long totalSegments = 0;
  vector<long> segs;
  segs.reserve(WARP * dims);

  for (long w0 = 0; w0 < N; w0 += WARP) {
    segs.clear();
    long wEnd = MIN((long)N, w0 + WARP);
    for (long i = w0; i < wEnd; i++) {
      int id = idx[i];
      for (int d = 0; d < dims; d++) {
        long byteOffset = aos ? (long)id * dims * elemBytes + (long)d * elemBytes
                               : (long)d * N * elemBytes + (long)id * elemBytes;
        segs.push_back(byteOffset / clSize);
      }
    }
    sort(segs.begin(), segs.end());
    segs.erase(unique(segs.begin(), segs.end()), segs.end());
    totalSegments += segs.size();
    nWarps++;
  }
  return nWarps ? (double)totalSegments / nWarps : 0.0;
}

template <typename T, int DIMS, bool AOS>
static void runSweep(const Config &cfg, double freqHz, const string &dtypeName,
                     const string &layoutName) {
  cout << "Dtype,Dims,Layout,Stride,Frequency (GHz),Cache Line Size (B)\n";
  cout << dtypeName << "," << DIMS << "," << layoutName << "," << cfg.stride
       << "," << (freqHz / 1e9) << "," << cfg.clSize << "\n\n";
  cout << setw(14) << "N" << "," << setw(14) << "Size(kB)" << ","
       << setw(14) << "segs/warp" << "," << setw(14) << "time(s)" << ","
       << setw(14) << "time/elem(ns)" << "," << setw(14) << "GB/s" << ","
       << setw(14) << "cy/elem" << "\n";

  cudaEvent_t start, stop;
  GPU_ERROR(cudaEventCreate(&start));
  GPU_ERROR(cudaEventCreate(&stop));

  for (long N = cfg.minElems; N <= cfg.maxElems; N = (long)(N * 1.5) + 1) {
    int blockSize = cfg.blockSize;
    int grid = gridSizeFor(N, blockSize);

    T *dA = nullptr, *dOut = nullptr;
    int *dIdx = nullptr;
    GPU_ERROR(cudaMalloc(&dA, (size_t)N * DIMS * sizeof(T)));
    GPU_ERROR(cudaMalloc(&dIdx, (size_t)N * sizeof(int)));
    GPU_ERROR(cudaMalloc(&dOut, (size_t)N * DIMS * sizeof(T)));

    initDataKernel<T, DIMS, AOS><<<grid, blockSize>>>(dA, (int)N);
    initIdxKernel<<<grid, blockSize>>>(dIdx, (int)N, cfg.stride);
    GPU_ERROR(cudaDeviceSynchronize());

    if (cfg.test) {
      vector<int> hIdx(N);
      GPU_ERROR(cudaMemcpy(hIdx.data(), dIdx, N * sizeof(int),
                            cudaMemcpyDeviceToHost));
      vector<T> hOut((size_t)N * DIMS);
      gatherKernel<T, DIMS, AOS, true><<<grid, blockSize>>>(dA, dIdx, dOut,
                                                            (int)N);
      GPU_ERROR(cudaDeviceSynchronize());
      GPU_ERROR(cudaMemcpy(hOut.data(), dOut, (size_t)N * DIMS * sizeof(T),
                            cudaMemcpyDeviceToHost));

      bool failed = false;
      for (long i = 0; i < N && !failed; i++) {
        for (int d = 0; d < DIMS; d++) {
          T expected = AOS ? (T)((size_t)hIdx[i] * DIMS + d)
                            : (T)((size_t)d * N + hIdx[i]);
          if (hOut[(size_t)d * N + i] != expected) {
            failed = true;
            break;
          }
        }
      }
      cout << (failed ? "Test failed!\n" : "Test passed!\n");
      if (failed) {
        cudaFree(dA);
        cudaFree(dIdx);
        cudaFree(dOut);
        exit(EXIT_FAILURE);
      }
    }

    // Warmup
    gatherKernel<T, DIMS, AOS, false><<<grid, blockSize>>>(dA, dIdx, dOut,
                                                           (int)N);
    GPU_ERROR(cudaDeviceSynchronize());

    // Calibrate repeat count to target ~0.2s of measurement.
    const int calibReps = 5;
    GPU_ERROR(cudaEventRecord(start));
    for (int r = 0; r < calibReps; r++) {
      gatherKernel<T, DIMS, AOS, false><<<grid, blockSize>>>(dA, dIdx, dOut,
                                                             (int)N);
    }
    GPU_ERROR(cudaEventRecord(stop));
    GPU_ERROR(cudaEventSynchronize(stop));
    float calibMs = 0;
    GPU_ERROR(cudaEventElapsedTime(&calibMs, start, stop));
    double perCallS = MAX(1e-9, (double)calibMs / 1000.0 / calibReps);
    int rep = (int)MAX(1, MIN(100000, 0.2 / perCallS));

    GPU_ERROR(cudaEventRecord(start));
    for (int r = 0; r < rep; r++) {
      gatherKernel<T, DIMS, AOS, false><<<grid, blockSize>>>(dA, dIdx, dOut,
                                                             (int)N);
    }
    GPU_ERROR(cudaEventRecord(stop));
    GPU_ERROR(cudaEventSynchronize(stop));
    float ms = 0;
    GPU_ERROR(cudaEventElapsedTime(&ms, start, stop));
    double time = (double)ms / 1000.0 / rep;

    double segsPerWarp = 0.0;
    {
      vector<int> hIdx(N);
      GPU_ERROR(cudaMemcpy(hIdx.data(), dIdx, N * sizeof(int),
                            cudaMemcpyDeviceToHost));
      segsPerWarp = avgSegmentsPerWarp(hIdx, (int)N, DIMS, AOS, sizeof(T),
                                       cfg.clSize);
    }

    const double sizeKB = (double)N * (DIMS * sizeof(T) + sizeof(int)) / 1000.0;
    const double bytesPerCall = (double)N * (DIMS * sizeof(T) + sizeof(int));
    const double gbps = bytesPerCall / time / 1e9;
    const double timePerElemNs = time * 1e9 / N;
    const double cyPerElem = time * freqHz / N;

    cout << setw(14) << N << "," << setw(14) << fixed << setprecision(2)
         << sizeKB << "," << setw(14) << setprecision(3) << segsPerWarp << ","
         << setw(14) << setprecision(9) << time << "," << setw(14)
         << setprecision(4) << timePerElemNs << "," << setw(14)
         << setprecision(2) << gbps << "," << setw(14) << setprecision(4)
         << cyPerElem << "\n";

    cudaFree(dA);
    cudaFree(dIdx);
    cudaFree(dOut);
  }

  cudaEventDestroy(start);
  cudaEventDestroy(stop);
  cout << "\n";
}

static void usage(const char *prog) {
  printf("GPU (CUDA/HIP) variant of the gather-bench indexed-load "
         "microbenchmark.\n\n");
  printf("Usage: %s --stride=NUMBER [OPTION]...\n\n", prog);
  printf("\t-s, --stride=NUMBER    stride between two successive indices "
         "(required).\n");
  printf("\t-d, --dims=1|3         number of components gathered per index "
         "(default 3).\n");
  printf("\t-l, --layout=aos|soa   data layout, only relevant for dims=3 "
         "(default aos).\n");
  printf("\t    --sp               use single precision floats (default "
         "double).\n");
  printf("\t-f, --freq=REAL        GPU clock frequency in GHz (default: "
         "queried from the device).\n");
  printf("\t-t, --test             verify gathered results on the host.\n");
  printf("\t-b, --block=NUMBER     CUDA/HIP block size (default 256).\n");
  printf("\t    --min-elems=NUMBER smallest N in the sweep (default "
         "1024).\n");
  printf("\t    --max-elems=NUMBER largest N in the sweep (default "
         "67108864).\n");
  printf("\t-h, --help             display this help message.\n");
}

int main(int argc, char **argv) {
  Config cfg;
  bool haveStride = false;

  struct option long_opts[] = {
      {"stride", required_argument, nullptr, 's'},
      {"dims", required_argument, nullptr, 'd'},
      {"layout", required_argument, nullptr, 'l'},
      {"sp", no_argument, nullptr, 1},
      {"freq", required_argument, nullptr, 'f'},
      {"test", no_argument, nullptr, 't'},
      {"block", required_argument, nullptr, 'b'},
      {"min-elems", required_argument, nullptr, 2},
      {"max-elems", required_argument, nullptr, 3},
      {"help", no_argument, nullptr, 'h'},
      {nullptr, 0, nullptr, 0}};

  int opt;
  while ((opt = getopt_long(argc, argv, "s:d:l:f:tb:h", long_opts, nullptr)) !=
         -1) {
    switch (opt) {
    case 's':
      cfg.stride = atoi(optarg);
      haveStride = true;
      break;
    case 'd':
      cfg.dims = atoi(optarg);
      break;
    case 'l':
      cfg.aos = (strcmp(optarg, "soa") != 0);
      break;
    case 1:
      cfg.sp = true;
      break;
    case 'f':
      cfg.freqGHz = atof(optarg);
      break;
    case 't':
      cfg.test = true;
      break;
    case 'b':
      cfg.blockSize = atoi(optarg);
      break;
    case 2:
      cfg.minElems = atol(optarg);
      break;
    case 3:
      cfg.maxElems = atol(optarg);
      break;
    case 'h':
    default:
      usage(argv[0]);
      return opt == 'h' ? EXIT_SUCCESS : EXIT_FAILURE;
    }
  }

  if (!haveStride) {
    fprintf(stderr, "Error: --stride is required\n\n");
    usage(argv[0]);
    return EXIT_FAILURE;
  }

  if (cfg.dims != 1 && cfg.dims != 3) {
    fprintf(stderr, "Error: --dims must be 1 or 3\n");
    return EXIT_FAILURE;
  }

  int deviceId = 0;
  cudaDeviceProp prop;
  GPU_ERROR(cudaGetDevice(&deviceId));
  GPU_ERROR(cudaGetDeviceProperties(&prop, deviceId));
  smCount = prop.multiProcessorCount;

  int clockRateKHz = 0;
  GPU_ERROR(cudaDeviceGetAttribute(&clockRateKHz, cudaDevAttrClockRate, deviceId));
  double freqHz = cfg.freqGHz > 0 ? cfg.freqGHz * 1e9 : (double)clockRateKHz * 1e3;

  cout << "Device," << prop.name << "\n";
  cout << "SM count," << smCount << "\n\n";

  const string layoutName = cfg.aos ? "AoS" : "SoA";

  if (cfg.dims == 1) {
    if (cfg.sp)
      runSweep<float, 1, true>(cfg, freqHz, "SP", "-");
    else
      runSweep<double, 1, true>(cfg, freqHz, "DP", "-");
  } else {
    if (cfg.sp) {
      if (cfg.aos)
        runSweep<float, 3, true>(cfg, freqHz, "SP", layoutName);
      else
        runSweep<float, 3, false>(cfg, freqHz, "SP", layoutName);
    } else {
      if (cfg.aos)
        runSweep<double, 3, true>(cfg, freqHz, "DP", layoutName);
      else
        runSweep<double, 3, false>(cfg, freqHz, "DP", layoutName);
    }
  }

  return EXIT_SUCCESS;
}
