# MOD-003: Connectivity and wiring

Status: Draft

## Summary

Robine represents electrical components, terminals, internal wiring, jacks,
plugs, patch cables, power connections, and acoustic routing as typed connectivity
graphs. Visible wires and cables are spatial projections of those graphs, not the
source of electrical truth.

## Graph separation

The model maintains related but distinct graphs:

1. **Internal electrical graphs** connect component pins, PCB nets, wires, and
   controls inside equipment.
2. **External connection graphs** connect equipment ports using plugs, patch
   cables, speaker cables, and power leads.
3. **Acoustic placement graphs** relate speakers, cabinets, microphones, and
   listening or capture targets.

Future audio code may compile these descriptions into processing graphs. The model
does not perform DSP and MUST NOT depend on the audio module.

## Typed endpoints

Every connectable object exposes typed endpoints. Endpoint metadata includes:

- Stable identity and owning equipment role.
- Electrical or acoustic kind.
- Direction or bidirectional capability.
- Conductor or pin identity.
- Signal role, such as audio, power, ground, control, or shield.
- Mechanical connector compatibility.
- Optional electrical limits and nominal characteristics.

Connecting endpoints requires both mechanical and semantic compatibility. A plug
fitting physically does not imply that a speaker output is safe for a line input.

## Electronic components

The initial component model supports at least:

- Resistors, capacitors, diodes, transistors, and integrated circuits.
- Potentiometers and switches shared with external controls.
- Jacks, power connectors, LEDs, and other electromechanical parts.
- PCB footprints, point-to-point terminals, and named circuit nodes.

A component definition describes package, pins, editable properties, and
compatibility rules separately from its visual geometry. A runtime component may
carry a selected value or variant.

Replacing a component validates:

- Role and component kind.
- Footprint or mounting compatibility.
- Pin mapping.
- Required electrical metadata.
- Any product rule that marks the part fixed or non-serviceable.

Successful replacement preserves the role and reconnects compatible nets
atomically. An incompatible replacement produces a structured explanation.

## Internal wiring

Internal connectivity can be described as nets, explicit wires, or a combination:

- PCB traces are logical nets with optional board-routing geometry.
- Point-to-point wires connect named terminals.
- Multi-conductor harnesses group related wires.
- Ground and shield relationships remain explicit.

Product descriptions connect semantic endpoints, for example
`input_jack.tip → input_stage.signal_in`. They do not draw a wire through a list of
coordinates.

The assembly model supplies obstacles, routing zones, clips, and attachment
points. A cable-routing system derives a visible curve and can report when no
valid route exists. Manual route hints MAY name semantic waypoints but MUST NOT
replace the electrical connection graph.

## External cables and jacks

- Jacks expose sockets and conductor mappings.
- Cables expose plug endpoints and conductors.
- Insertion creates conductor connections only after compatibility validation.
- Removing a plug removes those connections but does not delete the cable.
- Cable length and routing constrain valid pedalboard placement.
- Signal-flow direction is derived from endpoint roles, not screen position.

Pedalboard wiring therefore consists of placing equipment and connecting named
ports. Visual cable paths follow the resulting assembly and can update when a
pedal moves.

## Acoustic relationships

An acoustic edge identifies a source speaker or cabinet, a microphone or capture
target, and its MOD-002 placement. Multiple microphones can target one speaker and
one microphone can be reassigned without changing cabinet assembly.

The model stores placement and routing intent only. Frequency response, room
simulation, and signal mixing belong to future audio compilation.

## Validation and graph queries

The model provides queries for:

- Connected and unconnected endpoints.
- Signal paths between two roles.
- Powered or isolated subgraphs.
- Cycles and fan-in/fan-out.
- Components affected by a replacement or disconnection.
- External cable length and route validity.

Validation MUST distinguish mechanical incompatibility, electrical
incompatibility, missing routing, and incomplete connectivity.

## Acceptance criteria

- An opened pedal exposes its jacks, controls, PCB, components, and internal nets.
- One compatible component can be replaced without rebuilding the product
  definition.
- Three pedals can be patched in a validated external signal chain.
- Moving a pedal recomputes cable presentation without changing connectivity.
- Disconnecting a plug updates the external graph and visible cable state.
- A cabinet and microphone placement produce an inspectable acoustic relationship.
- No wire or cable requires product-authored render coordinates.

