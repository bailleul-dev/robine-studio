# AUD-007: Tumnus Deluxe overdrive

Status: Implemented

## Summary

The gold single pedal describes the supplied Wampler Tumnus Deluxe capture grid.
The catalog default uses the neutral Normal-mode capture while preserving all
30 captures for a future discrete resolver. The neutral capture is active in
the full-quality real-time chain.

## Model mapping

- Pedal two MUST use processor resource `nam.wampler-tumnus-deluxe`.
- Its initial variant MUST be `normal-b5-m5-t5-l6-g5`, resolving to
  `Tumnus Deluxe Nrm B-5 M-5 T-5 L-6 G-5.nam`.
- Any future audible activation MUST load the full 8-channel submodel.
- The enclosure MUST expose five physical controls named Bass, Mids, Treble,
  Level, and Gain. They MUST remain non-interactive until the capture-grid
  resolver defines deterministic snapping and transitions.
- Studio MUST project the Tumnus footswitch and amber LED from the same atomic
  state observed by audio.
- Bypass transitions MUST use the existing 5 ms wet/dry smoother.

## Capture grid

The archive contains 30 unique fixed captures spanning Normal and Hot modes,
three EQ profiles, and multiple Gain values. Filenames are provenance-bearing
capture descriptions, not proof of continuous parameters. Only the selected
capture is embedded into the application and evaluated in real time.

All embedded training metadata records ignored data checks. Robine preserves
the files as supplied for development and MUST NOT represent them as separately
validated captures.

## Performance

The target production benchmark includes the enabled Tumnus stage in signal
order:

```text
WAV -> SP Compressor -> Tumnus Deluxe -> Big Muff -> King of Tone -> Dumble -> Skysurfer -> cabinet IR
```

Following AUD-010, the complete five-NAM, stereo-reverb, dual-cabinet
`ReleaseFast` chain renders 26.384 seconds of audio in 6.792 seconds on the
reference M1 (`3.88x` real time). The embedded Tumnus evaluates its full
8-channel A2 model; no lightweight submodel is selected.

## Rights

The archive provides no license. These assets MUST remain local development
material until redistribution rights are known.
