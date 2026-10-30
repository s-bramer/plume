# Decisions

Brief record of consequential design/science simplifications and setup choices, per `PLUME_PROJECT_BRIEF.md` §10.

## 2026-10-13 — Hex grid topology, not isometric

The project originally had a test scene (`map.tscn`) built on Godot's `ISOMETRIC` tile shape with a grass/water
demo tileset. That shape is visually isometric but topologically still a 4-neighbor square grid — not the same
thing as a hex grid, and not what the brief's coordinate/transport sections assume. `map.tscn` was kept in place
unreferenced at first, then deleted on 2026-10-13 at the user's explicit request once the hex grid (`scenes/main.tscn`)
was confirmed working.

Switched to a true hex grid (`HEXAGON` topology, pointy-top, axial `(q, r)` coordinates) because:

- A hex grid's 6 neighbors are all equidistant from the cell center, which avoids the diamond/plus-shaped
  diffusion artifacts square grids are prone to — directly serves design pillar 1 ("physics creates the puzzle")
  and guardrail 7 ("do not equate a plume front with one tile per turn").
- The brief's coordinate convention (§7) is already written in terms of axial hex coordinates and neighbor
  offsets; switching topology away from hex would have meant rewriting that section, not just a config value.
- A flat top-down hex grid keeps overlay alignment (heatmap/contour shaders) simple — no projection skew to
  account for, which matters for Phase 0's overlay-legibility spike.

The isometric assets already in `art/` (`roadTiles/`, `isometric tileset/`, `simupak64-124-3/`) are not deleted,
just no longer used for ground tiles. The critter sprites in `art/critters/` are unaffected — they're ordinary
directional sprites that sit on top of the grid regardless of its topology.

## 2026-10-13 — Placeholder cells before any terrain art

`scripts/rendering/hex_grid_view.gd` draws each cell as a procedural `Polygon2D` + `Line2D` outline rather than
a `TileMapLayer` with imported art. This avoids blocking the first playable grid on an art/tileset decision
(guardrail 5: build one playable scenario before adding polish). A `TileMapLayer`-based terrain set is expected
to replace this once Phase 0's look-and-feel spike picks a tile style.

## 2026-10-13 — Quasi-3D relief via a per-cell "skirt," driven by real elevation

The user asked whether a flat top-down hex grid could get some visual depth without re-introducing an isometric
projection (which would complicate overlay alignment — see the first decision above). Added a short darkened
"skirt" polygon under each cell's two lower edges — a cheap, common 2D trick (seen in e.g. Civilization VI's hex
rendering), not a topology or projection change. `pseudo_3d` is an exported toggle on `HexGrid` so the look can
be A/B compared; confirmed on by the user.

First version scaled the skirt's *length* by elevation but kept every cell at the same screen position — the
user correctly reported this read as "very flat," since a longer shadow under a flat silhouette is a weak depth
cue. Revised to shift each cell's screen position upward in proportion to its own elevation (so higher ground
visibly rises above lower ground — the silhouette itself changes) and switched the skirt to a constant
thickness representing physical "block depth" instead. Added a secondary, zoom-independent cue: a continuous
top-face color tint (lighter = higher) between two close tan tones, deliberately kept within the brief's
"warm, calm, desaturated healthy-landscape" palette (§6) rather than a rainbow elevation ramp, so it can't be
mistaken for a future scientific overlay (head/concentration) once those exist.

## 2026-10-13 — Synthetic elevation data (`scripts/simulation/grid_model.gd`)

