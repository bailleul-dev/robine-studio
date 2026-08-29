# UI-003: Controls and interaction

Status: Draft

## Summary

Robine interaction maps picked visual objects to semantic equipment actions,
camera operations, or core parameter gestures. Visual objects do not own the
canonical equipment or parameter state.

## Control families

The initial UI engine supports:

- Rotary knobs.
- Toggle, rocker, and rotary switches.
- Footswitches.
- LEDs and status lamps.
- Linear and VU-style meters.
- Jacks and cable endpoints.
- Replaceable electronic components and terminals.
- Articulated lids, panels, battery doors, and detachable parts.
- Speakers, microphones, and semantic placement handles.
- Static and value-aware labels.

Panels, enclosures, screws, grills, and decorative elements are visual scene
recipes without mandatory interaction behavior.

## Separation of concerns

A projected interactive object combines:

1. A visual recipe from UI-001.
2. A generated 3D or screen-space hit region.
3. An interaction behavior.
4. A MOD-001 semantic role and supported actions.
5. An optional core parameter binding.
6. A semantic role and accessible label.

The same rotary behavior can operate different knob recipes. The same knob recipe
can be read-only, bound to different parameters, or driven by simulation.

## Hit testing

- Hit testing uses the final projected transforms, depth, and visibility.
- Hit regions MAY be larger than visible geometry for usability.
- Disabled or hidden controls do not accept input.
- Overlap resolves using explicit input priority and final visual order.
- Pointer capture keeps an active gesture attached when the pointer leaves the
  original hit region.
- Picking returns semantic equipment identity, not a transient mesh index.

## Equipment interaction

The initial semantic interactions include:

- Select, focus, orbit, pan, zoom, and frame selection.
- Open, close, flip, remove, reinstall, and show exploded view.
- Insert and remove plugs and connect compatible cable endpoints.
- Select, inspect, and replace compatible internal components.
- Move a microphone using speaker-relative radial position, distance, and angle.
- Toggle visibility of internal wiring, external routing, and connection paths.

Focused equipment navigation follows UI-005. Picking an amplifier in a rig emits
a semantic focus action; platform code does not decide which view to construct.

The UI submits typed model actions and displays validation failures. It MUST NOT
edit assembly transforms or connectivity edges directly.

## Rotary interaction

The default rotary interaction provides:

- Vertical drag for coarse adjustment.
- A modifier-assisted fine adjustment mode.
- Wheel adjustment using defined discrete increments.
- Double-click or an explicit reset gesture to restore the default.
- Keyboard increments when focused.
- Optional stepped or enumerated behavior from the parameter descriptor.

Radial dragging MAY be implemented as an alternate policy. Pointer movement is
converted to normalized values by the behavior, not by the knob artwork.

## Gesture lifecycle

Controls emit the CORE-001 gesture sequence. They must end or cancel an active
gesture on pointer cancellation, focus loss, editor closure, scene replacement,
or loss of the bound parameter.

External parameter changes update visuals without synthesizing a user gesture.
When an automation change races with an active UI gesture, host policy determines
the resulting value; the UI continues to display the current store value.

## Focus and semantics

- Interactive controls have deterministic keyboard focus order.
- Every bound control exposes a semantic role, label, current display value, and
  enabled/read-only state.
- Decorative scene nodes are omitted from semantic navigation.
- Tooltips and value popovers are presentation layers and do not own formatting.

## Simulation

Studio can drive controls with recorded or procedural parameter automation. The
simulation panel can start and stop automation, set direct values, inspect event
streams, and verify gesture balance.

## Acceptance criteria

- Three visually different knobs share one rotary interaction implementation.
- Drag, fine drag, wheel, keyboard, reset, and cancellation are tested.
- Pointer capture remains correct through parent transforms.
- Picking preserves semantic identity while an enclosure opens or the camera
  moves.
- Two controls bound to the same parameter update each other.
- Opening, replacing, plugging, and microphone movement go through validated model
  actions.
- A hidden or disabled control cannot begin a gesture.
- Every gesture-begin event has exactly one matching end or cancellation.
- Controls expose semantic labels and formatted values without duplicating core
  mapping logic.
