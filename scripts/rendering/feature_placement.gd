extends Resource
class_name FeaturePlacement

## One hand-placed feature for a sandbox level (World.sandbox_features,
## user's 2026-10-29 ask: dragging a separate Sprite2D per feature was too
## tedious/imprecise). Each entry is placed through the exact same anchor
## code the procedural pass already uses (World._add_feature /
## _add_tree_feature), so a hand-placed tree/rock/decal lands pixel-exact on
## its cell -- no manual Sprite2D, no eyeballing against the grid.
##
## Only consulted when World.procedural_generation is false (see that
## export's doc comment) -- the procedural pass already places everything
## itself otherwise.

@export var axial: Vector2i = Vector2i.ZERO
## True picks the bottom-anchored, wind-swaying tree path (_add_tree_feature)
## -- right for trunk-based art (TREES). False is a plain center-anchored
## sprite (_add_feature) -- right for anything "sitting" on the ground
## (rocks, bushes, flowers, mountains, or any other feature art).
@export var is_tree: bool = false
@export var texture: Texture2D
## Fine pixel adjustment on top of the automatic anchor, same idea as
## World's tree_visual_nudge/rock_visual_nudge exports.
@export var nudge: Vector2 = Vector2.ZERO

## User's 2026-11-10 ask: "larger terrain features" (e.g. a farm/wetland drawn
## as one composite image spanning several hex cells, not just a bigger prop
## sitting on one). The OTHER cells `texture` visually covers, as axial
## offsets relative to `axial` -- `axial` itself is always implicitly
## included and must not be repeated here. Empty (the default) means "this
## texture sits on just axial's own cell", exactly the original single-tile
## behavior -- every sandbox_features entry predating this field is
## unaffected.
##
## When non-empty, World._footprint_anchor_shift shifts the usual
## texture-center/bottom-center anchor by the real on-screen pixel distance
## from `axial` to the footprint's centroid (the average of every covered
## cell's own position, via the SAME cell_centre_in_features positions
## everything else in this project places against -- not a separate
## hex-geometry formula that could drift out of sync with Godot's own
## TileMapLayer placement). This assumes the art is itself drawn centered on
## that centroid, true for a symmetric cluster like a diamond of 4 hexes
## (this project's own receptor_farm.png: `axial` + Vector2i(-1, 1) + Vector2i(1, 0)
## + Vector2i(0, 1), if `axial` names the diamond's top hex) -- an
## asymmetric footprint still needs `nudge`'s own fine pixel adjustment on
## top, same as every other feature here.
@export var footprint_offsets: Array[Vector2i] = []
