# AUD-004: Cabinet impulse-response convolution

Status: Implemented

## Summary

Robine applies a complete cabinet impulse response after amplifier inference.
The initial cabinet is the imported Orange 2x12 V30 pack, with its `SM57 C`
response selected as the development default.

## Asset contract

- Imported WAV files MUST remain byte-for-byte identical to the source archive.
- Every response in the initial pack is mono PCM24, 48 kHz, 24,000 frames
  (500 ms).
- The complete 24,000-tap response MUST be processed. Energy-based truncation
  is forbidden even when most measured energy occurs near the start.
- The microphone labels `SM57`, `e906`, `C414`, and `RM700` are source metadata.
- Positions `A` through `E` MUST remain opaque identifiers until the source
  provides a reliable geometry mapping. The UI MUST NOT invent distances,
  angles, or cone positions for them.
- The imported pack has no supplied license. It MAY be used for local
  development but MUST NOT be redistributed in a public release until its
  rights are established.

## Processing contract

- Convolution MUST be implemented in portable Zig and MUST NOT depend on a
  platform DSP framework.
- The initial runtime MUST use uniform partitioned overlap-add convolution with
  a 64-frame partition and FFT size 128.
- Reported algorithmic latency MUST be 64 frames: 1.333 ms at 48 kHz.
- Loading MAY allocate and precompute spectra. The real-time processing path
  MUST allocate no memory, access no files, lock no mutex, or log.
- Resetting a cabinet MUST clear input spectra, overlap, pending input, and
  pending output deterministically.
- Studio MUST flush the response tail after the development input ends, then
  emit silence.

## Initial signal chain

```text
mono WAV -> full compressor NAM -> full King of Tone NAM -> full amplifier NAM -> Orange 2x12 V30 SM57 C -> native output
```

The default selection is for development only and is not a claim that position
`C` is a particular physical microphone placement.

## Verification

- A deterministic unit test MUST compare partitioned convolution against a
  direct time-domain FIR across the entire output and fixed-latency prefix.
- The full compressor, King of Tone, and amplifier NAM chain plus complete
  24,000-tap cabinet response MUST complete faster than real time in a release
  build on the reference Apple M1 machine. The production DSP build uses
  `ReleaseFast`; validation tests remain `ReleaseSafe`.
- The convolver source MUST compile for the supported Windows and Linux Zig
  targets without platform DSP dependencies.
