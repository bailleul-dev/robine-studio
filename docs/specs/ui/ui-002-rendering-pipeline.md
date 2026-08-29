# UI-002: Rendering pipeline

Status: Draft

## Summary

The rendering pipeline presents semantic equipment as an interactive hybrid 3D
and 2D scene. It renders physical assemblies, articulated enclosures, electronic
components, wires, cables, cabinets, speakers, and microphones, then composes
sharp screen-space controls, labels, and inspection overlays above them.

It is not a general game engine. Its geometry, material, camera, picking, and
effect capabilities are bounded by musical-equipment representation.

## Pipeline

Each frame proceeds through these stages:

```text
model and parameter snapshot
    → assembly transform and articulation update
    → scene projection update
    → camera and visibility resolution
    → 3D draw-list generation
    → 2D overlay generation
    → backend execution and picking data
    → presentation
```

Equipment and connectivity truth belongs to `model`. Projection and draw-list
generation belong to `ui`. Surface creation, native event pumping, and
presentation belong to `platform`.

## Equipment rendering operations

The initial equipment pass MUST support:

- Procedural primitives and imported indexed meshes.
- Hierarchical affine transforms and articulated joints.
- Opaque, masked, and transparent materials.
- Base color, textures, normals, roughness-like highlights, and emissive surfaces.
- Decals, engraved or embossed markings, and reusable wear masks.
- Directional and environment lighting with bounded shadows.
- Curves or swept geometry for internal wires and external cables.
- Selection, hover, isolation, and connectivity overlays.
- Stable depth and object IDs for picking.

The rendering style may be realistic or stylized. The MVP does not require a
general physically based renderer, arbitrary skeletal animation, terrain,
particles, or game-world physics.

## Screen-space operations

The overlay pass MUST support:

- Solid and gradient shapes, paths, arcs, images, and nine-patch images.
- Text with explicit font, size, alignment, and color.
- Nested transforms, clipping, opacity, and standard alpha compositing.
- Labels anchored to projected semantic points.
- Parameter values, focus rings, tooltips, inspector affordances, and diagnostics.

Equipment-specific controls expand into these operations or equipment meshes. The
renderer MUST NOT special-case individual products.

## Cameras and view transitions

- Cameras support orthographic and perspective projection.
- Orbit, pan, zoom, focus, frame-selection, and view presets are engine actions.
- Camera bounds derive from solved assembly bounds.
- Opening, flipping, and exploded-view transitions preserve object identity and
  picking.
- View transitions may animate but must be interruptible and deterministic from
  their current state.

## Visual correctness

- Model-space dimensions use MOD-002 physical units.
- Internal colors use a documented linear workflow with explicit display
  conversion.
- Images use a documented premultiplied-alpha convention.
- Text and decals remain legible at supported UI scales.
- Transparent enclosures, wires, and overlays use deterministic ordering or an
  explicitly documented approximation.
- Shadows and post effects use bounded intermediate resources.

## Resource model

Meshes, images, fonts, materials, pipelines, and compiled paths use opaque
handles. Resources are created outside scene traversal. Steady-state rendering
SHOULD NOT perform unbounded allocation or decode source assets.

Resource caches are scoped to a renderer instance or explicitly shared device.
They MUST support multiple plugin editors in one process without global mutable
UI state.

## Invalidation and animation

A frame is requested when:

- Equipment, assembly, connectivity, parameter, or selection state changes.
- Input changes hover, focus, camera, or gesture state.
- An articulation, camera, control, meter, or cable animation is active.
- The surface is exposed or resized.
- Model, recipe, or asset data is successfully hot reloaded.

Idle editors SHOULD stop continuous rendering. Metering and animation MAY opt
into a bounded refresh rate.

## Backend contract

A backend provides:

- Surface attachment to a standalone or host-owned native view.
- Logical and physical dimensions and display scale.
- GPU or reference-renderer resource creation.
- Equipment and overlay draw-list execution.
- Object-ID or equivalent picking support.
- Normalized pointer, wheel, keyboard, focus, and text events.
- Safe loss and recreation of the graphics surface.

The contract MUST support multiple surfaces and MUST NOT assume ownership of the
application event loop. This is required for later plugin embedding.

## Testing and diagnostics

- A deterministic reference path produces named snapshots from fixed model,
  camera, viewport, and lighting inputs.
- Snapshot metadata records model version, view, camera, viewport, renderer
  version, and asset hashes.
- Debug overlays show bounds, anchors, joints, constraints, connectors, cable
  routes, picks, batches, and frame timing.
- Tests compare projected scene and draw-list structure separately from final
  pixel snapshots where possible.

## Initial performance targets

After resources are warm, the reference Studio scene at 1280×800 SHOULD:

- Sustain 60 frames per second on supported development hardware.
- Avoid source asset decoding during a frame.
- Avoid frame-over-frame growth in live allocations or graphics resources.
- Render idle content only after invalidation.

These are UI regression targets, not real-time audio-thread guarantees.

## Acceptance criteria

- One equipment instance renders in exterior, interior, underside, and exploded
  views without independent scenes.
- Picking identifies the same semantic part through view and articulation changes.
- Internal wires and external cables remain attached while assemblies move.
- The same projected scene renders on interactive and snapshot paths.
- Surface destruction and recreation do not invalidate equipment state.
- Two surfaces can render different equipment instances in one process.
- The reference scene meets the initial performance targets.

