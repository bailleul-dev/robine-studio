# UI-005: Focused equipment navigation

Status: Draft

## Summary

Selecting equipment in a rig can open a focused view generated from the same
semantic instance. The first interaction selects the active amplifier in the
signal chain and transitions from the pedalboard view to an amplifier view.

## Interaction contract

The generated scene exposes hit regions associated with typed semantic actions.
For the first increment:

- The active amplifier node exposes `show_amplifier`.
- The amplifier-view back control exposes `show_rig`.
- Picking returns the action rather than a mesh index or platform view object.
- `ViewState` owns the current `rig` or `amplifier` projection mode.

The macOS host converts a pointer event into normalized viewport coordinates and
submits it to the UI interaction layer. It does not know amplifier bounds, scene
layout, or navigation rules.

## Amplifier view

The amplifier view projects:

- A dominant amplifier housing and front panel.
- Power, controls, input jack, handle, grille, badge, and assembly details derived
  from the amplifier description.
- The existing signal-chain overview with the focused amplifier highlighted.
- An amplifier-oriented catalog browser.
- An explicit route back to the rig view.

The reference image informs screen hierarchy only. Robine does not copy its
branding, artwork, product geometry, or fixed coordinates into equipment data.

## State and regeneration

View changes regenerate disposable line, fill, and hit-region geometry. They do
not replace the rig, amplifier, controls, parameters, or connectivity graph.

If regeneration fails, the previous `ViewState` and render buffers remain active.
The host uploads replacement geometry only after a successful transition.

Future focused views for pedals, cabinets, microphones, and internal assemblies
reuse the same action and projection mechanism.

## Acceptance criteria

- Clicking the active amplifier in the signal chain enters `amplifier` view.
- The selected amplifier is visually identified in the retained signal chain.
- Clicking the back affordance returns to `rig` view.
- Both transitions regenerate geometry without restarting the macOS window.
- Hit regions derive from projected semantic bounds rather than platform-authored
  coordinates.
- Platform code contains no equipment-specific navigation logic.
- A unit test exercises the complete `rig → amplifier → rig` state transition.
