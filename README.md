# gather-bench
A X86 gather instruction performance benchmark

## GPU (CUDA/HIP) variant

`gpu/main.cu` ports the same idea to GPUs: a permutation index array
`idx[i] = (i * stride) % N` is used to gather either a single value
(`--dims 1`) or a 3-component "particle" (`--dims 3`, AoS or SoA layout,
mirroring `src/main-md.c`) per element, sweeping the problem size `N` and
reporting achieved bandwidth, time/element and cycles/element.

Build (single source, following the same nvcc/hipify-perl/hipcc flow used by
the `gpu-benches` repo):

```
cd gpu
make cuda-gather-bench   # requires nvcc
make hip-gather-bench    # requires hipify-perl + hipcc
```

Run, e.g.:

```
./cuda-gather-bench --stride=8 --dims=3 --layout=aos --test
```

See `./cuda-gather-bench --help` for all options (stride, dims, layout,
precision, block size, N sweep bounds, correctness test).
