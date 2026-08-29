# UI-010: Progressive idle ray tracing

Status: Draft

## Summary

Robine keeps rasterization as the immediate and portable rendering path. When a
3D equipment view becomes static, a bounded Metal ray-tracing pass progressively
improves contact shading without consuming a permanent per-frame GPU budget.

The first vertical slice computes ambient visibility only. It is deliberately
not a full path tracer: direct lighting, materials, reflections, tone mapping,
depth, and the existing shadow map remain in the raster pipeline.

## Runtime policy

The renderer MUST obey this state machine:

```text
camera or geometry changes
        |
        v
raster-only interaction ---- 200 ms idle ----> progressive AO
        ^                                          |
        |                                          v
        +------ any scene change -------- 24 samples reached
                                                   |
                                                   v
                                            converged / no RT work
```

- Camera motion MUST display the normal raster/MSAA result immediately.
- Accumulation MUST restart after a camera or geometry change.
- Ray-traced work MUST begin only after 200 milliseconds of stable view state.
- The MVP MUST trace four ambient-visibility rays per pixel per accumulation
  frame and average them before temporal accumulation.
- The accumulation MUST stop after 24 samples per pixel.
- A converged view MUST issue no further ray-tracing compute dispatches.
- Presentation rasterization MAY continue for meters, automation, and other
  dynamic plugin UI elements.

## Resolution and composition

The ambient-visibility buffer uses half the width and half the height of the 3D
viewport. It is a single-channel floating-point texture, linearly reconstructed
over the raster result. A bounded 3 by 3 spatial filter suppresses residual
Monte-Carlo noise. Primary camera rays sample pixel centers without temporal
jitter so equipment silhouettes remain stable. The composite is bounded to
contact-darkening only and MUST NOT replace direct-light shadows or globally
change the material palette.

The current maximum occlusion distance is 1.35 scene units. Primary rays use
the semantic camera pose and field of view; they do not infer a position from
window pixels or from equipment-specific layout constants.

Screen-space wireframe controls render after this composite and therefore remain
crisp and unaffected by stochastic accumulation.

## Geometry contract

The Metal backend builds a primitive acceleration structure from the same
non-indexed world-space triangle buffer used by the PBR raster pass. Vertex
positions and normals therefore have one source of truth.

Camera-only navigation MUST reuse the acceleration structure. A changed mesh
buffer MUST produce a new acceleration structure before sampling resumes. Future
instancing and refitting MAY reduce rebuild costs, but they MUST preserve the
description-driven equipment model defined by MOD-001 and MOD-002.

## Capability and failure behavior

Ray tracing is an optional backend capability:

- The backend MUST query Metal ray-tracing support before compiling ray-tracing
  shaders or creating acceleration structures.
- An unsupported device MUST use the complete raster path without a missing
  surface, disabled interaction, or changed layout.
- Shader, pipeline, or acceleration-structure setup failure MUST degrade to the
  raster path and report a diagnostic.
- No ray-tracing API type may leak into the declarative `ui` or `model` domains.

Metal's `supportsRaytracing` capability means that acceleration structures and
intersection functions are available. It MUST NOT be presented as proof of
dedicated fixed-function ray-tracing hardware. On an Apple M1 this work executes
as a Metal compute workload on the GPU.

This boundary is required for future Windows and Linux render backends. They MAY
implement the same policy with another hardware API or select the raster fallback.

## Plugin budget

This feature runs on the GPU and never enters the real-time audio callback. Its
work is both spatially reduced and temporally bounded. The plugin host MUST be
able to disable the enhancement through a future quality profile without
changing equipment state or sound.

The renderer SHOULD expose timings before increasing the sample count, adding
bounces, or tracing glossy reflections. Audio stability takes precedence over
visual convergence.

## Acceptance criteria

- Moving from pedalboard view to amplifier view shows continuous raster output
  throughout the camera transition.
- No ray-tracing dispatch occurs during the transition or its 200 ms idle gate.
- A static view progressively gains contact occlusion over at most 24 frames.
- The ray-tracing pass stops dispatching after the 24th sample.
- Returning to the pedalboard resets and recomputes the accumulation.
- Resizing the fixed-aspect window reallocates a correctly sized half-resolution
  texture and restarts accumulation.
- A device without the Metal ray-tracing API opens and renders the same usable UI via
  rasterization.
- The release build completes without an external renderer or shader compiler
  dependency.
