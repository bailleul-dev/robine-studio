# UI-009: Pedal control hardware

Status: Draft

## Summary

Pedal knobs and footswitches are reusable procedural hardware assemblies rather
than generic cylinders. Their geometry, material zones, and moving parts derive
from semantic control descriptions and remain independent from screen position.

## Chicken-head knob recipe

The initial knob recipe contains:

1. A circular molded-plastic skirt.
2. A narrower central hub.
3. A raised tapered grip with separate top, side, back, and front faces.
4. An ivory index stripe that crosses the top and folds down the front face.

The complete grip and index rotate from the control's normalized value. A product
description chooses a knob recipe and dimensions; it does not supply mesh
vertices or a rendered pointer image.

## Footswitch recipe

The initial momentary footswitch contains:

1. A six-sided polished mounting nut against the enclosure.
2. A convex chrome collar with smooth radial normals.
3. A lathed central shaft.
4. A wider cylindrical actuator with a beveled top transition.

All metallic pieces use runtime PBR reflections from UI-006. The footswitch does
not use rubber or a painted highlight. Its LED remains the independent UI-008
indicator assembly and is not fused into the switch geometry.

## Acceptance criteria

- Every demo control renders with a circular skirt and tapered chicken-head grip.
- Rotating a control changes both grip and index orientation from the same value.
- The ivory stripe is visible on the grip top and front face.
- Every demo footswitch exposes a hexagonal nut, convex collar, shaft, and cap.
- Footswitch metal reflects both named studio strips at runtime.
- Changing recipe dimensions does not require renderer-specific coordinates.
- Generated geometry remains within the fixed 80,000-vertex pedalboard mesh
  capacity and allocates nothing during a frame.
