# AUD-002: Native audio backends

Status: Draft

## Summary

Robine standalone hosts use a narrow session abstraction over the production
audio API of each operating system:

- Core Audio HAL on macOS.
- ASIO on Windows.
- PipeWire on current Linux desktops, with direct ALSA as a fallback.

CLAP and VST3 hosts do not open a native audio session. A DAW supplies their
buffers and timing directly to the host-independent processor defined by AUD-001.

This distinction is structural: native device transport belongs to `platform`
and standalone orchestration belongs to `hosts`; neither belongs to the DSP
module.

## Backend findings

### Core Audio HAL

An `AudioDeviceIOProc` receives input and output `AudioBufferList` values for one
I/O cycle, together with separate current, input-acquisition, and
output-presentation timestamps. A device owns the I/O cadence and may expose
interleaved or non-interleaved streams.

The backend uses the modern `AudioObject` property API for enumeration,
persistent device UIDs, sample rate, stream configuration, buffer frame size,
default-device changes, and device-loss notifications. It uses
`AudioDeviceCreateIOProcID` rather than the deprecated `AudioDeviceAddIOProc`.

A single physical duplex device provides the preferred zero-copy path. Selecting
unrelated input and output devices creates two clock domains and therefore
requires an explicit asynchronous bridge above the native session.

### Windows ASIO

An ASIO driver supplies double-buffered input and output channel buffers and
invokes `bufferSwitchTimeInfo` or the legacy `bufferSwitch` callback. Input and
output for a driver are synchronous and share the selected buffer size and sample
rate. The host must accept the sample type reported for every channel; it cannot
assume floating point samples.

`ASIOGetBufferSize` reports minimum, maximum, preferred, and granular buffer
sizes. The driver may request a reset, report a sample-rate or latency change,
lose synchronization, or report an overload. These notifications are restart or
telemetry events and MUST NOT cause allocation inside the buffer callback.

ASIO time information is optional. When present, the adapter preserves sample
position, system time, speed, and validity flags. Input and output latencies are
reported separately.

The ASIO SDK is dual-licensed under GPLv3 or Steinberg's proprietary agreement.
Robine MUST select and record a compatible product license before SDK files are
vendored or a Windows ASIO binary is distributed. Until then, the public Robine
transport interface must not contain copied ASIO declarations.

WASAPI is not a production backend for the initial Robine standalone host. A
future shared-mode fallback MAY be added without changing this specification.

### Linux PipeWire

A PipeWire `pw_filter` represents Robine as a graph node with input and output
ports. Its real-time `process` callback can receive both directions in one graph
quantum. PipeWire negotiates the graph rate, quantum, channel positions, and
buffer format, and provides graph position and monotonic timing.

The backend requests mapped 32-bit float DSP buffers and performs no file,
allocation, blocking, or non-real-time PipeWire operation in `process`. Graph and
registry changes stay on the control loop. Port links and the selected graph
driver determine routing rather than a hard-coded hardware device pair.

PipeWire is the default Linux backend because it composes with the desktop audio
graph, professional routing, and PipeWire's JACK compatibility without Robine
owning a second graph model.

### Linux ALSA fallback

ALSA exposes capture and playback as separate PCM handles. The fallback backend
uses poll-driven or memory-mapped transfers, negotiates actual hardware and
software parameters, and links compatible PCM handles when the driver supports
`snd_pcm_link`.

ALSA periods are not assumed to equal the full ring-buffer size. Capture and
playback availability can differ, and an overrun or underrun moves a PCM to XRUN
state. The adapter reports the discontinuity, calls the ALSA recovery operation
outside the processor invocation, resets affected history, and restarts the
session.

Direct ALSA commonly owns the hardware path and is therefore a fallback, not the
default desktop integration. An unlinked input/output pair is treated as two
clock domains.

## Architectural split

The implementation is split into three independent layers:

```text
platform native backend     standalone session engine       audio processor
-----------------------     -------------------------       ---------------
devices and permissions     routing and channel mapping     planar f32 DSP
format negotiation          format conversion               parameter events
native callback/thread  ->  clock/drift policy          ->  NAM and later DSP
device-loss events          restart and safe handoff        no OS dependency
```

