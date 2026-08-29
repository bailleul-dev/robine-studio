# Electro-Harmonix Op-Amp Big Muff

User-supplied NAM capture grid for local development.

## Provenance

- Original archive: `Electro-Harmonix Op-Amp Big Muff.zip`.
- Source archive SHA-256:
  `e39c19d92e235fc36843d4af7e5e4a6ebf54140355481dfa89c383a0fea2bb45`.
- Embedded modeler: `outmodedelectronics`.
- Modeled gear: Electro-Harmonix Op-Amp Big Muff pedal.
- The archive contains no license. Do not include these files in a public
  distribution until redistribution rights have been established.

## Technical inventory

- 35 unique NAM 0.7.0 `SlimmableContainer` captures at 48 kHz.
- Every container provides 3-channel and full 8-channel WaveNet submodels.
- Filenames encode fixed Volume, Tone, and Sustain settings. Five captures use
  the pedal's Tone Bypass state instead of a Tone value.
- All embedded training records mark their data checks as ignored. Robine
  preserves that provenance rather than treating the captures as independently
  validated.

The initial catalog mapping selects `EHX IC Big Muff V-6 T-5 S-5.nam`. The
remaining captures form a discrete grid for a later capture resolver. This
catalog mapping does not activate another real-time NAM stage and does not
imply continuous NAM parameters.

## Verification

```sh
shasum -a 256 -c SHA256SUMS
```
