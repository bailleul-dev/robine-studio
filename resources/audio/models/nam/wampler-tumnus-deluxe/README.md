# Wampler Tumnus Deluxe

User-supplied NAM capture grid for local development.

## Provenance

- Original archive: `Wampler Tumnus Deluxe.zip`.
- Source archive SHA-256:
  `4aea34bf6c8743cb06eb55c8accb2d7b6443c2562dd8dd6b302b123a1a9fb2c8`.
- Embedded modeler: `outmodedelectronics`.
- Modeled gear: Wampler Tumnus Deluxe pedal.
- The archive contains no license. Do not include these files in a public
  distribution until redistribution rights have been established.

## Technical inventory

- 30 unique NAM 0.7.0 `SlimmableContainer` captures at 48 kHz.
- Every container provides 3-channel and full 8-channel WaveNet submodels.
- Filenames encode mode (`Nrm` or `Hot`) and the fixed Bass, Mids, Treble,
  Level, and Gain settings.
- All embedded training records mark their data checks as ignored. The captures
  remain useful user-supplied development material, but Robine records this
  provenance rather than treating them as independently validated.

The initial catalog mapping selects
`Tumnus Deluxe Nrm B-5 M-5 T-5 L-6 G-5.nam`. The remaining captures are
versioned as a discrete grid for a later capture resolver. The catalog mapping
does not activate another real-time NAM stage and does not imply continuous NAM
parameters.

## Verification

```sh
shasum -a 256 -c SHA256SUMS
```
