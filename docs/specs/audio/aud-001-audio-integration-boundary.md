# AUD-001: Audio integration boundary

Status: Deferred

## Summary

This specification reserves the boundary through which a future real-time audio
engine will consume core parameter events and expose metering to hosts and UI. It
does not specify an amplifier model or require audio in the rendering MVP.

## Architectural requirements

- Audio processing belongs to the top-level `audio` module.
- The audio module imports `core` and may compile validated structures from
  `model`, but MUST NOT import `ui`, `platform`, or a plugin format.
- DSP instances are owned by a host and are independent of editor instances.
- Audio processing continues when no UI is open.
- Opening or closing an editor does not rebuild or reset the DSP graph.

## Processor boundary

The future processor interface must cover:

- Preparation for sample rate, maximum block size, and channel layout.
- Activation, reset, processing, and deactivation.
- Bounded parameter events with optional sample offsets.
- Input and output audio buffers without ownership transfer.
- Reported latency and tail behavior.
- Bounded meter or telemetry output suitable for UI consumption.
- A non-real-time compilation boundary for electrical, external-routing, and
  acoustic graphs supplied by MOD-003.

The interface MUST NOT expose plugin-format event or buffer types.

## Real-time rules

Once activated, the processing path MUST NOT:

- Allocate or free general-purpose memory.
- Acquire a blocking mutex or wait for the UI.
- Access the filesystem or decode assets.
- Log synchronously.
- Call platform windowing or graphics APIs.

Large state changes and graph reconstruction happen outside the real-time path and
are published using an explicit safe handoff.

Semantic equipment and wiring graphs MUST NOT be traversed directly from the
real-time processing callback. They are compiled into bounded audio-owned runtime
structures before publication.

## UI communication

- UI changes enter audio through a bounded event transport using CORE-001 IDs and
  normalized values.
- Audio publishes bounded telemetry snapshots; UI polling frequency cannot affect
  processing correctness.
- The UI renders the canonical core value and treats telemetry as read-only.
- No UI scene node or control pointer crosses the audio boundary.

## Future acceptance criteria

- The same processor passes a host-independent offline render test and runs in
  standalone and plugin hosts.
- Processing performs no allocation after activation in instrumented tests.
- Closing the UI while processing does not change output or reset state.
- Parameter events retain order and sample offsets across the host adapter.
- A stalled UI cannot stall the processing thread.
