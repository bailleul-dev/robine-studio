# UI-005: Focused equipment navigation

Status: Draft

## Summary

Selecting equipment in a rig can open a focused view generated from the same
semantic instance. The first interaction selects the active amplifier in the
scene and transitions from the pedalboard camera to an amplifier-focused camera.

## Interaction contract

The generated scene exposes hit regions associated with typed semantic actions.
For the first increment:

- The active 3D amplifier exposes `show_amplifier` through a projected hit region.
- The amplifier-view back control exposes `show_rig`.
- Picking returns the action rather than a mesh index or platform view object.
- `ViewState` owns the current `rig` or `amplifier` projection mode.

The macOS host converts a pointer event into normalized viewport coordinates and
submits it to the UI interaction layer. It does not know amplifier bounds, scene
layout, or navigation rules.

## Amplifier focus

The first 3D amplifier focus presents:

- The same amplifier mesh, approached by a 2.8-second quintic-eased camera move.
- A near-frontal pose placed between the pedal row and the amplifier, so the
  pedals pass behind the camera and cannot occlude the controls or grille.
- Power, controls, input jack, handle, grille, badge, and assembly details derived
  from the amplifier description.
- The existing signal-chain overview with the focused amplifier highlighted.
- An amplifier-oriented catalog browser.
- An explicit route back to the rig view.

The reference image informs screen hierarchy only. Robine does not copy its
branding, artwork, product geometry, or fixed coordinates into equipment data.

## State and regeneration

Camera focus does not regenerate equipment geometry. The Metal backend
interpolates camera position, target, and field of view every frame while reusing
the existing vertex and shadow buffers. Other view changes may still regenerate
disposable line, fill, and hit-region geometry; none replace the rig, amplifier,
controls, parameters, or connectivity graph.

If regeneration fails, the previous `ViewState` and render buffers remain active.
The host uploads replacement geometry only after a successful transition.

Future focused views for pedals, cabinets, microphones, and internal assemblies
reuse the same action and projection mechanism.

## Acceptance criteria

- Clicking the visible combo amplifier starts a slow camera transition toward its
  front face.
- The combo remains the same semantic instance and GPU geometry during the move.
- The selected amplifier is visually identified in the retained signal chain.
- Clicking the back affordance returns to `rig` view.
- Both transitions regenerate geometry without restarting the macOS window.
- Hit regions derive from projected semantic bounds rather than platform-authored
  coordinates.
- Platform code contains no equipment-specific navigation logic.
- A unit test exercises the complete `rig → amplifier → rig` state transition.
