# MOD-005: Jack mounting and visible connections

Status: Draft

## Summary

Pedal descriptions mount every jack on a named enclosure surface and semantic
slot. A pedal may use side-mounted, top-mounted, or mixed connections without
supplying render coordinates. The scene always projects the physical socket and,
when connected, its inserted plug and cable anchor.

## Semantic mounting

The initial pedal vocabulary contains:

- Surfaces: `left_side`, `right_side`, and `top`.
- Surface slots: `start`, `center`, and `end`.
- Port roles: `input` and `output`.

Slots are ordered in the local frame of their surface. On the top surface,
`start` is toward the enclosure's left and `end` toward its right when viewed from
the control face. On a side surface, `start` is toward the top edge and `end`
toward the footswitch edge.

These values express assembly intent, not percentages or screen positions. The
catalog enclosure or assembly solver maps a slot to an exact mounting opening.
Future catalog definitions may expose named multi-jack patterns while preserving
the same rule.

## Ports, sockets, and plugs

A pedal port has a stable ID, electrical role, connector specification, and jack
mount. The jack is part of the pedal assembly and remains visible whether or not
a cable is inserted.

The projected connection contains distinct objects:

1. The mounted jack and its socket.
2. An inserted plug when the external connectivity graph contains the endpoint.
3. A cable anchor derived from the plug orientation.
4. A routed cable between the two derived anchors.

Disconnecting a cable removes its plug and route but does not remove or relocate
the jack. Moving, flipping, or opening a pedal recomputes the socket transform,
plug transform, and cable route from the same assembly.

## Layout and routing rules

- Pedal form factor MUST NOT determine jack location.
- Product names MUST NOT appear in jack projection or routing code.
- Cable paths MUST terminate at plug anchors, not at generic pedal bounds.
- A renderer MUST show an unconnected socket rather than hiding the port.
- Multiple ports on one surface require distinct semantic slots or a named
  catalog mounting pattern.
- Exact drilling positions belong to catalog geometry and assembly solving, not
  product descriptions or screen-space UI.

## Acceptance criteria

- Two `single` pedals can place their audio jacks on different surfaces.
- A top-mounted pair and a side-mounted pair render visible socket rings.
- Every connected port renders an inserted plug and the cable reaches its anchor.
- Disconnecting a port leaves its empty socket visible.
- Switching a port from a side surface to the top requires no renderer change.
- No pedal description contains jack `(x, y)` or screen-space coordinates.