`GridModel` generates `top_elevation_m` per cell from a deterministic analytic formula (a downhill slope toward
+r, where the flagship scenario's receptor sits, plus a smooth two-term cosine ripple) rather than a real DEM or
surveyed geology. This is a placeholder standing in until Phase 2 scenario data exists, chosen specifically
because it's reproducible and easy to unit-test (bounded, deterministic, smoothly varying between neighbors) —
see `tests/run_tests.gd`. The slope direction is not arbitrary: it anticipates Phase 1 step 4 (a prescribed head
gradient) and keeps elevation, not hydraulic head, correctly as cell geometry per the brief's §4 distinction
("hydraulic head is a dynamic state variable, not an immutable geological property").

## 2026-10-13 — Procedural mountain glyphs and a placeholder river, pending real art

Position/tint/skirt depth still read as "very flat" to the user even after the prior revision. Rather than wait
for real pixel art (no image-authoring tool is available here — that needs Aseprite or a sourced pack per the
brief's §7 tooling plan), added two procedural placeholders to strengthen the read immediately:

- A small twin-peak glyph (plain `Polygon2D` triangles, vapor-grey per the brief's palette) on cells above
  `mountain_threshold` (elevation percentile, default 0.75) — not real art, but an actual recognizable shape
  rather than relying on subtle color/offset alone.
- A single hex-wide "river": a deterministic winding path of one cell per map row from north to south edge,
  rendered as a transparent fill (literal gap to the dark background) with an opaque teal outline so it reads
  as intentional, not a missing/broken tile. This is *not* derived from flow accumulation or a DEM — it's an
  authored path (`_generate_river_path`), independent of `GridModel`'s elevation field, matching guardrail 2
  ("avoid misleading simplifications... label abstracted systems").

Scattered low-elevation cells (a percentile slice of the existing noise field) were considered and rejected for
the river specifically, because the noise doesn't form a connected line — it would have read as a splotchy low
patch, not a stream. A connected, single-tile-wide path reads as a recognizable feature at the cost of being
authored rather than physically derived.

## 2026-10-13 — Switched to real art: Kenney "Hexagon Tiles" (CC0)

The user pointed at `art/kenney_hexagon-tiles/` (already present, CC0, no attribution required per its
`license.txt`) and asked for `tileGrass_full.png` / `tileGrass.png` / `tileWater_full.png` / `tileStone_full.png`
to be wired onto the grid, replacing the procedural polygons/glyphs/gap from the prior two decisions.

Rather than guess pixel offsets from the filenames, inspected the actual PNGs headlessly (`Image.load_from_file`
+ per-row opaque-pixel counts, via a throwaway script since deleted). Findings, since they drove every placement
constant below:

- All four textures share an identical 65×89 canvas and the *same* alpha silhouette: a tapering "top face" from
  row 0–15 (widening to the full 65px width), a constant-width "wall" from row 16–73 (58 rows — the baked-in
  puck depth), and a tapering bottom from row 74–88. This confirms the art already bakes in the exact
  quasi-3D "puck" effect the user asked about earlier — no procedural skirt is needed on top of it.
- `tileGrass.png` and `tileGrass_full.png` have *identical* alpha masks (not a partial/occluded version as
  first guessed) — the difference the user described ("corners, showing lower edge") must be in color/shading
  detail within the same shape, consistent with Kenney's intended use: `tileGrass.png` as the less-prominent
  tile meant to peek out from a neighboring stack, `tileGrass_full.png` as the standalone/featured tile.
- The top face's own natural width (confirmed via the separate `topTiles` flat variant, 55px) implies a native
  hex radius of 55/√3 ≈ 31.8px — close enough to the existing `hex_size = 32` that no grid rescale was needed.
  (Revised below — this specific conclusion turned out to be wrong.)

Placement: each cell is now a `Sprite2D` (`centered = false`, anchored at `(-32.5, -16)`) so image row 16 — the
top-face/wall boundary — lands exactly on the cell's existing axial grid position; the wall and bottom taper
hang below it. The already-existing elevation-driven vertical offset (previous decision) is unchanged and
composes with this directly. Texture choice: `tileGrass_full.png` above `grass_variant_threshold` (0.4) and
`tileGrass.png` below it (mirroring the old lowland/highland tint bands), `tileStone_full.png` above
`mountain_threshold` (0.75, replacing the triangle glyph), `tileWater_full.png` on river cells (replacing the
literal transparent gap).

Removed as dead code: the procedural fill/skirt/mountain-glyph `Polygon2D`s and the lowland/highland/mountain
color constants. Hover/selection feedback was reworked to use `Sprite2D.modulate` (brighten on hover) and a
`Line2D` selection ring using `HexMath.hex_points()` (the grid's own abstract hex shape, not the sprite's — kept
invisible via alpha except when a cell is selected) — this generalizes uniformly across land/water/mountain
cells instead of the old per-cell-type color bookkeeping.

Also set `rendering/textures/canvas_textures/default_texture_filter = 0` (nearest) in `project.godot` so the
pixel art doesn't get blurred by Godot's default linear filtering.

## 2026-10-14 — Fixed tile scale/spacing: decoupled rendering pixel math from `HexMath`

The user reported overlapping tiles and cut-off shapes on hover right after the above change. Root cause was
two compounding errors in the previous entry's measurements:

- Horizontal: the 55px figure used for `hex_size` came from the separate `topTiles` flat variant, not the tall
  puck image actually in use — the puck's own widest row is 65px (measured directly, not estimated), so cells
  were packed ~15% too tight. `hex_size` corrected to 65/√3 ≈ 37.5.
- Vertical: row spacing used `HexMath`'s "pure" hex formula (`1.5 * hex_size`, 48–56px depending on the
  `hex_size` value), but the art's wall is 58px deep. A tile's wall reached *past* the next row and into the row
  after that, so y-sort was drawing things on top of each other across two rows at once — the actual cause of
  the reported overlap/cutoff, not just the horizontal mismatch.

Fix keeps `HexMath` itself a pure, unmodified regular hexagon (still used for the simulation grid and the
selection-ring shape) and adds a rendering-only vertical stretch: `row_spacing_px` (73px = texture height 89
minus the top-face anchor 16, i.e. the next row's top point lands exactly where this row's wall ends — one row
of overlap, not two). New `_axial_to_screen()` / `_screen_to_axial()` helpers apply this consistently for both
placement and mouse hit-testing (verified by a new round-trip test in `tests/run_tests.gd` — placement and
click detection must agree, or hover would drift from what's visually under the cursor). `hex_size` and
`row_spacing_px` are the two Inspector fields to hand-tune further if the defaults aren't quite right.

## 2026-10-14 — Reverted the stretch; walls should hide on flat ground, not show everywhere

The 73px-stretch fix above was itself wrong, per the user's next report: every tile's wall was now visible,
making flat terrain look like a uniform staircase, and the selection ring was visibly offset from the tile
(since the ring used `HexMath`'s true spacing while the sprite used the stretched spacing — the two had
diverged). The user suggested either building a reference scene or finding another source to ground the
geometry in; the pack's own `sample.png`/`preview.png` (viewed directly) turned out to answer this cleanly:
on a flat plateau, neighboring tiles' walls are almost entirely hidden by the tile drawn in front of them —
only an actual elevation step (grass-to-mountain) or the unobstructed outer edge of the island shows a wall.

Reverted to **true, unmodified `HexMath` spacing** for every cell (no custom `row_spacing_px` stretch) — at
true spacing, a same-tier cell's wall is naturally covered by the cell in front of it via y-sort, matching the
sample art. This also fixes the selection ring: since there's only one coordinate system again (ring and sprite
both positioned by plain `HexMath.axial_to_pixel`), they can no longer disagree.

Elevation changed from a continuous per-meter offset to a **discrete step**: only cells at/above
`mountain_threshold` get a fixed `mountain_rise_px` (40px) upward shift, which is what exposes their wall
against the unshifted (tier-0) cell in front — the clean cliff look in the sample image, rather than a smooth
continuous tilt (which, at true spacing, would partially expose every cell's wall by varying amounts and
reintroduce the staircase problem). The southmost row's wall now shows "for free," with no special-case code:
nothing is drawn in front of it in y-sort order, so its wall is simply never covered.

`hex_size` corrected again: 55/√3 ≈ 31.75, derived from the *flat* `tileGrass_tile.png` variant's own top-face
width (55px, pixel-measured), not the taller puck's wider 65px "equator" — the puck is deliberately drawn wider
than the true grid footprint for visual weight, and using its width for spacing was the original horizontal bug.

Known limitation, not yet fixed: mouse hit-testing uses each cell's *true* (unshifted) grid position, so a
mountain cell's hit-box doesn't visually track its raised sprite. Not reported as a problem yet; flagging so
it's not mistaken for new, undiagnosed behavior if noticed later.

## 2026-10-14 — Dropped the puck/wall approach entirely: flat tiles + decorative props

The discrete-step fix above still produced overlap/cutoff artifacts and a visibly broken mountain (a gap of
background showing as a "black lip" at its base) — traced to the offset/wall-reach math only working cleanly
within a narrow range the 40px default didn't respect, confirming the approach was too fragile to keep patching.
Per the user's request, searched for existing implementations before guessing further: no public repo solves
"2D sprite-stacked Kenney hex tiles with elevation" cleanly — the closest hits either don't address elevation at
all ([Zehir/godot-hexagon-tile-map-layer](https://github.com/Zehir/godot-hexagon-tile-map-layer), whose "stacked
layout" terminology turned out to mean grid-coordinate layout, not height) or are genuinely 3D
([KenneyNL/KayKit-Hexagons](https://github.com/KenneyNL/KayKit-Hexagons), using `GridMap` + 3D meshes — likely
what the user had seen and found impressive). Multiple Godot forum threads and an open
[godot-proposals issue](https://github.com/godotengine/godot-proposals/issues/6715) confirm 2D sprite-stacked
height is a known-awkward, poorly-supported area of the engine, not something being missed.

Given a choice between pursuing fragile 2D puck-stacking further or pivoting to 3D (which would contradict the
brief's explicit §7 "2D, not 3D" decision), the user chose a third option after sharing a reference image: a
genuinely flat 2D hex grid where terrain/elevation reads through biome color and decorative icons (mountain rock
clusters, trees) rather than through any pseudo-3D offset geometry. This sidesteps the entire class of bugs from
the last several revisions — no walls, no y-sort offset math, no stacking, no multi-row overlap to get wrong.

Implementation: every cell uses a flat `_tile` texture (`tileWater_tile`/`tileSand_tile`/`tileGrass_tile`/
`tileSnow_tile`), banded by `_elevation_t()` (water via the river path, then sand/grass/snow thresholds, all
Inspector-tunable). Forest-band and snow-band cells get a deterministically-chosen decorative prop (pine/round
tree, or a `rockSnow` jagged-peak ground-tile swap) via a cheap reproducible hash (`_pseudo_random01`, a
sin-based hash — not Godot's RNG, specifically so results don't depend on execution order or a seed to manage),
covered by a new test (`_test_decoration_hash`) checking range, determinism, and salt independence.

All anchors here are pixel-measured, not guessed: every ground texture (`_tile` variants and `rockSnow`) shares
one 65×89 canvas with content bottom-aligned at row 61 (confirmed across grass/sand/snow/rockSnow), so one
`GROUND_ANCHOR_PX` constant positions all of them. Tree props have zero canvas padding (opaque content fills the
full height, confirmed by bbox inspection), so they're anchored at their own canvas bottom instead — the "feet"
land exactly on the cell's true grid position.

This also fixes the selection-ring misalignment for good, the same way the true-spacing revert did: every piece
(ground sprite, prop, ring, label) is now a child of one `Node2D` positioned by plain, unmodified
`HexMath.axial_to_pixel` — there is no second coordinate system left for anything to disagree with.
(The ring-alignment claim above turned out to be undermined by a real bug — see the next entry.)

## 2026-10-14 — Fixed a real anchor bug (zigzag seams, ring offset); added water-edge banks

The flat-tile pass above still showed a dark zigzag at every row boundary and a badly offset selection ring, per
a screenshot the user shared. Cause: `GROUND_ANCHOR_PX` was set to 61 (the *bottom* of each ground texture's
opaque content), when the earlier pixel inspection had correctly found the content's vertical *center* at row 33
— row 61 was the number that happened to match between the flat tile and `rockSnow` (both end their content at
that row), which is a different fact than "this is the grid anchor." Using the bottom instead of the center
shifted every tile ~28px above its true position, which is what produced the zigzag (adjacent rows no longer
overlapped correctly) and the ring offset (the ring was never wrong — it stayed at the true position the whole
time; the sprite was wrong and only looked like the ring had moved). Corrected to row 33.

Also added small dark "bank" edges along water, per the user's reference image (`hex_example.png`): water sits
flush with its neighbors (no Y-offset — offsets are exactly the mechanism that caused every bug in this session,
so deliberately avoided here) but gets a short `Line2D` segment, in `BANK_COLOR`, drawn along any hex edge where
a river cell borders a non-river cell. This needed knowing which of `HexMath.hex_points()`'s 6 edges corresponds
to which axial neighbor direction — derived once by computing each `NEIGHBOR_OFFSETS` entry's actual pixel-space
angle (via `HexMath.axial_to_pixel`) and matching it to the edge facing that angle, stored as the new
`EDGE_NEIGHBOR_OFFSETS` (ordered to match edge index, unlike `NEIGHBOR_OFFSETS` which is order-independent for
its own use). Unlike the anchor bug above, this derivation is covered by a geometric test
(`_test_edge_neighbor_offsets`) rather than just asserted by hand — exactly the kind of claim that caused the
anchor bug, so this one checks itself against `HexMath`'s own formulas instead of trusting arithmetic done once
and not re-verified.

## 2026-10-14 — Fixed the real cause: row spacing itself was too wide for this art

The anchor fix above still left a visible dark zigzag between every row, per the user's next screenshot. Viewed
`tileGrass_tile.png` directly — no border or outline baked into the art at all, confirming the dark zigzag was
the canvas background bleeding through an actual gap between rows, not a style choice or a residual offset bug.

Rather than hand-derive another spacing number (three previous rounds of that produced three different wrong
numbers this session), wrote a throwaway script that composites two real copies of the tile's alpha channel at a
range of candidate spacings and measures the combined coverage width in the overlap band directly. Result: the
"pure" hex row-spacing formula (`1.5 * hex_size` ≈ 47.6px) leaves a real gap at every spacing tested down to
44px; full gap-free coverage only starts at spacing ≤ 30px. This art's vertical taper is shallower than a true
regular hexagon's, so it needs tighter rows than hex math alone would suggest — consistent with the long-known
oddity (way back in this session) that the flat tile's own bounding box is nearly square (55×57) rather than
the elongated proportions a true hex would have.

Reintroduced `_axial_to_screen()`/`_screen_to_axial()` (same shape as the approach tried and reverted twice
before, but this time with an empirically-verified value, `ROW_SPACING_PX = 30`, not a guess) — horizontal
placement still comes from `HexMath` unchanged (confirmed correct by the user: "tile selection seems to be
aligned now"), only vertical spacing is overridden. Applied to both cell placement and mouse hit-testing, with a
round-trip test (`_test_screen_space_round_trip`) so the two can't silently disagree the way they did before.

Known, deliberately unaddressed mismatch: the selection ring and water-bank lines still use `HexMath.hex_points()`
at the full mathematical hex height (~63.5px), taller than the new 30px row spacing — they may look oversized
relative to the tighter grid. Not fixed proactively, to keep this change scoped to the reported bug; flagging so
it isn't mistaken for a new, unexplained issue if noticed.

## 2026-10-14 — Rebuilt on TileMapLayer, per the user's `godot_hex_map_spec.md`

The user shared a screenshot still showing skewed tiles, a selection ring that didn't fit the tile, black river
edges, and misshapen edges along the river/map boundary — plus a spec document (`godot_hex_map_spec.md`)
diagnosing exactly why: hand-rolled axial-to-pixel math, with placement/hit-testing/debug-overlay each computed
independently, is inherently prone to silent divergence. That's a correct diagnosis of the actual pattern behind
every bug this session (ring offset, hit-test drift, the zigzag) — not just this specific screenshot.

Rebuilt the renderer on the spec's prescribed architecture: `Ground` is a real `TileMapLayer` with a hex
`TileSet`, using `map_to_local()`/`local_to_map()` as the single source of truth, instead of parallel hand-coded
position functions that could disagree. New files: `scripts/rendering/world.gd` (builds the TileSet/TileMapLayer,
replaces `hex_grid_view.gd`'s role), `scripts/rendering/hex_debug_overlay.gd` (the spec's mandated debug
overlay — cell centers, coordinates, and a hex outline derived from the TileSet's own `tile_size`, not an
independently-chosen size). `scenes/main.tscn` now matches the spec's scene tree (`Ground`/`Features`/
`DebugOverlay`/`Camera2D`). `hex_grid_view.gd` and `grid.tscn` are now unused/orphaned, not deleted — superseded,
not removed, in case anything in them is still wanted for reference.

`tile_size = (55, 40)`: width from the art's measured top-face span (55px), height chosen so
`tile_size.y * 0.75 = 30px` matches the gap-free row spacing measured earlier.

**A second real bug, caught by testing rather than assumed fixed:** initially assumed Godot's
`TILE_LAYOUT_STACKED` + `TILE_OFFSET_AXIS_HORIZONTAL` treats map coordinates as axial `(q, r)` directly, based on
a probe that only checked `|r| <= 1`. A permanent test using a wider range (`q` in [-4,4], `r` in [-5,5])
immediately failed — Godot's `STACKED` layout is actually a discrete "odd-r" offset-coordinate scheme (odd rows
shoved right by half a tile, regardless of magnitude), which only happens to coincide with continuous axial
scaling for `|r| <= 1`. This is exactly the mistake the spec explicitly warns against ("do not mix hand-coded
axial-to-pixel formulas with TileMapLayer map coordinates... implement explicit, tested conversions at the
boundary") — and would have been shipped as a confirmed-correct claim without the wider test. Added
`scripts/rendering/godot_hex_offset.gd` (`axial_to_offset`/`offset_to_axial`, the standard "odd-r" formulas)
and now apply it at every point axial coordinates reach the TileMapLayer (`world.gd`'s cell placement and
`cell_under_mouse()`, `hex_debug_overlay.gd`'s cell-center lookup) — `GridModel` itself stays keyed by axial
`(q, r)` per the brief's §7 convention; the conversion happens only at this one boundary.

This is **Test A only**, per the spec's own incremental methodology (ground alignment before features before
occlusion before camera/hit-testing, each visually confirmed before the next): a simple 3-terrain test pattern,
no river, no elevation banding, no decorative props yet. Those return in later passes once ground alignment
itself is confirmed — deliberately not rebuilding everything in one pass again, since that's what produced
several of the undetected bugs earlier this session.

## 2026-10-14 — Fixed the debug overlay outline (squished, offset from the tiles)

The TileMapLayer rebuild worked — the user confirmed zero gaps/overlaps across the whole map, the actual goal of
Test A. But the debug overlay's hex outline looked vertically squished and offset from the real tiles.

Cause: `hex_debug_overlay.gd` used `tile_set.tile_size` (55, 40) as if it were the hex's true rendered
dimensions. It isn't — `tile_size.y` is a *layout/spacing stride* for Godot's offset-coordinate math, deliberately
shorter than the art (that's the whole point of the earlier row-spacing fix: so consecutive rows overlap enough
to hide gaps). Using it as the outline's height produced a shape about 2/3 the real tile's visual size, which
then also reads as "offset" even though its center point was correct — a hex outline much smaller than the tile
it's centered on doesn't visually trace the tile's edges.

Fixed by decoupling "where is the cell" (from `TileMapLayer.map_to_local()`, unchanged, already verified correct)
from "what does the art actually look like" (now `GROUND_ART_SIZE = (55, 57)`, measured directly from the tile
PNG's alpha channel — max width 55px, opaque content spans 57 rows top-to-bottom — not a layout parameter).
Covered by a new test (`_test_debug_overlay_outline_matches_measured_art`) that re-measures the real art file
directly rather than trusting the one-off inspection from earlier in the session.

## 2026-10-14 — Fixed the outline's remaining position offset (not size)

Correct size, still offset (confirmed by the user's next screenshot — the outline no longer looks squished, but
its position still didn't match the rendered tiles). The remaining cause: `TileSetAtlasSource` was given the
*full* 65×89 canvas as its `texture_region_size`, so Godot centers that whole padded canvas on the tile position
by default — not the visible content within it. The content's own center (row 33 of 89, pixel-measured) sits
~11.5px above the full canvas's geometric center (44.5), so the rendered art appears shifted up from where the
debug overlay (correctly centered on the logical tile position) draws its outline.

The textbook fix is `TileData.texture_origin`, but its exact sign convention isn't reliably documented and isn't
verifiable here — there's no way to render an actual frame headlessly to check which direction it shifts things,
and this session already shipped two confident-but-wrong sign/offset guesses this way. Sidestepped the ambiguity
instead: measured the art's precise opaque bounding box directly (`x[5..59] y[5..61]` within the 65×89 canvas,
confirming content is horizontally centered — 5px margin each side) and set `TileSetAtlasSource.margins = (5,5)`,
`texture_region_size = GROUND_ART_SIZE = (55,57)` so the atlas region *is* the visible content, not the padded
canvas. Godot's default region-centering then lands on the content regardless of which exact internal convention
it uses — the fix doesn't depend on knowing that convention at all. `hex_debug_overlay.gd` now reads
`GROUND_ART_SIZE` from `World` instead of duplicating the value, so the two can't drift apart again the way
`tile_set.tile_size` and the outline math did two entries ago.

## 2026-10-14 — Remaining tiny mismatch: likely rendering style, not coordinates

A zoomed-in screenshot showed a very slight residual offset, with the debug outline "looking like a higher
resolution" than the tile art's own edges. Likely explanation: `draw_polyline()` draws a smooth, possibly
anti-aliased vector line, while the actual ground art renders nearest-neighbor-filtered (blocky by design, for
crisp pixel art — set in `project.godot` earlier this session). Two different rendering techniques tracing very
similar boundaries can look mismatched even when the underlying coordinates agree. Explicitly passed
`antialiased = false` to `draw_polyline()` as a cheap, safe test of this hypothesis — much lower-risk than another
pixel-offset guess, since it changes a rendering flag, not a position/size number already verified correct.

Noted but not chased further: the debug outline is a mathematically idealized hex (straight edges, linear
taper from `HexMath.hex_points()`); if the art's actual silhouette tapers non-linearly, a small residual
mismatch near the corners specifically is possible even with correct overall size and position. This doesn't
affect real functionality — `Ground`'s actual tile positions come from `TileMapLayer.map_to_local()`, verified
correct by test and by the user's confirmation of zero gaps/overlaps; only the diagnostic outline's corner-level
precision is in question, not gameplay positioning or hit-testing.

## 2026-10-14 — Test B: river + elevation-driven features, per the spec

With Test A (ground alignment) confirmed, moved to Test B: river and elevation back in, this time following the
spec's non-negotiable rule that elevation selects ground terrain/feature art but never moves a ground tile's
logical position. `world.gd` now builds: river (the same deterministic winding-path generator from earlier in
the session, unchanged) selects the water ground terrain; elevation bands select sand/grass/snow ground terrain
(`SAND_THRESHOLD`/`SNOW_THRESHOLD`); a new `TERRAIN_SNOW` atlas source was added (`tileSnow_tile.png`, same
crop-to-content treatment as the other three). Forest-band and snow-band cells may additionally get a `Features`
child (tree or `rockSnow` rock cluster) via the same deterministic hash used before, placed per the spec's
prescribed pattern: a `Node2D` root at `cell_centre_in_features(axial)`, a child `Sprite2D` with
`centered = false` and `offset = -ground_anchor`. `ROCK_GROUND_ANCHOR` is pixel-measured (rockSnow's opaque
content ends at the same canvas row, 61, as the ground tiles — they share the template — and is close to
horizontally canvas-centered), not guessed; trees use the spec's own stated zero-padding formula directly
(`Vector2(width/2, height)`), confirmed earlier this session to have no transparent margin.

**A second false-positive test bug, caught before being reported as fixed:** the first version of the new World
tests called `World.new()` and immediately accessed its state — but `Node._ready()` is deferred by Godot's
lifecycle (it does not fire synchronously on `add_child()`), and this test script's `_init()` returns and calls
`quit()` before the engine ever processes a frame. So `@onready var ground`/`features` were still `null`, and
everything gated on `_ready()` having run (`_model`, `_elevation_lo/hi`, `_river_cells`) silently no-op'd instead
of erroring — one test crashed outright (`cell_centre_in_features` on a null `ground`), but the other two
*reported PASS* while iterating empty/default state (an empty river-cell dict, elevation always falling back to
the midpoint default). This is the exact false-positive pattern from earlier in the session (a compile/runtime
error in a called function silently zeroing out the caller's failure count) recurring in new test code, not
fixed by the earlier fix. `_make_world()` now builds the child nodes and calls `World`'s build methods directly,
in the same order `_ready()` uses, instead of relying on the deferred lifecycle at all — deterministic regardless
of engine timing.

## 2026-10-14 — Test B feedback: confirmed river gap (real bug), investigated and ruled out tree/rock anchors

The user reported five issues from a screenshot. Investigated each rather than guessing which were real:

- **"Water tiles not all connected (gap in the river)" — confirmed, real bug.** A throwaway script measuring
  `HexMath.axial_distance()` between consecutive river cells found 4 actual gaps (hex distance 2, not 1),
  concentrated near the map edges. Root cause: `_generate_river_path()` computed each row's column
  *independently* via a sine formula, clamped to that row's valid range — but "one cell per row, each valid"
  does not imply consecutive rows are adjacent, and the only property ever tested was the weaker one. Near the
  map's edges the valid-column range narrows and clamps differently row-to-row, producing a jump. Fixed by
  rewriting it as an actual walk: each step moves to a genuine hex neighbor (straight down or diagonal-left),
  biased by the same sine signal for the wander shape, so adjacency holds by construction rather than by hoping
  the formula doesn't clamp inconsistently. Covered by a new test comparing every consecutive pair with
  `HexMath.axial_distance()`.
- **"Trees not rooted in centre (offset)" and "mountain art... makes it look odd" — investigated, anchors
  measured correct.** Rather than assume these needed a pixel-offset fix (this session's most common and most
  expensive mistake), directly measured the trunk/rock base position at the bottom rows of each texture: tree
  trunks center within 0.5px of `width/2` (what's already used); rockSnow's base centers within ~1px of the
  `ROCK_GROUND_ANCHOR` already in use. Both anchors are correct. The visual effect is more likely the natural
  consequence of tall feature sprites (~100px for trees, ~60px for rocks) against the deliberately tight 30px
  row spacing (needed for gap-free ground tiles) — their upper portions extend into neighboring rows by design,
  the same way the reference `sample.png` shows trees/mountains overlapping their own hex. Not changed, since
  there's nothing measurably wrong to fix; flagged honestly as a design tension rather than silently left alone.
- **"Blue outlines still showing" and "weird overlap at specific tiles"** — added `World.show_debug_overlay`
  (now `false` by default, toggle on in the Inspector to re-check alignment). Test A's goal (confirmed ground
  alignment) is done; the overlay was always meant to be a diagnostic, not a permanent fixture. The reported
  "weird overlap at 1,6/1,7 and 2,2/2,1" may well have been overlay line/label clutter rather than a real ground
  tile issue — asked the user to re-check with the overlay off before investigating further, rather than guess
  at a fix for an effect that might not exist in the actual game view.

## 2026-10-14 — Mountain anchor changed to center; "truncated" tiles traced to baked-in art detail, not a bug

With the overlay off, the user saw two more things: ground tiles each showing a short diagonal grey mark that
reads as "truncated," most noticeable at terrain-type boundaries (grass/sand); and explicit confirmation that
trees should stay ground-contact/bottom-anchored but mountains should be CENTER-anchored instead (a rock cluster
sitting balanced on a cell, not growing from one edge of it — the actual cause of "mountains... look odd").

**Mountain anchor — fixed.** Measured rockSnow_1/2's true geometric center (not just its base) directly:
`(31.75, 30.5)`. Added `ROCK_CENTER_ANCHOR`, used only for rocks; trees keep their existing ground-contact
anchor (ok per spec and per the user's own words: "tree trunks need to start in cell centre... mountains have to
be centred on the cell (which is different)").

**"Truncated" tile outlines — investigated, not a bug.** Measured all four ground textures' (grass/sand/water/
snow) opaque bounding boxes independently rather than assume they share one crop: all four are pixel-identical
(`x[5..59] y[5..61]`), ruling out a per-terrain-type cropping inconsistency. Then opened `tileSand_tile.png` and
`tileWater_tile.png` directly — both show the same subtle lighter diagonal highlight along the top-left edge
that `tileGrass_tile.png` showed back at the very start of this work (documented at the time: "a very subtle
lighter highlight on the top-left edge"). This is baked into the source art itself, not introduced by any code
here, and not something fixable by adjusting positions/crops — there's nothing measurably wrong to correct. It
reads as more noticeable at terrain-color boundaries because the color contrast there draws the eye, not because
the detail itself is different there (confirmed identical across all four textures). It was very likely present
the entire time the TileMapLayer rebuild has been in place, just visually buried under the debug overlay's own
lines/dots/labels until those were turned off — a visibility change, not a regression from the last round's
actual code change (which only touched the river algorithm and the overlay toggle).

## 2026-10-14 — Restarted per the spec's own incremental methodology, after skipping ahead

The user correctly called out that the last several rounds had become reactive guess-and-patch cycles on a full,
busy scene (all four terrain types, probabilistic tree/rock density, the river, all at once) — exactly what
`godot_hex_map_spec.md`'s "Required incremental test scenes" section exists to prevent. In hindsight: Test A
(ground alignment) was done properly and is independently confirmed solid. But Test B was never actually done as
specified ("**one** hill, **one** forest, **one** mountain on known cell coordinates... do not jump directly to a
complex random map") — it was skipped straight to something closer to Test E (full terrain transitions +
decoration), with Tests C (occlusion) and D (camera/hit-testing) never done in isolation at all. Every screenshot
since then mixed multiple variables (terrain banding, decoration crowding, anchor correctness, the baked-in art
highlight) into one image, which is exactly why real bugs (the mountain anchor, the river gap) and non-bugs (the
art highlight, feature crowding from tall sprites at tight spacing) kept getting tangled together.

Added `World.minimal_test_mode` (default `true`): flat grass everywhere, no river, exactly one tree (`(-4, 0)`)
and one rock (`(4, 0)`), well separated, with `show_debug_overlay` also defaulted back to `true` — matching the
spec's literal Test B instruction to mark cell centres and image anchors and visually confirm they coincide,
with nothing else on screen to confound that specific check. The full biome/decoration/river system (previous
entries) is preserved behind `minimal_test_mode = false` for Test E, once B through D are each confirmed in turn
— not deleted, just not what's currently on screen. `tests/run_tests.gd`'s existing full-system tests now set
`minimal_test_mode = false` explicitly (they were silently exercising the new minimal path otherwise, once its
default flipped); a new test confirms the minimal scene itself matches its own description (all-grass, exactly
one tree + one rock).

Plan from here, one test at a time, stopping for visual confirmation after each (per the spec's own working
instructions — "Implement only Test A, then run and visually verify... Stop before terrain transitions unless
all earlier tests pass"): confirm Test B, then Test C (occlusion — tall features in adjacent rows/columns,
sensible front/back draw order), then Test D (camera pan/zoom, hit-testing unaffected), then restore
`minimal_test_mode = false` for Test E.

## 2026-10-14 — Test B result: rock anchor likely fine, tree needs more evidence, found a real asset-shape insight

From the isolated Test B scene: the rock's center-anchor reads as roughly right (user: "I think the rock looks
good"); the tree's trunk reads as sitting too high. Investigated rather than re-guessing a sprite offset a third
time:　

- Confirmed the imported `Texture2D`'s reported dimensions exactly match the raw PNG (30×101 for `pineGreen_mid.png`)
  — rules out an import-pipeline size mismatch as the cause.
- Confirmed `Sprite2D`'s documented `centered=false`/`offset` semantics match what's implemented (offset shifts
  the texture's top-left corner; the existing `_test_world_feature_centre_matches_ground` test already proves the
  feature root's position is correct, matching Ground exactly).
- Given both of those check out, the likely explanation is the debug overlay itself: the coordinate label is
  intentionally offset from the true center by `Vector2(-18, -26)` (so it doesn't overlap the center dot) — a
  casual visual comparison against the label's position, rather than the small dot, would read as "too high" even
  when the trunk is correctly at the cell's logical center. Added a precise magenta crosshair exactly at that
  logical center (the dot has visible radius/fuzziness; the crosshair pins an exact pixel) to make the comparison
  unambiguous, and asked the user to re-check against it specifically before changing any position math again.

**Real, useful finding about the "steps" on the mountain's outline:** measured rockSnow_1's own row-width profile
the same way the old `_full` "puck" tiles were measured earlier in the session. It is *not* the same tall-wall
puck structure (`max_width` over a 58-row band) — it's much closer to the flat ground tile's own shape (56px
over a 27-row band), except its content starts at row 0 instead of row 5, i.e. the rock peaks extend ~19px above
where a normal flat tile's content would start. The debug outline is sized to the *flat tile's* shape
(`GROUND_ART_SIZE`), so it doesn't — and structurally can't — fully enclose a silhouette that pokes out above
that shape by design (that's literally what makes it read as a mountain instead of a flat hex). The "steps" are
most likely the outline cutting across the rock's genuinely non-hexagonal, jagged silhouette, not a position bug.

## 2026-10-14 — Tree still read ~10px off against the crosshair; exposed tuning instead of continuing to verify

Fetched Godot's actual engine source (not documentation summaries) for both `TileMapLayer::draw_tile()` and
`Sprite2D::_get_rects()` and confirmed the implemented formulas match exactly. Traced the arithmetic directly
for cell `(-4, 0)`: computed trunk-base position matched the cell center to an exact `(0.0, 0.0)` difference, not
an approximation. No pixel-snapping setting is enabled that could explain even a small deviation. Every
verifiable layer checks out, and the gap (per the user's own words) isn't worth more of this: "this kind of
tinkering seems to be a waste of tokens... I assume these are easy settings I could adjust. Please pass simple
things like this onto me."

Added `tree_visual_nudge`/`rock_visual_nudge` (`Vector2`, exported on `World`/`Main`) — added directly to each
feature's final `Sprite2D.offset`, so +Y moves it down on screen, +X moves it right, standard screen convention.
Wired into both the minimal-test-mode placements and the full biome system's placements, so a value tuned now
carries forward to Test E. This is a deliberate shift in approach, not just this one fix: see
`memory/feedback_expose_visual_tuning.md` — fine visual tuning goes to an Inspector-adjustable export the user
can see-and-adjust directly, rather than more blind verification on something only visible on their screen.

## 2026-10-14 — Permanent grey hex grid outline (new node: GridOutline)

The user asked for an even grey outline on every tile edge (per the `hex_example.png` reference) and reported
some edges — "all vertical lines" — missing, wondering if it was an alignment bug. It isn't: the ground art has
only a single subtle highlight stroke on the top-left edge (confirmed by direct pixel inspection much earlier
this session), never a full border on any tile. There was nothing to misalign — the look the user wants simply
didn't exist as a rendered element yet.

Added `scripts/rendering/grid_outline.gd`, a new permanent node (`GridOutline`, between `Ground` and `Features`
in `scenes/main.tscn`) that draws a complete grey hex outline on every cell, always on (not tied to
`show_debug_overlay`). Reuses the same `GROUND_ART_SIZE`-derived outline shape `DebugOverlay` used, sourced from
`World` directly rather than duplicated, so the two can't drift (covered by a new test). Simplified
`hex_debug_overlay.gd` to drop its own now-redundant outline — it keeps only the dot/crosshair/label, the
genuinely diagnostic elements; the permanent grid line is a real design element now, not something to debug with.
`line_color`/`line_width` are exported on `GridOutline` for direct Inspector tuning, per the same "expose it,
don't guess" approach from the previous entry.

## 2026-10-14 — Fixed outline overlap ("step"); brought back hover/click selection

The grey grid outline (previous entry) showed a double-line/lattice "step" pattern, and the user asked for
hover/selection highlighting back, plus confirmation the outline sits behind features.

**Outline fix.** The outline was sized from `GROUND_ART_SIZE` (55×57) — the same size as the actual rendered
art, which deliberately *overlaps* between rows (that's the whole mechanism behind the 30px row spacing staying
gap-free on art whose proportions aren't a true regular hexagon). Using that same overlapping size for the
*outline* meant adjacent rows' outlines crossed through each other. Switched to `TILE_SIZE` (55×40) instead —
not a guess: `TILE_SIZE.y * 0.75` is literally the formula that produces the 30px row spacing in the first
place, so a hex of that exact size tiles edge-to-edge with no overlap and no gap at the spacing actually in use.
This is the one size that's geometrically consistent with how the grid really works, independent of whatever the
art's own (overlapping) footprint happens to be.

**Behind features, confirmed not just assumed.** `GridOutline` was already placed before `Features` in
`scenes/main.tscn`'s node order, and Godot draws siblings in tree order — so this was already correct by
construction, not something that needed a fix; happy coincidence that reducing the overlap artifact likely also
reduced any visual sense of the grid "crossing over" trees.

**Hover/selection, rebuilt on the spec-correct foundation.** Added `scripts/rendering/hex_selection.gd`: hover
shows a semi-transparent fill, click shows a persistent blue outline, both using the same corrected `TILE_SIZE`
shape as `GridOutline` (covered by a new consistency test). Hit-testing goes entirely through
`World.cell_under_mouse()` (itself `Ground.local_to_map()`), never an independent coordinate computation — the
exact discipline the whole TileMapLayer rebuild exists to enforce. Placed last in the scene tree (after
`Features`/`DebugOverlay`) so the highlight is always visible on top, regardless of what's on the cell — the
opposite placement requirement from `GridOutline`, which must stay behind features.

On "perhaps I need a tileset with outlines": not needed for this specific problem — the fix above is purely
geometric (which `Vector2` the outline code reads), nothing to do with the art. A proper outlined tileset would
still face the exact same spacing-vs-art-proportions tension that drove the whole row-spacing investigation
earlier this session, so it's not obviously simpler; worth revisiting only as a genuine art/polish decision
later, not as a fix for this.

## 2026-10-14 — Explained the overlap; exposed outline/selection size instead of guessing a compromise

The user asked *why* every tile overlaps its neighbors so much, and reported the new outline looked "vertically
squished" relative to the rendered tiles. Measured the real cause rather than describe it vaguely: the tile art
is at **full width for 30 of its 57 rows** (rows 19–48) — a true hexagon only reaches full width at a single
point (its vertical center), then tapers continuously the rest of its height. This art's taper is squeezed into
the remaining ~27 rows at the top/bottom extremes, giving it far less "interlocking give" than a true hexagon of
the same width — confirmed earlier this session by directly compositing the art's alpha channel at a range of
spacings (needs ≤30px to stay gap-free; a true hexagon this wide would only need ~47.6px).

This also explains the "squished outline" complaint precisely: `GridOutline`'s shape (`TILE_SIZE`, 40px tall) is
the mathematically non-overlapping size at 30px spacing, but the real art — because of its wide-waisted shape —
visually occupies more like 57px of apparent height at that same spacing, via overlap rather than its own
boundary. No single size is simultaneously non-overlapping *and* art-sized for this specific art; that's not a
bug to fix, it's an inherent property of the chosen asset's shape.

Exposed `grid_size` on both `GridOutline` and `HexSelection` (previously a hardcoded `TILE_SIZE`-based constant)
so the user can pick their own point on that tradeoff directly in the Inspector, per the standing practice from
`memory/feedback_expose_visual_tuning.md` — rather than another round of me guessing a "compromise" value I can't
see rendered. Both default to the same value and a test confirms they still match, so tuning one is a clear
signal to also tune the other.

## 2026-10-14 — Abandoned Kenney ground art; generate true hexagons at runtime instead

The user tried tuning `grid_size.y` upward in the Inspector (as the previous entry invited) and got overlapping
outlines again, and pushed back hard: a simple, flat, no-elevation hex map should not still be unsolved after
this much iteration. Right call — the previous entries were explaining and exposing a tradeoff, not removing it.
The actual root cause was never a coordinate bug: it was that Kenney's `tileGrass_full.png` silhouette simply
isn't a true hexagon (full width for 30 of its 57 rows, true hexagons are only full width at one point), so no
single outline size could ever be simultaneously gap-free *and* match the art. No amount of further coordinate
math fixes a geometry mismatch with a fixed third-party asset.

Fix: stopped using Kenney art for ground tiles entirely. Added `scripts/rendering/hex_tile_texture.gd`, which
rasterizes a solid-color hexagon (plus optional border) straight from `HexMath.hex_points()` — the same formula
already proven correct for all the grid math — onto a runtime `ImageTexture`. `World._add_generated_source()`
builds one `TileSetAtlasSource` per terrain color (grass/sand/water/snow) from this instead of from art files.
`TILE_SIZE` changed from the old art-compromise `(55, 40)` to the *true* hexagon proportions `(55, 64)`
(`height = 2*HEX_SIZE`, row spacing `= 1.5*HEX_SIZE`), since there's no more art footprint to compromise with.

This removes the tradeoff, not just hides it: the generated texture *is* the hex math, so `GridOutline`'s and
`HexSelection`'s existing `TILE_SIZE`-based outline now traces the real tile edges exactly at any zoom, with no
overlap and no gap, by construction — not by picking a value that happens to look okay. Updated their header
comments accordingly (previously described a now-nonexistent "pick your tradeoff" situation). Also found and
removed a leftover `grid_size = Vector2(55, 50)` override on `GridOutline` in `scenes/main.tscn` — a stale value
from earlier Inspector experimentation that no longer matched the real tile geometry; this, not a new bug, was
what produced the overlap the user just saw. Trees/rocks are untouched (separate `Features` sprites, still
Kenney art, never were part of this problem).

Replaced the two tests that measured Kenney ground-art specifics (`_test_tileset_row_spacing_is_gap_free`,
`_test_debug_overlay_outline_matches_measured_art`) with `_test_generated_hex_texture`, which checks the
generated texture is an actual hexagon (opaque center, transparent corner) at the right size, and that
`GridOutline`'s default `grid_size` matches the new `World.TILE_SIZE`. Full suite: 36/36 assertions pass.

## 2026-10-14 — Richer procedural fills (vignette shading + per-cell tint variants)

User confirmed the alignment fix works but found flat-color hexes "very simplistic," and asked about sourcing a
real 55x64 tileset. Recommended staying procedural rather than sourcing new art: any sourced hex art would need
its actual silhouette re-verified against the hex math before trusting it (the exact problem just solved), while
richer *fills* on the already-correct generated shape carry none of that risk. User chose to try richer
procedural fills first.

Two additions, both on the existing generated-hex pipeline, nothing art-related:

1. `HexTileTexture.generate()` gained a `shading_strength` parameter: a soft radial vignette (full `fill_color`
   at the hex centre, darkening smoothly toward the border) computed from the same `p.length() / hex_size` used
   everywhere else in this file. Default `0.0` reproduces the old flat fill exactly, so this is additive, not a
   behavior change for any other caller.
2. `World._add_generated_source()` now also creates `TINT_VARIANT_COUNT` (4) alternative tiles per terrain, same
   texture, differing only by a `modulate` brightness jitter (`tile_tint_jitter`). `_build_terrain()` picks a
   variant per cell via the existing deterministic `_pseudo_random01` hash (new salt, `29.0`) so the same map
   always looks the same, but neighboring same-terrain cells don't read as one stamp repeated — without needing
   multiple textures or any per-pixel noise baked into a single shared (and therefore visibly tileable) texture.

Both `tile_shading_strength` and `tile_tint_jitter` are `@export_range` on `World`, per the standing practice
from `memory/feedback_expose_visual_tuning.md` — exact look is the user's call in the Inspector, not another
round of me guessing values I can't see rendered.

Added `_test_generated_hex_shading_and_tint_variants`: confirms `shading_strength=0` is still flat, that shading
actually darkens a point away from center more than the center itself, that each terrain source gets exactly
`TINT_VARIANT_COUNT` alternative tiles, and that their modulates actually differ. One iteration needed: the first
version asserted the shaded centre pixel was exactly full brightness, which failed because `TEXTURE_CANVAS_SIZE`
is even in both axes (56x64) so no pixel center lands exactly on the geometric center — off by (0.5, 0.5),
enough for the vignette to shave a fraction of a percent off even the "center" pixel. Fixed by asserting
near-full brightness and a relative comparison instead of an exact value. Full suite: 40/40 assertions pass.

## 2026-10-15 — Pre-phase health check; terrain decals; formalized the depth/overlap rule

User confirmed the alignment fix works but called the result "very simplistic" and asked for ideas on making the
world beautiful/magical before committing to a direction, plus wanted a phase-boundary check for loose ends, and
explicitly asked for a rule letting large features (mountains/trees) overlap the tiles behind them for a sense of
depth. Agreed to start with terrain decals.

**Pre-phase check.** Full suite green (40/40), project loads headless clean. Found two things not worth silently
carrying into a new phase: (1) a dozen `current_terrain*.png`/`hex_example.png` files sitting untracked in the
project root — leftover debug dumps from the earlier alignment investigation, referenced by nothing but their
own `.import` files; flagged to the user for cleanup rather than deleted unasked. (2) Discovered the asset
library already has unused, relevant art: a full `critters` set (badger/boar/stag/wolf, directional, with
idle/walk/burrow/tunnel animations) and a `roadTiles` vector set — `simupak64-124-3` is Simutrans's own `.pak`
format and not directly usable in Godot. Noted for the later phases (wildlife, infrastructure) rather than acted
on now.

**Depth/overlap rule.** The mechanism the user asked for already existed, just undocumented and only half
enforced: `Sprite2D` features are never region-clipped to their hex, and `Features.y_sort_enabled` sorts by each
root's ground-contact Y (which increases monotonically with row), so a feature further south always draws in
front of one further north — exactly "a tall thing can lean into the tile behind it and still occlude correctly."
Formalized this as an explicit, non-negotiable rule in `world.gd`'s `_build_features` doc comment (same tier as
the "features never move ground tiles" rule), and closed the one gap found while writing the covering test:
`y_sort_enabled` was being set only in `scenes/main.tscn`, not enforced in code, so nothing would have caught it
if a future scene edit silently dropped it. Moved the assignment into `_build_features()` itself. New test,
`_test_feature_overlap_depth_rule`, checks all three legs: `y_sort_enabled` is true, a southward cell's
ground-contact Y is strictly greater (so y-sort really does draw it in front), and feature sprites have
`region_enabled == false` and no per-sprite `z_index` (the spec's explicit "don't do this, it breaks y-sort" warning).

**Terrain decals.** Added small ground-clutter sprites (flowers, bushes, small rocks/pebbles) on cells that
didn't already get a major feature (tree/rock) this pass, so a cell never carries both. Sourced from Kenney's
hexagon-tiles pack, same art family as the existing trees/rocks for visual consistency — but these are genuinely
small standalone sprites (12x11 to 29x33px, measured directly via a headless `Image.load()` probe before
committing to anchors), not the oversized tile-shaped art that caused the ground-tile silhouette problem, so a
plain bottom-center anchor (`Vector2(width/2, height)`, same formula as trees) is trustworthy here with none of
the earlier measuring care. `DECAL_SETS` keys by the cell's actual rendered terrain id (grass/sand/snow; none for
water yet) rather than by elevation band, so a decal always matches the ground tile under it even if the terrain
logic changes later. Picked deterministically per cell (existing `_pseudo_random01` hash, new salts) with two new
`@export` knobs on `World` — `decal_density` and `decal_visual_nudge` — per the standing practice from
`memory/feedback_expose_visual_tuning.md`.

New test `_test_world_decals` (plus a shared helper, `_axial_for_feature_root`, that reverses a Features-local
position back to its axial cell via the same `TileMapLayer` round trip `cell_under_mouse` uses — never hand-rolled
math) confirms: decals actually get placed, every decal's texture belongs to its cell's terrain's `DECAL_SETS`
entry, and no cell ends up with both a decal and a major feature. Needed `DECAL_SETS` to be `static var` rather
than `const` so the test could reach it as `World.DECAL_SETS` (a `const` initialized from other consts works for
simple values, but GDScript can't class-reach a plain instance `var`). Full suite: 47/47 assertions pass.

## 2026-10-15 — Decal anchor fix, real clustering/scatter, and the Node.name uniqueness trap

User reported two concrete problems with the first decal pass: every decal sits visibly "just above" the tile
center rather than on it (fine for the tree, wrong for round blobs), and the result looks too even — they want
genuine per-cell variety (0/1/2/3 decals, scattered, not one stamped dead-center every time), explicitly framing
this toward an eventual slider-driven random map generator built on top of these same Inspector knobs (confirming
the exposed-tuning approach is the right one, not just a one-off convenience).

**Anchor bug, fixed.** Decals were using the tree's bottom-center anchor formula (`Vector2(w/2, h)`), but a tree
is a trunk growing from one ground point while a flower/bush/pebble is a round blob *sitting on* the ground —
exactly the distinction `ROCK_CENTER_ANCHOR` already existed to handle for mountains. Switched decals to a
geometric-center anchor (`Vector2(w/2, h/2)`), which is what actually centers a squat sprite on the tile instead
of floating it above center. Not a tuning matter (no slider for this) — it was simply the wrong formula.

**Real clustering + scatter.** Replaced "roll once per cell, place at dead center" with up to `decal_cluster_max`
(new export, default 3) independent per-slot rolls against `decal_density`, each slot independently placed at a
random angle and `sqrt(random)`-weighted distance (uniform-over-disk, not uniform-over-radius, so decals don't
bunch near the center) up to `decal_scatter_radius` (new export, default 14px — well inside `HEX_SIZE`'s ~31.75px
so decals stay visually on their own tile) from the cell's exact center. One slider (`decal_density`) now
produces a natural spread of bare/one/several-decal cells by itself, which is what was actually asked for, rather
than needing an explicit count distribution. `_add_feature` gained a `scatter` parameter for this and now stores
the owning axial as node metadata (`set_meta("axial", ...)`) so nothing downstream has to reverse-map a
(now off-center) pixel position back to a cell.

**Real bug caught by the new clustering test, before it shipped.** `_build_features`/`_maybe_add_decal` tagged
nodes by setting `root.name = "Feature"` / `"Decal"` for later identification. Godot enforces unique sibling
names and silently *appends a number* to any colliding name — so only the very first tree/rock ever placed kept
the exact name `"Feature"` and only the very first decal kept `"Decal"`; every later sibling silently became
`"Feature2"`, `"Decal3"`, etc. `_test_decal_clustering_and_scatter` (written to confirm clustering actually
produces >1 decal on some cell) initially reported almost no decals/features findable at all, which is what
caught this — exact-string identity checks on `Node.name` are not a safe way to tag sibling nodes. Fixed by
tagging with `set_meta("kind", "feature" | "decal")` instead (metadata has no uniqueness constraint), keeping the
display name for editor readability only. Updated `_test_world_decals` to match.

Also had to stop `_test_decal_clustering_and_scatter` from reusing the shared `_make_world()` helper: that helper
already calls `_build_features()` once with default settings, and `Node.queue_free()` is deferred — it never
actually flushes in this script's single-pass, non-looping `_init()` (same lifecycle fact `_make_world`'s own
comment already documents for `_ready()`) — so a second `_build_features()` call with overridden density would
have left the first pass's still-attached, "freed-but-not-really" children mixed into the count. Built a fresh
`World` inline instead, setting `decal_density`/`decal_cluster_max` before the one and only `_build_features()`
call. Full suite: 49/49 assertions pass.

## 2026-10-15 — Switched to flat-top hexagons

User asked to rotate the hex grid from pointy-top to flat-top (flat edges top/bottom, pointy corners left/right):
it reads more "map-like" and matches most off-the-shelf hex terrain art, which was the explicit reason given.
This is a real coordinate-system change, not a sprite rotation -- touched every layer that encodes hex
orientation:

- **`hex_math.gd`**: `hex_points()` corners rotate from `60*i - 30` to `60*i`. `axial_to_pixel`/`pixel_to_axial`
  swap which axial component scales which pixel axis (flat-top: `x = 1.5*size*q`, `y = size*(sqrt(3)/2*q +
  sqrt(3)*r)` -- x now depends on q alone, y depends on both q and r, the opposite of pointy-top where y
  depended on r alone). `NEIGHBOR_OFFSETS` and `cells_in_radius` are untouched -- axial adjacency is the same six
  (q,r) deltas regardless of pixel orientation, only the pixel mapping changes.

- **`godot_hex_offset.gd`**: pointy-top used `TILE_OFFSET_AXIS_HORIZONTAL` + the empirically-confirmed "odd-r"
  offset scheme (odd rows shoved right). Flat-top needs `TILE_OFFSET_AXIS_VERTICAL`, which this session confirmed
  empirically (not just assumed from symmetry) is the mirrored "odd-q" scheme: odd *columns* shoved down by half
  a tile. Implemented by swapping the roles of q/r and row/col in the old odd-r formula, then verified directly
  against a real `TileMapLayer.map_to_local()` with the new axis/layout across a wide (q,r) range
  (`_test_tileset_matches_axial_spacing`) -- it matched on the first attempt, but the point was verifying it, not
  assuming the mirror-symmetry guess was right.

- **`world.gd`**: `tile_offset_axis` -> `TILE_OFFSET_AXIS_VERTICAL`. `TILE_SIZE`/`TEXTURE_CANVAS_SIZE` transposed
  (64x55 / 64x56 instead of 55x64 / 56x64) -- same `HEX_SIZE` (same physical hex, just rotated 90°), so the
  circumradius and column/row spacing magnitude are unchanged, only which screen axis they apply to.
  `hex_tile_texture.gd`'s rasterizer needed no changes at all -- it was already fully parametrized by
  `HexMath.hex_points()` and a caller-supplied canvas size, so it draws whatever orientation `hex_points()`
  currently produces with no awareness of which orientation that is. Same for `GridModel`/terrain/decal logic:
  all pure axial-space math, untouched.

- **`grid_outline.gd`/`hex_selection.gd`**: `_outline_points()` scales a unit hex (from `HexMath.hex_points(1.0)`)
  up to `grid_size`. The unit hex's own width/height swapped (flat-top unit hex is 2 wide x sqrt(3) tall, versus
  pointy-top's sqrt(3) wide x 2 tall), so `scale_x`/`scale_y`'s divisors swapped to match (`grid_size.x/2.0`,
  `grid_size.y/sqrt(3.0)`).

**Deleted `hex_grid_view.gd` and its orphaned `scenes/grid.tscn`** (plus the four tests exercising it:
`_test_river_path`, `_test_decoration_hash`, `_test_edge_neighbor_offsets`, `_test_screen_space_round_trip`), with
the user's explicit go-ahead. This was a fully superseded pre-`TileMapLayer` renderer (direct Kenney-art ground
tiles, no `map_to_local()`) -- `project.godot`'s `run/main_scene` already pointed at `main.tscn`, never
`grid.tscn`, so nothing in the running game used it. Its own placement math (`_axial_to_screen`/
`_screen_to_axial`) depended on a pointy-top-specific shortcut -- it derived screen Y from `axial.y` alone via a
hardcoded art-tuned `ROW_SPACING_PX`, which only works because pointy-top's true Y formula also happens to depend
on r alone. Flat-top's Y genuinely depends on both q and r, so that shortcut had no valid flat-top equivalent
without a real rewrite of dead code -- better to remove it than maintain a parallel, unused coordinate scheme.

**Verification**: full suite green at 45/45 assertions (49 minus the 4 deleted), clean headless project load.
`_test_tileset_matches_axial_spacing` is the load-bearing test here, exactly as it was for the original odd-r
discovery -- it compares real `TileMapLayer.map_to_local()` output against `HexMath`'s formulas across a wide
(q,r) range, not just a handful of cells where a wrong offset scheme might coincide with the right one by
accident.

**Not touched**: the user's own Inspector-tuned values on `Main` (`tree_visual_nudge`, `decal_density`,
`tile_tint_jitter`, etc.) are pixel offsets/thresholds tuned against the old pointy-top layout and will likely
want re-tuning by eye now that the grid orientation changed -- per
`memory/feedback_expose_visual_tuning.md`, that is deliberately left for the user to redo in the Inspector, not
re-guessed in code.

## 2026-10-19 — Real hand-cut ground art, replacing the procedural tiles where it exists

User didn't like the procedurally-generated flat-fill look and wants to move to real painted art (reference:
a flat-top isometric-style hex terrain pack). Re-using a pre-rendered pack wholesale was rejected -- same
silhouette-mismatch risk as the original Kenney pack problem, worse here since mountains/trees in that reference
tower past their own hex footprint. Agreed split instead: **ground tiles** stay flat/bare (near-true-hex
silhouette, tile cleanly), **features** (trees/rocks/mountains) are separate sprites on the existing
y-sorted Features layer, which already handles overlap/depth correctly.

**The cutting-mask problem.** User's first batch (`art/pretty_tiles/`, cut by eye with a Photoshop CS2 mask from
their own large source sheet) came in at 110x93px -- ratio 1.1828 vs a true flat-top hex's 2/sqrt(3) ~= 1.1547,
about 2.4% off, with almost no transparent margin to absorb it. Rather than accept that drift, generated
`art/hex_cutting_mask_1000x866.png`: a hard-edged, zero-margin flat-top hexagon rasterized directly from this
project's own `HexMath.hex_points()` (point-in-polygon fill, same method `hex_tile_texture.gd` already used) --
not redrawn by hand, so it can't drift from the engine's actual geometry. Instructed the user to load it via
Ctrl-click-thumbnail (exact alpha-based selection, not magic-wand tolerance), and -- the key trick -- to resize
a *copy* of this exact master with "Constrain Proportions" ON and only one dimension typed in, so Photoshop
computes the matching companion dimension instead of the user eyeballing a new ratio each time. The user
rescaled it to fit their sheet and re-cut: second batch came in at 107x93, ratio 1.1505, ~0.36% off -- a ~7x
improvement, confirming the mask approach works.

**Wiring real art into `_build_tileset`.** `TILE_SIZE` is now derived FROM the real art (107x93, the actual
`art/pretty_tiles/` canvas, no margin) rather than the art being fit to a pre-chosen engine constant --
once real art exists for a terrain, it's the source of truth, not the other way round. `HEX_SIZE` is derived
from `TILE_SIZE.y` (same "height is exact" convention already used for the flat-top switch).
`GROUND_TEXTURES: Dictionary[TERRAIN_* -> Array[Texture2D]]` (new, same shape as the existing `DECAL_SETS`
pattern) holds real art per terrain; `_add_source` dispatches to `_add_real_art_source` when a terrain has any,
else the existing generated fallback (`_add_generated_source`) at the same `TILE_SIZE` -- so terrains without
real art yet (`TERRAIN_SAND`, pending a decision on the `dirt_01`/`rocky_01` art -- see below) don't block the
others and the grid geometry stays one consistent thing regardless of which terrains have real art.

Grass has two real variants (`grass_01`, `grass_03`); `_add_real_art_source` lays variants side by side on one
combined atlas texture (one `TileSetAtlasSource` per terrain, one atlas column per variant -- `Image.blit_rect`,
not alpha-blended, since destination starts transparent and source edges carry their own alpha) and gives each
column its own `TINT_VARIANT_COUNT` modulate-jitter alternative tiles, same as the generated fallback always had.
`_build_terrain` now picks the atlas column and the modulate variant with two *independent* hash salts (61.0 for
which variant, 29.0 for which jitter, same `_pseudo_random01` mechanism as everywhere else in this file) so they
don't correlate. `_test_real_ground_art_variants` (new) confirms a multi-variant terrain's atlas tile count
matches its art array and that more than one variant actually gets used across a map, not silently always
column 0.

**`.import` gotcha.** New PNGs dropped into `art/` aren't loadable via `preload()`/`load()` in headless
`--script` mode until Godot's asset importer has produced a matching `.import` file for them -- that only
happens automatically when the editor opens the project (or scans on focus). Running
`godot --headless --import` once (a supported one-shot CI-style command) generates the missing `.import` files
without opening a GUI window; needed here since every test run in this project has been via `--headless --script`
only, never the editor.

**`dirt_01.png`/`rocky_01.png`**: no current `TERRAIN_*` slot obviously fit either (the engine's terrain enum is
GRASS/SAND/WATER/SNOW only) -- asked the user rather than guessing, since extending the enum would have
simulation implications beyond a visual swap. Decision: `dirt_01.png` -> `TERRAIN_SAND`'s real art (both read as
"low/dry ground"). `rocky_01.png` stays unused in `art/pretty_tiles/` until a real slot exists for it -- not
wired to anything. All four terrains now have real art; the generated-fallback code path
(`_add_generated_source`) stays in place for whenever a new terrain/variant doesn't have real art yet, rather
than being removed.

`art/cartoon_hex_assets/` (a ChatGPT-attempted cut, confirmed failed by the user -- every file in it, including
feature sprites, suspiciously exactly 544x476) is explicitly not used anywhere.

## 2026-10-19 — Real feature art (trees/boulders/decals), and a rocky terrain tied to boulder placement

User didn't like the bevel on the first art batch ("too fussy") and re-extracted ground tiles at 122x106
(art/pretty_tiles/tiles/, ratio 1.1509 vs true 1.1547 -- ~0.33% off, same mask approach, still excellent) plus a
third grass variant (grass_02) and real feature art (art/pretty_tiles/features/): trees, boulders (3 sizes),
flowers, bushes. Asked to replace the Kenney trees/rock/flower/bush art entirely with these, and to use the
"rocky" ground tile specifically as the surface under boulders.

**`tree_autumn.png` excluded.** Looked at it directly (Read can view static image files even though there's no
way to render the live game) -- unlike every other feature here, it has a solid WHITE background, not
transparency. Shipping it would render a white box around the tree. Left out of `TREES`, flagged to the user
rather than silently dropped or silently used broken.

**Rocky terrain tied to boulder placement, not just visual layering.** The ask was specific: boulders need to
stand ON rocky ground, not float on whatever the elevation-band terrain would otherwise be (snow). Added
`TERRAIN_ROCKY` as a real terrain id (own `GROUND_TEXTURES` entry: `rocky_01.png`, own `TileSetAtlasSource`), but
it is NOT a new independent elevation band -- `_terrain_for` now rolls the identical deterministic check
(`_pseudo_random01(axial, 0.0) < DECORATION_DENSITY`, same axial, same salt) that `_build_features` already used
to decide "does this snow-band cell get a boulder." Same roll, same cell, same answer, computed independently by
both passes rather than threading shared mutable state between them -- consistent with how every other per-cell
decision in this file already works (tint variant, which decal, scatter angle, all just the same hash with a
different salt). `_build_features`'s snow-band branch now checks `terrain == TERRAIN_ROCKY` instead of re-rolling
its own copy of the same condition, so there's exactly one place that expression lives.

**Caught myself almost introducing a band-exclusivity bug.** First draft of the merged branch read `if terrain ==
TERRAIN_ROCKY: ... elif t >= FOREST_THRESHOLD: ...` at the top level -- wrong, because a plain-snow cell (boulder
roll failed, terrain stays TERRAIN_SNOW) still has `t >= SNOW_THRESHOLD >= FOREST_THRESHOLD`, so it would have
fallen through into the tree branch and grown a tree on a snow tile. Fixed by keeping the original `if t >=
SNOW_THRESHOLD: (rocky check) elif t >= FOREST_THRESHOLD: (tree roll)` elevation-band structure intact, only
swapping the *inner* condition. Added `_test_rocky_terrain_boulder_coupling` specifically to guard this: confirms
every rocky cell's ground tile uses the rocky source, and that every major feature at/above the snow threshold is
a rock, never a tree -- a regression test for a bug that didn't ship, written because the near-miss made clear
how easy it'd be to reintroduce silently later.

**Per-texture anchors, not one shared constant.** The old Kenney `ROCK_CENTER_ANCHOR` was one hand-measured
constant because both rock variants shared one canvas size. The new boulders (large/medium/small) don't share a
canvas, so anchors are computed per-texture at placement time (`Vector2(tex.get_width()/2.0,
tex.get_height()/2.0)`), same pattern decals already used. Trees keep bottom-center (trunk-based), computed the
same way.

**Decal reassignment**: grass decals -> the four new flower/bush sprites. Sand and snow decals both reuse
`boulder_small.png` as a generic small-rock accent (no dedicated per-terrain small-rock art in this batch) --
noted to the user as a judgment call, not a guess passed off as given.

Full suite: 49/49 (added `_test_rocky_terrain_boulder_coupling`), clean headless load.

**Follow-up same day**: user confirmed `tree_autumn.png` was accidentally the old ChatGPT-failed export, not a
bad cut of the new batch -- re-exported properly (106x150, real transparency, confirmed by looking at it
directly) and added as a 4th `TREES` variant. Suite still 49/49.

## 2026-10-19 — mountain_large landmark tier, and fixing the river's monotonic-drift bug

**Mountain tier.** User added `mountain_large.png` (186x149, confirmed real transparency) and asked to wire it in
to test mountainous areas in the north. Checked `grid_model.gd` first rather than guessing: `SLOPE_M_PER_ROW`
makes elevation drop toward +r, i.e. the north edge (r close to -radius) is ALREADY the map's highest terrain --
so no new placement logic was needed to "put mountains in the north," just a new elevation tier. Added
`MOUNTAIN_THRESHOLD := 0.95` as the top slice of the existing snow band: `_terrain_for` returns `TERRAIN_ROCKY`
unconditionally there (no `DECORATION_DENSITY` roll -- elevation rarity alone already makes it a sparse landmark,
and unconditional placement is more useful for "testing" than probabilistically hiding the only few cells that
qualify), and `_build_features` places a `MOUNTAINS` feature (own array, parallel to `ROCKS`, same center-anchor
"sitting object" reasoning) instead of a boulder there. `_test_mountains_concentrate_north` (new) confirms both
that a mountain actually appears and that every one sits at r < 0 -- not just trusted from the slope-direction
reasoning above, verified against the actual generated map.

**River undulation: a real structural bug, not a tuning problem.** User reported the river reads as "almost
straight." The existing `_generate_river_path` picked between "straight south" (q unchanged) or "diagonal
southwest" (q-1) each step, biased by a sine wander target -- looked like a tuning issue (weak amplitude), but
tracing it through: axial hex neighbors only ever allow q to decrease or hold while r increases by 1; there is no
single hex step that is both "south" and "east" (no such neighbor offset exists in axial coordinates -- the two
r+1 neighbors are (0,1) and (-1,1), full stop). So the old path could only ever drift left or pause, never
actually swing back right, regardless of amplitude/frequency -- a structural ceiling on how undulating it could
ever look, not a value to retune. Fixed by allowing a third move: a SIDEWAYS step (q+1, r unchanged, neighbor
offset (1,0)) when the wander target wants to go right, which stays single-hex-adjacent the whole time and lets
the path genuinely meander both directions, at the cost of "exactly one cell per row" (now "at least one cell per
row" -- a row can carry an extra cell from a sideways jog). Amplitude/frequency exposed as
`river_wander_amplitude`/`river_wander_frequency` (fraction of radius / full S-curves across the map), per the
usual practice of not hand-picking a "right" visual value.

Updated `_test_world_river_path`: replaced the "exactly one cell per row" assertion (no longer true by design)
with "every row is visited at least once," and added a check that the path's q sequence contains both an
increase and a decrease somewhere -- a direct regression guard for the exact monotonic-drift bug just fixed, not
just the symptom (straightness) but the mechanism (one-directional movement).

Full suite: 53/53, clean headless load. **Not done yet, explicitly deferred**: user asked to "think about" making
river tiles read as sitting lower than their neighbors (dark edges of the bordering land tile visible along the
top of each water tile) -- a design proposal was given in chat (reviving the old deleted hex_grid_view.gd's
per-edge "bank line" concept, now built properly against GodotHexOffset/TileMapLayer, drawing a darker/thicker
GridOutline edge specifically between land and water cells as the cheapest first version) but NOT implemented
this session, pending the user's go-ahead on approach.

## 2026-10-19 — Shore edges: camera-aware, not "every water/land boundary"

User approved the thick-edge approach but corrected an assumption in the proposal before any code was written:
the game's implied camera looks south-to-north (viewer south of the map, looking up/north across it), so a drop
from land down to water only shows a visible cliff face on the side that faces the camera. Explicitly: "There is
no point putting thicker edges along all river tile edges as this would not add the effect of sunken tiles."

**The geometry.** A land-to-water drop's vertical cliff faces the direction the water is relative to the land --
if water sits south of a land tile, the cliff faces south, toward this camera, and is visible; if water sits
north of a land tile, the cliff faces north, away from the camera, and is NOT visible from here. Translated to a
water cell's own edges: only its three NORTH-facing edges (N, NE, NW -- the hex's upper half, where the
*bordering land* is to the north and the cliff therefore faces south toward the camera) can ever show a visible
shore line. Its three SOUTH-facing edges (S, SE, SW) must stay plain even when they also border land, because
that cliff faces away from the camera. This is exactly "along the top of water tiles" from the original ask --
the north-facing edges are literally drawn across the top portion of a water tile's hex.

**Implementation** (`grid_outline.gd`): switched `_draw()` from one `draw_polyline` per cell (uniform style) to
one `draw_line` per edge (6 per cell), so each edge can independently choose plain vs. shore styling. The
direction/edge-index mapping was hand-derived (edge i = hex_points()[i] to hex_points()[i+1]; for this flat-top
hex, edges 0-5 are SE/S/SW/NW/N/NE in order) then verified geometrically in a test, not just trusted -- the exact
kind of hand-derived mapping that has produced real bugs earlier in this project (EDGE_NEIGHBOR_OFFSETS, now
deleted along with the rest of hex_grid_view.gd, but the lesson -- verify, don't just assert -- still applies).
The actual decision (`_is_shore_edge`) is a pure query method, not buried inside the draw loop, specifically so
tests can call it directly rather than needing to inspect rendered output (which this project has no way to do).
An off-map neighbor (`get_cell_source_id == -1`) deliberately does NOT count as "land bordering this edge" -- the
map's own outer boundary isn't a cliff, just where the world stops.

**A real bug caught immediately by the test suite, not eyeballing**: `_SHORE_EDGE_INDICES`/
`_SHORE_EDGE_NEIGHBOR_OFFSETS` were first declared as untyped array consts (`const X := [3, 4, 5]`), which made
`_SHORE_EDGE_NEIGHBOR_OFFSETS[shore_idx]` a `Variant` to the type checker, and `var neighbor_axial :=
axial + <Variant>` failed to infer a type -- a parse error, loud and immediate (same class of bug as earlier
`static var DECAL_SETS`/explicit-Array-typing issues this project has hit before). Fixed by declaring both consts
with explicit `Array[int]`/`Array[Vector2i]` types.

Full suite: 57/57 (4 new tests: the geometric edge-direction check, and three `_is_shore_edge` scenarios -- shore
when land is north, no shore when land is south, no shore water-to-water, no shore at the map's own edge), clean
headless load.

Follow-up same day: shore_line_width 3.0->5.0, shore_line_color 2e2a26 (near-black) -> 3a3a3a (dark grey, user
said the near-black read too harsh), and split shore width by edge direction -- the straight-north shore edge
(most face-on to this camera) now uses `shore_line_width`, the two diagonal NW/NE shore edges (foreshortened from
this angle) use a new, thinner `shore_line_width_diagonal` -- user's own idea, confirmed it strengthens the
sunken-tile illusion. `_shore_edge_width` extracted as its own pure method (same reasoning as `_is_shore_edge`:
directly testable without inspecting rendered output); 2 new tests. Suite: 59/59.

## 2026-10-19 — Camera pan, zoom range exposed, selection outline red

Three quick asks. (1) `hex_selection.gd`'s `selected_color` default 4a90d9 (blue) -> e03c3c (red). (2)
`camera_zoom.gd`'s `min_zoom`/`max_zoom` were already `@export`, just not `@export_range` -- switched to
`@export_range(0.01, 10.0)` for a proper Inspector slider; relevant now that ground tiles jumped from 64x55
(procedural) to 122x106 (real art), which changes what zoom range actually reads as "readable." (3) Added
panning: arrow keys (Godot's built-in `ui_left/right/up/down` actions, already bound by default, nothing to add
to project.godot) and middle-mouse-button drag -- deliberately NOT left-drag, since left-click is already
`hex_selection.gd`'s select action and overloading it would make selection and panning fight each other. Drag
direction follows the convention Godot's own 2D editor uses (content follows the cursor, so the camera's own
center point moves opposite the drag) for familiarity. Arrow-key pan speed is divided by the current zoom level
so it reads as a constant SCREEN speed rather than a constant world speed -- otherwise panning would be
unusably slow zoomed out and uncontrollable zoomed in. No new tests (camera_zoom.gd is pure mouse/keyboard
interaction, same category as hex_selection.gd's input handling, which this project has never unit-tested either
-- there's nothing to assert against without an actual rendered frame). Suite still 59/59 (unchanged), clean
headless load.

## 2026-10-19 — Major features (tree/rock/mountain) now scatter too, not just decals

User asked for trees/decals to sit at random positions within their cell "so it looks a bit more natural" --
decals already did this (decal_scatter_radius); the one major feature a cell gets (tree, boulder, or mountain)
was always placed dead-center, which reads as an artificial grid once there are enough of them.

Extracted the scatter math decals already used (`angle = hash*TAU`, `dist_t = hash`, `offset =
from_angle(angle) * (radius * sqrt(dist_t))` -- sqrt-weighted so points don't bunch near the center) into a
shared `_scatter_offset(axial, salt_base, radius_px)` helper, used by both `_maybe_add_decal` (refactored, same
behavior, no change in what it produces) and the three major-feature placements (tree/rock/mountain, each its own
salt so they don't scatter in lockstep). New `feature_scatter_radius` export (default 15px, smaller than decals'
14-40px range default since these sprites are much bigger -- a little scatter reads as natural, a lot reads as
"this tree fell off its tile").

`minimal_test_mode`'s isolated Test B placements deliberately do NOT scatter (still call `_add_feature` with no
scatter argument) -- that mode exists specifically to compare an anchor against the cell's exact center via the
debug overlay crosshair, which scatter would defeat the point of.

New test `_test_major_feature_scatter` confirms at least one major feature actually sits away from its cell's
exact center in the full procedural build. Suite: 60/60, clean headless load.

## 2026-10-20 — Phase 1 steps 1–2: cell data table (geology/K/porosity/head) + Darcy face fluxes + cell inspector

First actual simulation-logic work, per the brief's §8 Phase 1 list (steps 3–4: "Create data-backed cells with
`K`, effective porosity, elevation and hydraulic head" and "Prescribe a simple head gradient and compute face
fluxes using Darcy's law") and the user's explicit sequencing decision to do mechanics before ambient-life polish.

**GridModel (`scripts/simulation/grid_model.gd`)** now tracks, per cell, in addition to `top_elevation_m`:

- `geology_id` — one of three units (`Geology.SAND`/`SILT`/`CLAY`), assigned by a smooth function of `(q, r)`
  (two cosine terms, same style as the elevation ripple) thresholded into bands, not independent per-cell noise —
  real geological contacts are sharp-edged contiguous blobs, not salt-and-pepper, and a smooth underlying field is
  what produces that without extra blob-growing logic. Clay is deliberately the rarest band: easy to miss while
  characterizing, matches the fog-of-war tension the brief's §9 wants once characterization-as-a-cost exists.
- `k_m_s`, `porosity` — looked up from the geology unit's table entry (sand 3e-4 m/s / 0.30, silt 2e-5 / 0.25, clay
  5e-8 / 0.12). Placeholder literature-typical values, not a real site's numbers — swap the table, not the
  mechanism, once Phase 2 scenario data exists.
- `head_m` — a **purely linear** gradient in `r` only (`BASE_HEAD_M - HEAD_GRADIENT_M_PER_ROW * r`), no noise. The
  brief is explicit this MVP step is an *imposed* gradient, not a solved balance (that's Phase 2's "solve a
  conservative steady-state groundwater-flow balance with fixed-head/no-flow boundaries, recharge and well
  sinks/sources") — adding ripple here would blur the distinction and make the flux formula harder to sanity-check
  by hand.

New `CELL_SPACING_M` constant (100.0, a placeholder): the hex grid has no real-world scale defined anywhere yet
(map extent/DEM is a later, separate task), so this is the one place that assumption lives, documented so it's
easy to find and replace rather than buried inside a formula.

**Face flux**: `face_flux_m_s(a, b)` implements `q = -K∇h` using the **harmonic mean** of the two cells' K (correct
averaging for two conductivities in series along the path between cell centers — a single clay cell should
dominate the face conductance the way it would physically, not get diluted by averaging with a sandy neighbor),
divided by `CELL_SPACING_M`. Positive return means flow from `a` to `b`. `pore_velocity_m_s(a, b)` is `v = q / n_e`
using the two cells' average porosity. `neighbor_fluxes_m_s(axial)` returns all six (or fewer, at the map edge)
neighbor fluxes keyed by neighbor axial — convenience for the inspector now, and for the transport step next
without re-deriving `HexMath.neighbors()` + `face_flux_m_s()` itself.

**Cell inspector** (user's explicit ask: "a way to interrogate the cell data... info box on hover/on click"):
`World.cell_info(axial)` is the one place that assembles a cell's full state (terrain, elevation, geology, K,
porosity, head) from `_terrain_for` + `GridModel`, so any UI reads one dictionary instead of reaching into model
internals and risking drift. The actual display lives in `hex_selection.gd` (not a new node) since that script
already tracks exactly the "hovered"/"selected" states the panel needs and already owns the hit-testing — a
`CanvasLayer`/`PanelContainer` pinned to the bottom-left screen corner (not a cursor-following tooltip: simpler,
never clips off a screen edge, reads as a persistent HUD readout). Shows the hovered cell; falls back to the
selected cell once the mouse leaves the map, so clicking and moving away still leaves something to read.

K spans five orders of magnitude between geology units, and GDScript's `%` string formatting has no `%e`
specifier (`String.num_scientific()` was tried first — rejected, since it only switches to exponential notation
below a fixed magnitude threshold: `3e-4` prints as `"0.0003"`, inconsistent with `5e-8` printing as `"5e-08"`).
Wrote a small manual `_format_scientific()` instead so every K value prints in one consistent, comparable format
regardless of which geology unit it belongs to.

New tests: `_test_grid_model_cell_data_fields` (determinism, table consistency, actual heterogeneity — a radius-8
map that was secretly all-sand would defeat the point), `_test_grid_model_head_gradient` (depends only on `r`,
strictly decreasing toward `+r`), `_test_grid_model_face_flux` (antisymmetry, correct flow direction, exact
harmonic-mean formula, pore velocity, `neighbor_fluxes_m_s` consistency), `_test_world_cell_info` (the dict matches
`GridModel`/`_terrain_for` exactly), `_test_hex_selection_format_cell_info` (pure string-formatting check, split
from the actual panel display for the same reason `_is_shore_edge` was split from `draw_line` — the live
hover/click panel itself needs a real Viewport to drive and isn't practical to test headlessly). Suite: 87/87,
clean headless load.

## 2026-10-20 — Flow-vector overlay (simple, always-revealed) + x-ray view parked

User asked whether the flow field could be visualized, then described a bigger idea: a separate subsurface
"x-ray" view (geology/head/flow/plume), distinct from the surface art, revealed progressively by characterization
and scaled by difficulty. Agreed with the recommendation to split this in two: build the cheap always-revealed
flow arrows now, park the fog-of-war x-ray view until the turn loop + characterize action exist to gate it on
(nothing to reveal-by-measurement yet, since nothing is unmeasured yet) -- written up in `docs/BACKLOG.md`.

New `scripts/rendering/flow_overlay.gd` (`FlowOverlay` node in `scenes/main.tscn`, between DebugOverlay and
HexSelection in draw order): one resultant arrow per cell, reconstructed by summing each of the cell's 6
neighbor-face Darcy fluxes (`GridModel.face_flux_m_s`) times the unit direction toward that neighbor
(`HexMath.axial_to_pixel`, normalized) -- a simple, not RT0-accurate, face-flux-to-vector reconstruction, but
enough to read direction/relative magnitude at a glance, which is this overlay's whole job. `_flow_vector(axial)`
is pure math, split from the actual `_draw_arrow`/`draw_line` call for the same headless-testability reason
`GridOutline._is_shore_edge` was split from its draw call.

Flux magnitudes are tiny (~1e-5 to 1e-4 m/s for these placeholder K/head values), so arrow length needs a large
px-per-(m/s) multiplier to be visible at all -- exposed as `arrow_scale` (Inspector-tunable, per
`memory/feedback_expose_visual_tuning.md`, default 4.0e6), with `arrow_max_length` capping it so a cell with an
unusually large resultant (e.g. right at a clay-lens boundary) can't draw an arrow spanning half the map.

`World` owns `show_flow_overlay` (Inspector default, mirrors `show_debug_overlay`'s pattern); the overlay also
toggles its own visibility at runtime on the F key, independent of that default, since the flow arrows and the
surface art visually compete and a quick on/off is useful while both are being tuned.

New test `_test_flow_overlay_vector` recomputes the expected resultant vector from scratch (same formula, written
independently in the test) and compares against `_flow_vector`'s actual output -- guards against a sign flip or
wrong-direction bug in the reconstruction, the same risk class as the river/shore-edge bugs earlier this project.
Suite: 88/88, clean headless load.

## 2026-10-20 — Transport step: seeded contaminant mass + conservative advection (brief §8 Phase 1 step 5)

`GridModel` gains a single-species `mass_kg` field per cell and the machinery to move it: `seed_mass_kg(axial,
mass)` (additive, not a set, so a later leaking-source feature can call it repeatedly), `get_concentration_kg_m3`
(mass / pore volume), and `step_transport(dt_s)` — conservative, one-layer, advection-only, explicitly NOT yet
dispersion/sorption/reactions (that's Phase 2, brief §8).

**No real layer geometry exists yet**, so two more placeholder constants join `CELL_SPACING_M` (same "documented,
easy to find and replace" spirit): `CELL_THICKNESS_M` (10.0 m, one saturated layer) and `CELL_AREA_M2`
(`CELL_SPACING_M²`, treating each hex as if it were a square of that side length for volume purposes only — its
exact shape doesn't matter for a lumped mass balance, only its area does). `FACE_AREA_M2` (thickness × spacing) is
the cross-sectional area mass crosses through one face — the standard "equivalent width" simplification simple
grid flow models use when true face geometry isn't modeled.

**Scheme**: upwind finite-volume. For each face, volumetric flow `Q = face_flux_m_s * FACE_AREA_M2`; mass crossing
that face over `dt_s` is `Q * (upstream cell's concentration) * dt_s` — always the source side's concentration,
the standard way to keep an explicit advection scheme stable. Every face is visited exactly once per step, using
half of `HexMath.NEIGHBOR_OFFSETS` as a canonical direction set (`_TRANSPORT_EDGE_OFFSETS` — each of the three
offsets used is the exact opposite of one of the other three, so every edge of the grid is covered without
double-counting; same pattern `GridOutline`'s shore-edge code already uses for the same reason). All transfers are
computed from pre-step concentrations into a `delta` dict and applied only after the full pass, so processing
order can never make one edge's update see another's already-applied change within the same step.

**Stability**: an explicit upwind scheme can drive a cell's mass negative (unphysical, a real conservation
violation) if `dt_s` is too large relative to a cell's outflow and its own current mass. Added `max_stable_dt_s()`
— the standard CFL bound (`min` over cells of `pore_volume / total_outflow_rate`) — as a query the caller (the
turn loop, next) is expected to respect; `step_transport` itself does not clamp to it (no flux limiter — out of
scope for this MVP, and the brief's own guardrail is "build one playable scenario" before adding sophistication
nothing is asking for yet).

Hit the same **untyped-collection type-inference bug** as `grid_outline.gd`'s `_SHORE_EDGE_INDICES` earlier this
project, in a new shape: `Dictionary.keys()` returns a plain (untyped) `Array`, so `for axial in
top_elevation_m.keys(): var neighbor := axial + face_offset` failed to infer `neighbor`'s type, the same
"Variant poisons everything derived from it" failure, cascading into the same misleading "Invalid call: Nonexistent
function 'new'" pattern everywhere `GridModel.new()`/`World.new()` were called elsewhere in the test file, while
unrelated earlier tests still printed PASS. Fixed with GDScript's typed-for-loop-variable syntax (`for axial:
Vector2i in top_elevation_m.keys():`), not by touching `top_elevation_m`'s own declared type. Lesson reinforced
for next time: any loop over a `Dictionary.keys()/.values()` result needs the loop variable typed explicitly if
anything inside the loop relies on `:=` inference from it.

New tests: `_test_grid_model_concentration` (seeding adds not overwrites, concentration = mass/pore-volume),
`_test_grid_model_transport_conservation` (total mass exactly preserved across 10 steps at half of
`max_stable_dt_s()`, and no cell goes negative), `_test_grid_model_transport_direction` (a seeded cell loses mass
and its downstream neighbor — the same `(0,0)->(0,1)` pair already proven to have positive flux in the earlier
face-flux test — gains some). Suite: 92/92, clean headless load.

Not yet visible on screen: this is data-model only, same deliberate split as the brief's own step 5 vs. step 6.
Next: Next Turn (Space) + turn counter + concentration overlay, which is what actually makes the plume's movement
visible — and the natural point to revisit `docs/BACKLOG.md`'s parked x-ray/fog-of-war view.

## 2026-10-20 — Turn loop + plume cloud overlay (brief §8 Phase 1 step 6)

User's explicit ask: visualize the plume "as a proper cloud that moves downstream," never binary per-cell
contamination, with a readable % contamination at any time, and movement "as close to actual behaviour as
possible" for the educational goal.

**The data was already continuous** (previous entry: `step_transport` moves a flux-proportional fraction of a
cell's mass per step, never all-or-nothing) — the remaining work was turn pacing and making the *rendering*
honor that continuity instead of flattening it back into discrete hex-colored blocks.

**Turn loop** (`World._advance_turn()`, bound to Space via a raw keycode check, not an InputMap action — no
existing default action fit and one more project-settings edit wasn't needed): advances `turn_duration_s`
(export, default ~30 days) of simulated time per press, **substepping** so no individual `step_transport` call
ever exceeds `GridModel.max_stable_dt_s()` — brief §4's explicit instruction ("Time step must obey stability/
nonnegative-mass constraints; substep within a player turn if required"). `turn_duration_s` is deliberately NOT
derived from the CFL bound: with today's placeholder K/head values that bound is tens of days, so using it
directly as the turn length would make a single turn nearly invisible. It's a pure pacing/feel dial instead —
how many Space-presses before the plume visibly advects — tunable like every other visual/feel export in this
project. A `MAX_TRANSPORT_SUBSTEPS` cap (500) guards against a pathological flow field looping forever; not
expected to ever bind.

**Scenario seeding** moved from "nothing seeds automatically" to a fixed source at `_ready()`
(`source_axial`/`source_mass_kg` exports). First default was the map center `(0,0)` — wrong: `GridModel.
_geology_at`'s two cosine terms both peak at exactly `(0,0)` by construction, so the exact center is
*deterministically* always a clay lens (confirmed by direct query, not assumed), and clay's K is ~6000x sand's —
a demo source planted there would barely move, undermining the entire point of this feature. Moved the default to
`(0, -5)` (confirmed sand on both the radius-8 test default and `scenes/main.tscn`'s radius-14), with several rows
of travel distance south to actually watch advection happen.

**The "cloud" rendering** (`scripts/rendering/plume_overlay.gd`, new `PlumeOverlay` node — sits between
DebugOverlay and FlowOverlay in `scenes/main.tscn`'s draw order, so flow arrows stay crisply visible drawn on top
of the translucent cloud): each cell with measurable concentration draws a soft circular glow (a once-generated,
cosine-falloff radial gradient texture, continuous first derivative so it reads as a soft puff rather than a hard
disc or a banded gradient) sized `glow_radius_factor` (default 1.7x) larger than one hex, so a contaminated cell's
glow overlaps and blends with similarly-contaminated neighbors' — the overlap/blend itself *is* the cloud shape;
no particle system needed. Uses brief §6's reserved saturated color for contamination, `#9FE870` ("toxic green"),
kept out of the healthy-landscape palette everywhere else in this project specifically so its appearance always
reads as "something's wrong."

Alpha is `sqrt(concentration / full_scale) * max_alpha`, not linear — the sqrt eases low concentrations toward
visibility rather than requiring near-saturation before anything shows at all. This matters for the educational
goal specifically: a real plume's leading/trailing edge (low concentration, the part a player most needs to
notice arriving or lingering) would otherwise be the exact part that stays invisible longest under a linear
mapping. `full_scale_kg_m3` (`World.contamination_full_scale_kg_m3`, default 0.03 kg/m³ ≈ 30 mg/L) is the
concentration that reads as max intensity — a placeholder visual reference, not a regulatory threshold, since no
real receptor/cleanup-standard system exists yet; it's the single source of truth for both the overlay's alpha
and the cell inspector's new "Contamination: NN%" reading (`World.cell_info`), so the two always agree. The
numeric reading is intentionally uncapped (can read e.g. 140%) even though the visual clamps at 100% — the exact
number should stay honest about supersaturation even though the glow can't visually exceed max_alpha.

New tests: `_test_plume_overlay_display_alpha` (zero->zero, exact-full-scale->max_alpha, clamping above
full_scale, monotonic increase, a 25%-of-full-scale concentration still reads visibly nonzero — directly guards
the "low concentrations shouldn't be invisible" requirement), `_test_world_turn_advance_transport` (seeding
actually happens, `_advance_turn()` increments the counter, and the substep loop itself — not just a bare
`step_transport` call — still conserves mass exactly). `_test_world_cell_info` and
`_test_hex_selection_format_cell_info` extended for the new `concentration_kg_m3`/`contamination_percent` fields.
Suite: 107/107, clean headless load (including the real scene's actual `_ready()` path, not just the bypassed
test-harness construction — this is the first feature in this project exercised that way).

## 2026-10-20 — X-ray toggle button (surface art was obscuring the plume cloud)

User tried the plume overlay and couldn't tell if it was working: the surface terrain/feature art sits on top of
(and visually competes with) the translucent cloud, exactly the problem `docs/BACKLOG.md`'s parked "x-ray view"
idea was ultimately meant to solve — but building that idea's fog-of-war/difficulty-scaling machinery wasn't
needed to fix *this*. What was actually needed is simpler: a way to get the terrain out of the way. Added that
now as its own small feature; the parked BACKLOG entry is still the right place for the fog-of-war version later.

`World.set_xray_mode(enabled)`, wired to a new "X-Ray View" toggle `Button` in the HUD panel (user asked for "on a
button click", not a hotkey, so that's the only trigger — no `F`-style keycode added for this one). When enabled:

- `Ground` and `Features` are hidden outright (not dimmed) — those two are exactly what was obscuring the cloud,
  and a translucent glow drawn over anything still competes with it visually. `GridOutline` is deliberately left
  alone: it reads its grid lines from `Ground`'s cell data directly, independent of `Ground.visible`, and thin
  grey lines don't meaningfully compete with the cloud — so there's still a spatial reference grid underneath.
- A full-screen backdrop in brief SS6's reserved "dark aquifer blue" (`#0D1B2A`) shows through once Ground is
  hidden. Implemented as a `ColorRect` inside its own `CanvasLayer` at `layer = -1` — screen-space, always drawn
  behind the default layer-0 world content regardless of camera pan/zoom, unlike a `Node2D`/world-space rect that
  would need to track the camera's exact visible bounds to always fully cover the screen. Explicitly set
  `mouse_filter = IGNORE`: a full-screen `Control` defaults to `STOP`, which would otherwise silently swallow
  every mouse click/hover across the entire viewport once visible, breaking `hex_selection`'s hover/click and
  `camera_zoom`'s drag-pan the moment x-ray mode turned on.
- `FlowOverlay`/`PlumeOverlay` are forced visible, remembering whatever they were set to beforehand (Inspector
  default, or a previous `F`-key toggle on `FlowOverlay`) and restoring that exact state on exit — x-ray mode's
  whole point is showing the subsurface data, so entering it shouldn't stay dark just because the player had
  toggled flow arrows off earlier, but leaving it also shouldn't silently overwrite that earlier preference.

New test `_test_world_xray_mode`: hides Ground/Features, forces Flow/Plume visible regardless of a simulated
prior off-state, and confirms leaving x-ray mode restores Ground/Features AND the exact prior Flow/Plume state
rather than leaving them forced on. Suite: 111/111, clean headless load.

## 2026-10-20 — Two bugs from testing the x-ray toggle: Space un-toggled it, and the cloud looked blocky

**Bug 1 — pressing Space for the next turn silently turned x-ray mode back off.** Root cause: a clicked `Button`
keeps keyboard focus afterward, and Godot's default `ui_accept` input action is bound to both Enter AND Space.
A focused `Button` responds to `ui_accept` by re-pressing (and, since it's `toggle_mode`, re-toggling) itself --
so every "next turn" Space-press was *also* an invisible second click on the still-focused X-Ray View button,
undoing it immediately. Fixed with `xray_button.focus_mode = Control.FOCUS_NONE`: the button then only ever
responds to an actual mouse click, which is what "on a button click" (the user's own phrasing in the original
request) asked for in the first place. General lesson for any future on-screen button in this project sharing
screen-space with a hotkey: set `FOCUS_NONE` unless the button is specifically meant to be keyboard-operable.

**Bug 2 — the plume cloud looked "very blocky."** Two separate causes, both fixed in `plume_overlay.gd`:

1. `project.godot` sets `textures/canvas_textures/default_texture_filter = 0` (NEAREST) project-wide -- correct
   and deliberate for the crisp pixel-art ground/feature tiles, but it meant the glow texture's smooth cosine
   falloff was being point-sampled when magnified onto a ~200px cell, producing a hard-edged, stepped look
   instead of a soft gradient. Fixed with `texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR` set once in
   `PlumeOverlay._ready()` -- a per-node override (every `CanvasItem` has this property specifically for this
   purpose) that doesn't touch the project-wide default or any other node's rendering.
2. Even with smooth edges, one perfectly centered, uniformly sized circle per cell still reads as "a grid of
   circles" once there are many side by side -- not what "an actual plume/cloud" looks like. Replaced the single
   glow per cell with `PUFFS_PER_CELL` (3) smaller glows, each independently scattered to its own pseudo-random
   position (`puff_scatter_radius`), size (`puff_size_jitter`, ±40% by default), and alpha (`puff_alpha_jitter`,
   only ever dimmer than the cell's base alpha, never brighter) -- all new Inspector-tunable exports, same
   established pattern as the decal/feature scatter radii elsewhere in this project. The per-puff randomization
   (`_puff_params(axial, index)`) reuses `World._pseudo_random01` (a static function, called directly off the
   `World` class reference rather than reimplementing the same hash, since this overlay only needs the hash
   itself, not a `World` instance) with its own distinct salt stream (`_PUFF_SALT_BASE`), split from the actual
   `draw_texture_rect` calls for the same headless-testability reason every other overlay's logic is split from
   its draw call in this project.

New test `_test_plume_overlay_puff_params`: every puff's offset/size/alpha jitter stays within its own
export-declared bounds, a cell's several puffs don't all land on the same offset (which would just be one circle
again -- the exact bug this fix exists to avoid reintroducing), and params are deterministic for a given
axial+index. Suite: 114/114, clean headless load.

## 2026-10-20 — Hold-to-repeat turns, and an open downstream boundary so contamination can escape

Two user asks: holding Space should keep advancing turns rather than needing a fresh press each time, and
contamination should be able to "escape at the bottom of the screen (most downstream cells)" instead of piling
up against the map edge forever.

**Hold-to-repeat** (`World`): the initial Space press still fires once via `_unhandled_input`'s keydown event
(correct for a single tap). A new `_process(delta)` additionally checks `Input.is_key_pressed(KEY_SPACE)` every
frame and, once held past `turn_hold_repeat_delay_s` (0.4s default), fires another turn every
`turn_hold_repeat_interval_s` (0.1s default) -- ordinary press-and-hold UX (a delay, then a faster steady rate),
not the OS's own key-repeat rate, which arrives at a fixed interval the game can't tune. The actual timing math
lives in `_advance_hold_timer(held, delta) -> bool`, deliberately split from `_process` itself: `Input.
is_key_pressed` reads real OS input state that a headless test script has no way to drive, so the pure timing
logic takes `held` as a parameter instead of reading the global `Input` singleton directly -- the same
"separate the engine-dependent trigger from the testable logic" split as `_is_shore_edge`, `_display_alpha`, and
every other overlay's pure-math core in this project.

**Open downstream boundary** (`GridModel`): previously, a neighbor direction that fell outside the modeled
hexagonal domain was just skipped entirely in `step_transport`/`max_stable_dt_s` -- equivalent to an implicit
no-flow (closed) boundary at every edge of the map, which is why contamination reaching the southern rim had
nowhere to go and would pool there indefinitely. Added `_SOUTH_OUTFLOW_OFFSETS` (`(0,1)` and `(-1,1)` -- south
and southwest, i.e. "further downstream," the outflow-side counterpart of the same south-facing-camera
convention `grid_outline.gd`'s shore-edge code already uses for the cliff side, just pointed the opposite way):
any cell whose neighbor in one of these two specific directions falls outside the domain now drains mass through
that face entirely out of the system, via `_south_boundary_outflow_m3_s(axial)` -- the cell's own K against a
notional "one more row south" head obtained by continuing the SAME imposed linear gradient the whole domain
already uses (the gradient doesn't mysteriously stop at the map edge; continuing it is the simplest coherent
boundary condition available before a real receptor/discharge model exists). Every OTHER edge of the map (east,
west, north) stays implicitly no-flow exactly as before -- unaffected, since this only adds new behavior for
these two specific directions.

This is a deliberate open boundary, not a conservation bug, but it does change what "conserved" means: the
existing `total_mass_kg()` (sum still in the grid) will now legitimately decrease once a plume reaches the edge.
Added `escaped_mass_kg` to track what left, so the real invariant becomes `total_mass_kg() + escaped_mass_kg ==
everything ever seeded` -- the stronger, physically correct sense of mass balance a real groundwater model with a
discharge boundary actually has, not the weaker "nothing ever leaves" one a fully closed domain would. Also
folded the boundary's outflow into `max_stable_dt_s()`'s CFL sum (a cell draining fast through an open boundary
face can go negative too, same as any interior face, if dt is too large relative to it).

Hit an interesting non-bug while writing the regression test: a strict `escaped_mass_kg == 0.0` assertion for a
source seeded at the map's exact center (0,0) after 10 small transport steps FAILED -- not because mass actually
reached the boundary, but because an explicit upwind scheme has no literal propagation speed limit: any nonzero
flux at all gives a neighbor a formally nonzero (if astronomically tiny) mass, so after 10 steps even the nearest
real boundary cell (8 hex-steps away, the map's own radius) had accumulated a ~1.2e-10 kg trace out of 1000 kg
seeded -- about a tenth of a nanogram. Loosened that assertion to "stays under 1e-6 kg" (physically meaningless,
not literally zero) rather than treating it as a real bug -- the lesson being that "has this reached X" is the
wrong question to ask of a continuous numerical field at exact-equality precision; "is this still physically
negligible" is the question that actually matters.

New tests: `_test_grid_model_south_boundary_outflow` (confirms `(0, 8)` is a genuine open-boundary cell -- both
downstream neighbors verified off-map directly, not assumed; mass escapes once stepped; the domain-mass +
escaped-mass invariant holds exactly; the boundary-outflow formula matches a from-scratch recomputation; an
interior cell never contributes any boundary outflow), `_test_world_hold_to_repeat_timer` (no repeat while not
held; no repeat before the delay; the first repeat fires once the delay is crossed; subsequent repeats are
spaced exactly `turn_hold_repeat_interval_s` apart, not faster; releasing resets the timer). Suite: 128/128,
clean headless load.

## 2026-10-20 — Adjustable transport parameters (contamination getting "stuck" in clay)

User observed: contamination flowing through high-K cells moves as expected, but on entering a low-K clay cell
it gets stuck there, showing a large, slow-fading concentration on every adjacent clay tile after the plume has
moved past. They correctly guessed this is partly expected, and asked for adjustable transport parameters rather
than a fix.

It IS largely real physics, not a bug, for two compounding reasons (documented in `GridModel.step_transport`'s
doc comment, since this is exactly the kind of thing a future reader would otherwise re-discover by confusion):
`face_flux_m_s`'s harmonic-mean K is symmetric, so a clay cell's low K throttles mass draining back OUT of it
just as much as it throttled mass flowing IN -- contamination that reaches a low-permeability zone drains out
far slower than it arrived. Combined with clay's lower porosity (the same mass, a smaller pore volume, so a
higher concentration reading per brief SS4's "derive concentration from mobile-water volume"), a clay cell can
show a disproportionately large value for a long time after the main plume has moved on. This is a well-known
real remediation problem (low-K zones acting as long-term secondary sources via back-diffusion/matrix diffusion)
-- but its exact severity here rides entirely on this MVP's own placeholder K-contrast (6000x, sand:clay) and
porosity numbers, not a law of nature, which is exactly why it's worth exposing rather than hand-tuning in code.

`GridModel._init` now accepts `k_overrides`/`porosity_overrides` dictionaries (keyed by the `Geology` enum),
merged onto renamed `DEFAULT_GEOLOGY_K_M_S`/`DEFAULT_GEOLOGY_POROSITY` tables (any geology not mentioned keeps
its default) -- every existing caller passes neither and gets the exact old behavior, so this is purely
additive. `World` now owns the actual Inspector-facing knobs -- `sand_k_m_s`/`silt_k_m_s`/`clay_k_m_s`,
`sand_porosity`/`silt_porosity`/`clay_porosity` -- passed into `GridModel.new()` at `_ready()`, same "World owns
the tunable, GridModel just accepts it" pattern already used for `source_axial`/`source_mass_kg`/
`turn_duration_s`. The K exports use the `"exp"` `@export_range` hint: K spans multiple orders of magnitude
(1e-9 to 1e-2), where a linear slider would be nearly unusable (barely movable in the small end, all bunched up
at one extreme) -- `"exp"` gives a logarithmic slider instead, confirmed to still load cleanly in the editor.

New test `_test_grid_model_geology_overrides`: an overridden geology's K/porosity take effect, a geology with NO
override still falls back cleanly to its default (not 0/missing), and every actual per-cell value for that
geology across the map reflects the override, not just the lookup table in isolation. Existing
`_test_grid_model_cell_data_fields` updated for the `DEFAULT_GEOLOGY_K_M_S`/`DEFAULT_GEOLOGY_POROSITY` rename
(the only other reference to the old names in the codebase). Suite: 134/134, clean headless load.

## 2026-10-20 — Fixed: geology parameter edits had no effect once the scene was running

Follow-up to the previous entry. User tried raising `clay_k_m_s` to its slider maximum (1e-5, vs. the 5e-8
default) and `clay_porosity` to 0.3, and saw no change at all -- "similar behaviour of clay soaking up and
trapping the concentration" -- and correctly suspected "the flow vectors are not updated with the new hydraulic
parameters."

Root cause, found rather than guessed: `GridModel`'s per-cell `k_m_s`/`porosity` dictionaries were populated
exactly ONCE, inside `_init()`, at `World._ready()`. Nothing ever re-read the exports afterward. Editing
`clay_k_m_s` in the Inspector while the scene is running changes the *export variable* on the `World` node, but
since `_model` already exists and nothing was watching that variable, the already-built `GridModel` kept its
original K/porosity values forever -- so BOTH transport (the real bug: the simulation itself wasn't using the
new value, not just the arrows) and `FlowOverlay`'s one-time-drawn arrows stayed exactly as they were. The
user's own diagnosis ("flow vectors aren't updated") was the correct symptom pointing at the right root cause,
just describing it from the visual side.

Fixed in two parts:

1. **`GridModel.apply_geology_parameters(k_overrides, porosity_overrides)`** (new): re-derives `k_m_s`/
   `porosity` for every cell from that cell's EXISTING `geology_id` and the given override tables. Deliberately
   does NOT touch `top_elevation_m`/`geology_id`/`head_m`/`mass_kg`/`escaped_mass_kg` -- a "hot swap" of just the
   hydraulic parameters, not a rebuild, so a mid-game tweak re-prices the whole map's K/porosity without
   resetting the plume's current position or the turn in progress. `_init` now just calls this once after
   setting up `geology_id`, rather than duplicating the merge logic inline.
2. **Each of `World`'s six geology exports (`sand_k_m_s`/`silt_k_m_s`/`clay_k_m_s`/`sand_porosity`/
   `silt_porosity`/`clay_porosity`) now has a `set()`** that calls a new `_refresh_geology_parameters()`: pushes
   the current six export values into `_model.apply_geology_parameters(...)`, then explicitly calls
   `flow_overlay.queue_redraw()` and `plume_overlay.queue_redraw()` -- both overlays only redraw when told to,
   so without this they'd stay visually stale even after the underlying data changed. Guarded by `if _model !=
   null` (the setters also fire during the node's own construction, before `_ready()` has built `_model` at
   all) and `if flow_overlay/plume_overlay != null` (same reason, for the `@onready` refs). `_ready()` now just
   calls `_refresh_geology_parameters()` once instead of duplicating the override-dict construction inline.

General lesson for this codebase: a value read once at construction and cached (`GridModel`'s old approach) is
invisible to live Inspector tuning, unlike a value read fresh every draw call (how `FlowOverlay`'s
`arrow_scale`/`PlumeOverlay`'s `puff_size_jitter` etc. already worked, which is why nobody noticed this gap
until a value that's genuinely baked into simulation STATE, not just read at render time, needed the same
live-tunability memory/feedback_expose_visual_tuning.md promises for everything else in this project.

New tests: `_test_grid_model_apply_geology_parameters_live` (K/porosity update for the affected geology; everything
else -- elevation, geology_id, head, and critically `mass_kg` -- stays byte-for-byte untouched, so a live tweak
never loses progress), `_test_world_geology_setter_refreshes_live_model` (assigning `World.clay_k_m_s` after
`_model` already exists immediately updates the running model's K, simulating exactly the Inspector-while-
playing edit the user made). Suite: 142/142, clean headless load.

## 2026-10-20 — clay_k_m_s specifically not sticking: widened its slider range

Follow-up again. User reported their `clay_k_m_s` edit never actually made it into `scenes/main.tscn` -- the
saved scene had `clay_porosity = 0.3` (their edit, present) but no `clay_k_m_s` line at all (the slider's
default, 5.0e-8, silently in effect). I suggested that might be a Local-vs-Remote-Inspector workflow mix-up.
The user came back and narrowed it further: every other slider (sand/silt K, all three porosities) saves and
updates the flow field correctly -- only `clay_k_m_s` doesn't, ruling out the general workflow explanation and
pointing at something specific to that one export.

Verified directly (not assumed) that the GDScript-level mechanism itself is NOT the problem: both a plain
`world.clay_k_m_s = 0.00001` assignment and `world.set("clay_k_m_s", 0.00001)` (the same call path the editor's
Inspector/Remote tab uses to push a property edit) correctly update both the export variable and the live
model's K immediately, in a throwaway headless script. The setter, the merge logic, and `apply_geology_parameters`
are all confirmed working -- identical in every way to the siblings that already work for the user.

The one thing that WAS different about `clay_k_m_s` specifically: its old range was `1.0e-9 .. 1.0e-5`, and the
value the user tried ("the highest possible K") was exactly `0.00001` -- the slider's own maximum, sitting
precisely on the end-stop. Couldn't reproduce an editor-widget bug directly from here (no interactive Godot
editor session available to drive), so this is the best-supported hypothesis rather than a confirmed root cause,
but it's also simply a bad UI situation regardless: a value sitting exactly on a slider's boundary gives no way
to tell "dragged all the way and it worked" apart from "the drag silently failed and snapped back" just by
looking at the number. Widened the range to `1.0e-9 .. 3.0e-4` (3.0e-4 being sand's own K -- clay can now be
pushed all the way to "as permeable as sand," fully removing the bottleneck) so a mid-range test value like
1e-5 sits comfortably away from either end. If the slider still doesn't stick after this, that confirms a real
editor bug worth its own investigation rather than a boundary-value fluke, and the next move would be checking
Godot's issue tracker for `EditorSpinSlider`/`"exp"` hint reports rather than continuing to guess from here.

## 2026-10-20 — mass-balance display and Reset (brief SS8 Phase 1 step 6, completed)

Closed out the one remaining piece of step 6 ("Add Next Turn (Space), turn counter, concentration overlay,
mass-balance display and reset") -- the turn loop, counter, and concentration overlay were already done; the
mass-balance readout and reset action were not.

`GridModel.reset_mass()`: zeroes every cell's `mass_kg` (not just the original source cell -- transport may have
since spread it elsewhere) and `escaped_mass_kg`, while leaving elevation/geology_id/head_m/k_m_s/porosity
completely untouched, so a reset replays the *same* map and the player's current live-tuned geology parameters
rather than regenerating a new map or discarding their tuning work (same "hot swap, don't rebuild" spirit as
`apply_geology_parameters`).

`World.reset_scenario()`: calls `reset_mass()`, re-seeds the source, resets `turn` to 0, and forces both overlays
to redraw. Wired to a new "Reset" button in the HUD, next to the existing X-Ray toggle (now both sit in an
`HBoxContainer`). Gave it `focus_mode = Control.FOCUS_NONE` for the exact same reason the X-Ray button already
needed it: a focused `Button` re-fires on every `ui_accept` event, and `ui_accept` is bound to Space -- without
this, every "next turn" press would also silently re-press Reset.

`World._total_seeded_mass_kg` tracks everything ever seeded (incremented in `_seed_initial_contamination`, reset
to the single re-seed amount by `reset_scenario`) -- this is what the mass-balance display checks the simulation
against: "In domain" (`_model.total_mass_kg()`) + "Escaped" (`_model.escaped_mass_kg`) should always sum to
"Seeded total". This is the same invariant `_test_grid_model_south_boundary_outflow` already proved numerically;
the HUD just makes it visible during play, satisfying the brief's SS9 mass-conservation guardrail as a player-
facing readout, not only a test assertion.

Tests added: `_test_grid_model_reset_mass` (zeroes mass/escaped everywhere, never touches elevation/K),
`_test_world_reset_scenario` (turn/mass return to scenario start, re-seed is tracked exactly once not
accumulated, and the mass-balance invariant still holds after a reset followed by further turns). Suite:
158/158 (grid_model + world totals), clean headless load.

Deliberately did not add a keyboard shortcut for Reset -- no existing precedent for a "destructive-ish" action
on a bare key, and a deliberate click matches how X-Ray's own button already works.

## 2026-10-20 — capture well and continuing source leak (brief SS8 Phase 1 step 7)

Implemented step 7: "Add one physically defensible player remediation choice (e.g. a capture well with
specified pumping rate) and one source behavior that keeps threatening the receptor without player input (e.g.
a continuing release from the source)." Real art provided by the user for both: `well_abstraction.png` and
`contamination_barrel.png` (`art/pretty_tiles/features/`). Neither had a `.import` file yet (dropped into the
folder outside the editor this session) -- `preload()` from the headless test script failed with "no resource
loaders (unrecognized file extension)" until a one-time `Godot --headless --editor --quit` run imported them;
noted here in case a future asset drop hits the same thing.

**Capture well** (`GridModel.well_axial`/`well_pumping_rate_m3_s`/`captured_mass_kg`, `set_well()`): modeled as
a lumped volumetric sink at one cell, exactly parallel to the existing open-downstream-boundary mechanism
(`_south_boundary_outflow_m3_s`) -- `max_stable_dt_s()` and `step_transport()` treat the well's pumping rate
the same way they already treat boundary outflow, withdrawing water (and whatever concentration it currently
carries) at the specified rate, tracked in `captured_mass_kg` rather than discarded. Explicitly documented as
NOT solving a local drawdown/capture-zone around the well -- it never touches `head_m` or `face_flux_m_s`, so
FlowOverlay's arrows won't visibly bend toward it. A true capture zone needs a solved local flow balance, which
is Phase 2's "solve a conservative steady-state groundwater-flow balance," not this MVP's imposed-gradient
model. "Physically defensible" here means: a genuine, conservative sink proportional to a real pumping rate and
the water's actual concentration -- not a magic delete button -- while being honest about what it doesn't yet
model.

**Continuing source leak** (`World.source_leak_rate_kg_s`): added to `source_axial` every substep of
`_advance_turn()`, proportional to that substep's `dt` (not dumped once per turn), so it advects the same way
the rest of the plume does. Nonzero by default (`1.0e-5 kg/s`) so the "keeps threatening without player input"
behavior is actually observable without extra setup. Tracked in the same `_total_seeded_mass_kg` the
mass-balance display already checks against, so the conservation invariant (`in domain + escaped + captured ==
seeded total`) covers the leak automatically rather than needing a separate check.

**Visual markers**: both are placed as ordinary Features-layer sprites via the existing `_add_feature()` (no new
mechanism needed), but tagged `kind = "scenario"` rather than `"feature"`/`"decal"` so they're excluded from
every existing kind-based rule (rocky/mountain coupling, the decal/feature double-dressing check, major-feature
scatter) -- those rules are about ordinary procedural dressing, not a fixed, precisely-placed gameplay marker.
Placed dead-center on their cell (no scatter), since the player needs to read these locations exactly.
`source_axial`/`well_axial` are explicitly skipped in `_build_features()`'s main per-cell loop so neither ever
also gets a random tree/rock/decal underneath. New `well_visual_nudge`/`source_visual_nudge` exports follow the
same Inspector-tunable-nudge pattern as `tree_visual_nudge` etc.

Existing `_test_world_turn_advance_transport`'s old assertion (`total_mass_kg()` exactly unchanged across one
turn) no longer holds now that mass can legitimately enter (leak) or leave (well) during a turn -- replaced with
the stronger invariant (`in-domain + escaped + captured == total ever seeded`), which is the test that should
have existed anyway. `_test_world_reset_scenario`'s invariant check was extended to include `captured_mass_kg`
too, defensively (it stays zero in that particular test since it never calls `_refresh_well()`).

Tests added: `_test_grid_model_well_capture` (set_well plumbing, actual capture on a transport step, mass
conserved including the well, CFL bound shrinks with a strong enough pumping rate, reset_mass clears
`captured_mass_kg` but preserves the well's own configuration), `_test_world_well_setter_refreshes_live_model`
(mirrors the geology live-tuning test), `_test_world_continuing_source_leak` (leak actually adds seeded mass
over a turn, folded into the same conservation invariant), `_test_world_scenario_markers_placed` (exactly one of
each marker, at the right cell, with no ordinary feature/decal double-dressing that cell). Suite: 174/174, clean
headless load.

## 2026-10-21 — receptor target, win/loss rules, per-turn explanation (brief SS8 Phase 1 step 8)

Implemented step 8: "Add a receptor target, win/loss rules and a short on-screen explanation of each turn."
Real art provided by the user: `receptor_lake.png` (`art/pretty_tiles/features/`, 221x129px) -- same missing
`.import` gotcha as the well/barrel assets two entries up, fixed the same way (one `Godot --headless --editor
--quit` run).

**Placement.** The user asked for the receptor "on grass tiles somewhere in the bottom of the catchment."
Rather than guess an axial that happens to land on grass under `_terrain_for`'s elevation-band formula, wrote a
throwaway probe script (since discarded) that builds a real `World` for both the default export radius (8) and
`scenes/main.tscn`'s actual radius (14) and printed each cell's terrain for the southern rows. Picked
`Vector2i(0, 6)` as `World.receptor_axial`'s default (grass, two rows north of the radius-8 map's southern edge,
off the river) and overrode it to `Vector2i(-10, 12)` in `scenes/main.tscn` for the real radius-14 scene (also
grass, off the river, well clear of that scene's own `source_axial`/`well_axial`). Rendered via the existing
`_add_feature()`/`_add_scenario_markers()` mechanism, tagged `kind = "scenario"` and dead-center on its cell,
exactly like the source/well markers -- `receptor_axial` is now also skipped in `_build_features()`'s main loop
so it never doubles up with an ordinary tree/rock/decal.

**Win/loss rules** (`World.GameState` enum: `PLAYING`/`WON`/`LOST`, `game_state`, `_check_win_loss()`). No new
`GridModel` sink/source was needed -- the receptor doesn't remove or add mass, it's purely a cell `_check_win_loss`
reads via the already-existing `get_concentration_kg_m3()`. LOSS: the receptor's concentration reaches
`receptor_contamination_threshold_kg_m3` (checked first, so crossing it on the very last allowed turn reads as a
loss, not a last-second win). WIN: surviving to `max_turns` while still `PLAYING`. Deliberately a SEPARATE export
from `contamination_full_scale_kg_m3` even though they share the same default (0.03) -- `full_scale` is a
display-only "what reads as 100% on the overlay/inspector" scale (that export's own doc comment: "not a cleanup
standard"), while this one is the actual pass/fail limit for this one cell; tuning how the plume *looks* must
never silently change what counts as a loss. `_advance_turn()` now no-ops once `game_state != PLAYING`, so
further Space presses/hold-repeats past a win or loss are harmless rather than quietly running turns past the
stated budget. `reset_scenario()` returns `game_state` to `PLAYING` and clears the trend-tracking state below,
same as every other piece of scenario state it already resets.

**Per-turn explanation** (`World._status_label`, `_refresh_status_label()`): a new HUD line, under the existing
mass-balance display, reading "Lake contamination: X% of limit (rising/falling/steady)" plus "Turn N of
max_turns" while playing, replaced by a plain "SAFE"/"FAILED" banner once the game has ended. The trend word
comes from comparing against `_receptor_prev_concentration_kg_m3` (the previous call's reading, updated at the
end of the same function) -- gives the player a plain-language read on how the scenario is going without needing
to interpret the mass-balance numbers or the plume cloud themselves, per the brief's own phrasing. Refreshed
alongside `_refresh_mass_label()` in `_ready()`, `_advance_turn()`, and `reset_scenario()`.

Tests added: `_test_world_receptor_marker_placed` (exactly one lake marker, at `receptor_axial`, no ordinary
feature/decal double-dressing), `_test_world_win_condition` (surviving `max_turns` wins, and the turn counter
stops climbing afterward -- run with `source_leak_rate_kg_s = 0.0` specifically to isolate the timing rule from
whether the default receptor/leak/well placements happen to interact, which is this project's own tuning, not
what the test checks), `_test_world_loss_condition` (seeding mass directly at the receptor and calling
`_check_win_loss()` crosses to `LOST`, same "test the pure per-turn logic directly" spirit as
`_test_world_hold_to_repeat_timer`), `_test_world_status_label_text` (status text reports percent-of-limit,
turn/budget, a rising trend, and the WON/LOST banners). Suite: 186/186, clean headless load.

## 2026-10-21 — Gate A: replaced the imposed linear head field with a solved heterogeneous-K balance

The user updated `PLUME_PROJECT_BRIEF.md` with a much more rigorous SS12 ("Scientific transport specification")
and asked to validate that groundwater flow is "fully integrated" before continuing. **Audit finding:** it
wasn't. `GridModel` had heterogeneous K (sand/silt/clay) layered on top of the ORIGINAL MVP's imposed linear
head field (`BASE_HEAD_M - HEAD_GRADIENT_M_PER_ROW * r`, applied identically at every cell) -- exactly the gap
brief section 4 names explicitly: "a prescribed linear head field... generally does not conserve water across
heterogeneous cells." This is brief SS12.6 Gate A's missing half (the uniform-K benchmark existed; the
"conservative heterogeneous-K head solver" did not).

**New file `scripts/simulation/flow_solver.gd`** (per the brief's own suggested `SS7` structure): a
GridModel-agnostic Gauss-Seidel/SOR steady-state solver over an integer-indexed conductance network (see
`docs/SIMULATION_ASSUMPTIONS.md` for the exact governing equation, boundary conditions, and solver parameters --
not duplicated here). `GridModel._solve_heads()` assembles this domain's specific network (Dirichlet north row,
specified-flux south boundary + well, harmonic-mean-K interior faces, no-flow elsewhere) and is now called from
`apply_geology_parameters()` (K changed -> conductances changed) and `set_well()` (the well sink moved/changed
rate) -- the existing "hot swap, live-tuning" pattern this file already uses for everything else.

**Performance matters here, unusually:** the solver runs on every live K/well Inspector edit, not just once at
startup -- an early Vector2i-Dictionary-keyed version took ~60s to solve a radius-14 map, making live tuning (and
even scene startup) unworkable. Rewrote the hot loop around integer-indexed `Packed*Array`s instead of
`Vector2i`-keyed Dictionaries (GridModel still does all bookkeeping in axial coordinates; only the solver's inner
loop is integer-indexed) -- cut a radius-14 solve to ~3s, radius-8 to ~0.3s. Still a real, user-visible cost per
live edit; not optimized further this round since correctness came first, but worth revisiting (e.g. debouncing
Inspector edits, or a faster iterative scheme) if it proves annoying in practice.

**The well is now a real sink in the head balance**, not a deferred limitation: SS12.4 test 9 explicitly requires
"pumping changes flow field... removes dissolved mass by extracted-water concentration," and including it in
the same linear system as the south-boundary sink was essentially free once the solver existed. `set_well()`'s
and `World._refresh_well()`'s doc comments (and `_refresh_well()`'s behavior -- it now redraws `FlowOverlay`
too) are updated accordingly; earlier entries in this file describing the well as deliberately NOT bending the
flow field are superseded by this one.

**A genuine, interesting finding, not a bug:** a uniform-K solve does NOT exactly reproduce the old imposed
linear formula on this specific hexagonal domain. The hex's slanted east/west edges have cells missing exactly
one neighbor in a direction that isn't either designated boundary type; their implicit no-flow treatment there
doesn't exactly match what the idealized 1D linear field implies crossing that face, and because the governing
equation is elliptic (globally coupled), that mismatch doesn't stay local -- it diffuses across the WHOLE domain
(confirmed numerically: even the exact center cell differs from the hand-derived formula by several meters).
This is an inherent property of modeling a bounded, irregularly-shaped domain with simple no-flow side edges,
not a solver defect -- any finite-volume groundwater model has some version of this at an irregular boundary.
Adjusted the uniform-K benchmark test to check what actually should hold (water balance, strict monotonic
north-south decrease, small cross-column spread) instead of exact formula equality, and to explicitly CONTRAST
that small spread against the heterogeneous case's much larger one (a real clay lens visibly deflecting flow --
confirmed directly, e.g. a steep head drop concentrated specifically across the clay band on a column that
crosses it, much steeper than an equal-length run through sand).

**Existing tests updated:** `_test_grid_model_apply_geology_parameters_live` no longer asserts head is untouched
by a K change (now explicitly the opposite -- see above); `_test_grid_model_head_gradient` split into
`_test_grid_model_head_gradient_uniform_k_benchmark` and `_test_grid_model_heterogeneous_k_head_solve_conserves_water`.
`_south_boundary_outflow_m3_s` was simplified to drop its now-redundant dependency on `get_head()` (algebraically
identical output -- the external-head-minus-gradient formulation always canceled to a head-independent constant;
this just makes that explicit, and is what makes it usable as a fixed RHS sink in the solver rather than part of
the matrix).

**New tests:** `_test_grid_model_well_changes_flow_field` (SS12.4 test 9's flow-field half -- pumping measurably
draws down head and increases inflow toward the well versus an unpumped baseline), `_test_grid_model_zero_gradient_no_transport`
(SS12.4 test 1, previously missing entirely -- a flat head field produces exactly zero face flux and leaves
mass_kg bit-for-bit unchanged after a transport step, regardless of step size). New `docs/SIMULATION_ASSUMPTIONS.md`
per brief SS12.4's explicit instruction to record assumptions/units/tolerances in one place. Suite: 197/197,
clean headless load.

**Audited but not changed this round:** Gate B (conservative advection) was already substantially implemented
pre-dating this brief revision -- conservative upwind transport, CFL-stable substeps, multiple mass-conservation/
nonnegativity/direction/boundary tests. Gates C (dispersion/diffusion), D (sorption/reactions), E (recharge/
scenarios) and F (vertical layers) are not started, per the "implement one gate at a time" working rule.

## 2026-10-21 — X-ray-exclusive plume; geology fill + legend; head-contour overlay

Three amendments the user asked for after the Gate A head-solver work above, all about `PLUME_PROJECT_BRIEF.md`
SS6/SS12.5's "toggle geology/K, hydraulic head/equipotentials, water-flux arrows, dissolved concentration" idea --
the subsurface-data overlays are supposed to live in a dedicated view, not compete with the surface art.

**1. Plume cloud is now x-ray-only.** Previously `PlumeOverlay` was visible on the ordinary surface view by
default (`show_plume_overlay = true`), with x-ray mode just forcing it on and restoring whatever it was
beforehand on exit -- the same "remember and restore" pattern `FlowOverlay` still uses. That pattern is now
WRONG for the plume specifically: it should never appear outside x-ray at all, so there is no "prior state" to
restore. `World._ready()` now always sets `plume_overlay.visible = false`; `set_xray_mode()` sets it to
`show_plume_overlay` on entry and unconditionally `false` on exit. `show_plume_overlay`'s own meaning changed
from "visible right now" to "enabled whenever x-ray is active." `FlowOverlay` is unchanged (still a normal
surface toggle via F, still remembers/restores its prior state in x-ray) -- only the plume was asked to move.

**2. New `scripts/rendering/head_contour_overlay.gd`: equipotential contour lines.** Brief section 4's own
"learning aid" ask, implemented without any real marching-squares contouring: a line is drawn along any shared
cell edge where the two cells' solved head (`GridModel.get_head`, now the Gate A steady-state solve, not an
imposed formula) falls into a different `contour_interval_m`-wide band -- the exact same "detect a property
change across a shared edge, draw a line there" technique `grid_outline.gd`'s shore-edge cue already uses,
generalized from one boolean to many numeric bands. This needed its own hand-derived hex-edge-index ->
neighbor-offset mapping (`_EDGE_NEIGHBOR_OFFSETS`), verified geometrically against `HexMath.hex_points()` by a
new test (`_test_head_contour_overlay_edge_offsets_match_geometry`) -- the exact kind of claim that produced a
real bug earlier in this project (`grid_outline.gd`'s own shore-edge derivation needed the identical check).
Tightly packed contour lines read as a steep local gradient; confirmed numerically (not just by eye) that a
patch of cells immediately around the capture well shows more contour-band crossings than an equally sized
patch far from it -- a real drawdown cone falls straight out of the already-solved head field, no well-specific
drawing code needed at all. x-ray-exclusive, same pattern as the plume above (no surface toggle).

**3. New `scripts/rendering/geology_overlay.gd`: flat geology fill, plus a legend.** A simple semi-transparent
fill per cell keyed by `GridModel.get_geology()`. The 3 colors live in a new `GridModel.GEOLOGY_COLOR` constant
(alongside the existing `GEOLOGY_NAME`) rather than in either rendering script, specifically so the fill and
`World._build_xray_legend()`'s swatches read the exact same table and can never drift apart. The legend is a
small top-right screen-space panel (same `CanvasLayer` + `PanelContainer` pattern as the existing top-left HUD
and bottom-left cell inspector, placed in the one remaining free corner), shown/hidden alongside the geology
fill itself. A `_test_geology_overlay_colors_cover_all_geologies` test guards against a future 4th geology
silently falling through to the fill's `MAGENTA` fallback or being missing from the legend.

Both new overlays are plain `Node2D` children of `Main` (new ext_resources/nodes in `scenes/main.tscn`, inserted
between `DebugOverlay` and `PlumeOverlay` so the geology fill draws first/underneath, contour lines next, then
flow arrows and the plume cloud on top), configured in `_ready()` alongside the existing overlays, and redrawn
by `_refresh_geology_parameters()`/`_refresh_well()` whenever K or the well change (the solved head field
changes too -- geology itself never does, so `GeologyOverlay` doesn't need a redraw hook for either).

Updated `_test_world_xray_mode` to wire up and check all four x-ray-gated overlays (flow/plume/geology/contour),
distinguishing FlowOverlay's "remember and restore" behavior from the other three's "never visible outside
x-ray, no prior state to restore." Suite: 204/204, clean headless load.

## 2026-10-21 — Fixed: invisible legend, invisible contour lines

User report after the above: the geology fill worked, but the legend never appeared and no contour lines were
visible. Rather than keep guessing from source alone, actually rendered the scene (Godot can run with a real
window even from this shell -- `godot.exe --script <probe>.gd --rendering-driver opengl3`, no `--headless`) and
captured `get_viewport().get_texture().get_image()` to a PNG, which is what actually found both root causes.

**Legend: a real bug, not a logic error.** `_build_xray_legend()` called `panel.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT, PRESET_MODE_KEEP_SIZE, 12)` BEFORE adding the title/swatches/labels -- at that moment the panel's size is `(0,0)`, so a RIGHT-anchored preset (whose offsets are computed outward from the current size, growing left/up from the anchor point) collapsed to a zero-size rect pinned to a single point: technically `visible = true`, but nothing to actually see. `_build_hud`'s existing top-LEFT panel uses the identical call-before-children ordering and works fine -- coincidentally, not because the ordering is safe in general: a LEFT/TOP-anchored preset's corner doesn't depend on the panel's own size, so it was never exposed to this bug. Fixed by moving the anchor/offset call to AFTER every child is added, so `PRESET_MODE_KEEP_SIZE` captures the panel's real, final size.

**Contour lines: present, but visually unreadable, not missing.** The screenshot proved `_draw()` was being called and drawing exactly as many lines as the standalone logic probe predicted (1004) -- the bug was never "nothing draws," it was "everything draws." At the old fixed `contour_interval_m = 1.0`, ~84% of every edge on the map crossed a band, because this scenario's default `well_pumping_rate_m3_s` (0.05 m3/s) against its clay-heavy K produces roughly **25m of drawdown at the well alone**, stacked on an existing ~35m regional gradient -- a dense wash indistinguishable from "the grid, lightly tinted," not a legible set of contour lines. Rather than hand-pick a new fixed interval (which would just silently break again the next time K or the well's rate is retuned -- exactly this bug, one Inspector edit away), `head_contour_overlay.gd` now computes its interval dynamically each draw: the current head range (max - min across every visible cell) divided by a new `target_contour_count` export (default 15), floored at `min_interval_m`. Confirmed numerically (not just by eye) that this produces real contrast between background and the well's own vicinity (71% of near-well edges cross a band vs. 47% for sand-sand edges generally, at the auto-computed interval for this scenario) and, via a second real screenshot zoomed on the well, an actual visible ring of lines encircling it, matching FlowOverlay's arrows converging on the same cell. Also brightened `contour_color` to a highly saturated cyan and increased `line_width` to 2.0 -- the old pale, GridOutline-adjacent tint was hard to tell apart from the plain grid even where it WAS drawing correctly.

`_band()`'s signature changed from reading an export directly to taking `interval_m` as a parameter (since it's now computed fresh per draw, not a fixed Inspector value) -- `tests/run_tests.gd`'s `_test_head_contour_overlay_band_and_drawdown` updated to match, plus a new assertion that `_current_interval_m()` actually scales inversely with `target_contour_count` for a fixed head range. Suite: 206/206, clean headless load, and -- unlike the previous round -- actually confirmed visually via real rendered screenshots, not just inferred from passing tests.

## 2026-10-21 — Contour lines bound to hex edges, replaced with marching-triangles contouring

User's follow-up: the fixed contour overlay above worked, but every line ran along a hex cell edge -- correct
data, "blocky" presentation, not what a real equipotential contour map looks like. Root cause: the previous
version detected a contour by comparing adjacent CELLS and, when their head fell into different bands, drew a
line along the shared hex EDGE -- a line following the grid's own geometry, not the underlying continuous head
field the grid is just a discrete sample of.

Replaced with proper "marching triangles" contouring. Hex cell CENTERS form a triangular lattice (the dual of a
hex grid): each hex corner is shared by exactly 3 mutually-adjacent cells, i.e. one small triangle. `grid_model.gd`'s
solved `head_m` at each triangle's 3 corners is treated as varying linearly across it (the standard assumption
any marching-squares/-triangles contouring makes), and for every contour level that falls within a triangle's
head range, the two triangle edges that level crosses are found by linear interpolation (`_triangle_crossing`,
a pure, directly-tested primitive) and joined with a short line segment. Segments are short relative to a cell
but, critically, cut through cells at whatever angle the real head gradient has -- never forced to run along a
hex boundary -- which is what makes the result read as smoothly curving rather than hexagonal. Confirmed with a
real rendered screenshot (same `--script ... --rendering-driver opengl3`, no `--headless`, technique the previous
entry introduced): wide contour lines now flow diagonally across the clay band like an actual piezometric map,
unmistakably not tied to the grid.

A useful side effect of handling multiple levels per triangle (the old version could only ever draw one line per
hex face, however big the head jump across it): a triangle spanning several contour levels at once (e.g. near
the well, or across the clay band) now correctly draws multiple parallel lines there, which is MORE physically
accurate, not just prettier -- real contour density should track gradient steepness.

`_TRIANGLE_OFFSETS` replaces `_EDGE_NEIGHBOR_OFFSETS` (same 6 values, different meaning -- consecutive pairs now
define triangle corners, not shared edges); verified geometrically (each consecutive pair is a genuine 1-hex-step
neighbor of the other, confirming 3 mutually-adjacent cells) rather than just asserted, same discipline as
`grid_outline.gd`'s own shore-edge offsets needed. New tests: `_test_head_contour_overlay_triangle_offsets_are_mutually_adjacent`,
`_test_head_contour_overlay_triangle_crossing` (the interpolation primitive, including the "no crossing" cases),
`_test_head_contour_overlay_drawdown` (replaces the old band-based version, same drawdown-contrast claim against
the new machinery). Suite: 209/209, clean headless load, visually confirmed via rendered screenshots at both a
wide view and zoomed on the well.

## 2026-10-21 — Contour line labels ("42.3 m"-style, like a real topographic map)

User's follow-up ask: label the contour lines. Added per-level labels (`head_contour_overlay.gd`), placed
periodically along each level's lines rather than once per tiny triangle segment (unreadable clutter -- a single
contour level is made of many short segments) or once per contour line (a single label can land off-screen or
somewhere illegible, and there's no reconstructed polyline/ordering to pick a "good" spot from anyway -- segments
are a soup, not linked curves).

**Placement.** `_select_label_points`: a pure, order-dependent greedy filter -- walks a level's collected segment
midpoints (in the same raster order `_draw()`'s per-cell loop generates them) and keeps a point only if it's at
least `label_min_spacing_px` away from every point already kept. This doesn't require reconstructing actual
polyline connectivity from the triangle-crossing segment soup (a meaningfully bigger undertaking -- matching
segment endpoints across triangle boundaries, handling branches); raster order is spatially coherent enough in
practice that the result reads as "a label every so often along the line," confirmed visually (a rendered
screenshot shows clean, non-overlapping labels scattered naturally across a dense field of parallel contour
lines). Tested directly (`_test_head_contour_overlay_label_spacing`): close points get thinned, far points are
always kept regardless of how many candidates came before them.

**Rendering.** `draw_string_outline()` behind `draw_string()` (both from `ThemeDB.fallback_font`, no custom font
resource needed) -- a dark outline is what keeps "42.3 m" readable against the x-ray view's highly variable
backdrop (geology fill, plume cloud, flow arrows, dark background), the same problem the mass-balance HUD panel
solves with an opaque background instead (not applicable here since labels sit directly on top of map content,
not a fixed screen corner). `show_labels`/`label_font_size`/`label_color`/`label_outline_color`/`label_min_spacing_px`
all Inspector-tunable, per this project's standing "expose it, don't hand-tune blind" practice.

Suite: 215/215, clean headless load, visually confirmed via a rendered screenshot.

## 2026-10-21 — Gate C: molecular diffusion

Implemented brief SS12.6 Gate C's first half: "effective molecular diffusion" (anisotropic mechanical dispersion
is a separate, later addition -- the user explicitly asked for molecular diffusion specifically this round).

**Governing equation and implementation**: Fick's law applied face-to-face
(`GridModel._face_diffusion_conductance_m3_s`), exactly parallel in structure to how `face_flux_m_s` already
computes an advective face conductance from harmonic-mean K -- see `docs/SIMULATION_ASSUMPTIONS.md`'s new
Molecular diffusion section for the full formula, face-averaging conventions, and parameter table (not duplicated
here). The resulting conductance is dimensionally a volumetric-flow equivalent (m3/s), which is what lets both
`step_transport()` and `max_stable_dt_s()` fold it directly into the SAME accumulators advection already uses,
with no new bookkeeping structures needed.

**A real, non-obvious science point, worth a dedicated parameter table rather than reusing K's**: diffusion
coefficients were given their OWN, much narrower per-geology range (sand 1.0e-9, silt 7.0e-10, clay 4.0e-10 m2/s
-- roughly 2.5x spread) instead of mirroring K's dramatic 6000x sand:clay contrast. This isn't a smaller slider
range by oversight -- free-water molecular diffusion is primarily a property of the dissolved SPECIES, only
mildly reduced by tortuosity in a porous medium (a few-x effect), unlike K, which depends much more severely on
pore-throat geometry. Exposed as new `sand_diffusion_m2_s`/`silt_diffusion_m2_s`/`clay_diffusion_m2_s` Inspector
exports on `World`, live-tuned through the same `apply_geology_parameters` hot-swap path K/porosity already use
(`_init`/`apply_geology_parameters` both gained an optional `diffusion_overrides` parameter, defaulting to `{}`
so every existing call site is unaffected).

**Direction is unconditional, unlike advection**: diffusion always moves mass from higher to lower concentration
regardless of the flow field (no upwind scheme needed, since Fick's law doesn't care which way water is moving,
or whether it's moving at all) -- confirmed directly by brief SS12.4 test 5 ("pure diffusion: plume spreads at
zero groundwater velocity"), previously impossible to write since nothing but advection existed.

**CFL stability**: diffusive conductance is added SYMMETRICALLY to both cells on a face in `max_stable_dt_s()`
(unlike advection, which only ever accumulates outflow on the single upstream cell) -- since diffusion has no
fixed direction, either cell could be the one losing mass across a given face on a given step, so the
conservative (worst-case) treatment counts the face's full conductance as potential outflow for both.

**Scope, deliberately limited**: interior cell-to-cell faces only -- the open south boundary and the capture well
do not yet diffuse. Diffusing across an open boundary needs an external-concentration assumption with no clear
answer yet (documented in `docs/SIMULATION_ASSUMPTIONS.md` rather than guessed at), and nothing in brief SS12.4's
required test list needs it.

**Existing test updated**: `_test_grid_model_zero_gradient_no_transport` (brief test 1) now explicitly zeroes
diffusion via the new override mechanism, since a flat head field alone no longer implies zero transport --
diffusion is exactly the exception the brief's own test-1 wording already anticipates ("no advective transport;
diffusion only if concentration gradients exist"). Its complement, `_test_grid_model_pure_diffusion_spreads_at_zero_velocity`,
is new and is brief test 5 verbatim. `cell_info()`/`_format_cell_info()` (the cell inspector) gained a
"Diffusion" line, same scientific-notation formatting as K, so the new parameter is inspectable like every other
one (brief SS12.5: "cause and effect inspectable").

New tests: `_test_grid_model_pure_diffusion_spreads_at_zero_velocity`, `_test_grid_model_diffusion_included_in_cfl_bound`,
`_test_world_diffusion_setter_refreshes_live_model`, plus diffusion coverage added to the existing geology-override
and live-tuning tests. Verified end-to-end in the real scene, not just unit tests: 5 real turns advanced with
diffusion active, mass-balance invariant (in-domain + escaped + captured == seeded total) held exactly. Suite:
237/237, clean headless load.

## 2026-10-21 — PlumeOverlay rebuilt as filled isoconcentration zones (replaces the puff-cloud renderer)

User's ask, after sharing a real site plume map (naphthalene isoconcentration contours, naturally a yellow-to-red
band ramp around a documented "center of mass"): make the game's plume read more like that -- "zones of higher
(inner plume) to lower concentration shown in different colours" -- without necessarily reproducing the
reference's black contour outlines.

**Replaced, not layered on top of, the puff/glow renderer** (`glow_radius_factor`/`puff_scatter_radius`/
`puff_size_jitter`/`puff_alpha_jitter`/`max_alpha`/`plume_color` all removed from `plume_overlay.gd`). Keeping
both would have meant two independent, visually competing renderings of the same field; the zone-fill approach
directly answers what was asked, so there was no reason to keep the old one around as dead weight.

**Reused `head_contour_overlay.gd`'s core insight rather than re-deriving it**: hex cell centers form a
triangular lattice (the dual of the hex grid), and treating concentration as linear across each small triangle
(`_TRIANGLE_OFFSETS`, identical enumeration to the head-contour overlay) lets a band boundary cut through cells at
whatever angle the real plume has, instead of being forced to run along a hex edge. Confirmed via a real rendered
screenshot: the resulting fill is a smoothly rounded, organic blob, not a hex-blocky spreadsheet-style fill.

**The actual new piece: filled isoBANDS, not isoLINES.** head_contour_overlay draws a line wherever one level
crosses a triangle; this needs the region BETWEEN two levels filled. `_clip()` is a general Sutherland-Hodgman
clip of a convex polygon against one linear scalar half-plane (keep where interpolated value >= or <= a
threshold); clipping a triangle against a band's lower bound, then its upper bound, produces that triangle's
contribution to that band (0 vertices if the triangle misses the band entirely, up to a pentagon if the band
retains a middle vertex and double-crosses one edge -- confirmed by hand-working a sample triangle in
`_test_plume_overlay_clip`, since "cutting one vertex off a polygon always adds one vertex" is the kind of
assumption worth checking rather than asserting).

**Dedup needed, unlike head_contour_overlay's lines**: that overlay accepts drawing each lattice triangle 3 times
(once per corner cell) as harmless redundancy for thin lines. A FILLED polygon drawn twice over itself with
alpha < 1 visibly double-darkens at every triangle, which would have produced visible seams wherever a triangle
happened to only be drawn once (an edge-of-map triangle) next to one drawn multiple times (an interior one).
`_triangle_key()` canonicalizes a triangle's 3 corner axials (sorted) so `_draw()` can skip any triangle it's
already filled, regardless of which of its 3 corner cells it's enumerated from.

**Bands are fractions of `full_scale_kg_m3`, not absolute kg/m3** (`zone_thresholds_fraction`, default
`[0.02, 0.06, 0.15, 0.3, 0.55, 1.0]`), the same existing "100% contaminated" reference the cell inspector's %
reading and the old puff renderer both already used -- retuning `full_scale_kg_m3` rescales the zones instead of
silently breaking them. Colors (`zone_colors`) default to ColorBrewer's "YlOrRd" 6-class ramp (pale yellow to
red), the same palette convention the reference site map uses, with alpha baked in per-band (low bands more
transparent, the top band most opaque) so the plume's core reads as visually denser than its edge. Both arrays,
plus a global `opacity` multiplier and an off-by-default `draw_band_outlines` (the user's "not exactly... with
black outlines," kept available rather than deleted outright), are Inspector-tunable per
`memory/feedback_expose_visual_tuning.md`.

**Verified via real rendered screenshots** (this session's established technique for UI/rendering changes,
`--rendering-driver opengl3` + `get_viewport().get_texture().get_image().save_png()`), in two passes: first at a
real 40-turn scenario state (confirmed a smooth, rounded single-band blob, no hex artifacts); second with mass
synthetically boosted near the source so every band in the ramp actually got exercised in one shot (confirmed all
6 colors render with no gaps or seams between adjacent bands -- the dedup is working as intended).

Replaced `_test_plume_overlay_display_alpha`/`_test_plume_overlay_puff_params` with `_test_plume_overlay_fraction`,
`_test_plume_overlay_clip`, `_test_plume_overlay_triangle_key_order_independent`. Cleared the 3 puff-era Inspector
overrides left on `scenes/main.tscn`'s `PlumeOverlay` node (properties that no longer exist on the script).
Suite: 246/246, clean headless load.

## 2026-10-21 — Rounded plume zone edges (union + Chaikin smoothing), and a real perf bug caught before it shipped

User's follow-up ask: the filled isoconcentration zones above were a big improvement, but each band's edge was
still visibly a chain of short straight segments (a single lattice triangle's clipped edge can only ever be
straight, since concentration is only assumed linear within one triangle) -- jagged/angular rather than smoothly
curving, most noticeable on a sparse plume with few triangles per band.

**Redesigned `_draw()` around SUPERLEVEL sets instead of [lo, hi) bands.** Rather than clipping each triangle
twice (lower bound, then upper bound) to get one band's own ring-shaped piece, each threshold now gets ONE clip
(`_clip(..., keep_above: true)`) producing that threshold's whole `{concentration >= threshold}` region, painted
in ascending threshold order so each smaller, higher-threshold region paints over the inner part of the previous
one -- the same nested-fill trick real contour-fill renderers (matplotlib's `contourf`) use. Simpler than the old
double-clip approach AND a prerequisite for smoothing: rounding needs one connected boundary loop, and a
single-clip superlevel region only ever needs union-ing its own triangle pieces together, not also tracking a
separate inner/outer boundary pair per band.

**`_union_polygons()`**: folds a band's many small per-triangle clipped pieces (via `Geometry2D.merge_polygons`)
into the smallest set of whole, disjoint polygons -- needed because only the TRUE outer silhouette of a band's
full region should get smoothed; internal edges between two same-colored adjacent triangle pieces disappear
entirely once unioned, so there's nothing there to look jagged in the first place.

**`_chaikin_smooth()`**: standard Chaikin corner-cutting subdivision (each pass replaces every edge with 2 new
points at 1/4 and 3/4 along it, discarding the original sharp corner) applied to each unioned boundary loop --
simple, no spline library needed, converges toward a smooth curve. New `smoothing_iterations` export (default 2,
0 disables it and returns to the pre-smoothing straight-edged look).

**A real performance bug, caught before it reached the user, not after**: the FIRST version of `_union_polygons`
tested every new polygon piece against every already-merged piece (`merge_polygons` called up to O(n^2) times).
A quick synthetic worst-case probe (the whole map pushed near-uniformly above the lowest threshold -- i.e.
exactly what a near-total-loss end state looks like) made a single redraw take long enough to look hung. This
would have meant the single most game-relevant moment -- contamination close to covering the map, right before a
loss -- was also the one moment the plume overlay stalled the game. Rewrote `_union_polygons` to an O(n) amortized
algorithm instead: each outer pass picks one seed polygon as a growing accumulator and sweeps the REMAINING
pieces once (not a running list of separately-merged pieces), absorbing whatever touches it; one real connected
blob (the normal case for a plume from one source) finishes in a single pass. Re-verified via an instrumented
probe that logs progress to a file as it goes (stdout itself turned out to be fully buffered until process exit
in this environment, making naive `print()`-based timing probes look hung even when the actual work had already
finished in under a second -- a tooling trap, not a real stall, worth remembering for any future perf probe here).
Confirmed: the same worst-case scenario (331 contaminated cells, 600 triangles per threshold, all 6 thresholds)
now completes in well under 1 second total.

**`_MAX_PIECES_FOR_SMOOTHING` (600), a hard safety valve, not a tuning knob**: even the O(n) union is only fast
for the realistic case (a plume is one or a few connected blobs); a pathologically fragmented/scattered field
(many isolated single-triangle specks that never touch anything) could still force one full pass per disjoint
piece. Past this many pieces in one band, that band falls back to raw, unsmoothed per-triangle fill for that one
frame rather than risking a stall -- a graceful, still-correct degradation.

New tests: `_test_plume_overlay_union_polygons` (touching pieces merge into 1 polygon; disjoint pieces stay
separate; a piece bridging two separate blobs correctly folds all 3 into 1), `_test_plume_overlay_chaikin_smooth`
(vertex count doubles per pass; no surviving point sits on an original sharp corner; stays within the original
bounding box; 0 iterations is a real no-op). Suite: 254/254, clean headless load. Verified visually via a real
rendered screenshot (40-turn scenario): the filled zones now read as genuinely smooth, rounded, organic shapes,
a clear step up from the straight-edged version -- with one known minor cosmetic artifact (occasional small thin
spikes at a band's edge, likely where Chaikin runs on a non-convex or near-self-intersecting merged polygon from
real, slightly asymmetric advected-and-diffused field data) left as a documented, acceptable imperfection rather
than chased further.

## 2026-10-21 — Fixed: plume breaking up into separate ellipses (a real `_union_polygons` correctness bug)

The "minor cosmetic artifact" noted above undersold it: the user's next screenshot showed the plume's outer band
had split into a column of several small disconnected ellipse/finger shapes along the map edge, not one coherent
region -- a real correctness bug, not a smoothing quirk.

**Root cause**: `_union_polygons`' single-pass sweep (introduced in the earlier perf fix) is order-dependent, and
that dependence can silently produce the WRONG answer, not just a slower one. If piece C only touches the growing
region through piece B, but B happens to appear after C in the input array, C gets tested against a `current` that
doesn't yet include B, is judged "doesn't touch," and is permanently written off as its own separate polygon --
even though the true region is one connected whole. `_collect_triangles`' enumeration order (cells in whatever
order `HexMath.cells_in_radius` returns, then 6 triangle directions each) is roughly spatial but not an adjacency
walk, so this kind of out-of-order gap was always going to happen somewhere on a real map; it just took a second
real scenario to expose it.

**Fix, two parts working together**:
1. **`_union_polygons` now retries until a full round makes no further progress**, instead of a single sweep --
   a fixed-point iteration that correctly finds everything transitively connected to a seed regardless of input
   order. This alone fixes correctness (confirmed: a direct regression test feeds a 3-piece chain in the exact
   order that exposed the bug, `[A, C, B]`, and checks it still merges into 1 polygon) but reintroduces a
   performance risk if applied blindly to a band's whole (unordered) piece list.
2. **`_build_adjacency()`**: a NEW triangle-to-triangle adjacency graph built once per `_draw()` call from the
   fixed lattice topology alone (which triangles share 2 of their 3 corner cells -- completely independent of any
   threshold/concentration data). `_band_loops()` uses it to group a band's included triangles into connected
   components via real BFS over actual mesh connectivity BEFORE folding each component's pieces -- so the
   retry-until-no-progress loop in part 1 almost always converges in very few rounds (most pieces now arrive
   already adjacency-ordered), getting both correctness AND speed back. Measured on the same worst-case
   near-fully-contaminated scenario used for the earlier perf fix: the un-grouped retry-until-no-progress version
   alone took ~2.4s total across all 6 thresholds (correct, but slow); with adjacency grouping, ~224ms, with a
   full real-Viewport redraw+frame measured at ~312ms.

Note two non-adjacent triangles can never have touching clipped pieces anyway (the triangulation is a proper
planar partition -- two triangles that don't share an edge don't border each other at all), so grouping by this
graph first never incorrectly separates anything the retry loop would otherwise have joined; it only avoids
wasting merge attempts between pieces that could never touch in the first place.

**New export, also directly answering the user's "expose more parameters" ask**: `min_region_area_px2` (default
100, range 0-2000) culls any post-union region smaller than this screen-space area before smoothing/drawing --
guards against any future stray single-triangle sliver rendering as a tiny fleck, and doubles as a way to
simplify a visually busy, speckled low band.

New tests: `_test_plume_overlay_union_polygons`'s chain-order regression case (above), `_test_plume_overlay_edge_key_order_independent`,
`_test_plume_overlay_build_adjacency` (two triangles sharing a real lattice edge are adjacent and symmetric;
two triangles sharing only a single corner cell, no edge, are NOT). Suite: 260/260, clean headless load.
Re-verified visually via a real rendered screenshot of an actual 60-turn scenario (not a synthetic boost this
time, specifically to reproduce the conditions that exposed the bug): the plume now renders as one coherent,
smoothly rounded shape, no fragmentation.

## 2026-10-22 — Fixed: "indented" plume edges + "Invalid polygon data, triangulation failed." engine error

User report after the above fix: "it look much better but there are still some areas that are indented along
the outer edges of the bands of the plume," plus this error appearing in the log:

```
E 0:00:25:102   plume_overlay.gd:413 @ _draw(): Invalid polygon data, triangulation failed.
  <C++ Error>   Condition "indices.is_empty()" is true.
  <C++ Source>  servers/rendering/renderer_canvas_cull.cpp:1713 @ canvas_item_add_polygon()
```

**Root cause, unifying both symptoms**: `draw_colored_polygon` triangulates its input internally before filling
it. `Geometry2D.merge_polygons` can produce a polygon that touches itself at (or very near) a single point where
two unioned pieces meet only at a vertex rather than along a real shared edge -- a near-zero-length edge --
and Chaikin-smoothing a tight concave notch can occasionally fold the boundary over itself too. Either produces a
degenerate (self-intersecting or zero-area) polygon that fails Godot's internal triangulator. When that happens,
the engine logs the error above and **silently draws nothing** for that one polygon -- it doesn't crash, it just
skips the draw call. That's exactly what read as an "indented" edge: a bite taken out of a band where its region's
draw call quietly failed that frame.

**Fix** (`scripts/rendering/plume_overlay.gd`): two new static helpers, used in `_draw()`'s per-loop fill step:

- `_dedupe_points(points, epsilon=0.01)` -- collapses consecutive (including wrap-around) points closer than
  epsilon into one. This is the actual preventative fix: it removes the near-zero-length edges that are the most
  common cause of a degenerate polygon in the first place, applied to both the raw unioned loop and the
  Chaikin-smoothed result.
- `_triangulates(points)` -- calls `Geometry2D.triangulate_polygon()` directly, the exact same check
  `canvas_item_add_polygon()` does internally, so a bad polygon can be caught and handled BEFORE it ever reaches
  the renderer rather than after.

`_draw()`'s fill step now: dedupe the raw loop -> dedupe the Chaikin-smoothed result -> if the smoothed version
fails `_triangulates()`, fall back to the deduped raw loop -> if even that fails, skip drawing that one region
this one frame (same graceful-degradation philosophy as `_MAX_PIECES_FOR_SMOOTHING`) rather than ever calling
`draw_colored_polygon` on something that can't be triangulated.

New tests: `_test_plume_overlay_dedupe_points` (a near-duplicate consecutive point collapses; a point nearly
coincident with the first point, i.e. the wrap-around closing edge, also collapses; a clean polygon is
unchanged), `_test_plume_overlay_triangulates` (a simple triangle passes; fewer than 3 points always fails; a
hand-built self-intersecting "bowtie" quad fails, confirming the check actually catches the failure mode we're
guarding against). Suite: 262/262, clean headless load.

Re-verified two ways: (1) a real rendered screenshot of the same actual 60-turn scenario used for the previous
fix -- no triangulation error in the console log, and the previously-visible dents on the yellow zone's edge and
the orange lobe are gone, replaced by one continuous smooth boundary; (2) the worst-case near-total-contamination
stress scenario (331 cells, all 6 bands at their largest, `--rendering-driver opengl3` so the real
`RenderingServer.frame_post_draw` end-to-end path actually runs) -- completed cleanly with no triangulation
error, band_loops ~162ms, full real redraw+frame ~239ms, both in line with (in fact slightly faster than) the
previous fix's measured numbers.

## 2026-10-27 — Tree wind sway + a synced contact shadow

User ask, as a "look and feel" detour before returning to transport work: "add a light back and forth to the
trees as they shake in the wind and a shadow underneath that interacts with the movement." Scoped to trees only
(not rocks/decals/mountains, per the ask) -- see brief §6 ("Visual direction and UX") for where this kind of
polish sits in the project's stated priorities.

**Implementation** (`scripts/rendering/world.gd`, `scripts/rendering/shaders/tree_sway.gdshader`,
`scripts/rendering/shaders/tree_shadow_sway.gdshader`, `scripts/rendering/tree_shadow_texture.gd`): a new
`_add_tree_feature()` wraps the existing `_add_feature()` (left untouched, so every test that assumes a plain
feature's sprite is `root.get_child(0)` still holds) and adds two things, both GPU-side (a canvas_item vertex
shader), not per-frame GDScript -- zero added script cost no matter how many trees are on screen:

- **Canopy sway**: `tree_sway.gdshader` bends the sprite from a fixed pivot at the trunk base
  (`VERTEX.x += sin(TIME * sway_speed + phase) * sway_amount_px * (1.0 - UV.y)`) -- UV.y=1 at the texture's
  bottom (the trunk, which `_add_feature`'s `ground_anchor` already places at this node's local origin) stays
  planted; UV.y=0 at the top (the canopy) gets the full lean. A real bend, not a whole-sprite rotation/translation.
- **Contact shadow**: a procedurally generated soft radial-falloff blob (`tree_shadow_texture.gd`, same
  "compute it, don't import an asset" approach as `hex_tile_texture.gd`), squashed into an oval
  (`tree_shadow_squash`) and given its own simpler shader (`tree_shadow_sway.gdshader`, a uniform sideways shift,
  no bend) with the SAME per-tree `phase`/`sway_speed` as the canopy (smaller `sway_amount_px`) so it visibly
  tracks its own tree, not some other one.

Every tunable (`tree_sway_amount_px`, `tree_sway_speed`, `tree_shadow_sway_fraction`, `tree_shadow_opacity`,
`tree_shadow_squash`, `tree_shadow_diameter_fraction`, `tree_shadow_offset`) is an `@export`/`@export_range` on
World, per `memory/feedback_expose_visual_tuning.md` -- fine visual tuning belongs in the Inspector, not another
round of code-and-reverify.

**Two real bugs found and fixed during verification, both worth recording**:

1. **The shadow sorted in front of its own tree instead of behind it.** The first version nudged the shadow
   "down and forward" by setting `shadow.position` directly. Y-sort (`features.y_sort_enabled`) reads a
   CanvasItem's own `position` to decide draw order, and that nudge made the shadow's global Y strictly greater
   than its own tree sprite's -- so Y-sort (correctly, by its own rule: greater Y draws later/"in front") painted
   the shadow ON TOP of the tree's lower trunk instead of underneath it. Fix: the shadow's node `position` stays
   at the root's exact origin (tied with the sprite, so sibling order -- shadow added as child 0 -- decides it,
   same trick `_test_feature_overlap_depth_rule` already relies on for ordinary features); the visual "nudge
   down" moved into the shader instead (`tree_shadow_sway.gdshader`'s `offset_px` uniform, applied to `VERTEX`),
   which happens entirely GPU-side after Y-sort has already run and so can never perturb it.
2. **The shadow was invisible even once correctly behind the tree.** This art's canopy hangs low, close to the
   ground-contact point, so a shadow sized/centered tightly under the trunk (the first attempt: diameter = 55%
   of tree width) was entirely hidden behind the foliage's own silhouette. Fixed by widening it
   (`tree_shadow_diameter_fraction` default raised to 0.9 of tree width) and increasing the downward shader
   offset (6px -> 14px) so its edges clear the canopy and it actually reads as a shadow on the grass. Confirmed
   via a real rendered screenshot, cropped and upscaled around a tree's trunk base.

**New tests** (`tests/run_tests.gd`, `_test_tree_sway_and_shadow`): the shadow is child 0 / sprite is child 1 (so
the shadow draws first/underneath); neither gets its own `z_index`; the shadow's node `position` is exactly
`Vector2.ZERO` (the regression guard for bug 1 above); both use the correct, distinct shaders; a tree's shadow
shares its canopy's exact `phase` (sync) while two different trees get different phases (desync, so a forest
doesn't sway in lockstep); the shadow's `sway_amount_px` is smaller than the canopy's but nonzero; and at least
one naturally-generated tree from the real `_build_features()` pass (not just a direct test call) has the
shadow too. Suite: 277/277, clean headless load.

Re-verified visually: a real rendered screenshot (`--rendering-driver opengl3`) of an actual forest cell, cropped
and upscaled, shows a clear soft oval shadow under the trunk; a second screenshot taken ~4.2 real seconds later
(timed via `Time.get_ticks_msec()`, not a frame count -- this environment runs an uncapped script-driven
`SceneTree` far faster than real-time, so a fixed frame count is not a reliable proxy for elapsed wall time) shows
the canopy visibly leaned over and the shadow shifted with it.

Also confirmed (re-derived from last session's lesson, extended): instantiating a full live scene
(`get_root().add_child(main)`, triggering real `_ready()`) hangs indefinitely under `--headless` even with no
`await RenderingServer.frame_post_draw` anywhere in the probe -- apparently any live scene instantiation needs
`--rendering-driver opengl3`, not just screenshot-taking probes specifically. `@onready` vars (e.g. `features`)
also aren't populated the instant `add_child()` returns inside a custom `SceneTree._init()`; a probe needs at
least a couple of `await process_frame` cycles first, same as the existing screenshot probes already did.

## 2026-10-27 — Animated flow arrows

User ask, continuing the look-and-feel detour: "please animated flow arrows next" (brief §6: "animated flow
arrows and well influence" is one of the few concrete asks in the visual-direction section).

**Implementation** (`scripts/rendering/flow_overlay.gd`): the shaft of each arrow is now a scrolling dash
pattern instead of one solid line, with the dashes moving from the cell center toward the arrowhead -- i.e.
visually "toward where the water is going," not just a generic sparkle. The scroll SPEED is scaled by the
arrow's own (already-clamped) pixel length (`dash_speed_factor`), so a fast well-capture cell's dashes visibly
race while a clay-constrained cell's barely creep -- the animation itself carries information (relative flow
magnitude) rather than just decorating every cell identically, the same "make the reason visible" spirit as the
arrow's length already being physically meaningful (design guardrail 6). The arrowhead stays a solid static
mark; only the shaft dashes, so the overlay still reads clearly as "arrow," not noise.

Unlike the tree sway (a GPU vertex shader, since Sprite2D textures have UVs to bend along), this overlay only
ever issues raw `draw_line()` calls in `_draw()` -- no texture, so no UV to drive a fragment shader with. Animated
it the direct way instead: a new `_process(delta)` accumulates `_time` and calls `queue_redraw()` every frame
(guarded by `if not visible: return`, since this overlay defaults OFF in `scenes/main.tscn` and is toggled by the
F key -- no point re-issuing hundreds of draw calls a frame for an overlay nobody can see), and `_draw_arrow`
picks the dash pattern's phase from `_time * shaft_len * dash_speed_factor`.

The dash-segment math is split into a pure static `_dash_segments(total_len, dash_len, gap_len, phase) ->
Array[Vector2]` -- same "separate the math from the drawing" discipline `flow_solver.gd` already follows for the
numerics, and the same reason `_flow_vector` was already split out this way -- so the scrolling logic is
testable without a live draw context. New tunables (`dash_length_px`, `dash_gap_px`, `dash_speed_factor`) are
`@export_range` on FlowOverlay, per the usual practice (`memory/feedback_expose_visual_tuning.md`).

**New tests** (`tests/run_tests.gd`, `_test_flow_overlay_dash_segments`): a zero-length shaft produces no
segments; a known phase=0 case matches hand-computed segment positions exactly; every segment stays clipped
inside `[0, total_len]` regardless of how large phase gets; increasing phase shifts a dash toward larger t (i.e.
toward the arrowhead, not backward -- the exact kind of sign-flip bug `_flow_vector`'s own test guards against
for the vector itself); the pattern exactly repeats every `dash_length + gap_length` of phase. Suite: 284/284,
clean headless load.

Re-verified visually (`--rendering-driver opengl3`): a real screenshot of the strongest-flow cell on the map
(found by scanning `_flow_vector` magnitude across every cell, not guessed), cropped and upscaled, shows the
expected dashed shaft + solid arrowhead. A second screenshot ~1 real second later (`Time.get_ticks_msec()`-gated,
not a frame count -- same lesson as the tree-sway verification) shows the dashes visibly shifted along the
shaft. One false alarm during this check, worth recording: an earlier attempt at ~1.7s elapsed showed two
seemingly-identical screenshots -- not a bug, but `dash_speed_factor * shaft_len` and the ~1.7s gap happened to
land within half a pixel of a whole number of dash periods (confirmed by reading `flow_overlay._time` directly
before each screenshot: it HAD advanced correctly, 0.08s -> 1.72s, matching real elapsed time). Any periodic
animation check needs a wait duration that isn't a near-multiple of the period, or the comparison is meaningless
by coincidence, not because nothing moved.

## 2026-10-27 — Animated water shimmer

User ask, continuing the look-and-feel detour: "water shimmer next please. Please provide slider to adjust it."
(brief §6 names "pixel-art terrain" and mood lighting; this is the water-surface half of that, after trees and
flow arrows.)

**Implementation** (`scripts/rendering/water_shimmer_overlay.gd`, `scripts/rendering/shaders/water_shimmer.gdshader`):
a new always-on overlay (NOT x-ray-gated -- ambient mood only, never obscures simulation data, per brief §6's own
"never obscure critical simulation information"), inserted in `scenes/main.tscn` right after `Ground` and before
`GridOutline` so the grid/shore lines still draw crisply on top of it. For every water cell (`World._river_cells`
-- confirmed the ONLY source of `TERRAIN_WATER`, see `_terrain_for`), it draws one translucent hex polygon
using the exact same `HexMath.hex_points()` + `World.TILE_SIZE` scaling `grid_outline.gd` already uses (tested
directly against `GridOutline._outline_points()` so the two can never silently drift apart). A single
canvas_item fragment shader on the whole overlay node paints one shared moving diagonal glint band in WORLD
space across every water polygon at once -- deliberately one continuous phase, not a per-cell random one (unlike
the trees' deliberately-desynced phase): light glinting off a lake should read as one surface, not independently
sparkling tiles. Same "GPU animates, GDScript just redraws flat shapes every frame" split as `tree_sway.gdshader`,
so the cost stays flat regardless of water cell count.

**New sliders** (WaterShimmerOverlay, Inspector, per `memory/feedback_expose_visual_tuning.md`): `shimmer_color`
(base translucent wash), `shimmer_speed`, `shimmer_scale` (glint band spacing), `shimmer_strength` (how much
extra opacity the band adds at its peak), `shimmer_band_sharpness` (narrow crisp glints vs. broad soft waves).

**One real bug found and fixed during verification**: the shader's first version brightened the glint by adding
to `COLOR.rgb`, and `shimmer_color`'s default is near-white -- additively brightening an already-near-white base
clamps invisibly (white plus anything is still white), so the very first screenshot showed no visible shimmer at
all despite the shader compiling and running correctly. Fixed by modulating `COLOR.a` instead: the glint band
now boosts the translucent wash's OPACITY rather than its color, which both fixes the visibility bug and reads
more like real water (a brighter, more-opaque glint flaring in and fading out) than a flat color shift would
have. Caught by a real rendered screenshot, not by code review -- this specific failure mode (additive
brightening clamping invisibly against a white base) has no headless-testable signature; only actually rendering
it shows it.

**New tests** (`tests/run_tests.gd`, `_test_water_shimmer_overlay`): `configure()` is given exactly the water
cells and nothing else (checked against `World._terrain_for` as ground truth, not just a count); the shimmer
polygon's geometry exactly matches `GridOutline`'s independently-derived hex outline, corner for corner. Same
"drawn, not tested headlessly" scope as every other `_draw()`-based overlay in this project (`GridOutline`'s
shore edges, `FlowOverlay`'s arrow geometry) -- the moving glint itself lives entirely in the GPU shader, nothing
pure-math to unit-test there. Suite: 314/314, clean headless load.

Re-verified visually (`--rendering-driver opengl3`): a real screenshot centered on a cluster of water cells
(picked from the actual generated river, not guessed) shows a clear diagonal bright band across the water. A
second screenshot ~2.3 real seconds later (`Time.get_ticks_msec()`-gated, chosen deliberately not to be a
near-multiple of the shimmer's own period, per the flow-arrows entry's lesson) shows the band visibly shifted
along the diagonal.

## 2026-10-27 — Ambient day/night mood lighting (CanvasModulate)

Last item from the trees/water/flow "alive, beautiful, precious" look-and-feel pass. Added
`scripts/rendering/mood_lighting.gd` on a new `MoodLighting` node (a `CanvasModulate`, between
`WaterShimmerOverlay` and `GridOutline` in `scenes/main.tscn`). `CanvasModulate` tints every `CanvasItem` in the
main viewport at once -- the same "the engine does the per-pixel work, GDScript just updates one value every
frame" cost profile as the other mood passes, except here there's nothing to draw at all, just one `Color`
property to set.

Cycles `day -> dusk -> night -> dusk -> day` on a continuous loop: a pure `_phase_color(phase, day, dusk, night)`
function (phase wraps every 1.0, four evenly-spaced stops, straight `Color.lerp` between neighbors) wrapped by
`_cycle_color(time, duration, ..., strength)`, which maps elapsed time to phase via `cycle_duration_sec` and
blends the result toward `Color.WHITE` by `strength` -- same "separate the math from the drawing" split as
`FlowOverlay._dash_segments` and `WaterShimmerOverlay`'s outline math, and fully testable headlessly since the
whole effect is one deterministic color computation with no shader/GPU step involved.

**Design choice: deliberately gentle, not a real night.** `night_color` is a dim, cool blue-grey
(`Color(0.4, 0.45, 0.65)`), never black, and `strength` defaults to `0.5` (halfway toward `Color.WHITE`) rather
than `1.0`. This directly follows the brief's §6 guardrail that ambient/mood effects must never obscure critical
simulation information -- `CanvasModulate` tints *everything* in the canvas, including the x-ray overlays, the
plume fill, and flow arrows, since they're ordinary `CanvasItem`s in the same viewport with no special exemption.
A full-strength, near-black night would risk making those unreadable at the cycle's dark end; confirmed in the
verification screenshots below that UI/label text stays legible even at a strong tint.

**Sliders**, all on the `MoodLighting` node (per `memory/feedback_expose_visual_tuning.md`): `day_color`,
`dusk_color`, `night_color` (the three-stop palette), `cycle_duration_sec` (how long one full day/night loop
takes), `strength` (0 = no tint at all, 1 = the full undiluted palette).

**New tests** (`tests/run_tests.gd`, `_test_mood_lighting`): each of the four phase stops (0.00/0.25/0.50/0.75)
returns its exact palette color; phase 1.0 matches phase 0.0 (the loop has no seam); a between-stops phase is a
straight lerp; `strength=0.0` always returns `Color.WHITE` regardless of time/duration; `strength=1.0` at the
half-duration mark returns the exact, undiluted night color; `strength=0.5` returns the color halfway to white;
scaling `cycle_duration_sec` scales the period rather than shifting it (the same *fraction* of two different
durations lands on the same color). All pure math, no node/Viewport needed. Suite: 324/324, clean headless load.

Re-verified visually (`--rendering-driver opengl3`, `cycle_duration_sec` and `strength` overridden in the probe
only, to 4.0s/1.0 respectively, so a real shift is visible within a short wait -- the scene's own slower/subtler
defaults would be too gradual to tell apart from noise in a quick screenshot diff): a screenshot at `_time=0.16s`
(`color` near-white, `(1.0, 0.95, 0.92)`) versus one ~2.16s later at `_time=2.32s` (`color` dimmed and cooled to
`(0.59, 0.52, 0.60)`, past the dusk stop and heading into night) shows the whole scene visibly darker and
cooler-toned in the second frame, with the status-panel text still fully readable in both.

## 2026-10-29 — Water effects: shoreline ripples; seamless connected water; glints replace the scrolling band

The user reported the water shimmer from 2026-10-27 "looks too static" and asked for three specific things:
shoreline ripples on edges that border land; a seamless water surface where individual hex boundaries aren't
visible; and occasional world-space glints instead of one continuously scrolling band.

**Shoreline ripples (new file, `scripts/rendering/shoreline_ripple_overlay.gd` + new `ShorelineRippleOverlay`
node in `scenes/main.tscn`, between `GridOutline` and `Features`).** For every water cell, checks all 6
neighbors (not just 3) and draws a small, pale, dashed line just inside the water, inset toward the hex centre by
`ripple_inset_fraction`, on any edge whose neighbor is real, placed, non-water. Deliberately NOT built on
`GridOutline`'s existing `_is_shore_edge` -- that one is intentionally restricted to the 3 camera-facing north
edges (a one-direction "cliff face" illusion, see its header comment), which is the wrong rule for a ripple: real
water laps at land on every side it touches, regardless of which way the camera happens to be facing. Dash
geometry reuses `FlowOverlay._dash_segments` (literally the same function, duplicated rather than imported so
the overlay stays self-contained) to scroll broken dashes along each shore edge; opacity additionally pulses per
edge via a new `_pulse()` function, phase-offset per edge by `World._pseudo_random01(axial, edge_index + 101.0)`
so the whole shoreline doesn't flash in lockstep -- each edge reads as its own small wave lapping in and
receding on its own timing, not a synchronized strobe.

**Seamless connected water (`grid_outline.gd`, not a new file).** Investigated why water read as a lattice of
individual hexes despite the shimmer shader already being world-space-continuous: `GridOutline` draws its
permanent grey grid line on *every* edge of *every* cell, water included, except where `_is_shore_edge` swaps in
the darker cliff-cue line -- so two adjacent water cells still got an ordinary grey line drawn straight across
their shared, fully-open interior edge. That line, not the shimmer shader, was the actual "individual tile
boundaries visible" culprit. Added `_is_water_interior_edge(axial, offset, edge_index)` (true iff both the cell
and its neighbor across that edge are real, placed water) and a new `_ALL_EDGE_NEIGHBOR_OFFSETS` table (all 6
edges, extending the existing 3-edge `_SHORE_EDGE_NEIGHBOR_OFFSETS` derivation) -- `_draw()` now skips the edge
entirely (no line, either color) whenever this is true. Land-land edges and shore (water-land) edges are
unaffected. This is a one-line geometry fix, not a shader or mesh change -- no need to union hex polygons into a
single mesh (the shader was already seamless; only the separately-drawn grid lines on top of it weren't).

**Occasional glints replace the scrolling band (`scripts/rendering/shaders/water_shimmer.gdshader`,
`water_shimmer_overlay.gd`).** The single continuously-scrolling diagonal band (2026-10-27's version) is the
same motion forever once you watch it for more than a few seconds -- correctly read as "static" even though it
was technically moving. Replaced with a jittered-grid point-glint scatter: world space is divided into
`glint_cell_size`-px lattice cells, each cell gets one pseudo-randomly jittered point (`hash22`), and each point
flashes briefly on its own randomized cycle (`hash11`-derived phase, `glint_frequency` flashes/sec,
`glint_duration` fraction of each cycle visible, a `sin(t*PI)` rise-then-fall for a smooth pulse rather than a
hard on/off). A pixel's own `world_pos` (unchanged from the prior version's vertex-shader varying) is still what
makes this continuous across hex polygon boundaries -- which lattice cell a glint belongs to, and when it
flashes, depends only on world position and `TIME`, never on which polygon is currently being rasterized under
it, so a glint never "restarts" at a hex edge. New export `glint_tint`/`glint_tint_strength` lets a glint also
shift colour (via `mix`, not addition -- stays visible against a near-white base, unlike the additive-RGB bug
from 2026-10-27's entry) on top of the existing alpha-boost mechanism. All five old band exports
(`shimmer_speed`/`shimmer_scale`/`shimmer_strength`/`shimmer_band_sharpness`) are gone, replaced by
`glint_cell_size`, `glint_radius_px`, `glint_frequency`, `glint_duration`, `glint_strength`, `glint_tint`,
`glint_tint_strength` -- the user's prior Inspector tuning on the old names no longer applies; removed the stale
overrides from `scenes/main.tscn` rather than leave them silently ignored.

**New tests** (`tests/run_tests.gd`): `_test_grid_outline_water_interior_edges` -- the new `_ALL_EDGE_NEIGHBOR_
OFFSETS` table is geometrically verified (each entry actually points toward its matching edge, same check as the
existing shore-edge test) rather than just asserted, then a 3-cell connected lake confirms both directions of a
water-water edge are interior (symmetric) while the lake's actual land-facing ends are not.
`_test_shoreline_ripple_overlay` -- same geometric verification for `_EDGE_NEIGHBOR_OFFSETS`, confirms a water
cell's south edge (not just north) counts as a ripple shore edge when it borders land (the deliberate difference
from `GridOutline`'s camera-restricted rule), confirms open water-to-water isn't a ripple edge, re-checks the
reused dash-segment math against the known case from `_test_flow_overlay_dash_segments`, and checks `_pulse` stays
within `[ripple_pulse_min, 1.0]`, is periodic, and that two different phase offsets actually produce different
values at the same instant (one iteration needed: the first version compared `phase01=0.0` against `phase01=0.5`,
which coincidentally land on the same `sin` value one full half-cycle apart -- fixed by using `phase01=0.25`
instead). The glint shader itself has no headless-testable signature, same "drawn, not tested headlessly" scope
as every other GPU-side effect in this project. Suite: 337/337, clean headless load.

Re-verified visually (`--rendering-driver opengl3`, zoomed into a river stretch, glint density/strength bumped
in the probe only for a clearer screenshot at this zoom): the screenshot shows the river reading as one
continuous water surface with no grid line down its center, pale dashed ripples along every edge bordering grass
on both banks (not just the north-facing ones), and several small glint points scattered across the water. A
second screenshot 1.4 real seconds later shows some glints faded out, new ones appeared at different positions,
and the ripple dashes have visibly scrolled -- confirming occasional, independently-timed sparkles rather than
one coherent shape in constant motion.

## 2026-10-29 — Amended shoreline ripples: wash inward, don't scroll along the shore

The ripple motion in the entry above was wrong on reflection -- the user clarified it should NOT move parallel
along the shoreline (a tangential scroll) at all: a real shoreline ripple appears right at the water's edge,
washes a couple pixels inward toward shore, then fades -- a perpendicular in-and-out motion, not a sideways
drift. Also sharpened "different shoreline segments animate at different times" to mean each individual broken
dash, not just each hex edge.

Reworked `shoreline_ripple_overlay.gd`: `_dash_segments` is now called once with a fixed `phase=0.0` (the broken
dashes along an edge are a static layout, never scrolling tangentially) instead of a time-driven scroll phase.
Replaced `_pulse()` (opacity-only, floored so it never fully vanished) with `_ripple_state(time, speed, phase01,
active_fraction, max_expand_px)`, which returns both an alpha multiplier AND an inward-drift distance together:
at the start of a ripple's own active window it sits exactly at the true edge (drift=0), by the window's end it
has washed to `max_expand_px` (drift scales linearly with the same progress `t` that drives alpha), and alpha
itself rises then falls via `sin(t * PI)` so it's a smooth appear-expand-fade rather than a hard cut -- and
outside its active window it's fully invisible (not dimmed to a floor the way the old `_pulse` was), a real gap
before that same dash ripples again. The inward direction is computed per edge from the two hex corners it
connects (`-(corner_a + corner_b).normalized()`, pointing from the edge toward the hex's own centre) and applied
as a uniform translation to both endpoints of a dash -- the dash's position along the edge (tangential) never
changes, only its distance from the edge (perpendicular).

Per-segment desync: each individual dash (not just each edge) now gets its own phase via
`World._pseudo_random01(axial, 101.0 + edge_index*7.0 + dash_index*13.3)`, baking the dash's own index into the
salt -- so two dashes on the SAME edge ripple independently, not just two different edges, matching "different
shoreline segments" literally rather than per-edge-only.

Removed exports: `ripple_inset_fraction` (a ripple's distance from the edge is now a function of its own
animation progress, not a fixed static setting) and `ripple_scroll_speed_px_s`/`ripple_pulse_speed`/
`ripple_pulse_min` (replaced by `ripple_max_expand_px`, `ripple_cycle_speed`, `ripple_active_fraction`).

**Updated tests**: replaced the `_pulse` checks with `_ripple_state` checks -- fully zero (not dimmed) outside the
active window; `drift=0` at the very start of a window; `drift` reaches near `max_expand_px` by the window's end;
alpha peaks near the window's middle rather than jumping on/off; periodic over one full cycle; a different
`phase01` changes the state at the same instant (segments desync). Suite: 340/340, clean headless load.

Re-verified visually (`--rendering-driver opengl3`, `ripple_cycle_speed`/`ripple_max_expand_px`/
`ripple_active_fraction` bumped in the probe only for a clearer diff over a short wait): two screenshots 636ms
apart, zoomed on a single water hex's shoreline, show a different subset of dashes lit along the edges each
frame (some faded that were visible before, others newly appeared) -- the appear/fade behavior is clearly live;
the pure `_ripple_state` math above is what's actually verified for the inward-wash-not-sideways-scroll claim,
since that distinction is finer than this screenshot pairing can show by eye at normal dash speeds.

## 2026-10-29 — Ripples now start past GridOutline's dark cliff line, not underneath it

The user asked for ripples on the 3 north-facing edges (N/NW/NE) to start beyond/below GridOutline's existing
dark "shore_line" cliff cue, not underneath/overlapping it.

Added `_cliff_inset_px(edge_index)` to `shoreline_ripple_overlay.gd`: 0 on any edge without a cliff line (no
`_grid_outline` wired, or the edge isn't one of GridOutline's 3 camera-facing shore indices); on a cliff edge,
returns `shore_line_width` (straight north) or `shore_line_width_diagonal` (NW/NE) -- read from a live
`_grid_outline` node reference, not a duplicated magic number, so retuning the cliff line's width in the
Inspector keeps the ripple's start position correct automatically. `_draw()` now adds this as a constant base
offset on top of each ripple's own animated inward drift (`drift = inward_dir * (base_inset + state.y)`), so a
cliff-edge ripple's full travel range is `[cliff_width, cliff_width + ripple_max_expand_px]` instead of
`[0, ripple_max_expand_px]` -- it still appears, washes inward, and fades exactly as before, just starting from
further in. `configure()` gained an optional third `grid_outline: Node2D = null` parameter (defaults to the old,
pre-this-feature behavior if omitted); `world.gd` now passes its own `grid_outline` node through.

Also took the opportunity to delete `_EDGE_NEIGHBOR_OFFSETS`, the local 6-entry copy of GridOutline's
`_ALL_EDGE_NEIGHBOR_OFFSETS` table (added 2026-10-29, duplicated at the time specifically so this file had no
GridOutline dependency) -- now that `_cliff_inset_px` has made that dependency real and intentional anyway,
keeping two independently-derived copies of the same geometry table serves no purpose and is exactly the kind of
drift risk this project avoids elsewhere (`GridOutline`/`HexSelection`'s shared `grid_size`,
`PlumeOverlay`/`HeadContourOverlay`'s shared triangle-lattice offsets). `_is_shore_edge` now reads
`GridOutline._ALL_EDGE_NEIGHBOR_OFFSETS` directly.

**Updated tests**: the now-redundant standalone geometric check of the deleted local table was removed (the
identical check already exists against `GridOutline._ALL_EDGE_NEIGHBOR_OFFSETS` in
`_test_grid_outline_water_interior_edges`, and that table is now literally the same one this file uses, not a
separate derivation to re-verify). Added direct `_cliff_inset_px` checks: 0 on all 3 non-cliff edges even with a
`GridOutline` wired; the straight-north edge's inset exactly matches a test `GridOutline` instance's own
`shore_line_width`; both diagonal edges match `shore_line_width_diagonal` instead. Suite: 343/343, clean headless
load.

Re-verified visually (`--rendering-driver opengl3`, cliff line widths exaggerated to 10px/8px and ripple timing
forced to fully-visible in the probe only, so the effect is unambiguous at this zoom): a screenshot of a water
cell with real land to its north and northwest shows the dark cliff lines on those two edges with the pale
ripple dashes clearly sitting past them, not under them -- while the plain grass-bordering edges (no cliff line
there) still show ripples starting right at the true edge, unchanged from before this amendment.

## 2026-10-29 — Slow-moving cloud shadows (new overlay, world-space, not per-hex)

The user asked for slow-moving cloud shadows, explicit about the architecture: "a world-space overlay covering
multiple hexes, rather than shading individual tiles."

Added `scripts/rendering/cloud_shadow_overlay.gd` (new `CloudShadowOverlay` node in `scenes/main.tscn`, right
after `ShorelineRippleOverlay`, before `Features`) + `scripts/rendering/shaders/cloud_shadow.gdshader`. Literally
ONE static rect, sized once to the map's own bounding box plus a margin, covers the whole map in a single draw
call -- not one shape per hex. All of the actual cloud shape/motion lives in the fragment shader, sampling a
fractal value-noise field (`hash12` -> `value_noise` -> 4-octave `fbm`, same hash-based "no texture lookup, no
RNG to manage" family as `water_shimmer.gdshader`'s glints) in WORLD space via the same `world_pos` vertex-shader
varying pattern used there -- the noise field is one continuous surface under the whole map, so a cloud drifting
across never restarts or seams at a hex boundary, and critically was never evaluated "per tile" at all: the GPU
just paints whatever the noise function says at each pixel's own world position, regardless of which (if any)
hex that pixel happens to be over. Motion is `world_pos + cloud_speed_px_s * TIME` fed into the noise -- the
rect itself never moves or resizes; the apparent drift is entirely the noise coordinates scrolling.

**Efficiency note, not just a style choice:** unlike every other animated overlay in this project,
`cloud_shadow_overlay.gd` does NOT call `queue_redraw()` every frame. Its one rect's shape never changes, and a
`ShaderMaterial`'s `TIME`-driven fragment code is re-evaluated by the GPU every rendered frame regardless of
whether the CPU reissues draw commands -- `queue_redraw()` is only needed when the draw commands THEMSELVES must
change each frame (true for `FlowOverlay`'s dash positions and `ShorelineRippleOverlay`'s inset/alpha, computed
in GDScript from `_time`; not true here, or for `WaterShimmerOverlay`'s static hex polygons, whose glint is 100%
GPU-shader-driven too).

**Layering, chosen deliberately for the brief's §6 guardrail** (ambient mood must never obscure critical
simulation information): placed after `ShorelineRippleOverlay` but before `Features` in the scene tree, so a
cloud shadow dims the ground/grid/water plane but renders UNDER tree/rock/decal sprites and under every x-ray
data overlay (`GeologyOverlay`/`HeadContourOverlay`/`PlumeOverlay`/`FlowOverlay`, all later in the tree) --
confirmed directly in the visual verification below (a probe run with `cloud_coverage=1.0` and a fully opaque
color replaced every grass/sand/water tile with solid color while every tree, rock, flower, and the well/
receptor markers stayed completely unaffected on top of it). Always visible, NOT x-ray-gated, same reasoning as
`water_shimmer_overlay.gd`: ambient-only, never simulation data.

Sliders (`memory/feedback_expose_visual_tuning.md`): `cloud_color` (including alpha -- how dark a cloud's
densest point gets), `cloud_scale` (noise frequency -- smaller clouds need a larger value), `cloud_speed_px_s`
(drift velocity, a `Vector2` so direction and speed are one setting), `cloud_coverage` (how much of the sky is
in shadow), `cloud_softness` (edge blur of a cloud's silhouette). Defaults are deliberately slow/subtle
(`cloud_speed_px_s = (6, 2.5)`, `cloud_coverage = 0.45`) per the user's explicit "slow-moving" ask.

**New tests** (`tests/run_tests.gd`, `_test_cloud_shadow_overlay`): the noise shader itself has no
headless-testable signature (same "drawn, not tested headlessly" scope as every GPU noise effect in this
project), but the bounding-rect geometry it's painted onto is pure and fully tested: an empty position list
produces an empty `Rect2` rather than crashing; a known 3-point set produces a rect whose corners are exactly the
tightest bounding corners minus/plus the margin (not padded more than asked); every point in the set lands inside
the result; and, on a real generated map, every actual cell center lands inside the configured bounds -- the
whole point of a single map-spanning rect is that a cloud can cross any hex, so there must be no gap at the
map's own edge. Suite: 351/351, clean headless load.

Re-verified visually (`--rendering-driver opengl3`, zoomed far out to see the whole map in one frame, coverage/
color boosted in the probe only for a clear screenshot at normal map-art contrast -- the real defaults are
intentionally subtler). First pass with `cloud_coverage=1.0` and an opaque magenta color confirmed the
layering claim above (ground replaced, decorations untouched). Second pass at a realistic-but-visible strength
(`cloud_coverage=0.55`, a dark blue-grey at 0.8 alpha) showed a soft diagonal dark band crossing several hexes
with no visible seam at any tile edge; a second screenshot ~2.6 real seconds later shows that band had visibly
shifted and reshaped -- confirming both the "multiple hexes, one continuous surface" architecture and genuine
drift over time.

2026-10-29 -- Cloud shadows moved above Features (trees/rocks/decals)
-----------------------------------------------------------------------
User's ask: "the cloud shadows need to be the top layer - on top of trees, decals, rocks, etc." The initial
placement (right after ShorelineRippleOverlay, before Features) deliberately kept clouds under tree/rock
silhouettes per the brief's §6 "never obscure critical simulation information" guardrail -- but the user wants
the visual effect of a cloud passing over everything on the ground, decorations included.

Fix: in scenes/main.tscn, moved the CloudShadowOverlay node (and the still-unwired CloudShadowOverlay2 node
alongside it -- see note below) to right after Features in the scene tree, instead of right before it. It is
now drawn on top of trees/rocks/decals, but still BELOW every x-ray data overlay (GeologyOverlay,
HeadContourOverlay, PlumeOverlay, FlowOverlay, HexSelection, DebugOverlay) -- preserving the one part of the
original guardrail that still matters: ambient mood must never obscure simulation data, but it's fine for it to
darken decorative silhouettes, which is exactly what the user asked for. Updated cloud_shadow_overlay.gd's
header comment to match. No shader or script logic changed -- this was purely a node-order change.

Note found while making this change: the scene has two CloudShadowOverlay nodes ("CloudShadowOverlay" and
"CloudShadowOverlay2") with identical parameters, but world.gd only ever does
`@onready var cloud_shadow_overlay: Node2D = $CloudShadowOverlay` and only configures that one node -- the
second one is never configured, so its `_bounds_rect` stays `Rect2()` and its `_draw()` returns immediately
without drawing anything (dead/inert). Left as-is since removing or wiring it up wasn't asked for; flagged to
the user in the chat response.

Suite: 351/351, clean headless load. No new automated test needed (pure node-reorder, no new behavior to
assert beyond what's already covered); re-verified by inspection that Features is now listed before
CloudShadowOverlay and CloudShadowOverlay comes before DebugOverlay in scenes/main.tscn.

2026-10-29 -- Rainfall events
-----------------------------------------------------------------------
User's ask: "add rainfall events: Clouds covers all tiles. Visible drops/short lines. Rain should produce
expanding circular ripples on water tiles, wet ground darkens, tree sway intensifies, and the ambient sound
changes (lateR)." Ambient sound explicitly deferred by the user ("later") -- not attempted this pass.

Architecture: ONE new node, RainController (rain_controller.gd, extends Node, no drawing of its own), owns
just the timing/intensity state machine -- a real-time ramp 0 -> 1 -> 0 per event (_intensity_for, a pure,
tested function: fade in over fade_s, hold at 1.0, fade out over fade_s; degrades to a triangular pulse for
a short event where fade-in and fade-out overlap, rather than snapping to a plateau that doesn't exist).
Between events it waits a random real-time gap in [min_interval_s, max_interval_s] (auto_events); force_rain
is a one-shot Inspector trigger for testing without waiting on the schedule, same "expose it, don't hand-tune
blind" practice as the rest of this project (memory/feedback_expose_visual_tuning.md). Every reactive system
reads RainController.intensity directly off a shared reference every frame -- the same "configure once, read
a shared data source every frame" pattern GridOutline/HexSelection already use for grid_size -- rather than a
signal fan-out, since every consumer already gets configured with references to shared nodes (ground, model,
grid_outline) this same way.

Each of the user's five asks maps to one existing or new piece, deliberately NOT a pile of new overlay classes:
- "Clouds covers all tiles": CloudShadowOverlay (already built 2026-10-29 for ordinary drifting clouds) gained
  set_rain_intensity(t), lerping cloud_coverage/cloud_color toward new storm_coverage (default 1.0 -- the
  user's literal "all tiles") / storm_color exports. A storm is this same mechanism pushed to its extreme,
  not a second cloud system.
- "Visible drops/short lines": a new RainOverlay (CanvasLayer + full-viewport ColorRect + rain_streaks.gdshader).
  Screen-space, not world-space, like the HUD -- streak size/speed must read the same regardless of camera
  zoom. The shader hashes the screen into per-pixel-sized vertical "lanes," each either empty or carrying one
  falling streak (FRAGCOORD-based, so it's resolution-independent and needs no vertex-stage world_pos). Hit one
  real Godot shader-language constraint while wiring this up: an early `return` inside fragment() is a SHADER
  ERROR ("Using 'return' in the 'fragment' processor function is incorrect") -- fixed by replacing the
  early-exit with a multiplicative `lane_mask` folded into the final alpha instead.
- "Expanding circular ripples on water tiles": a new RainRippleOverlay (Node2D), a DIFFERENT effect from
  shoreline_ripple_overlay.gd's dashed shore-edge wash -- plain growing/fading rings spawned at random jittered
  points across the water cells themselves (not the shoreline), at a rate scaled by intensity. CPU-driven (ripple
  birth/death times and positions are decided on the CPU), so unlike CloudShadowOverlay this DOES need a
  per-frame queue_redraw() -- same category as FlowOverlay/ShorelineRippleOverlay. _ripple_radius/_ripple_alpha
  are pure linear growth/fade curves, tested headlessly; the random spawning itself is only verified visually.
- "Wet ground darkens": no new overlay at all -- World._apply_rain_effects() lerps Ground's own `modulate`
  from WHITE toward a new wet_ground_tint export as intensity rises. There was no drawing of its own to add; an
  existing TileMapLayer property was the whole job.
- "Tree sway intensifies": tree sway materials were never kept around after _build_features() (unlike the
  geology/well exports, there was no live-tuning hook for them at all before this). Fixed minimally: every
  tree's sway ShaderMaterial (and its shadow's) is now appended to _tree_sway_materials/_tree_shadow_sway_materials
  as it's built, and _apply_rain_effects() pushes a rain-boosted sway_amount_px/sway_speed to all of them each
  frame (World._boosted_for_rain, a pure lerp-to-multiplier helper, tested). As a side effect, ordinary
  Inspector edits to tree_sway_amount_px/tree_sway_speed now also take effect live during play, the same
  "live-tuning" fix _refresh_geology_parameters already established for the K/porosity sliders -- not a new
  concept, just extended to a value that had been missed.

Suite: 382/382 (31 new assertions: RainController's intensity ramp shape including the short-event/zero-fade/
zero-duration edge cases, RainRippleOverlay's radius/alpha curves and configure()/spawn wiring against a live
fake RainController, World._boosted_for_rain's clamping, and World._apply_rain_effects actually reaching real
tree materials and Ground's modulate on a built map). Clean headless load.

Verified with a real --rendering-driver opengl3 screenshot: forced a rain event straight into its held
(intensity == 1.0) plateau rather than waiting on fade_s/min_interval_s real seconds (same "jump to the
extreme, confirm the mechanism" approach as every other shader-driven overlay here). The screenshot shows
diagonal white streaks covering the whole viewport, a fully overcast dark sky, visibly darker/cooler ground,
and one ripple ring already growing on the river -- all simultaneously, with trees/features/HUD still drawn
correctly on top/behind as expected. A second screenshot, intended ~2.5 real seconds later, instead landed
~422 real seconds later (this dev machine's opengl3 software path renders this many simultaneous shaders very
slowly under the scripted probe) -- which incidentally became a second, unplanned confirmation: RainController's
own real-time duration (60s) had elapsed by then, so intensity had correctly fallen back to 0, and every
reactive system (cloud coverage, ground tint, streaks, ripples) had cleanly reverted to baseline right along
with it, with nothing left stuck in a "rained on forever" state.

Noted, not fixed: the same pre-existing dead "CloudShadowOverlay2" node flagged in the entry above is still
present and still unwired -- untouched again this pass.

2026-10-29 -- Rain streaks were falling bottom-to-top; added a direction handle; removed the dead CloudShadowOverlay2
-----------------------------------------------------------------------
User report: "the [rain] is failing from the bottom to the top. Is there a way to change its direction (add
handle). We also have two CloudShadowOverlay which both seem to have the same options."

Rain direction bug: rain_streaks.gdshader computed each lane's falling position as
`mod(p.y + fall_speed_px_s * TIME + phase, tile_height_px)`. Worked through on paper: for a fixed screen
pixel to stay lit as TIME advances, its own p.y has to counter-shift by -fall_speed_px_s*TIME to stay inside
the active window -- meaning the lit position actually drifts toward SMALLER p.y (up the screen, since Y
increases downward) as TIME grows, regardless of fall_speed_px_s's own sign. Fixed by subtracting instead of
adding: `mod(p.y - fall_speed_px_s * TIME + phase, tile_height_px)`. Verified with a lightweight probe
(rain_overlay.gd instantiated alone, not the whole main.tscn -- the full-scene rain probe from the entry above
took ~7 real minutes per pair of screenshots on this machine, too slow to re-run for a one-line sign check) --
two screenshots ~0.35 real seconds apart show the same streak clusters clearly shifted DOWN-and-slightly-right
(wind drift) between frames, not up.

Direction handle: fall_speed_px_s's Inspector range was hint_range(100, 3000) -- positive-only, so flipping
direction required editing the shader/script. Widened to hint_range(-3000, 3000) in both the shader and
rain_overlay.gd's matching @export_range: the sign now IS the fall direction (positive = down, the normal
case; negative = up), draggable from the Inspector, same "expose it, don't hand-tune blind" practice as the
rest of this project.

CloudShadowOverlay2: confirmed (again) that world.gd only ever wires up `$CloudShadowOverlay` -- the second
node was always dead weight, now actually deleted from scenes/main.tscn instead of just flagged.

Suite: 382/382 (unchanged -- this was a sign fix, a range widen, and a dead-node deletion, nothing new to
assert). Clean headless load.

2026-10-29 -- Fixed extreme tree shaking at the start/end of a storm
-----------------------------------------------------------------------
User report: "at the beginning and end of the storm/rainfall events the trees shake extremely, please fix."

Root cause: tree_sway.gdshader computes each tree's lean as `sin(TIME * sway_speed + phase)`, where TIME is
the engine's total elapsed time since startup -- already large (seconds to minutes) by the time any storm
happens. _apply_rain_effects() (added for rainfall events, entry above) was pushing a rain-boosted sway_speed
to every tree's ShaderMaterial every single frame while RainController.intensity was fading in/out. Since
sway_speed multiplies that large TIME inside the sine, even a TINY per-frame change in sway_speed produced a
LARGE jump in the sine's argument -- e.g. TIME=600s and a sway_speed change of just 0.004 between two
consecutive frames shifts the argument by ~2.4 radians, nearly half a full cycle, in one frame. That reads as
violent, chaotic shaking, not a smooth wind-speed-up -- and explains exactly the symptom reported: it only
happens while intensity (and so sway_speed) is actively changing, i.e. the fade-in/fade-out windows at the
start/end of an event, and is absent mid-storm once intensity holds steady at 1.0.

Fix: stopped boosting sway_speed during rain entirely -- removed the rain_tree_sway_speed_boost export and the
per-frame `sway_speed` shader-parameter push from _apply_rain_effects(). Only sway_amount_px (amplitude) is
still rain-boosted; amplitude only scales the sine's OUTPUT, so varying it continuously every frame is
perfectly smooth -- no argument discontinuity, because TIME never multiplies it. "Tree sway intensifies"
(the original ask) is still satisfied: bigger-amplitude sway at a constant frequency reads as windier just
fine, without needing the frequency itself to change.

General lesson, worth remembering for any future TIME-based oscillator in this project: a uniform that
multiplies TIME inside a trig function must never be changed continuously at runtime from script -- doing so
retroactively reinterprets the entire elapsed history, not just the behavior going forward. If a speed-up
effect like this is ever wanted again, it needs a CPU-tracked accumulated phase (integrate speed*delta into a
running total each frame, pass THAT to the shader instead of raw TIME*speed) rather than a live uniform.

Suite: 382/382 (no new assertions -- this was a removal, not new behavior to cover; the existing
_test_world_rain_effects assertion on sway_amount_px boosting still passes). Clean headless load.

## 2026-10-29 — Sandbox toggle: `procedural_generation` export + World.gd made `@tool`

User's ask: open the map up so they can hand-build an initial level and try terrain settings, instead
of only ever getting the procedurally generated one.

Everything about Ground (TileMapLayer) and Features (trees/rocks/decals) was previously built from
scratch every single run, in World._ready(): _build_terrain() calls ground.clear() and repaints every
cell from GridModel's elevation field, and _build_features() wipes and rebuilds Features the same way.
Nothing hand-placed in the editor could ever survive pressing Play.

Fix has two parts:

1. `@export var procedural_generation: bool = true` (world.gd). True (default, unchanged behavior) ->
   _build_terrain()/_build_features() run exactly as before. False -> both are skipped at runtime, so
   whatever cells you painted on Ground / children you placed under Features while editing the scene
   are exactly what the running game shows.
2. World.gd is now `@tool` (first line of the script), purely so _build_tileset() can also run while
   editing the scene, not just at runtime -- that's the one thing required for Ground to actually HAVE
   a TileSet while the editor is open, which is what lets Godot's own hex tile-painting panel work on
   it at all. _ready() returns immediately after _build_tileset() when Engine.is_editor_hint() is true:
   no GridModel, HUD, or overlay setup ever runs while editing, only the tileset build. _process() and
   _unhandled_input() got the same Engine.is_editor_hint() guard as cheap insurance, even though plain
   Node callbacks aren't expected to fire in the editor anyway. Every exported setter that touches
   _model (sand_k_m_s, well_axial, ...) was already null-guarded, so they're harmless while editing too
   -- _model only gets created in the runtime branch.

Water-dependent overlays (water_shimmer_overlay, shoreline_ripple_overlay, rain_ripple_overlay) used to
get their water-cell list from `_river_cells` (the procedurally generated river path), which would be
empty for a hand-painted lake. Replaced with `_water_cells()`, which reads water cells straight off
Ground's actually-painted tiles (`get_cell_source_id(offset) == TERRAIN_WATER`) -- works identically
whether Ground was procedurally painted or hand-painted, since `_build_tileset()` always keys each
terrain's TileSet source id to the matching TERRAIN_* constant either way.

minimal_test_mode is a separate, orthogonal toggle (Test B anchor isolation) and is untouched by this.

Verified: 382/382 tests still pass (headless, Engine.is_editor_hint() is false there, so this is the
procedural_generation=true/unchanged path); clean `--headless --quit` boot; clean
`--headless --editor res://scenes/main.tscn --quit` boot too (exercises the new editor-hint _ready()
branch with no script errors).

## 2026-10-29 — Sandbox follow-ups: scenario markers always placed; data-driven `sandbox_features`

Two follow-ons to the sandbox toggle above, both from the same conversation.

**Scenario markers.** `_add_scenario_markers()` (source/well/receptor) was called from inside the same
procedural block in `_build_features()` as the random tree/rock/decal pass, so turning
`procedural_generation` off silently hid them too -- wrong, since they're positioned from fixed exports
(`source_axial`/`well_axial`/`receptor_axial`), not randomness. Restructured so the children-clear step
and the procedural loop are each individually gated on `procedural_generation`, while
`_add_scenario_markers()` always runs (outside minimal_test_mode). A hand-built sandbox level now still
shows exactly where the simulation's source/well/receptor are.

**`sandbox_features`.** User found hand-dragging a separate `Sprite2D` per tree/rock/decal under
`Features` too tedious and imprecise (no snapping aid against the hex grid). Added
`scripts/rendering/feature_placement.gd`, a plain `Resource` with four fields: `axial`, `texture`,
`is_tree`, `nudge`. `World.sandbox_features: Array[FeaturePlacement]` is a new export -- only consulted
when
`procedural_generation` is false. `_add_sandbox_features()` places each entry through the *exact same*
anchor code the procedural pass already uses (`_add_tree_feature` for `is_tree == true`, `_add_feature`
otherwise), so a hand-placed feature lands pixel-exact on its cell -- no manual `Sprite2D`, no
eyeballing. No scatter, same convention as the scenario markers: a chosen cell means that cell,
dead-center. An entry with no texture set is skipped, not a crash (an empty array slot the user hasn't
filled in yet).

Covered by `_test_world_sandbox_mode` (tests/run_tests.gd): a rock placement lands exactly at
`cell_centre_in_features()`, a tree placement gets the same contact-shadow + sway wiring
`_test_tree_sway_and_shadow` already checks for procedural trees, an empty-texture entry doesn't crash,
and scenario markers are present. Suite: 386/386. Clean headless boot and clean
`--headless --editor ... --quit` boot (the new
`Array[FeaturePlacement]` export resolves fine in the editor's Inspector).

## 2026-10-29 — DebugOverlay's axial labels now visible while editing, not just at runtime

User feedback: picking a texture in a sandbox_features entry "doesn't seem to connect/show up" --
correct, nothing in that whole pipeline runs until you press Play (see the @tool comment in world.gd).
But the actual blocker was worse than that: there was no way to even know WHICH axial (q, r) to type
into a sandbox_features entry while still editing -- unlike Ground, which you paint by clicking
directly (no coordinate needed), a hand-placed feature needs you to already know its cell's axial
value.

Fix: made hex_debug_overlay.gd `@tool` too (its only virtual is _draw(), nothing else to guard) and
had World's editor-hint _ready() branch call debug_overlay.configure(...) and force it visible,
independent of show_debug_overlay's runtime value. Its magenta crosshair + "%d,%d" axial label at
every cell center (already built for comparing procedural anchors, per its own header comment) is now
exactly what you read off to fill in a FeaturePlacement's `axial` field.

Still true, and worth being explicit about: no sandbox_features entry actually appears in the viewport
while editing -- that part is still Play-only. This fix only solves "what coordinate do I type", not
"preview the placement live" (that would need Resource.changed-signal wiring to react to Inspector
edits inside the typed array, a meaningfully bigger feature nobody's asked for yet).

Verified: 386/386 tests pass; clean `--headless --quit` boot; clean
`--headless --editor res://scenes/main.tscn --quit` boot.

## 2026-10-29 — `feature_placement.gd` needs `class_name` after all

User feedback: clicking the "New Resource" dropdown on an empty `sandbox_features` array slot showed
~300 generic options with no "New FeaturePlacement" shortcut anywhere. Root cause: this script had no
`class_name`, so it was never registered as a named type at all -- the editor's resource picker can
only offer a named shortcut, or let you search by name in the "Create New Resource" dialog, for a type
it actually knows the name of. An unnamed custom Resource script doesn't show up in that dialog under
any discoverable name, which is exactly the dead end the user hit.

Re-added `class_name FeaturePlacement`. The earlier "Could not find type FeaturePlacement in the
current scope" parse error (which was the reason it got dropped in the first place) turned out NOT to
be a real class_name/headless incompatibility -- it was caused by world.gd referencing
`Array[FeaturePlacement]` with no explicit `const FeaturePlacement = preload(...)` fallback of its own
at the time. Once that const exists (added in the sandbox_features entry above, and kept even after
re-adding class_name here), a GDScript local const always resolves ahead of a global class lookup, so
the type reference no longer depends on whether the project's (gitignored, regenerable)
`.godot/global_script_class_cache.cfg` happens to already exist. Verified directly: deleted that cache
file to simulate a fresh clone/first-ever headless run, then re-ran `--headless --script
res://tests/run_tests.gd` cold -- still 386/386, no parse errors. class_name and an explicit local
const are not in tension; keeping both is strictly more robust than either alone (editor-friendly name
+ cache-independent headless compilation).

Verified: 386/386 tests pass (cold, cache deleted); clean `--headless --quit` boot; clean
`--headless --editor res://scenes/main.tscn --quit` boot.
