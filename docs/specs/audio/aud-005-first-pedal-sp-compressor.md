# AUD-005: First-pedal SP Compressor

Status: Implemented

## Summary

The first pedal in the demo signal graph is an SP Compressor backed by the
imported Low, Mid, and High captures. Its footswitch and range selector control
canonical states shared by the UI and audio runtime.

## Model mapping

- Pedal zero MUST describe processor resource `nam.sp-compressor` and capture
  variant `mid`.
- The development resource resolver MUST map the three selector positions to
  `SpCompressor_Low.nam`, `SpCompressor_Mid.nam`, and
  `SpCompressor_High.nam` respectively.
- Studio MUST select the full eight-channel NAM submodel. It MUST NOT silently
  substitute the lightweight three-channel model.
- `Mid` MUST be the initial position.
- The initial pedal MUST expose no rotary controls. Fixed-capture NAM assets do
  not provide continuous `VOLUME` or `BLEND` parameters, so presenting inactive
  knobs would misrepresent the available processing model.

## Range interaction

- The pedal description MUST expose one `RANGE` switch with ordered positions
  `LOW`, `MID`, and `HIGH` and front-to-back physical movement.
- Clicking its projected metal toggle MUST cycle `LOW -> MID -> HIGH -> LOW`.
- The lever MUST stand upright at `MID` and tilt approximately 21 degrees along
  the pedal depth axis for `LOW` and `HIGH`; it MUST NOT rotate sideways.
- The UI MUST display the requested position immediately.
- Audio MUST fade the current compressor path to dry over 5 ms, select and reset
  the requested full-quality model only after the wet mix reaches zero, then
  fade the new path in over 5 ms.
- Only one compressor NAM MUST be evaluated per audio block. Mode changes MUST
  NOT transiently double neural inference cost on the real-time thread.

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
mono WAV -> SP Compressor [Low | Mid | High] -> full amplifier NAM -> cabinet IR -> native output
```

## Rights

The supplied archive contains no license. The captures MAY be used for local
development but MUST NOT be included in a public distribution until their
redistribution rights are established.

## Verification

- Unit tests cover canonical bypass toggling, three-position cycling, bounded
  bypass smoothing, and dry-point mode transitions.
- Picking the projected first footswitch changes its semantic state rather than
  editing render-only LED data.
- Rebuilding the same mesh storage MUST still upload the new LED material and
  emissive-light list to the GPU.
- Picking the projected range toggle MUST cycle all three captures and rebuild
  its lever orientation.
- The active full-quality pedal, amplifier, and cabinet chain MUST be benchmarked
  against the real-time duration of the development fixture.
