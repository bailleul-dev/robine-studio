# STU-001: Equipment-modeling and rendering MVP

Status: Draft

## Summary

The first executable product milestone is Robine Studio: a desktop development
host for exercising the semantic equipment model and its generated interactive
views with real core parameters and simulated automation. Its initial rendering
stage contains no sound generation or audio-device processing; AUD-003 adds the
subsequent development playback stage without changing the rendering boundary.

The milestone proves that pedals, electronics, pedalboards, amplifiers, cabinets,
speakers, microphones, and their connections can be described through domain
relationships, inspected from multiple views, and rendered without product-level
scene coordinates.

## Deliverables

The milestone delivers:

- A desktop Studio executable.
- The shared core parameter and state model.
- The semantic equipment, assembly, articulation, and connectivity models.
- The UI projection, renderer, controls, materials, camera, and asset runtime.
- An asset compiler.
- A deterministic snapshot runner.
- Reference equipment descriptions covering a serviceable pedal, a patched
  pedalboard, and an amplifier/cabinet/microphone rig.

## Reference scene

The reference descriptions contain at least:

- One pedal that can be viewed closed, flipped, opened, and exploded.
- A visible PCB or point-to-point assembly with jacks, controls, internal wiring,
  and at least one replaceable electronic component.
- One pedalboard with three visually distinct pedals connected by patch cables.
- Three knob families assembled from shared catalog parts.
- Toggle and footswitch controls, LEDs, labels, decals, screws, and materials.
- One combo or head/cabinet arrangement with one or more speakers.
- One microphone that can move semantically from cone center to edge and change
  distance and angle.

These descriptions are coverage fixtures, not final Robine Amp product designs.
They MUST NOT contain product-authored render coordinates.

## Studio capabilities

Studio provides:

- A resizable equipment viewport with orbit, pan, zoom, focus, and view presets.
- Open, close, flip, remove-panel, and exploded-view actions.
- Model, catalog, visual-recipe, and asset hot reload with visible diagnostics.
- Mechanical assembly, electrical graph, and external-routing inspectors.
- Component selection and validated replacement.
- Jack/plug connection editing and automatic cable presentation.
- Speaker-relative microphone placement controls.
- A parameter inspector generated from the core registry.
- Direct value editing and default reset.
- Gesture and parameter event logging.
- Simulated automation for selected parameters and meters.
- Rendering diagnostics for bounds, anchors, constraints, joints, connectors,
  routes, hit regions, batches, invalidation, and frame timing.
- Capture of named snapshots at defined models, views, cameras, viewports, and
  scales.

A graphical CAD or drag-and-drop equipment authoring tool is explicitly outside
the MVP. Equipment descriptions, catalog definitions, and visual recipes may be
authored as data or Zig definitions and inspected in Studio.

## Initial no-audio stage

- The rendering milestone itself MUST be buildable and testable without an audio
  device. AUD-003 explicitly supersedes the launch-time no-audio behavior for the
  current Studio executable.
- The UI MUST use CORE-001 parameters rather than temporary widget-local values.
- Meter and automation inputs are deterministic simulations.
- Renderer tests require no DSP or plugin-format dependency. Audio tests remain
  independently selectable.

## Build interface

The project SHOULD provide equivalent build steps to:

```text
zig build studio
zig build run-studio
zig build test
zig build snapshots
zig build assets
```

Exact step names may change before the specification becomes Accepted, but CI
must expose separate unit, asset, and snapshot verification.

## Platform stages

- Stage 1: functional Studio and snapshot runner on macOS, with platform-neutral
  core, model, and UI modules.
- Stage 2: functional Studio on Windows and Linux using the same equipment
  descriptions, projections, and renderer contract.
- No platform may introduce a separate equipment, control, or scene
  implementation.

Plugin embedding is not an MVP acceptance condition, but the platform surface
contract must not assume ownership of the application event loop.

## Exit criteria

- The reference descriptions meet every acceptance criterion in MOD-001 through
  MOD-003 and UI-001 through UI-004.
- All reference controls are interactive through the real core parameter model.
- A pedal can be opened, inspected, rewired, and have a compatible component
  replaced through model actions.
- Three pedals can be patched without authoring cable render paths.
- A microphone can be positioned relative to a modeled speaker without world
  coordinates.
- Hot reload recovers from invalid model, recipe, and asset edits without
  restarting.
- Named exterior, interior, underside, exploded, pedalboard, and rig snapshots
  pass at their defined cameras and scales.
- A new knob family can be created by composing existing behavior with new or
  reused visual parts, without copying the knob implementation.
- Steady-state previewing shows no frame-over-frame resource growth.
- The rendering modules have no audio or plugin-format dependency.
