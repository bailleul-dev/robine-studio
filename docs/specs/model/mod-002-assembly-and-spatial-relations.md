# MOD-002: Assembly and spatial relations

Status: Draft

## Summary

The assembly model describes containment, mounting, articulation, and relative
placement using physical relationships and named reference frames. A solver turns
those relationships into concrete transforms for rendering, hit testing, and
inspection.

Product developers select meaningful locations such as `top control row`,
`right-side input`, `speaker cone edge`, or `inside PCB rail`; they do not choose
pixel or world-space coordinates.

## Physical model

- Physical dimensions use a single documented unit, initially millimetres.
- Every catalog part defines a local reference frame and physical bounds.
- Parts expose named surfaces, axes, openings, attachment sites, zones, and slots.
- Assemblies form a directed ownership graph with one mechanical parent per
  installed part.
- Render transforms are derived values and are not persisted as product intent.

Example named references include:

- `enclosure.top`, `enclosure.left_side`, and `enclosure.interior`.
- `panel.control_row`, `panel.foot_area`, and `panel.label_zone`.
- `pcb.component_side`, `pcb.slot(op_amp_1)`, and `pcb.mounting_holes`.
- `cabinet.speaker(0).axis`, `cone.center`, and `cone.edge`.
- `microphone.capsule_axis` and `stand.boom_end`.

## Relationship vocabulary

The initial solver supports relationships such as:

- `contains(parent, child)`
- `mounted_on(part, surface_or_site)`
- `inserted_into(part, opening)`
- `aligned_with(source_axis, target_axis)`
- `distributed_in(parts, zone, policy)`
- `stacked(parts, direction, spacing_policy)`
- `attached_by(part, fastener_pattern)`
- `positioned_relative_to(part, reference, semantic_placement)`

Semantic placement includes center, edge, corner, row, column, radial ring,
speaker-axis distance, cone radial position, and on-axis/off-axis angle. Explicit
physical clearances MAY be supplied where they represent real mechanical intent.

Raw transforms and arbitrary `(x, y, z)` coordinates are forbidden in product
descriptions. They are permitted inside catalog geometry definitions and imported
meshes, where they are encapsulated and reusable.

## Layout patterns

Reusable patterns express common equipment conventions:

- Evenly distributed pedal control rows.
- Symmetric control groups around a central control.
- Side-mounted input and output jack pairs.
- Footswitch and LED groups.
- Amplifier control strips.
- Speaker grids and baffles.
- PCB component rows and footprint slots.
- Cabinet microphone placements.

Patterns produce constraints rather than final coordinates. A product can replace
a pattern or provide additional physical constraints without altering rendering
code.

## Articulation and inspection

Assemblies can expose articulated relationships:

- Hinge, slide, screw-removal, detachable, and lift-off joints.
- Closed, opening, open, removed, and exploded presentation states.
- Collision or clearance limits where required for believable movement.
- Focus targets and preferred inspection orientations.

Opening an enclosure changes the articulation state of its lid and visibility of
its internal assembly. It does not replace the object with an unrelated interior
scene.

Flipping and zooming are camera/view operations over the same assembly. The model
supports perspective and orthographic presets such as front, rear, top, underside,
interior, exploded, and signal-chain views.

## Amplifiers, cabinets, and microphones

- A combo contains an amplifier assembly and a cabinet assembly.
- A cabinet contains a baffle and one or more mounted speakers.
- Speakers expose acoustic axes and semantic cone regions.
- A microphone placement is expressed by target speaker, radial position from
  cone center to edge, capsule distance, and on-axis/off-axis angle.
- A microphone stand constrains reachable positions but does not define the audio
  response.

These relationships can later compile into acoustic processing parameters without
being owned by the audio module.

## Solving and diagnostics

The solver either produces a complete set of transforms or a structured error. It
MUST detect:

- Missing or incompatible mounting sites.
- Multiple mechanical parents.
- Cyclic containment.
- Over-constrained or under-specified placement.
- Physical overlap when a relationship requires clearance.
- Parts that do not fit their opening, zone, or footprint.

Pedalboard distribution uses the physical footprint and layout units defined by
MOD-004. It MUST NOT infer pedal width from control count, artwork, or renderer
geometry.

It MUST NOT silently choose arbitrary coordinates for an ambiguous assembly.
Diagnostics name semantic roles and failed constraints rather than renderer nodes.

## Acceptance criteria

- A three-control pedal top is laid out from a row pattern without authored
  coordinates.
- The same pedal can render closed, open, upside down, and exploded from one
  instance.
- Internal parts remain mounted correctly while the enclosure is manipulated.
- A two- or four-speaker cabinet is generated from the same speaker-grid pattern.
- A microphone can be moved from cap center to cone edge using semantic placement.
- Ambiguous and physically impossible assemblies fail with actionable diagnostics.
