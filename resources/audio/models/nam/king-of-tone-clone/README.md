# LY Pedals King of Tone Clone

User-supplied NAM capture pack for local development.

## Provenance

- Original archive: `LY Pedals - King of Tone Clone.zip`.
- Source archive SHA-256:
  `dc728949f7bc21647fe94e207f2431517603bc1880b0b75e8955e979a4fdc738`.
- Embedded modeler: Daniel Sieber / `dsieber222`.
- Modeled gear: LY Pedals King of Tone clone.
- The archive contains no license. Do not include these models in a public
  distribution until redistribution rights have been established.

The three unique captures retain their original names and bytes. The archive's
`Both Channels DST_1` and `Red Channel OD_1` entries were byte-identical
duplicates and are intentionally not stored twice.

## Technical inventory

- NAM version: 0.7.0.
- Top-level architecture: `SlimmableContainer`.
- Sample rate: 48 kHz.
- Every container has 3-channel and full 8-channel WaveNet submodels.
- Captures: Orange channel clean boost, Red channel overdrive, and both
  channels distortion.
- The Orange capture metadata records ignored input-data checks; it is accepted
  as user-supplied development material, not silently treated as validated.

These are discrete fixed settings, not continuous knob parameters.

## Verification

```sh
shasum -a 256 -c SHA256SUMS
```
