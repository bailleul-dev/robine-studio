# UI-011: Studio chrome and context controls

Status: Superseded

## Summary

This proposal is superseded. Robine Studio uses a full-window equipment scene
without persistent toolbar, contextual equipment strip, or transport. Future
controls must be introduced contextually without permanently reducing the 3D
viewport.

## Persistent hierarchy

The production window contains exactly three persistent screen-space zones:

1. A top toolbar for preset identity, navigation, view mode, and application
   actions.
2. A narrow contextual strip directly below the equipment viewport.
3. A bottom transport for meters, playback state, and time display.

No persistent browser or signal-flow panel reserves viewport width or height.
Optional inspectors MUST appear on demand rather than reducing the default
equipment stage.

## Visual language

- Chrome uses warm-neutral charcoal surfaces so it belongs beside the studio
  scene without competing with equipment colors.
- Control groups use bounded rounded surfaces, an inner dark field, and a subtle
  outline rather than bare debug rectangles.
- Amber identifies the active navigation state and primary transport action.
- Pedal accents come from their semantic presentation color and are limited to
  small identity marks, indicators, and selected outlines.
- Green and red remain reserved for level/status and record semantics.
- Major groups MUST remain readable without relying on text labels alone.
- Icons share consistent optical size, line weight, and internal padding.

The raster primitives are an MVP implementation of these tokens. Future vector
or signed-distance-field rendering MAY improve edge quality without changing the
layout or semantic states.

## Toolbar

The toolbar contains:

- A bounded preset-number display and previous/next controls.
- A compact preset identity surface.
- A centered Robine identity mark that is visually quieter than the active
  equipment.
- One segmented mode selector for rig, amplifier, and inspection views.
- A separate application menu control.

Only one mode segment is active. Focusing the physical amplifier MUST activate
the amplifier segment even when the underlying semantic rig remains loaded.

## Contextual equipment strip

In rig view the strip projects one compact card per pedal. Card widths preserve
the same description-derived footprint ratios as the board layout. Every card
contains a power state, a bounded control-count cue, a pedal accent, and a menu
affordance.

In focused amplifier view pedal cards are replaced by:

- An explicit rig-return control.
- Amplifier identity.
- One normalized indicator per declared amplifier control.
- Power and input-jack status.

The strip MUST reflect the current equipment context; it must not show stale
pedal controls while the amplifier fills the viewport.

## Transport and meters

The transport keeps the play action as its dominant center control. Record,
previous, next, and loop actions remain secondary. The time display uses a dark
instrument field with a single status indicator. Input and output groups mirror
each other and combine one gain control with a segmented level meter.

Inactive meter segments remain visible at low contrast. Active level segments
use green until the bounded high-level range, which uses amber. These meters are
simulated in the no-audio MVP and later bind to the shared parameter/meter model.

## Acceptance criteria

- The equipment viewport remains the largest and brightest window region.
- Toolbar, context strip, and transport use one coherent surface and icon system.
- Bare rectangular debug outlines are not the dominant control treatment.
- Rig focus shows rig mode and description-colored pedal cards.
- Amplifier focus switches the mode state and contextual strip without replacing
  equipment geometry.
- The amplifier strip provides an explicit return to the rig camera.
- Transport groups remain balanced at the fixed application aspect ratio.
- All chrome remains inside normalized bounds at the minimum supported size.
- The release build renders the chrome without external image assets or fonts.
