# Bogner Shiva EL34

User-supplied NAM capture pack associated with the left amplifier in the studio
scene.

## Provenance

- Original archive: `Bogner Shiva EL34 new and new captures added.zip`.
- Filename label: Bogner Shiva EL34.
- The embedded metadata does not identify a modeler or license.
- Do not redistribute this pack outside Robine's repository or release
  artifacts until its upstream license has been recorded.

The five captures retain their original names and bytes. The source archive
itself is not committed.

## Runtime default

`bogner ch1.nam` is the initial deterministic clean-channel choice paired with
the Bogner Shiva 2x12 V30 R-121 runtime IR.

## Technical inventory

- Five NAM 0.7.0 captures covering channel 1 and channel 2 boost/shift states.
- SlimmableContainer architecture with 3-channel and 8-channel WaveNet models.
- Sample rate: 48 kHz.

## Verification

```sh
shasum -a 256 -c SHA256SUMS
```
