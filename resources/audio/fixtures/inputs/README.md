# Development audio inputs

Deterministic source recordings used by offline DSP tests and development tools.
Fixtures in this directory are inputs only; generated renders and golden outputs
belong in separate test-artifact directories.

## `celestial-guitar-48k-mono.wav`

- Original filename: `ui_public_inputs_Celestial - Guitar.wav`.
- User-supplied development fixture.
- WAVE, mono, 48 kHz.
- Signed little-endian PCM, 24 bits packed in 3 bytes.
- 1,266,416 sample frames.
- Duration: approximately 26.383667 seconds.
- Audio payload: 3,799,248 bytes.

The source file is preserved without resampling, normalization, trimming, or
sample-format conversion. It is suitable for testing PCM24 decoding, offline NAM
rendering, block-size independence, and output regression hashes.

The supplied file contains no license metadata. Do not redistribute it outside
Robine's repository or release artifacts until its source license has been
recorded.

Verify the fixture from this directory with:

```sh
shasum -a 256 -c SHA256SUMS
```
