# ARC-001: System architecture

Status: Draft

## Summary

Robine Amp is a Zig application composed of `core`, `model`, `ui`, `audio`,
`platform`, and `hosts` subsystems. The semantic equipment model is the source of
truth for pedals, amplifiers, cabinets, electronics, assemblies, and wiring. UI
scenes and future audio graphs are projections of that model.

The first milestone develops the equipment model, interactive rendering engine,
and Robine Studio without audio, but the repository and dependency rules must
support later standalone, CLAP, and VST3 products without restructuring the model
or UI project.

## Goals

- Keep domain logic independent of operating systems and plugin formats.
- Describe equipment through domain objects and relationships rather than render
  coordinates.
- Make the amp-oriented UI engine reusable by every host.
- Add audio later without moving parameter or state ownership into the UI.
- Prevent desktop, CLAP, and VST3 behavior from diverging.
- Keep host and platform concerns at the edges of the system.

## Non-goals

- Implementing audio processing in the rendering-engine MVP.
- Implementing a general-purpose GUI toolkit.
- Selecting the final DSP graph or amplifier models.
- Providing plugin-format-specific parameter registries or state formats.

## Top-level source layout

```text
src/
├── robine.zig
├── core/
├── model/
├── ui/
├── audio/
├── platform/
└── hosts/
    ├── studio/
    ├── standalone/
    ├── clap/
    └── vst3/
```

Tools and generated artifacts live outside `src`:

```text
tools/
├── asset-compiler/
└── snapshot-runner/

assets/
├── source/
└── manifests/

tests/
├── unit/
├── integration/
└── snapshots/
```

Compiled assets and build outputs MUST remain under `zig-out` or the Zig cache
and MUST NOT be committed unless a specification explicitly identifies them as
test fixtures.

## Dependency rules

The allowed production dependencies are:

```text
hosts ─────→ core, model, ui, audio, platform
model ─────→ core
ui ────────→ core, model
audio ─────→ core, model
platform ──→ operating-system and graphics/audio APIs
```

The following dependencies are forbidden:

- `core` importing `model`, `ui`, `audio`, `platform`, or `hosts`.
- `model` importing `ui`, `audio`, `platform`, or `hosts`.
- `ui` importing `audio` or a plugin format.
- `audio` importing `ui` or a plugin format.
- A host defining independent parameter metadata or state serialization.
- Product descriptions containing renderer coordinates, renderer nodes, or
  platform-native handles.
- Platform-native handles escaping into `core`, `model`, `ui` scene definitions,
  or `audio` processing code.

`ui` MAY consume an opaque rendering surface and normalized input events through
interfaces owned by `platform`. It MUST NOT depend on a top-level application
window and must be usable inside a host-owned plugin window.

## Shared ownership

| Concern | Owner |
| --- | --- |
| Parameter identity, range, defaults, and display metadata | `core` |
| Preset and session state schema | `core` |
| Equipment descriptions, assemblies, wiring, and semantic actions | `model` |
| Derived scenes, rendering, controls, cameras, and visual assets | `ui` |
| DSP graph and real-time processing | `audio` |
| Windows, graphics surfaces, devices, timers, and OS events | `platform` |
| Product lifecycle and format callbacks | `hosts` |

There MUST be one canonical parameter registry, one canonical equipment model,
and one canonical state codec.

## Execution model

- The UI runs on the host or application's main thread unless a platform adapter
  explicitly guarantees another compatible UI thread.
- Future audio processing runs on a real-time thread that cannot block on the UI.
- Communication across UI and audio thread boundaries uses bounded messages or
  atomic snapshots; it MUST NOT use a shared mutable object graph.
- Asset decoding, compilation, and file watching MUST NOT run on a future audio
  thread.

## Technology constraints

- All Robine-owned production code MUST be written in Zig.
- C ABI headers and narrowly scoped third-party platform or format adapters MAY
  be imported or linked when replacing them would create a separate framework
  project.
- Third-party code MUST be isolated behind interfaces owned by Robine.
- The initial toolchain target is Zig 0.16.x.

## Acceptance criteria

- The source tree exposes independent `core`, `model`, `ui`, `audio`, `platform`,
  and `hosts` modules.
- An import-boundary test or equivalent build rule rejects the forbidden
  dependency directions.
- Robine Studio can use `core`, `model`, and `ui` without linking the audio
  module.
- A reference pedal description contains no product-authored render coordinates.
- A test host can instantiate two independent UI instances in one process.
- No UI type appears in the public audio processing interface.
