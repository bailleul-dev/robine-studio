# TC Electronic Skysurfer Reverb

User-supplied stereo reverb impulse responses for local development.

## Provenance

- Original archive: `TC Electronic Skysurfer Reverb (Hall and plate).zip`.
- Source archive SHA-256:
  `40f8649d4243b91f063c62b0128a927dc58d6345d7cd1d3cc765cfffe91cb772`.
- Described hardware: TC Electronic Skysurfer Reverb pedal.
- The archive contains no license. Do not include these files in a public
  distribution until redistribution rights have been established.

## Technical inventory

- 10 unique stereo IEEE Float32 WAV responses at 48 kHz.
- Five Hall and five Plate variants range from `Very short` to `Very long`.
- Durations range from approximately 5.01 to 6.18 seconds.
- Both channels and every response frame MUST be preserved. These are not mono
  cabinet IRs and MUST NOT be passed through the current mono cabinet path.

The initial catalog mapping selects `Hall 3 - Medium.wav`. The duration labels
are discrete capture identities; they do not establish continuous knob values.
The supplied archive has no Spring response even though the physical pedal has
a Spring/Plate/Hall selector.

## Verification

```sh
shasum -a 256 -c SHA256SUMS
```
