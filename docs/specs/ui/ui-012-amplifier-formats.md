# UI-012 — Amplifier formats

Status: **Implemented**

## Purpose

The studio renderer represents amplifier rigs as semantic assemblies. A head and
cabinet stack MUST NOT be produced by stretching combo geometry.

## Formats

The initial renderer supports:

- `combo`: amplifier controls and speakers share one enclosure.
- `head_and_4x12`: a separate amplifier head rests on a four-speaker cabinet.

The Bogner Shiva uses `head_and_4x12`. Its cabinet declares a two-column,
two-row speaker grid. Dumble and Mesa retain the `combo` format.

## Finish

Physical format and cosmetic finish are independent. Every amplifier assembly
selects:

- `enclosure_color`: the intrinsic tolex or covering color.
- `gridcloth`: a reusable fabric recipe defining base material, warp, weft, and
  weave density.

Changing either property MUST NOT create a new amplifier format or duplicate its
geometry. The Mesa Lone Star remains a `combo` and selects a blue enclosure with
the reusable `light_gray` gridcloth recipe.

## Projection

- Dimensions use the studio's shared physical scale.
- Head placement is derived from the cabinet top, the head dimensions, and a
  small foot clearance.
- The 4x12 speaker positions are derived from the declared 2×2 grid.
- Rig-view picking uses the bounds of the complete assembly.
- Focused-view framing uses the complete assembly dimensions.
- The Power interaction targets the head control panel, never the cabinet.

The projection MAY add grille weave, piping, feet, handles, badges, and recessed
speaker detail. These details do not alter equipment identity or audio routing.

## Audio independence

Changing the visual assembly format MUST NOT silently replace a NAM capture or
cabinet IR. Audio resources remain explicit catalog mappings. A dedicated Bogner
4x12 IR can therefore replace the current development IR without changing the
scene description or interactions.

## Acceptance criteria

- Bogner renders as a visibly separate head over a proportionate 4x12 cabinet.
- Four speaker forms are visible in a 2×2 arrangement.
- Clicking any part of the stack opens its focused view.
- The focused camera contains the complete stack.
- The Power hit target selects the switch on the head.
- Dumble and Mesa continue to render and interact as combos.
- Mesa renders with a blue enclosure and fine light-gray woven gridcloth.
