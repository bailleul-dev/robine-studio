# AUD-010: Specialized A2 inference

Status: Implemented

## Summary

Robine provides native Zig inference kernels for the fixed A2-Lite and A2-Full
WaveNet shapes. The specialization preserves the generic WaveNet evaluator as a
compatibility and verification path while making full-quality multi-pedal chains
practical inside a DAW callback.

## Shape selection

- The loader MUST select the specialized path only after validating the complete
  A2 signature: 23 layers, the canonical kernel and dilation sequences, either
  three or eight channels, a 16-tap head, and LeakyReLU slope 0.01.
- A model that does not match every invariant MUST remain on the generic path or
  fail under the existing unsupported-topology rules. It MUST NOT be interpreted
  as A2 from its version, filename, or metadata alone.
- A2-Lite and A2-Full MUST retain separate kernels and data layouts when that
  improves predictable SIMD utilization.

## Real-time implementation

- File-order weights MUST be reordered once during non-real-time model loading.
- A2-Full MUST process four frames together using complete eight-channel SIMD
  vectors. A2-Lite MUST process eight frames together using planar channel
  histories and frame-oriented SIMD vectors.
- History storage MUST use power-of-two rings with contiguous mirrored tails.
  Mirror maintenance SHOULD update only the affected range and ring phases MUST
  be distributed across layers to avoid correlated callback spikes.
- Processing MUST allocate no memory, resize no buffer, acquire no lock, and
  perform no platform API call.
- Prewarmed steady-state histories MUST be cached. A later reset MUST restore the
  cache without replaying the full receptive field in the audio callback.
- Studio MUST continue selecting the full eight-channel captures. Optimization
  MUST NOT silently substitute the three-channel submodel.

## Numerical verification

- Specialized Full and Lite output MUST agree with the generic Zig WaveNet path
  within an absolute tolerance of `1e-5` over changing block sizes, including
  non-powers of two and scalar tail frames.
- Cached reset output MUST match a freshly prewarmed generic model within the
  same tolerance.
- Existing NeuralAmpModelerCore golden-sample tests remain mandatory.

## Performance verification

`make a2-bench` measures p50, p99, maximum block time, and real-time factor for
64, 128, 256, and 512 frames. `make nam-bench` measures the complete three-Full-
model and 24,000-tap cabinet chain.

On the reference Apple M1, the 2026-08-29 ReleaseFast baseline is:

| Shape | Frames | Robine p50 | NAM Core A2 fast p50 | Robine speedup |
| --- | ---: | ---: | ---: | ---: |
| Lite | 64 | 5.3 us | 6.4 us | 1.20x |
| Lite | 128 | 10.5 us | 12.8 us | 1.22x |
| Lite | 256 | 20.5 us | 25.6 us | 1.25x |
| Lite | 512 | 40.4 us | 51.2 us | 1.27x |
| Full | 64 | 31.6 us | 46.3 us | 1.47x |
| Full | 128 | 62.9 us | 87.4 us | 1.39x |
| Full | 256 | 125.2 us | 166.2 us | 1.33x |
| Full | 512 | 248.3 us | 326.3 us | 1.31x |

The comparison uses the same Dumble A2 container, 48 kHz sample rate, release
optimization, and matching maximum block size. The complete current chain MUST
remain above real time with zero deadline misses in an uncontended verification
run; the initial optimized baseline is approximately 10x real time at 512
frames.

## Portability

- The kernels MUST remain pure Zig and MUST NOT depend on Eigen, Accelerate,
  platform intrinsics, a C++ runtime, or a platform DSP library.
- Zig `@Vector` lowering is the portability boundary. The module MUST compile
  for AArch64 Linux, x86-64 Linux, and x86-64 Windows in addition to macOS.

