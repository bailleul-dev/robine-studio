# UI-004: Assets and materials

Status: Draft

## Summary

Robine uses generated and authored images as reusable inputs to a procedural,
layered material system. Assets must not multiply with every control state,
parameter value, color, or display scale.

## Source assets

The initial pipeline accepts:

- Raster images with transparency.
- Vector artwork suitable for logos, decals, masks, and procedural profiles.
- Indexed meshes for catalog parts whose geometry is not generated procedurally.
- Normal, roughness, wear, and emissive texture inputs where required.
- Font files with explicit redistribution metadata.
- Grayscale masks for wear, roughness, dirt, and material variation.
- Declarative material and recipe manifests.

Every source asset records provenance, authoring intent, and license or ownership
metadata. Generated assets SHOULD record the generating tool and prompt or recipe
when available.

## Generated-image policy

Image generation is appropriate for:

- Fabric, paint, metal, rubber, and paper texture sources.
- Logos and decorative illustrations.
- Wear, dirt, damage, and variation masks.
- Background artwork and unique enclosure graphics.

Image generation SHOULD NOT produce:

- One image for every knob value.
- Separate complete knobs for each material or pointer combination.
- Resolution-specific copies that the asset compiler can derive.
- Text that must remain sharp, localizable, or editable.

Generated images are treated as raw art. They pass through validation and
compilation like authored assets.

Generated base-color assets MUST describe the intrinsic appearance of a surface
under neutral illumination. They MUST NOT contain a directional highlight, a
reflected room or light source, a cast shadow, or ambient darkening that depends
on the final scene. These effects belong to the runtime lighting pipeline defined
by UI-006. Local wear, pigment variation, cavities, printed artwork, and material
masks remain valid asset content.

## Material model

A material combines a bounded set of layers and parameters such as:

- Base color or texture.
- Normalized roughness, normal detail, and highlight response.
- Edge highlight and cavity shading.
- Wear or dirt mask.
- Optional overlay, tint, emissive contribution, and opacity.

The MVP material system is a bounded equipment-oriented shading model rather than
a general physically based renderer. It must represent painted metal, bare metal,
plastic, rubber, wood, fabric, PCB substrate, electronic packages, glass, and
emissive indicators. Material parameters MUST be reusable across geometry and
controls.

## Asset compiler

The compiler:

- Validates manifests and source references.
- Normalizes color space and alpha representation.
- Rasterizes supported vector artwork where required.
- Validates and optimizes imported meshes and their named attachment metadata.
- Produces texture atlases and derived scale levels where beneficial.
- Emits content hashes and a typed runtime manifest.
- Produces deterministic output from identical inputs and tool versions.
- Reports unused assets, duplicate stable IDs, and unsafe atlas padding.

Runtime code MUST consume compiled assets in release builds. Source decoding and
file watching are development features owned by Studio or tools.

The current macOS prototype proves this boundary with one embedded 512 x 512
base-color texture on the studio rug. A material slot selects the texture while
world-space projection supplies deterministic coordinates. Runtime PBR still
owns direct light, local emissive light, shadows, reflections, exposure, and
progressive ambient occlusion. This prototype path precedes the general asset
compiler and MUST migrate to its typed manifest rather than becoming a second
permanent asset system.

## Stable identity and hot reload

Assets and materials use stable namespaced IDs. Successful recompilation can
replace resources while preserving scene references. Failed compilation leaves
the previous resource set active.

Hot reload MUST invalidate dependent display-list or resource-cache entries and
must not leak replaced textures or fonts.

## Acceptance criteria

- One knob geometry renders with at least three materials without duplicated
  source images.
- One enclosure mesh or procedural definition supports closed and open assembly
  views without duplicate exterior and interior assets.
- Wear and tint can be changed independently from base artwork.
- The compiler produces byte-identical output for identical input and version.
- Missing provenance is reported for distributable image and font assets.
- Invalid hot reload preserves the last valid resource set.
- Atlas edges show no neighboring-image bleeding at supported scales.
- Rotating a light changes highlights and cast shadows without changing any
  source asset or base-color texture.
- A generated base-color texture can be embedded, selected by a material, and
  shaded by the same runtime lighting path as an untextured material.
