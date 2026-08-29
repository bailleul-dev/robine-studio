# AUD-007: Tumnus Deluxe overdrive

Status: Accepted

## Summary

The gold single pedal describes the supplied Wampler Tumnus Deluxe capture grid.
The catalog default uses the neutral Normal-mode capture while preserving all
30 captures for a future discrete resolver. Real-time activation is deferred
because the current full-quality four-NAM chain misses its deadline on the
reference M1.

## Model mapping

- Pedal two MUST use processor resource `nam.wampler-tumnus-deluxe`.
- Its initial variant MUST be `normal-b5-m5-t5-l6-g5`, resolving to
  `Tumnus Deluxe Nrm B-5 M-5 T-5 L-6 G-5.nam`.
- Any future audible activation MUST load the full 8-channel submodel.
- The enclosure MUST expose five physical controls named Bass, Mids, Treble,
  Level, and Gain. They MUST remain non-interactive until the capture-grid
  resolver defines deterministic snapping and transitions.
- Until the NAM engine meets the full-chain deadline, Studio MUST project the
  Tumnus footswitch and amber LED as disabled and MUST NOT offer a false audible
  interaction.
- Future bypass transitions MUST use the existing 5 ms wet/dry smoother.

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
WAV -> SP Compressor -> Tumnus Deluxe -> King of Tone -> Dumble -> cabinet IR
```

The measured `ReleaseFast` experiment at 512 frames rendered 26.384 seconds of
audio in 30.518 seconds (`0.86x` real time), with 2,467 missed block deadlines.
Consequently, the real-time stage is not enabled. The implementation MUST keep
reporting this limitation rather than silently selecting the 3-channel model.

## Rights

The archive provides no license. These assets MUST remain local development
material until redistribution rights are known.
