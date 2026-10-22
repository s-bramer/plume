# Godot 4.x Hex Map — Implementation Brief for Claude Code

## Objective
Build a **2D, Civilization-style, pointy-top hex map** in Godot 4.x. Ground tiles are flat and aligned on a regular hex grid. Hills, mountains, forests, and other features are sprites layered over ground tiles; they do **not** change the logical position or size of the underlying hex.

**Priority:** visual correctness and repeatable alignment over procedural complexity. Do not add cliffs, actual raised terrain meshes, or 3D effects.

## First: inspect the existing project
Before modifying anything:
1. Read `project.godot`, the current map scene, its scripts, TileSet resource(s), and relevant sprite dimensions/import settings.
2. Identify the actual Godot 4.x minor version, current hex orientation, TileSet tile size, layout, offset axis, atlas source IDs, atlas coordinates, and node transforms.
3. Explain the specific likely causes of misalignment found in the existing project.
4. **Reuse the existing art and project structure where practical.** Do not rewrite the whole project or replace assets without a reason.
5. If Godot is available, run the project and inspect errors. If screenshots are possible, inspect the actual rendered result before declaring success.

## Non-negotiable design rules
- **Single source of truth for cell positions:** use `TileMapLayer.map_to_local(cell)` for tile centres and `TileMapLayer.local_to_map(point)` for hit-testing. Use `to_global()`/`to_local()` to convert between node spaces.
- Do **not** mix hand-coded axial-to-pixel formulas with TileMapLayer map coordinates. If simulation uses axial/cube coordinates, implement explicit, tested conversions at the boundary.
- The TileSet hex shape/layout/offset axis and the artwork must agree. Choose one pointy-top configuration and verify it visually; do not assume that a setting called `Stacked` automatically produces the desired orientation.
- Ground tile artwork has a consistent logical footprint. Transparent texture padding must be accounted for. Do not adjust cell positions per terrain type.
- Features are **separate sprites**, anchored consistently to their owning cell. Elevation is gameplay data and/or selects hill/mountain art; it does **not** move the ground tile.
- `Ground`, `Features`, and `DebugOverlay` should have identity transforms unless there is a deliberate documented reason otherwise.
- Do not solve alignment by adding arbitrary per-cell pixel nudges. Fix the coordinate system, tile dimensions, texture anchor, or parent transforms.
- Do not create every possible terrain-neighbour combination yet. First get flat tiles and feature anchors correct.

## Desired scene tree
```text
World (Node2D)                   World.gd
├── Ground (TileMapLayer)        hex TileSet
├── Features (Node2D)           y_sort_enabled = true
├── DebugOverlay (Node2D)       HexDebugOverlay.gd
└── Camera2D
```

Keep `Ground` behind `Features`. Features are added as direct children of the Y-sorted `Features` node, with each feature's node origin at its ground-contact point. For more complex objects, use a Node2D feature root at the anchor and place a Sprite2D beneath it. **Do not give each sprite an unrelated Z index**, which defeats sensible Y-sorting.

## Ground generation example
Replace source ID and atlas coordinates with values **inspected from the actual TileSet**. Do not assume these IDs exist.

```gdscript
extends Node2D

@onready var ground: TileMapLayer = $Ground
@onready var features: Node2D = $Features

const WIDTH := 12
const HEIGHT := 10
const TERRAIN_SOURCE_ID := 0  # VERIFY in TileSet
const TERRAIN_ATLAS := {
    "grass": Vector2i(0, 0),
    "desert": Vector2i(1, 0),
    "water": Vector2i(2, 0),
}

var cells: Dictionary = {}

func _ready() -> void:
    features.y_sort_enabled = true
    build_test_map()

func build_test_map() -> void:
    ground.clear()
    for child in features.get_children():
        child.queue_free()
    cells.clear()

    for y in range(HEIGHT):
        for x in range(WIDTH):
            var cell := Vector2i(x, y)
            var terrain := "grass"
            if x >= 8:
                terrain = "desert"
            if y >= 8:
                terrain = "water"
            cells[cell] = {"terrain": terrain, "elevation": 0, "feature": ""}
            ground.set_cell(cell, TERRAIN_SOURCE_ID, TERRAIN_ATLAS[terrain])

func cell_centre_in_features(cell: Vector2i) -> Vector2:
    return features.to_local(ground.to_global(ground.map_to_local(cell)))

func cell_under_mouse() -> Vector2i:
    return ground.local_to_map(ground.to_local(get_global_mouse_position()))
```

**Note:** `Vector2i(x,y)` above is in Godot TileMapLayer map coordinates, not necessarily axial `(q,r)` coordinates. Do not label it axial without a correct conversion.

## Feature placement and sprite anchoring
Prefer a feature scene with a `Node2D` root located at the logical hex centre and a child `Sprite2D`. Place the image relative to its **ground-contact point**, not its texture centre.

