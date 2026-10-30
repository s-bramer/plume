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
