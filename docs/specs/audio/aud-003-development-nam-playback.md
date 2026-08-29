# AUD-003: Development NAM playback

Status: Implemented

## Summary

When Robine Studio starts, it plays the deterministic mono guitar fixture once
through the initial Dumble NAM capture, the initial cabinet response, and the
default native output. This is a development path for validating the real audio
stack before live input, routing controls, and plugin hosts are introduced.

## Portable processing boundary

- WAV decoding and NAM inference MUST be implemented in Zig and MUST NOT depend
  on a C++ runtime, Eigen, CMake, or a platform audio API.
- The supported first NAM topology is version 0.7.0
  `SlimmableContainer/WaveNet`: one mono causal layer array, LeakyReLU layers,
  residual pointwise convolutions, and a causal output head.
- Unsupported NAM versions, architectures, sample rates, or topology features
  MUST fail explicitly during non-real-time loading.
- Both the three-channel lightweight and eight-channel full submodels MUST
  remain loadable. Studio MUST select the full eight-channel capture for live
  playback; performance work MUST NOT silently reduce model quality.
- The implementation MUST compile as a standalone object for Windows and Linux
  targets without introducing target-specific DSP source.

## Startup path

1. Studio decodes the embedded mono PCM24 fixture.
2. Studio loads and prewarms the selected NAM submodel outside the callback.
3. The native standalone backend negotiates the model's 48 kHz sample rate.
4. The callback consumes the fixture once, processes every frame through the
   full NAM and cabinet convolver, and duplicates the mono result to every
   native output channel.
5. Once the fixture ends, the callback flushes the cabinet tail and then emits
   silence until Studio closes.

## Real-time requirements

- The callback MUST allocate no memory, access no files, acquire no locks, and
  emit no synchronous logs.
- Model state and decoded fixture memory MUST have stable addresses from session
  start until the native device has stopped.
- Native output conversion MUST handle planar and interleaved channel views and
  the sample formats admitted by AUD-002.
- Playback MUST use the host-independent causal model state so block boundaries
  do not affect output.

## Verification

- Golden samples for both submodel sizes match an offline render produced by
  NeuralAmpModelerCore for the same NAM and WAV within a bounded float tolerance.
- WAV decoding verifies mono, 48 kHz PCM24 input.
- The release application negotiates 48 kHz CoreAudio output and starts with a
  64-frame callback on the reference macOS machine.
- The full eight-channel model and cabinet response complete in real time while
  the Studio window remains interactive.
- The NAM module compiles to Windows COFF and Linux ELF objects using Zig target
  selection alone.
