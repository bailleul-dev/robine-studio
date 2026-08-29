# Orange 2x12 V30 cabinet IR pack

User-supplied cabinet impulse responses for development and integration testing.

## Provenance

- Original archive: `Orange 2x12 V30.zip`.
- Reported cabinet: Orange 2x12 with Celestion Vintage 30 speakers.
- Archive SHA-256: `b64f9faa855e658b2189eaef597fa4b318614f4b934570b2c15cab20bb7ac67f`.
- The archive contains no author, source URL, geometry map, or license file.
- Do not redistribute this pack outside Robine's repository or release artifacts
  until its upstream license has been recorded.

The source archive is not committed. All extracted WAV files retain their
original names and bytes.

## Inventory

- 20 mono impulse responses.
- 48 kHz, signed PCM24, 24,000 frames, 500 ms each.
- Microphone families: `SM57`, `e906`, `C414`, and `RM700`.
- Five opaque positions per microphone: `A` through `E`.

The archive does not define the physical meaning of positions A–E. Code and UI
MUST therefore treat them as stable variant IDs rather than inferred distances
or cone positions. `SM57 C` is the initial development default, not a claim
about its physical placement.

## Verification

From this directory:

```sh
shasum -a 256 -c SHA256SUMS
```
