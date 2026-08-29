# HOST-001: Runtime hosts

Status: Deferred

## Summary

Robine products are host adapters around shared core, equipment model, UI, and
future audio modules. The planned hosts are Studio, standalone, CLAP, and VST3.

## Host responsibilities

A host owns:

- Product and instance lifecycle.
- Translation of external parameter, state, audio, and window APIs.
- Creation of core stores, equipment instances, processors, and editor instances.
- Platform surface attachment and event-loop integration.
- Packaging, validation, and product metadata.

A host does not own parameter metadata, equipment definitions, assembly or wiring
semantics, control definitions, DSP algorithms, or material assets.

## Host matrix

| Host | UI | Audio | External format |
| --- | --- | --- | --- |
| Studio | Required | Simulated only | Native desktop application |
| Standalone | Required | Device input/output | Native desktop application |
| CLAP | Optional editor | Host buffers | CLAP |
| VST3 | Optional editor | Host buffers | VST3 |

The processor and editor lifecycles are independent in every audio-capable host.

## Editor embedding

- The same `model` instance and `ui` projection system are used by all hosts.
- A platform adapter can attach the editor surface to a top-level Studio window or
  a DAW-owned child view.
- Editor creation, visibility, resize, scale, and destruction are explicit.
- The editor does not own the DAW event loop.
- Multiple plugin instances can create independent editors in one process.

## Format strategy

CLAP is the preferred native plugin contract because its ABI and GUI parent model
map cleanly to Zig and the platform surface abstraction. VST3 may initially be
provided through a narrowly scoped CLAP-to-VST3 adapter or a direct Zig adapter.
That implementation decision does not change the shared core, UI, or audio APIs.

No plugin SDK type may appear outside its host adapter.

## Validation

Future plugin milestones include:

- Unit tests for adapter translations.
- State and parameter parity tests across all hosts.
- Official CLAP and VST3 validation tools.
- Host smoke tests for editor open/close, resize, scale, automation, save/load,
  suspend/resume, and multiple instances.
- Standalone device-loss and audio-restart tests.

## Future acceptance criteria

- A preset created in standalone restores equivalent values in CLAP and VST3.
- Parameter IDs, defaults, formatting, and automation behavior match across hosts.
- The same editor scene and assets render in every host.
- Audio continues safely while an editor is repeatedly opened and closed.
- Host adapters contain translation code only and do not duplicate product logic.