```gdscript
func add_feature(cell: Vector2i, texture: Texture2D, ground_anchor: Vector2) -> Node2D:
    # ground_anchor is the pixel position within the texture that touches the ground.
    # Example: Vector2(texture.get_width() / 2.0, texture.get_height())
    var root := Node2D.new()
    root.position = cell_centre_in_features(cell)
    features.add_child(root)

    var sprite := Sprite2D.new()
    sprite.texture = texture
    sprite.centered = false
    sprite.offset = -ground_anchor
    root.add_child(sprite)
    return root
```

**Important:** The bottom-centre of the texture is only the right anchor if the actual artwork reaches that point. Transparent margins can make it wrong. Inspect each source texture and define an explicit anchor for each art family if needed. The anchor is measured in the source texture's pixel coordinates, not guessed from what looks approximately right.

**Y-sorting:** sort feature roots by their logical ground-contact Y position, not the top of their images. Test with adjacent tall mountains/trees in multiple rows. If the chosen Godot 4.x version has particular `y_sort_enabled`/`z_index` behavior, verify it in a minimal scene.

## Visual debugging (mandatory)
Add a toggleable overlay that draws:
- Each cell's logical centre using `Ground.map_to_local()` converted into overlay-local space.
- A hex outline with orientation and size matching the **actual TileSet**. Do not hard-code radius 32 unless the TileSet and artwork are known to use that geometry.
- The map coordinates next to the centre.
- Each feature's ground anchor as a different-coloured dot.
- Optional line from cell centre to feature anchor; it should be zero length unless a deliberate ground offset is specified.

For pointy-top regular hexes of radius `R`, the nominal width is `sqrt(3) * R` and height is `2 * R`; however, atlas texture bounds, integer TileSet sizes, and Godot layout settings can differ. The **actual TileSet mapping** is authoritative. Test an outline against rendered tiles, not just the mathematical formula.

## Required incremental test scenes
Do not jump directly to a complex random map. Make these tests first:

### Test A — Ground-only alignment
- At least 8×8 hexes with alternating grass/desert/water and visible cell outlines.
- No gaps, overlaps, drift, doubled staggering, or unexpected rotation.
- Check top/bottom and left/right extremes, not just the centre.

### Test B — Feature anchor test
- One hill, one forest, one mountain on known cell coordinates.
- Mark cell centres and image anchors; confirm they coincide.
- Try different image sizes and transparent padding.

### Test C — Occlusion test
- Several tall features in adjacent rows and columns.
- Confirm Y-sorting gives sensible front/back overlap.
- Ensure mouse selection uses logical ground positions, not mountain sprite bounds.

### Test D — Camera and transforms
- Pan and zoom camera, then click several known cells.
- Verify cell picking is unchanged by camera transform.
- Confirm no accidental scale/offset on Ground versus Features.

### Test E — Terrain transitions (only after A–D pass)
- Add coastlines or biome edges separately from logical tile positioning.
- Use a six-neighbour edge mask or overlay strategy, but do not change hex centres.

## Common root causes to investigate
1. Mixing axial coordinates, offset coordinates, and Godot TileMapLayer coordinates.
2. Wrong TileSet hex orientation, layout, offset axis, or tile size.
3. Texture atlas region sizes and transparency not matching logical hex footprint.
4. Incorrect sprite anchor (centred sprite vs bottom-centred ground contact).
5. Different transforms on Ground and Features.
6. Applying elevation as a positional shift to ground cells.
7. Inconsistent Z indices or incorrect Y-sort parentage.
8. Applying rounding to calculated positions prematurely.
9. Assuming visual sprite bounds define clickable tile bounds.

## Definition of done
- All ground hexes align across the entire test map, with debug outlines coincident with tile footprints.
- Hills/mountains/forests appear centred on their own hex, without displacing adjacent ground tiles.
- Tall features overlap in the expected order.
- Mouse-to-cell mapping is correct at different camera zooms.
- No per-cell hand-tuned offsets are needed.
- No Godot parser/runtime errors; explain any warnings.
- Provide screenshots (if available), files changed, and a concise explanation of the original root cause and the fix.

## Working instructions for Claude Code
1. **Inspect first; do not guess.** Report the current TileSet configuration and sprite dimensions.
2. Implement only Test A, then run and visually verify.
3. Implement Test B, then run and visually verify.
4. Implement Tests C and D, then run and visually verify.
5. Stop before terrain transitions unless all earlier tests pass.
6. If visual inspection isn't possible, explicitly state that and provide reproducible manual checks; do not claim the alignment is correct without seeing it.
7. Make the smallest coherent changes to the existing project and preserve unrelated functionality.
8. Summarise: root cause, changes made, remaining issues, and how to reproduce each test.

## Useful references
- Red Blob Games — Hexagonal Grids: https://www.redblobgames.com/grids/hexagons/
- Godot 4 TileMapLayer documentation: https://docs.godotengine.org/en/stable/classes/class_tilemaplayer.html
- Godot 4 TileSet documentation: https://docs.godotengine.org/en/stable/classes/class_tileset.html
- Godot hex grid helper project: https://github.com/Zehir/godot-hexagon-tile-map-layer
- Godot hex terrain reference (different rendering approach; borrow ideas, not blindly): https://github.com/davepruitt/hex_map_godot
