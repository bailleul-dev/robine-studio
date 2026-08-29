# AUD-005: First-pedal SP Compressor

Status: Implemented

## Summary

The first pedal in the demo signal graph is an SP Compressor backed by the
imported `SpCompressor_Mid.nam` capture. Its footswitch controls one canonical
bypass state shared by the UI and audio runtime.

## Model mapping

- Pedal zero MUST describe processor resource `nam.sp-compressor` and capture
  variant `mid`.
- The development resource resolver MUST map that description to
  `SpCompressor_Mid.nam`.
- Studio MUST select the full eight-channel NAM submodel. It MUST NOT silently
  substitute the lightweight three-channel model.
- `Low` and `High` MUST remain versioned alongside `Mid`, but they are not
  selected until a discrete range-control interaction is specified.
- The initial visible rotary controls are `VOLUME` and `BLEND`. They describe
  the physical pedal but do not interpolate NAM captures in this milestone.

## Bypass interaction

- Clicking the first pedal's first footswitch MUST toggle the compressor's
  canonical enabled state.
- When disabled, dry input MUST bypass the compressor before amplifier
  inference, and the corresponding LED emission and local light intensity MUST
  become zero.
- Clicking again MUST enable the compressor and restore the LED brightness from
  the pedal description.
- The UI-to-audio state transfer MUST be lock-free and allocation-free.
- Audio MUST ramp between dry and processed signals over 5 ms to prevent a hard
  discontinuity at the footswitch edge.
- The compressor model MAY continue processing while bypassed so that enabling
  it does not expose stale causal state. Its processed output MUST not enter the
  audible chain after the bypass ramp reaches zero.

## Signal chain

```text
mono WAV -> SP Compressor Mid -> full amplifier NAM -> cabinet IR -> native output
```

## Rights

The supplied archive contains no license. The captures MAY be used for local
development but MUST NOT be included in a public distribution until their
redistribution rights are established.

## Verification

- Unit tests cover canonical switch toggling and bounded bypass smoothing.
- Picking the projected first footswitch changes its semantic state rather than
  editing render-only LED data.
- Rebuilding the same mesh storage MUST still upload the new LED material and
  emissive-light list to the GPU.
- The active full-quality pedal, amplifier, and cabinet chain MUST be benchmarked
  against the real-time duration of the development fixture.
