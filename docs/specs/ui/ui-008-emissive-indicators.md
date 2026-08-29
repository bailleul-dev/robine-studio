# UI-008: Emissive pedal indicators

Status: Draft

## Summary

Pedal indicators are runtime light emitters rather than bright colors baked into
an asset. Each visible LED combines a chrome mount, a colored lens, a compact HDR
core, and one bounded local light that illuminates nearby enclosure material.

## Description contract

- `Pedal.indicator_brightness` is normalized from `0` to `1`.
- Brightness belongs to product state and MAY later follow bypass, automation,
  MIDI, or audio-engine state without modifying geometry.
- Indicator color, lens construction, emission response, light radius, and
  maximum luminous intensity belong to a reusable indicator recipe.
- Assets MUST NOT contain painted bloom, light spill, or exposure-dependent
  halos.

The MVP fixture uses one green recipe and one LED per footswitch. The renderer
clamps description values before deriving emission and local-light intensity.

## Rendering

The procedural LED contains three independently shaded parts:

1. A metallic mounting ring.
2. A glossy colored lens with moderate HDR emission.
3. A smaller high-intensity core that remains readable after tone mapping.

Every active indicator also contributes a small physically positioned light.
Its smooth finite-radius attenuation adds diffuse and GGX specular response to
nearby pedal surfaces. The light is evaluated in linear HDR before the common
ACES-like display transform.

The MVP deliberately avoids a full-screen bloom pass. The pedalboard supports at
most 16 active indicator lights in one fixed-size uniform block, so CPU and GPU
cost remain deterministic in standalone and plugin hosts.

## Acceptance criteria

- The five-pedal demo produces seven indicator lenses and seven local lights.
- Indicator brightness outside `0…1` is rejected by model validation or clamped
  by projection.
- A bright LED preserves a colored lens around its compact highlight.
- Nearby paint receives colored light while distant parquet remains unaffected.
- Chrome, lens, and emissive core remain separately readable in a focused view.
- Emission is tone-mapped and never bypasses the HDR display pipeline.
- Adding indicators cannot exceed the fixed light or mesh capacities silently.
