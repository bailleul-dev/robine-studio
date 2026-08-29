# CORE-001: Parameter and state model

Status: Draft

## Summary

The core module owns the parameter registry, runtime parameter values, gestures,
automation events, and versioned state representation shared by Studio, UI,
audio, standalone, CLAP, and VST3 hosts.

The rendering MVP uses the real model with a simulated consumer. It MUST NOT
introduce a UI-only parameter system that later needs to be replaced.

## Parameter identity

Every parameter has a stable numeric `ParameterId`. IDs:

- MUST remain stable across releases and host formats.
- MUST NOT be derived from display names or array positions.
- MUST NOT be reused after a parameter is removed.
- SHOULD be grouped into documented numeric namespaces by product domain.

The registry is immutable after product initialization. Each descriptor contains
at least:

```zig
pub const ParameterDescriptor = struct {
    id: ParameterId,
    path: []const u8,
    name: []const u8,
    short_name: []const u8,
    unit: []const u8,
    default_normalized: f64,
    mapping: ValueMapping,
    flags: ParameterFlags,
};
```

`path` is a stable machine-readable name such as `amp.preamp.gain`. Display names
and translated labels MAY change without changing identity.

## Values and mappings

- The canonical interchange value is normalized `f64` in the inclusive range
  `[0, 1]`.
- Descriptors convert normalized values to and from their natural domain.
- Supported mappings MUST include linear, logarithmic, stepped, boolean, and
  enumerated values.
- Conversions MUST clamp invalid external values and define behavior for NaN and
  infinity.
- Display formatting and text parsing belong to the descriptor or its mapping,
  not to individual UI controls or hosts.

## Runtime store

`ParameterStore` holds one current normalized value per registered parameter.
It provides:

- Initialization from defaults.
- Validated reads and writes by stable ID.
- Immutable snapshots for inspection and serialization.
- Reset of one parameter or the complete registry.
- Change notification through an injected event sink.

The initial Studio implementation MAY be single-threaded. Its API must still
permit replacing the event sink with a bounded UI-to-audio transport.

## Gestures and changes

User editing is represented by an ordered event stream:

```text
GestureBegin(parameter)
ValueChange(parameter, normalized_value)
GestureEnd(parameter)
```

- A control MUST begin a gesture before its first user change.
- A control MUST end every gesture it begins, including cancellation and window
  destruction.
- Programmatic state restoration does not create a user gesture.
- Events identify their origin as user, automation, state restore, reset, or
  simulation.
- The model reserves an optional sample offset for later sample-accurate audio
  automation. Studio may leave it unset.

## State

The canonical state document contains:

- A schema version.
- Product and component identifiers.
- Parameter values keyed by stable ID or stable path.
- Optional UI state in a separate namespaced section.
- Model instance state, part substitutions, articulation, and connections in a
  separate model-owned versioned section.
- Optional extension sections that unknown readers can skip.

Audio parameters and UI presentation state MUST NOT share an unversioned binary
memory layout. Deserialization validates all values before committing them and
must either apply a complete valid state or report failure without a partial
update.

The final on-disk encoding is intentionally not selected by this specification.

## Simulated parameters

Robine Studio provides a simulated event sink and automation source. Simulation
uses the same descriptors, store, gesture sequence, and normalized mappings as
future product hosts. Fake controls or values may be added only through a
dedicated development namespace.

## Acceptance criteria

- Registry validation rejects duplicate IDs, duplicate paths, invalid defaults,
  and invalid mappings.
- Mapping round trips are tested at boundaries and representative interior
  values.
- Two controls bound to one parameter remain synchronized through the store.
- Gesture tests cover normal completion, cancellation, reset, and editor closure.
- State round trips preserve registered parameter values.
- A newer state containing an unknown extension can be read without corrupting
  known values.
- UI code obtains parameter display text from the core descriptor rather than
  reimplementing formatting.
