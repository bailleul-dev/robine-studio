# Dumble ODS #102 Ford Hyper Accuracy+

User-supplied NAM capture pack for development and integration testing.

## Provenance

- Reported source: TONE3000.
- Original archive: `Dumble ODS #102 Ford Hyper Accuracy+.zip`.
- Model author in embedded metadata: `slamminmofo`.
- Modeled gear: `Dumble Overdrive Special 102 Ford`.
- Tone or model IDs were not included with the archive.
- The archive contains no license file. Do not redistribute this pack outside
  Robine's repository or release artifacts until its upstream license has been
  recorded.

The source archive itself is not committed. The extracted `.nam` files are kept
with their original names and bytes. `SHA256SUMS` records their imported content.

## Technical inventory

- 83 NAM files: 66 `_S` variants and 17 `_XS` variants.
- NAM file version: `0.7.0`.
- Top-level architecture: `SlimmableContainer`.
- Sample rate: 48 kHz.
- Gear type: amplifier.
- Embedded tone type: crunch.
- Every file contains two WaveNet submodels: a 3-channel lightweight model and
  an 8-channel higher-accuracy model.
- No cabinet impulse response is included.

The words in the filenames describe discrete capture settings. They are not
continuous amplifier parameters: switching from `CLN_WARM` to `OD_PAB_HIGAIN`,
for example, loads another neural model rather than turning a virtual knob.

## Verification

From this directory:

```sh
shasum -a 256 -c SHA256SUMS
```
