# UI-007: Procedural pedalboard 3D

Status: Draft

## Summary

The Studio rig view projects pedal descriptions into a real 3D pedalboard scene.
The projection derives enclosure dimensions, presentation state, controls,
footswitches, and jack mounting from semantic model data. Product descriptions do
not provide screen coordinates or renderer-specific triangles.

## Scene projection

The initial projection contains:

- A staggered parquet floor extending beyond the complete 3D viewport, assembled
  from long planks oriented along scene depth with narrow recessed grooves.
- Gently rounded enclosures sized from `PedalEnclosure.dimensions` in millimetres.
- Layout spacing derived from physical width and bounded semantic gaps.
- Procedural knobs and pointers generated from the control collection.
- One or more footswitches generated from `footswitch_count`.
- Visible sockets placed on `left_side`, `right_side`, or `top` according to
  MOD-005 mounting data.
- An open service presentation containing a tray, exposed PCB, components, and
  raised lid when `presentation` is `open`.
- Rounded enclosure footprints use subdivided arcs. Their upper edges use
  multiple quarter-circle fillet rings with smooth per-vertex normals rather
  than a single chamfer. Cylindrical controls, sockets, fasteners, and switches
  use a high-detail radial profile.
- Closed product views do not add decorative fasteners to the pedal face.
- Runtime metallic-roughness materials and cast shadows following UI-006.
- Painted enclosures add a runtime clearcoat response so studio strips produce
  clean reflections without baking highlights into product assets.

The current demo uses a single compiled triangle stream so the complete board and
its shadow pass each require one draw call. Future picking IDs and per-instance
updates may split or instance this stream without changing the description model.

## Layout rules

- Millimetre dimensions use one uniform model-to-world scale.
- `footprint_units` MAY guide authoring and coarse UI allocation but MUST NOT
  replace physical dimensions in the 3D scene.
- Control positions derive from named bounded zones and collection patterns.
- A double enclosure gains width from its catalog dimensions, not from a
  renderer branch on its product name.
- Ports derive from surface and slot semantics.
- Camera framing derives from solved board bounds rather than individual product
  coordinates.

The initial procedural control patterns are placeholders for the richer mounting
zones required by MOD-002. They MUST remain deterministic and data-driven while
that model is introduced.

## Rendering behavior

- The board uses the production 3D pipeline selected by UI-002.
- One static warm strip light placed laterally and one filtered shadow map
  illuminate the rig view. A restrained cool lateral fill separates the opposite
  edges without cancelling the key-light shadows; decorative continuous
  animation is disabled.
- Camera, key-light position and size, key intensity, exposure, environment
  strength, and fill radiance belong to one declarative `ViewProfile` in `ui`.
  The Metal backend consumes this profile and does not own product-view tuning.
- Equipment geometry and shadow geometry share the same vertex stream.
- The renderer overlays browser, signal-flow, transport, and other screen-space
  UI after the 3D pass.
- The renderer MUST allocate no geometry during a steady-state frame.

## Acceptance criteria

- The five-pedal demo rig renders as five 3D enclosures on one board.
- Staggered parquet planks cover the complete visible 3D background without
  exposing a black perimeter.
- The double pedal is physically wider than a single pedal.
- Changing enclosure dimensions changes 3D size without changing renderer code.
- The default demo presents every pedal as a normal closed product.
- An explicit open-state fixture exposes its interior and raised lid from the
  same pedal description.
- Side-mounted and top-mounted sockets appear on their declared surfaces.
- Knob and footswitch counts follow model collections.
- Pedal faces contain no decorative corner screws.
- Pedals and controls cast coherent runtime shadows.
- The rig still navigates to the focused amplifier view.
