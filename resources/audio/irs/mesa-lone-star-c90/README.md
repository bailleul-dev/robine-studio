# Mesa Lone Star C90

User-supplied cabinet impulse responses associated with the Mesa/Boogie Lone
Star combo in the studio scene.

## Provenance

- Original archive: `Ultra Brutal Karnivore_C90 IR Pack.zip`.
- Filename labels describe a Marshall 1960A/Karnivore and Mesa Lone Star 1x12
  C90 blend; the pack does not provide additional routing documentation.
- Microphones represented by the filenames: SM57, SM58, MD 441-style `Dyn441`,
  and an R-121/SM57 blend.
- The archive contains no license file. Do not redistribute this pack outside
  Robine's repository or release artifacts until its upstream license has been
  recorded.

The four WAV files retain their original names and bytes. The source archive
itself is not committed.

## Runtime default

`Marshall 4x12 1960A SM57 Karnivore - Mesa Lone Star 1x12 C90 Dyn441.wav` is
the initial deterministic Lone Star cabinet choice because it is supplied
natively at the engine's 48 kHz rate.

## Technical inventory

- Four mono, 24-bit PCM IRs.
- SM57 and Dyn441 variants: 48 kHz.
- SM58 and R121/SM57 variants: 44.1 kHz.
- Durations range from approximately 18 to 544 ms.

## Verification

```sh
shasum -a 256 -c SHA256SUMS
```
