# UI-006: Runtime lighting and materials

Status: Draft

## Summary

Robine separates what an object is from how the current scene illuminates it.
AI-generated assets describe intrinsic surface properties. The renderer creates
highlights, reflections, contact shading, and cast shadows at runtime from a
declarative material and lighting profile.

This separation lets the same pedal, amplifier, cabinet, knob, or component be
rotated, opened, inspected, and placed in another view without carrying a frozen
light direction in its artwork.

## Separation contract

Each visible surface is assembled from two independent descriptions:

```text
surface description                         scene description
base color / artwork                        studio light rig
metallic                                    environment response
roughness                                   camera and exposure
normal detail                               shadow quality
ambient-occlusion mask (optional)           display transform
emissive mask (optional)
                    └── runtime shading ──┘
```

The surface description MUST NOT include:

- Directional highlights or specular streaks.
- Reflections of a room, window, softbox, or other scene object.
- Cast shadows from controls, cables, enclosure walls, or nearby equipment.
- Vignetting or exposure compensation tied to a particular camera.
- Light-dependent color grading.

Ambient occlusion MAY encode small-scale, view-independent accessibility such as
a deep seam or cavity. It MUST NOT replace direct-light shadowing and SHOULD be
kept subtle enough that opening or disassembling equipment remains plausible.

## Material description

The bounded MVP material contract uses a metallic-roughness workflow:

```zig
Material {
    base_color: LinearRgb,
    base_color_texture: ?AssetId,
    metallic: UnitInterval,
    roughness: UnitInterval,
    normal_texture: ?AssetId,
    ambient_occlusion_texture: ?AssetId,
    emissive: LinearRgb,
    emissive_texture: ?AssetId,
}
```

Values are semantic material properties, not artistic descriptions of a light.
Material instances MAY tint or scale a reusable recipe but MUST remain bounded
and serializable. Equipment descriptions reference materials by stable ID; they
do not contain renderer-specific pipeline objects.

The first implementation supports opaque dielectric and metallic surfaces with
a GGX microfacet response. Painted enclosures also receive a restrained
clearcoat lobe driven by the same runtime studio strips; this preserves a clean,
material-independent reflection over the base paint. This is sufficient to
distinguish painted metal, brushed or polished metal, molded plastic, rubber,
and illuminated indicators.
Transmission, subsurface scattering, anisotropy, and multilayer automotive paint
are deferred until an equipment use case justifies them.

## Lighting profile

A `LightingProfile` is a reusable scene-level description independent from the
equipment model. The initial studio profile contains:

- One static warm side-wall source used as the shadow-casting key.
- One restrained warm fill and bounded conical light volumes for wall sconces.
- A bounded analytic environment contribution so unlit faces remain readable.
- Exposure and display-transform parameters.
- Shadow-map resolution, bias, and filtering parameters.

Production studio lights have visible procedural fixtures. Their emitter
geometry, world-space anchor, color family, and analytic light description MUST
agree so a highlight never appears to come from an absent fixture. Wall sconces
MAY define upper and lower cone directions independently. The animated orbiting
strip remains specific to the Lighting Lab diagnostic view.

Lights are defined relative to the focused equipment bounds or named semantic
anchors, not as arbitrary pixel coordinates. The same profile MUST adapt to a
single knob, a pedal, an amplifier head, or a complete rig after the view solver
provides world-space bounds.

Product views MAY choose another named profile, but equipment data MUST NOT
silently redefine global lighting. A user-facing brightness or studio preset is
a view preference, not a material mutation.

## Rendering path

For every 3D frame the backend:

1. Resolves camera and light transforms from scene descriptions.
2. Renders shadow-casting geometry into a depth map.
3. Shades equipment in linear color using base color, metallic, roughness,
   normals, environment response, direct lights, and filtered shadow visibility.
4. Applies bounded exposure, tone mapping, and the display color transform.
5. Composites semantic 2D controls and diagnostics after the 3D pass.

The current Metal vertical slice uses a depth buffer, 4x multisample
anti-aliasing for the color/depth presentation pass, a 1024 by 1024 shadow map,
percentage-closer filtering, and an ACES-like display curve. Devices without 4x
support fall back to 2x and then 1x. The shadow-only pass remains single-sampled.
Backend-specific objects remain inside `platform`; declarative mesh, material,
and profile data remain inside `ui`.

## Reference comparison view

The Lighting Lab presents an animated side-by-side comparison driven by the same
material values, light orbit, exposure, environment response, and display curve:

- The `3D` side renders procedural triangles with perspective, a depth buffer,
  and a shadow map.
- The `2.5D` side renders one screen-aligned layer. An analytic height field
  reconstructs per-pixel normals and an offset silhouette approximates the cast
  shadow.

The comparison is a visual architecture test, not a performance benchmark. It
MUST keep the light phase synchronized so differences come from representation
rather than from art direction. The 2.5D side demonstrates the eventual asset
contract: an AI-generated height or normal channel can replace the analytic
field without changing the runtime lighting model.

UI-002 selects actual 3D geometry as the production representation for physical
equipment. The 2.5D half of this view remains a diagnostic reference only; it
does not define an alternate asset path or equipment scene model.

## AI asset-generation handoff

An asset request handed to a generation skill MUST include:

- Stable equipment, part, material, and asset IDs.
- Physical dimensions and the surface or UV role of the output.
- Requested channels and their color-space interpretation.
- Required resolution, alpha behavior, tiling behavior, and edge padding.
- A neutral-light instruction and an explicit list of forbidden baked effects.
- Reference views that communicate shape and design, not a lighting target to
  reproduce in the base-color channel.

The request SHOULD ask for independent outputs when artwork, wear, roughness,
normal detail, or emissive areas must be edited separately. Validation SHOULD
flag suspicious strong gradients, repeated reflected shapes, or dark halos in a
base-color asset; final approval remains visual because such tests are heuristic.

## Quality profiles

The renderer MAY expose bounded quality levels for plugin scalability:

- `preview`: analytic lights, reduced shadow resolution, minimal filtering.
- `standard`: filtered shadow map and full material response.
- `high`: higher-resolution shadows and optional image-based environment data.

Quality changes MUST preserve material identity and scene meaning. They may
change sampling quality, never substitute differently lit base-color assets.

## Acceptance criteria

- A metallic knob and its panel render from constant material values while a
  strip light orbits around them.
- The knob highlight changes position and intensity during the orbit without
  changing its mesh or source assets.
- The knob casts a shadow whose direction changes with the light.
- Changing roughness changes highlight width without regenerating artwork.
- Switching to a dielectric material removes metallic response while preserving
  base artwork and geometry.
- Opening, rotating, or focusing equipment produces coherent new lighting rather
  than revealing a baked front-view highlight.
- The scene remains readable when the moving light is behind the equipment.
- Runtime rendering performs no source image generation or decoding per frame.
- Equipment silhouettes, diagonal parquet seams, and screen-space wireframe
  lines use the same supported multisample count in the presentation pass.
