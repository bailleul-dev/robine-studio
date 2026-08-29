# Mesa/Boogie Lone Star and Lone Star Special

User-supplied NAM capture pack associated with the right amplifier in the
studio scene.

## Provenance

- Original archive: `MESA_Boogie Lone Star & Lone Star Special
  (LiveSPICE2NAM).zip`.
- Embedded modeler: `83ennui`.
- Embedded trainer label: TONE3000.
- The archive contains no license file. Do not redistribute this pack outside
  Robine's repository or release artifacts until its upstream license has been
  recorded.

The 119 captures retain their original names and bytes. The source archive
itself is not committed.

## Runtime default

`FULL-6L6[100w]_MESA!BoogieLoneStar-CH1.nam` is the initial deterministic full
amplifier choice paired with the native-48-kHz Lone Star C90 Dyn441 IR.

## Technical inventory

- 119 NAM 0.7.0 captures at 48 kHz.
- SlimmableContainer architecture with 3-channel and 8-channel WaveNet models.
- Full-amplifier, preamp-only, and power-amp-only captures.
- Lone Star 6L6/EL34 captures at 10, 50, and 100 W.
- Lone Star Special captures at 5, 15, and 30 W.
- Channel 1 plus Channel 2 Normal/Thick and clean/drive variants.

## Verification

```sh
shasum -a 256 -c SHA256SUMS
```