- `platform/audio` owns the platform-neutral transport contract.
- `platform/<os>/audio` owns native handles, SDK types, enumeration, session
  negotiation, and callback adaptation.
- `hosts/standalone` owns device choice, channel mapping, conversion scratch,
  asynchronous bridging, and processor lifecycle.
- `audio` owns only host-independent processing.

No Core Audio, ASIO, PipeWire, ALSA, COM, file-descriptor, or native thread type
may cross into `audio`.

## Session contract

### Control plane

The non-real-time control plane exposes:

- Backend identity and capabilities.
- Enumeration of stable opaque device or graph-node identifiers.
- Human-readable names and input/output channel counts.
- Supported or preferred sample rates, buffer-frame ranges, sample formats, and
  clock-domain information when the backend can report them.
- Default-device and device-list change notifications.
- Session open, start, stop, restart, and close operations.
- A native control-panel request where the backend supports one, notably ASIO.

Opening a session returns the negotiated configuration. A requested sample rate,
block size, sample format, or device is a preference until the backend confirms
it. The DSP is prepared from the confirmed configuration, never from the request.

### Real-time data plane

The backend invokes one bounded callback with a `ProcessCycle` containing:

- Zero or more input channel views.
- Zero or more output channel views.
- The actual frame count for this cycle.
- The native sample format and memory layout.
- A `StreamTime` with optional sample position, monotonic time, input acquisition
  time, output presentation time, and independent validity flags.
- Status flags for input discontinuity, output underrun, overload, clock change,
  and silence.

Input-only and output-only sessions use the same callback with one side absent.
Frame count is variable up to the negotiated maximum even when a backend normally
uses a fixed quantum.

The native session does not call the amp DSP directly. The standalone session
engine maps and converts each cycle into the canonical AUD-001 format: bounded,
non-owning, non-interleaved `f32` channel slices. Conversion uses memory allocated
before activation.

### Clock domains and duplex

A session reports whether its input and output share a clock domain.

- Core Audio on one duplex device, one ASIO driver, and one scheduled PipeWire
  filter normally provide synchronous duplex processing.
- Separate Core Audio devices, unlinked ALSA PCMs, or any independently clocked
  endpoints are asynchronous even when nominal rates match.

The native abstraction MUST NOT pretend that equal sample-rate numbers imply a
shared clock. An asynchronous session requires a bounded FIFO plus drift
estimation and resampling in the standalone session engine. This bridge is not
part of the platform backend and is not required for the first macOS slice.

## State and failure model

A session follows this state machine:

```text
closed -> open -> running -> stopped -> closed
                  |    ^
                  v    |
                restart
```

Native callbacks only publish bounded flags or counters. Device invalidation,
sample-rate changes, buffer-size changes, ASIO reset requests, PipeWire graph
renegotiation, ALSA suspend, and XRUN recovery schedule a control-plane restart.

During a discontinuity the output is cleared and stateful DSP is reset before
processing resumes. The UI may display telemetry, but it never participates in
recovery.

## Initial implementation decisions

- macOS first backend: direct Core Audio HAL on one duplex device.
- Windows production backend: ASIO, behind a narrow C/C++ bridge if required by
  the SDK ABI; all Robine-owned orchestration remains Zig.
- Linux default backend: PipeWire `pw_filter`.
- Linux fallback: ALSA PCM.
- Canonical processor buffers: non-interleaved `f32`.
- Initial standalone channel layout: one selected mono input processed to two
  output channels.
- Initial preferred model rate: 48 kHz, with the actual device rate always
  negotiated and later reconciled with the NAM model rate explicitly.
- Graybox processing is outside this milestone.

## Acceptance criteria

- The same transport contract represents Core Audio HAL, ASIO, PipeWire, and ALSA
  without storing backend-specific types in common structures.
- A fake backend can vary frame counts, layouts, timestamps, and discontinuity
  flags in deterministic tests.
- A backend can report synchronous duplex or independent clock domains without
  changing the callback signature.
- No allocation, blocking lock, file access, logging, UI call, or control-plane
  API occurs in a native real-time callback.
- Native sample conversion and channel mapping use only preallocated memory.
- Device loss or an XRUN produces silence and a bounded restart request rather
  than invoking recovery from DSP code.
- Standalone and plugin hosts feed the same AUD-001 processor interface.
