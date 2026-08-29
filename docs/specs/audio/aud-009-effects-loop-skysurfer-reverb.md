# AUD-009: Effects loop and Skysurfer reverb

Status: Implemented

## Summary

Robine introduces an effects-loop signal stage between amplifier inference and
cabinet impulse-response convolution. The supplied TC Electronic Skysurfer
Reverb is the first loop device. Its semantic stage also projects it onto a
second pedal row behind the input-chain pedals; the product description does
not contain renderer coordinates.

## Signal graph

The rig MUST expose distinct `amplifier_output` and `cabinet_input` endpoints.
Its ordered graph is:

```text
rig input
  -> input-chain pedals
  -> amplifier input
  -> amplifier NAM
  -> amplifier output / effects-loop send
  -> effects-loop pedals
  -> cabinet input / effects-loop return
  -> cabinet IR
  -> output
```

An effects-loop pedal MUST declare `signal_stage = effects_loop`. DSP ordering
and scene lane selection derive from that stage rather than its array index or
an authored x/y position.

## Skysurfer mapping

- The blue single pedal MUST use processor resource
  `ir.tc-electronic-skysurfer-reverb` with format `impulse_response`.
- The initial variant MUST be `hall-3-medium`, resolving to
  `Hall 3 - Medium.wav`.
- Its façade MUST expose Reverb, Mix, and Tone controls plus the physical
  Spring/Plate/Hall three-position selector.
- Spring MUST remain unavailable as an audio variant because the archive only
  supplies Hall and Plate responses.
- The footswitch and blue LED MUST share one atomic bypass state and use a 5 ms
  transition. Continuous controls and the response selector remain
  non-interactive until the discrete resolver is implemented.

## Response contract

- The ten source files MUST remain byte-for-byte identical to the archive.
- Every response is stereo IEEE Float32 at 48 kHz and MUST retain both channels.
- Every response frame MUST be processed; tail truncation and mono folding are
  forbidden.
- After stereo reverb, the cabinet IR MUST process left and right independently
  so the effects-loop image survives to the native stereo output.
- The long responses SHOULD use a hybrid or non-uniform partitioned convolver.
  Reusing 64-frame uniform partitions across six seconds is not an acceptable
  production cost model.
- Loading MAY allocate, decode, normalize declared gain, and precompute spectra.
  The real-time path MUST allocate no memory, access no files, lock no mutex, or
  log.

## Activation and implementation

The Hall 3 Medium response is audibly active. A shared-input hybrid stereo
convolver processes a 2,048-frame early region with 64-frame partitions and the
remaining response with 512-frame partitions. It introduces 64 frames of
declared latency, preserves all 268,668 stereo frames, performs no real-time
allocation, and feeds two independent full cabinet convolvers. The complete
full-quality benchmark reaches `3.88x` real time on the reference M1 with zero
measured deadline misses; no IR truncation, mono fold, or lightweight NAM
selection is used.

## Rights

The archive provides no license. These assets MUST remain local development
material until redistribution rights are known.
