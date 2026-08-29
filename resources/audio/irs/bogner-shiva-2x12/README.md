# Bogner Shiva 2x12

User-supplied cabinet impulse responses associated with the Bogner Shiva combo
in the studio scene.

## Provenance

- Original archive: `Bogner Shiva 2x12.zip`.
- Cabinet label: Bogner Shiva 2x12.
- Speaker label: Celestion Vintage 30.
- Microphones represented by the filenames: Shure SM57 and Royer R-121.
- The archive contains no license file. Do not redistribute this pack outside
  Robine's repository or release artifacts until its upstream license has been
  recorded.

The four source WAV files retain their original names and bytes. The source
archive itself is not committed.

## Runtime default

`Bogner Shiva 212_V30-R121 01-48k-runtime.wav` is a deterministic 48 kHz
derivative of `Bogner Shiva 212_V30-R121 01.wav`, produced with macOS
`afconvert` as mono signed 24-bit PCM. The original is 44.1 kHz; the derived
file avoids runtime resampling in the initial 48 kHz audio engine.

## Technical inventory

- Four original mono, 24-bit PCM IRs at 44.1 kHz.
- One mono, 24-bit PCM runtime derivative at 48 kHz.
- Source durations range from approximately 33 to 42 ms.

## Verification

```sh
shasum -a 256 -c SHA256SUMS
```
