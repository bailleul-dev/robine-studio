# MOD-001: Equipment description

Status: Draft

## Summary

Robine models musical equipment as semantic, inspectable objects rather than
manually positioned UI widgets. Developers describe what an object is, what it
contains, how its parts relate, and what can be done with it. The engine derives
mechanical placement, renderable scenes, hit regions, views, and interaction
targets from that description.

A pedal is therefore an enclosure containing mounted controls, connectors, and
electronics. It is not a background image with controls placed at `(x, y)`.

## Goals

- Describe pedals, amplifiers, cabinets, pedalboards, microphones, and electronic
  assemblies using domain vocabulary.
- Reuse catalog parts and assembly patterns across products.
- Inspect an object from the outside and inside.
- Support opening, closing, flipping, zooming, connecting, and modifying objects.
- Generate visual and interaction scenes without product-level pixel placement.
- Preserve enough structure for future electrical and audio simulation.

## Description levels

The model has three distinct levels:

1. **Catalog definitions** describe reusable parts and their capabilities.
2. **Product definitions** assemble catalog parts through semantic relationships.
3. **Runtime instances** hold current state, connections, transforms, and user
   modifications.

A catalog definition can describe:

- An enclosure family and its named surfaces and mounting zones.
- A potentiometer with shaft, terminals, taper, and compatible knobs.
- A jack with socket, conductors, mounting requirements, and plug compatibility.
- An electronic component with pins, value, package, and footprint.
- A speaker with cone, dust cap, frame, terminals, and acoustic axis.
- A microphone with capsule axis, connector, and placement capabilities.

Catalog authors MAY define local geometry and dimensions. Product authors MUST
assemble catalog objects through named roles, sites, constraints, and
connections—not renderer coordinates.

Pedal enclosures use the standardized authoring categories and physical
definitions from MOD-004. A form-factor category never replaces the exact catalog
enclosure definition.

## Equipment kinds

The initial semantic model covers:

- Pedals and multi-effect enclosures.
- Pedalboards and patch bays.
- Amplifier heads.
- Combo amplifiers.
- Speaker cabinets and individual speakers.
- Microphones and stands.
- Printed circuit boards and point-to-point electronic assemblies.
- Controls, indicators, jacks, plugs, wires, and cables.

Kinds provide validated defaults and vocabulary but do not form a deep class
hierarchy. Capabilities and composition are preferred over inheritance.

## Product description

A product description identifies parts by stable local role and expresses intent.
For example:

```zig
pedal("green_overdrive", .{
    .enclosure = catalog.enclosures.compact_stompbox,
    .controls = .top_row(&.{
        knob("drive", .drive),
        knob("tone", .tone),
        knob("level", .level),
    }),
    .switch = footswitch("bypass", .true_bypass),
    .connectors = .{
        .input = jack(.signal_input, .right_side),
        .output = jack(.signal_output, .left_side),
        .power = jack(.dc_power, .rear_side),
    },
    .electronics = circuit("main_board", green_overdrive_circuit),
});
```

The example is illustrative. The final serialization or Zig DSL is selected
separately. Its important property is the absence of scene coordinates and
renderer nodes from the product description.

## Semantic state and actions

Runtime instances expose typed actions according to their capabilities:

- Open or close an enclosure, back panel, battery door, or cabinet.
- Flip, orbit, zoom, focus, or select an assembly.
- Remove, install, replace, or inspect a compatible part.
- Turn or actuate a mounted control.
- Insert or remove a plug.
- Route, connect, or disconnect a wire or cable.
- Move a microphone relative to a speaker or cabinet.

Actions validate the model first, then update instance state atomically. UI code
requests actions and observes results; it MUST NOT directly mutate assembly or
connectivity internals.

## Identity

- Catalog definitions have stable namespaced IDs.
- Product definitions have stable IDs and schema versions.
- Every contained role has a stable path such as
  `pedal.controls.drive.potentiometer`.
- Runtime instances have identities distinct from their definitions so multiple
  identical pedals can coexist on a board.
- Replacing a part changes the bound catalog definition while retaining the
  assembly role identity where compatible.

## Derived representations

The equipment model is the source of truth. Systems may derive:

- A mechanical assembly graph.
- One or more electrical connectivity graphs.
- External signal and power routing graphs.
- A render scene and hit-test structure for a chosen view.
- Inspector trees and property panels.
- Future DSP or acoustic processing graphs.

Derived structures MUST be rebuildable from the semantic definition and runtime
state. They MUST NOT become independent product descriptions.

## Acceptance criteria

- A pedal can be instantiated without any product-authored render coordinates.
- Two products can reuse the same enclosure, jack, potentiometer, or electronic
  component definitions.
- An instance can be opened, flipped, and inspected without changing its product
  definition.
- Product descriptions reference core parameters by stable ID or path.
- Unknown or incompatible part roles produce domain-oriented diagnostics.
- A render scene can be discarded and regenerated without losing equipment state.
