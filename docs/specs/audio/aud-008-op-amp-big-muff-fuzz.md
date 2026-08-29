# AUD-008: Op-Amp Big Muff fuzz

Status: Accepted

## Summary

The green pedal describes the supplied Electro-Harmonix Op-Amp Big Muff capture
grid. The obsolete coral/red fuzz placeholder is removed from the rig. The
catalog default uses the median Tone and Sustain capture while preserving all
35 captures for a future discrete resolver. Audible activation follows the NAM
engine optimization milestone rather than adding another deadline-violating
stage to the current Core Audio callback.

## Model mapping

- The green pedal MUST use processor resource
  `nam.electro-harmonix-op-amp-big-muff`.
- Its initial variant MUST be `v6-tone5-sustain5`, resolving to
  `EHX IC Big Muff V-6 T-5 S-5.nam`.
- Any future audible activation MUST load the full 8-channel submodel.
- The enclosure MUST be a closed single pedal with right-side input, left-side
  output, one footswitch, and three controls named Volume, Tone, and Sustain.
- Those controls MUST remain non-interactive until the capture-grid resolver
  defines deterministic snapping and transitions.
- Tone Bypass captures MUST remain explicit discrete variants; Robine MUST NOT
  pretend they are positions of the continuous Tone control.
- Until the NAM engine meets the complete-chain deadline, Studio MUST project
  the Big Muff footswitch and LED as disabled and MUST NOT offer a false audible
  interaction.

## Capture grid

The archive contains 35 unique captures: seven Tone states (`2` through `7`
plus `Byp`) crossed with five Sustain states (`0`, `2`, `5`, `8`, and `10`).
Volume remains fixed at `6`. Filenames are provenance-bearing capture
descriptions, not proof of continuous parameters.

Every NAM is a 48 kHz 0.7.0 `SlimmableContainer` with 3-channel and 8-channel
WaveNet submodels. All embedded training metadata records ignored data checks.

## Performance boundary

The eventual production benchmark MUST evaluate the full signal order:

```text
WAV -> SP Compressor -> Tumnus Deluxe -> Op-Amp Big Muff -> King of Tone -> Dumble -> cabinet IR
```

Robine MUST optimize the full 8-channel NAM path or move it outside the native
audio callback behind a bounded, latency-declared pipeline. It MUST NOT meet the
deadline by silently selecting the 3-channel submodel.

## Rights

The archive provides no license. These assets MUST remain local development
material until redistribution rights are known.
