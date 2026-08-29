# Robine Amp specifications

This directory contains the normative product and engineering specifications for
Robine Amp.

Specifications are grouped by domain and named using:

```text
docs/specs/<domain>/<feature-id>-<feature-name>.md
```

Feature identifiers are stable. Renaming a specification must not change its
identifier, and identifiers from removed specifications must not be reused.

The words **MUST**, **SHOULD**, and **MAY** describe mandatory requirements,
recommended behavior, and optional behavior respectively.

## Specification index

| Feature | Domain | Status | Description |
| --- | --- | --- | --- |
| [ARC-001](architecture/arc-001-system-architecture.md) | Architecture | Draft | Model-driven system boundaries and dependency rules |
| [CORE-001](core/core-001-parameter-and-state-model.md) | Core | Draft | Shared parameter, gesture, automation, and state model |
| [MOD-001](model/mod-001-equipment-description.md) | Model | Draft | Semantic descriptions of pedals, amplifiers, cabinets, and rigs |
| [MOD-002](model/mod-002-assembly-and-spatial-relations.md) | Model | Draft | Mechanical assembly, placement constraints, articulation, and views |
| [MOD-003](model/mod-003-connectivity-and-wiring.md) | Model | Draft | Internal electronics, external cabling, and typed connectivity graphs |
| [MOD-004](model/mod-004-pedal-form-factors.md) | Model | Draft | Standard pedal footprints and enclosure definitions |
| [MOD-005](model/mod-005-jack-mounting.md) | Model | Draft | Semantic jack surfaces, slots, sockets, plugs, and cable anchors |
| [UI-001](ui/ui-001-scene-composition.md) | UI | Draft | Equipment-to-scene projection and visual composition |
| [UI-002](ui/ui-002-rendering-pipeline.md) | UI | Draft | Hybrid 3D equipment and 2D overlay rendering pipeline |
| [UI-003](ui/ui-003-controls-and-interaction.md) | UI | Draft | Semantic equipment actions and parameter gestures |
| [UI-004](ui/ui-004-assets-and-materials.md) | UI | Draft | Asset compilation and procedural material system |
| [UI-005](ui/ui-005-focused-equipment-navigation.md) | UI | Draft | Semantic picking and focused equipment views |
| [UI-006](ui/ui-006-runtime-lighting-and-materials.md) | UI | Draft | Runtime material response, studio lighting, reflections, and shadows |
| [UI-007](ui/ui-007-procedural-pedalboard-3d.md) | UI | Draft | Description-driven procedural 3D pedalboard projection |
| [UI-008](ui/ui-008-emissive-indicators.md) | UI | Draft | HDR pedal LEDs with bounded local light spill |
| [UI-009](ui/ui-009-pedal-control-hardware.md) | UI | Draft | Procedural chicken-head knobs and metal footswitches |
| [UI-010](ui/ui-010-progressive-idle-ray-tracing.md) | UI | Draft | Bounded progressive ray-traced contact shading for static equipment views |
| [UI-011](ui/ui-011-studio-chrome-and-context-controls.md) | UI | Draft | Persistent toolbar, contextual equipment strip, transport, and visual hierarchy |
| [STU-001](studio/stu-001-rendering-engine-mvp.md) | Studio | Draft | Initial equipment-modeling and rendering milestone |
| [AUD-001](audio/aud-001-audio-integration-boundary.md) | Audio | Draft | Real-time audio subsystem boundary |
| [AUD-002](audio/aud-002-native-audio-backends.md) | Audio | Draft | Core Audio, ASIO, PipeWire, and ALSA transport contract |
| [AUD-003](audio/aud-003-development-nam-playback.md) | Audio | Implemented | Portable WAV-to-NAM startup playback through the native output |
| [AUD-004](audio/aud-004-cabinet-ir-convolution.md) | Audio | Implemented | Complete portable cabinet IR convolution after NAM inference |
| [HOST-001](hosts/host-001-runtime-hosts.md) | Hosts | Deferred | Studio, standalone, CLAP, and VST3 hosts |

## Status lifecycle

- **Draft**: open to structural changes.
- **Accepted**: approved for implementation.
- **Implemented**: acceptance criteria are verified.
- **Deferred**: intentionally outside the active milestone.
- **Superseded**: replaced by another identified specification.
