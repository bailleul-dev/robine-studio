# AUD-006: King of Tone dual overdrive

Status: Implemented

## Summary

The violet double pedal is backed by the supplied LY Pedals King of Tone Clone
captures. Its two footswitches express the Orange and Red channel states shared
by the UI and audio runtime.

## Model mapping

- Pedal four MUST use processor resource `nam.king-of-tone-clone`.
- The pedal MUST use a double enclosure with two footswitches.
- Left footswitch MUST control the Orange channel; right footswitch MUST control
  the Red channel.
- Orange only MUST select `OrangeChannel CLN Boost`.
- Red only MUST select `Red Channel OD`.
- Both enabled MUST select `Both Channels DST`.
- Both disabled MUST produce a dry bypass of the King of Tone stage.
- Studio MUST select the full 8-channel submodel from every capture.
- Both channels are enabled initially, matching the default capture variant
  `both-channels-dst`.
- The physical description MUST retain three knobs per channel: Volume, Drive,
  and Tone. They MUST be marked non-interactive because this pack describes
  fixed capture settings rather than continuous parameters.
- The Orange and Red footswitch indicators MUST use amber and red light
  descriptions respectively.

## Transitions and real-time behavior

- A footswitch click MUST update its corresponding LED and canonical atomic
  state.
- Audio MUST fade the current King of Tone path to dry over 5 ms before changing
  capture, reset the new capture at the dry point, then fade it in.
- A channel change MUST evaluate at most one King of Tone NAM per audio block.
- The real-time callback MUST allocate no memory and acquire no lock.

## Signal chain

```text
WAV -> SP Compressor -> King of Tone -> Dumble amplifier -> cabinet IR -> output
```

## Imported asset policy

The two `_1` members in the supplied archive are byte-identical duplicates and
MUST NOT be versioned. The archive provides no license, so the three unique NAM
files are local development assets and MUST NOT enter a public distribution
until redistribution rights are known.

## Verification

- SHA-256 verification covers the three imported unique files.
- Model tests cover the violet pedal resource, form factor, default variant, and
  absence of unsupported rotary parameters.
- UI tests cover independent footswitch LED state.
- Transition tests cover all four channel combinations without concurrent NAM
  evaluation.
- The complete full-quality chain MUST remain faster than real time in the
  production `ReleaseFast` benchmark. A 64-frame stress run on the reference M1
  exposed deadline misses despite passing on average; the standalone therefore
  requests 512 frames and benchmarks that exact block size. This does not claim
  that future CLAP/VST3 hosts are ready for 64-frame operation.
