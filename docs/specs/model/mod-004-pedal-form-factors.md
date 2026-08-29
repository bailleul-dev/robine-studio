# MOD-004: Pedal form factors

Status: Draft

## Summary

Robine standardizes common pedal footprints so equipment descriptions can request
a `mini`, `single`, or `double` enclosure without supplying dimensions or render
coordinates. A catalog enclosure still provides its exact physical measurements,
mounting surfaces, openings, and internal volume.

The form factor is an authoring and layout category. It does not define the
pedal's behavior, control count, footswitch count, circuit, or artwork.

## Model layers

Pedal sizing has three layers:

1. `PedalFormFactor` provides a stable semantic category.
2. `PedalEnclosure` is a catalog part with exact dimensions and mounting data.
3. A product selects an enclosure and mounts its controls, jacks, and electronics
   through the MOD-002 assembly model. Jack placement follows MOD-005 and is not
   implied by the form factor.

This permits several physically different enclosures to share the `single`
category while remaining mechanically accurate.

## Initial form factors

| Form factor | Nominal layout width | Intent |
| --- | ---: | --- |
| `mini` | 0.65 units | Narrow single-function pedal |
| `single` | 1 unit | Ordinary one-column pedal footprint |
| `double` | 2 units | Wide enclosure or paired control surface |
| `custom` | Explicit | Catalog-defined footprint outside standard categories |

Layout units describe relative pedalboard allocation. They are not millimetres and
MUST NOT be used for collision, cable length, mounting, or physical simulation.

## Enclosure definition

A pedal enclosure provides at least:

- A stable catalog ID.
- Its form-factor category.
- Exact width, depth, and height in millimetres.
- Nominal pedalboard footprint units.
- Named exterior surfaces and control zones.
- Jack, power, and footswitch mounting zones.
- Interior volume, access panels, and electronics mounting sites.
- Compatible articulation and opening behavior.

The initial demo may use generic enclosure definitions. Their dimensions are
defaults for visualization, not claims of an industry-wide mechanical standard.

## Layout rules

- Pedalboard layout allocates horizontal space from `footprint_units`.
- Physical clearance and overlap checks use exact dimensions.
- A `double` pedal normally occupies twice the nominal width of a `single`, but a
  catalog definition may declare a more precise footprint.
- Control layout uses named zones and patterns within the selected enclosure.
- The renderer consumes solved bounds and MUST NOT branch on product names.
- The number of controls or footswitches MUST NOT implicitly change form factor.

## Extension rules

New standard categories require a stable identifier and documented layout intent.
A one-off enclosure uses `custom` rather than creating a category named after a
product.

Catalog aliases MAY map familiar real-world enclosure families to these form
factors while retaining their exact dimensions and compatibility metadata.

## Acceptance criteria

- Replacing a generic `single` enclosure with another `single` preserves the
  nominal pedalboard layout while allowing dimensions to change.
- A `double` pedal receives two nominal width units without renderer-specific
  logic.
- A custom enclosure can participate in layout by declaring footprint units.
- Control and footswitch counts do not determine the form factor.
- Physical fit validation uses millimetres rather than nominal layout units.
- Product descriptions contain no pedal width or screen coordinates when a
  catalog enclosure already defines them.
