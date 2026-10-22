extends Node2D

## Visualizes GridModel's contaminant concentration as filled isoconcentration
## zones -- the user's ask, 2026-10-21, after seeing a real site plume map
## (naphthalene isoconcentration contours, yellow-to-red banding around a
## "center of mass"): "zones of higher (inner plume) to lower concentration
## shown in different colours," not the earlier soft-glow-puff cloud look.
##
## Replaces that puff-based renderer outright (see docs/DECISIONS.md's
## 2026-10-21 entry) rather than keeping both, for the same reason
## head_contour_overlay.gd already solved: a flat per-cell fill would look
## like a hex-blocky spreadsheet, so this contours the underlying continuous
## concentration FIELD instead, reusing that file's exact approach --
## hex cell centers form a triangular lattice (the dual of the hex grid), and
## treating concentration as linear across each small triangle lets each band
## boundary cut through cells at whatever angle the real plume has, not
## forced to run along a hex edge.
##
## The difference from head_contour_overlay: that one draws LINES at discrete
## levels (marching triangles). This one fills a region. Each band i's visual
## area is exactly the SUPERLEVEL set {concentration >= thresholds[i]} minus
## whatever a higher band later paints over it -- so _draw() never computes
## [lo, hi) bands directly; it fills thresholds[0]'s whole superlevel region
## first, then thresholds[1]'s (smaller, nested inside it) on top, and so on.
## This is the same nested-fill trick real contour-fill renderers (e.g.
## matplotlib's contourf) use, and it only ever needs ONE clip per triangle
## per threshold (_clip(), keep_above only), not two.
##
## ROUNDED EDGES (user's ask, 2026-10-21): a single triangle's clipped edge is
## always a straight segment (the field is only linear within one triangle),
## so with a sparse plume the silhouette of _clip()'s raw output reads as
## jagged/angular rather than smoothly curved. Fixing that needs the TRUE
## outer boundary of a band's full region, not each tiny triangle's own
## straight edge -- so _draw() first UNIONS every triangle's clipped piece for
## a given threshold into one or more whole polygons (_union_polygons(), via
## Geometry2D.merge_polygons), then rounds each resulting boundary with
## Chaikin's corner-cutting subdivision (_chaikin_smooth()) before filling.
## Only the true outer silhouette gets smoothed this way -- internal edges
## between two same-colored triangle pieces are gone entirely once unioned,
## so there's nothing there to look jagged in the first place.
##
## Unlike head_contour_overlay (which accepts drawing each triangle 3 times,
## "harmless redundancy" for thin lines), a filled polygon drawn twice over
## itself with alpha < 1 visibly double-darkens -- so this overlay dedupes
## each lattice triangle to exactly one owner cell via _triangle_key()
## (_collect_triangles()).
##
## Known limitation: a superlevel region is assumed hole-free (no local
## concentration minimum fully enclosed by higher concentration around it) --
## physically implausible for a single-source plume, so not handled; if it
## ever happened, Geometry2D.merge_polygons would still return a polygon, but
## draw_colored_polygon doesn't do hole-aware (even-odd) fill, so the hole
## would just get painted over rather than left see-through.

const GodotHexOffset = preload("res://scripts/rendering/godot_hex_offset.gd")
const GridModel = preload("res://scripts/simulation/grid_model.gd")

## Same triangle enumeration as head_contour_overlay.gd -- see that file's
## _TRIANGLE_OFFSETS doc comment for why these 6 offsets, taken as
## consecutive pairs, are each one small triangle of the hex-center lattice.
const _TRIANGLE_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1),
]

## Safety valve, not a visual tuning knob: _union_polygons is only O(n)
## amortized for the realistic case (a plume is one, or a few, connected
## blobs). A pathologically fragmented/scattered field (hundreds of isolated
## single-triangle specks that never touch anything) would still force one
## full O(remaining) pass per disjoint piece. Past this many pieces in one
## band, _draw() skips union+smoothing for that band THIS FRAME and falls
## back to the raw, unsmoothed per-triangle fill instead -- a graceful,
## still-correct (just less pretty that one frame) degradation, rather than
## a redraw that can stall the game.
const _MAX_PIECES_FOR_SMOOTHING := 600

## Band boundaries, as a FRACTION of full_scale_kg_m3 (configure()'s existing
## "100% contaminated" reference, the same one the old puff renderer and the
## cell inspector's % reading both already use) -- not absolute kg/m3, so
## retuning full_scale_kg_m3 rescales the zones instead of silently breaking
## them. Ascending; band i covers [thresholds[i], thresholds[i+1]), and the
## last band covers [thresholds[-1], +inf). Anything below thresholds[0]
## draws nothing, matching a real isoconcentration map leaving the area
## outside its lowest contour unshaded. Must stay the same length as
## zone_colors.
@export var zone_thresholds_fraction: PackedFloat32Array = PackedFloat32Array([0.02, 0.06, 0.15, 0.3, 0.55, 1.0])
## One fill color per band in zone_thresholds_fraction, low-to-high -- the
## default is ColorBrewer's "YlOrRd" 6-class ramp (pale yellow -> red), the
## same palette convention the reference site map uses, with alpha baked in
## per-band (low bands more transparent so they read as a faint edge, the
## highest band most opaque so it reads as the plume's core) rather than one
## flat alpha for every band.
@export var zone_colors: Array[Color] = [
	Color("ffffb2", 0.35), Color("fed976", 0.45), Color("feb24c", 0.55),
	Color("fd8d3c", 0.65), Color("f03b20", 0.75), Color("bd0026", 0.85),
]
## Global opacity multiplier on top of each band color's own baked-in alpha --
## Inspector-tunable rather than hand-picked, per
## memory/feedback_expose_visual_tuning.md.
@export_range(0.0, 1.0) var opacity: float = 0.85
## Chaikin corner-cutting passes applied to each band's unioned boundary --
## each pass roughly doubles the vertex count and rounds corners further
## (standard corner-cutting subdivision, converges toward a smooth curve).
## 0 disables smoothing entirely (raw straight-edged triangle boundary, the
## pre-2026-10-21 look). 2-3 is normally enough; higher only keeps shrinking
## sharp features slightly more, at a growing vertex-count cost.
@export_range(0, 4) var smoothing_iterations: int = 2
## Optional thin line between adjacent bands -- off by default (the user's
## explicit ask was zones of color, "not exactly" the reference's black
## outlines), but exposed rather than hardcoded off for anyone who later
## wants the sharper, more map-like look back.
@export var draw_band_outlines: bool = false
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.5)
@export var outline_width: float = 1.0
## Culls any resulting (post-union, pre-smoothing) region smaller than this
## screen-space area (px^2) -- stray single-triangle slivers at a band's
## fringe (e.g. a lone cell just barely crossing a threshold, geometrically
## disconnected from the main body) would otherwise still render as a tiny
## fleck. 0 disables culling entirely. Exposed per the user's ask for more
## "plume optics" controls, not just a bug workaround -- also useful to
## simplify a visually busy, speckled low band.
@export_range(0.0, 2000.0) var min_region_area_px2: float = 100.0

var _ground: TileMapLayer
var _model: GridModel
var _cells: Array[Vector2i] = []
var _full_scale_kg_m3: float = 1.0

## full_scale_kg_m3 is the concentration that reaches the TOP of the highest
## band -- see the matching doc comment on zone_thresholds_fraction. Signature
## unchanged from the puff-renderer version so World's call site didn't need
## to change.
func configure(ground: TileMapLayer, model: GridModel, cells: Array[Vector2i], full_scale_kg_m3: float) -> void:
	_ground = ground
	_model = model
	_cells = cells
	_full_scale_kg_m3 = full_scale_kg_m3
	queue_redraw()

## A cell's concentration as a fraction of full_scale_kg_m3 -- NOT clamped at
## the top (the highest band already extends to +inf, so anything above
## thresholds[-1] correctly lands there), only floored at 0 since
## concentration itself never goes negative.
func _fraction(axial: Vector2i) -> float:
	if _full_scale_kg_m3 <= 0.0:
		return 0.0
	return maxf(0.0, _model.get_concentration_kg_m3(axial) / _full_scale_kg_m3)

## Canonical, order-independent identity for one lattice triangle (its 3
## corner cells, sorted), so a triangle enumerated from any of its 3 corners
## hashes to the same key -- the dedup _draw() needs so a filled triangle is
## only ever painted once. Pure and directly testable, same reasoning as
## every other piece of per-triangle math in this project being split out of
## _draw().
static func _triangle_key(a: Vector2i, b: Vector2i, c: Vector2i) -> String:
	var pts: Array = [a, b, c]
	pts.sort_custom(func(p, q): return p.x < q.x or (p.x == q.x and p.y < q.y))
	return "%d,%d|%d,%d|%d,%d" % [pts[0].x, pts[0].y, pts[1].x, pts[1].y, pts[2].x, pts[2].y]

## General Sutherland-Hodgman clip of a convex polygon against one linear
## scalar half-plane: keeps the region where each vertex's "val" is >=
## threshold (keep_above true) or <= threshold (keep_above false), inserting
## a linearly-interpolated vertex (val == threshold exactly, by construction)
## wherever the polygon crosses it. `poly` is an Array of {"pos": Vector2,
## "val": float} dictionaries rather than a fixed Vector2/float pair, since
## clipping a triangle can grow it to a quad before the second clip is
## applied. Pure, and the core of why this overlay can draw smoothly-angled
## FILLED bands rather than being stuck with one flat color per hex cell.
static func _clip(poly: Array, threshold: float, keep_above: bool) -> Array:
	if poly.is_empty():
		return []
	var result: Array = []
	var n := poly.size()
	for i in range(n):
		var cur: Dictionary = poly[i]
		var nxt: Dictionary = poly[(i + 1) % n]
		var cur_in: bool = (cur["val"] >= threshold) if keep_above else (cur["val"] <= threshold)
		var nxt_in: bool = (nxt["val"] >= threshold) if keep_above else (nxt["val"] <= threshold)
		if cur_in:
			result.append(cur)
		if cur_in != nxt_in:
			var denom: float = nxt["val"] - cur["val"]
			var t: float = 0.0 if denom == 0.0 else (threshold - cur["val"]) / denom
			result.append({"pos": (cur["pos"] as Vector2).lerp(nxt["pos"], t), "val": threshold})
	return result

func _cell_centers() -> Dictionary:
	var centers := {}
	for axial in _cells:
		var offset := GodotHexOffset.axial_to_offset(axial)
		centers[axial] = to_local(_ground.to_global(_ground.map_to_local(offset)))
	return centers

## Every lattice triangle, deduped to its one canonical owner (_triangle_key)
## so a shared triangle is never processed twice, each carrying its 3
## corners' screen positions and concentration fractions -- the raw input
## _draw() clips per threshold. Split out from _draw() so the dedup/collection
## step itself (not just the math inside it) stays testable without a
## Viewport, same reasoning as every other piece of this overlay's logic.
func _collect_triangles(centers: Dictionary) -> Array:
	var seen: Dictionary = {}
	var triangles: Array = []
	for axial in _cells:
		for k in range(6):
			var n1: Vector2i = axial + _TRIANGLE_OFFSETS[k]
			var n2: Vector2i = axial + _TRIANGLE_OFFSETS[(k + 1) % 6]
			if not (centers.has(n1) and centers.has(n2)):
				continue
			var key := _triangle_key(axial, n1, n2)
			if seen.has(key):
				continue
			seen[key] = true
			triangles.append({
				"axials": [axial, n1, n2],
				"positions": [centers[axial], centers[n1], centers[n2]],
				"fracs": [_fraction(axial), _fraction(n1), _fraction(n2)],
			})
	return triangles

## Canonical key for one lattice EDGE (an unordered pair of adjacent cells),
## order-independent for the same reason _triangle_key is -- used to find,
## for every lattice edge, the (at most 2) triangles that share it.
static func _edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d|%d,%d" % [b.x, b.y, a.x, a.y]

## Triangle-to-triangle adjacency graph, built once per _draw() call from the
## fixed lattice topology alone (which triangles share 2 of their 3 corner
## cells) -- completely independent of any threshold or concentration data.
## _band_loops() walks a band's included triangles along this graph (a real
## BFS over actual mesh connectivity) instead of _collect_triangles' raw
## enumeration order, so the piece a growing region merges next is always one
## it's actually known to border -- see _union_polygons' doc comment for why
## that matters.
func _build_adjacency(triangles: Array) -> Array:
	var edge_to_triangles: Dictionary = {}
	for i in range(triangles.size()):
		var axials: Array = triangles[i]["axials"]
		var pairs: Array = [[axials[0], axials[1]], [axials[1], axials[2]], [axials[2], axials[0]]]
		for pair in pairs:
			var key := _edge_key(pair[0], pair[1])
			if not edge_to_triangles.has(key):
				edge_to_triangles[key] = []
			edge_to_triangles[key].append(i)
	var adjacency: Array = []
	for i in range(triangles.size()):
		adjacency.append([])
	for key in edge_to_triangles:
		var tris: Array = edge_to_triangles[key]
		if tris.size() == 2:
			adjacency[tris[0]].append(tris[1])
			adjacency[tris[1]].append(tris[0])
	return adjacency

func _clipped_triangle_points(tri: Dictionary, threshold: float) -> PackedVector2Array:
	var positions: Array = tri["positions"]
	var fracs: Array = tri["fracs"]
	var poly: Array = [
		{"pos": positions[0], "val": fracs[0]},
		{"pos": positions[1], "val": fracs[1]},
		{"pos": positions[2], "val": fracs[2]},
	]
	var clipped: Array = _clip(poly, threshold, true)
	var points := PackedVector2Array()
	for v in clipped:
		points.append(v["pos"])
	return points

## Groups a band's included triangles (max corner fraction >= threshold) into
## connected components via BFS over _build_adjacency's graph, then folds
## each component's clipped pieces into whole polygon(s) via _union_polygons.
## Triangles with no adjacency path between them (through OTHER included
## triangles) can never produce touching clipped pieces either -- the
## triangulation is a proper planar partition, so two non-adjacent triangles'
## interiors never border each other -- meaning grouping by this graph first
## never incorrectly separates anything _union_polygons would otherwise have
## joined; it only avoids wasting merge attempts between pieces that could
## never touch in the first place.
func _band_loops(triangles: Array, adjacency: Array, included: Dictionary, threshold: float) -> Array:
	var visited: Dictionary = {}
	var loops: Array = []
	for start in included.keys():
		if visited.has(start):
			continue
		var queue: Array = [start]
		visited[start] = true
		var component_polys: Array = []
		var head := 0
		while head < queue.size():
			var cur: int = queue[head]
			head += 1
			var piece := _clipped_triangle_points(triangles[cur], threshold)
			if piece.size() >= 3:
				component_polys.append(piece)
			for nb in adjacency[cur]:
				if included.has(nb) and not visited.has(nb):
					visited[nb] = true
					queue.append(nb)
		loops.append_array(_union_polygons(component_polys))
	return loops

## Folds a list of (possibly touching/overlapping) simple polygons into the
## smallest set of disjoint polygons covering the same total area, via
## Geometry2D.merge_polygons. NOT a single pass over the input: an earlier
## version picked a seed and swept the rest exactly ONCE, which is
## order-dependent and genuinely WRONG, not just slower than ideal -- if
## piece C only touches the growing region through piece B, but B happens to
## come after C in the input, C gets judged "doesn't touch" against a region
## that doesn't yet include B and is permanently written off as its own
## separate polygon, even though the true region is one connected piece. This
## is exactly what produced the user's "plume breaking up into smaller
## ellipses" bug: one real connected blob silently split into several.
## Fixed by retrying every not-yet-merged piece against the CURRENT state of
## the growing region, repeating until a full retry round makes no further
## progress -- a fixed-point iteration that correctly finds everything
## transitively connected to the seed regardless of input order, converging
## in practice in very few rounds once _band_loops feeds it an
## already-adjacency-grouped component (most pieces merge on the very first
## attempt; retries only matter for genuinely out-of-order leftovers).
## Whatever still doesn't merge after a round changes nothing really is
## geometrically disconnected (e.g. two hot spots in the same topological
## component whose connecting edge dips below the threshold everywhere along
## it) and correctly becomes its own separate output polygon.
static func _union_polygons(polys: Array) -> Array:
	var remaining: Array = polys.duplicate()
	var output: Array = []
	while not remaining.is_empty():
		var current: PackedVector2Array = remaining[0]
		var pending: Array = remaining.slice(1)
		var progress := true
		while progress and not pending.is_empty():
			progress = false
			var still_pending: Array = []
			for candidate in pending:
				var result: Array = Geometry2D.merge_polygons(current, candidate)
				if result.size() == 1:
					current = result[0]
					progress = true
				else:
					still_pending.append(candidate)
			pending = still_pending
		output.append(current)
		remaining = pending
	return output

## Shoelace formula -- signed area of a closed polygon, used by _draw() to
## cull slivers smaller than min_region_area_px2 rather than to orient
## anything, so only the magnitude is ever used by the caller.
static func _polygon_area(points: PackedVector2Array) -> float:
	var area := 0.0
	var n := points.size()
	for i in range(n):
		var p0: Vector2 = points[i]
		var p1: Vector2 = points[(i + 1) % n]
		area += p0.x * p1.y - p1.x * p0.y
	return area * 0.5

## Collapses consecutive (including wrap-around) points closer than epsilon
## into one -- the most common cause of a degenerate polygon that fails
## triangulation is a zero- or near-zero-length edge, which Geometry2D.merge_
## polygons can introduce where two unioned pieces touch at (or very near) a
## single point rather than along a real shared edge.
static func _dedupe_points(points: PackedVector2Array, epsilon: float = 0.01) -> PackedVector2Array:
	if points.size() < 2:
		return points
	var out := PackedVector2Array()
	for p in points:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > epsilon:
			out.append(p)
	if out.size() > 1 and out[0].distance_to(out[out.size() - 1]) <= epsilon:
		out.remove_at(out.size() - 1)
	return out

## True iff Godot's own triangulator can fill `points` -- the exact check
## canvas_item_add_polygon() does internally before drawing (see
## servers/rendering/renderer_canvas_cull.cpp), run here FIRST so a degenerate
## (self-intersecting or zero-area) polygon never reaches draw_colored_polygon
## and spams "Invalid polygon data, triangulation failed." to the log while
## silently drawing nothing -- which is exactly what produced the "indented"
## plume edges: a band's polygon failed this check, printed an engine error,
## and simply didn't get drawn that frame, leaving a bite out of the band.
static func _triangulates(points: PackedVector2Array) -> bool:
	return points.size() >= 3 and not Geometry2D.triangulate_polygon(points).is_empty()

## Chaikin's corner-cutting subdivision on a CLOSED polygon loop: each pass
## replaces every edge (P_i, P_i+1) with 2 new points at 1/4 and 3/4 along it,
## discarding the original sharp corner entirely -- the standard, simple way
## to turn a straight-edged polygon into a smoothly rounded one without any
## spline library, converging toward a quadratic B-spline as iterations grow.
## Pure and directly testable (same reasoning as every other piece of this
## overlay's math being split from its draw call).
static func _chaikin_smooth(points: PackedVector2Array, iterations: int) -> PackedVector2Array:
	var pts: PackedVector2Array = points
	for _iter in range(iterations):
		if pts.size() < 3:
			return pts
		var next := PackedVector2Array()
		var n := pts.size()
		for i in range(n):
			var p0: Vector2 = pts[i]
			var p1: Vector2 = pts[(i + 1) % n]
			next.append(p0.lerp(p1, 0.25))
			next.append(p0.lerp(p1, 0.75))
		pts = next
	return pts

func _draw() -> void:
	if _model == null or _cells.is_empty() or zone_thresholds_fraction.is_empty():
		return
	var centers := _cell_centers()
	var triangles := _collect_triangles(centers)
	var adjacency := _build_adjacency(triangles)

	for i in range(zone_thresholds_fraction.size()):
		var threshold: float = zone_thresholds_fraction[i]
		var included: Dictionary = {}
		for t in range(triangles.size()):
			var fracs: Array = triangles[t]["fracs"]
			if maxf(fracs[0], maxf(fracs[1], fracs[2])) >= threshold:
				included[t] = true
		if included.is_empty():
			continue

		var color: Color = zone_colors[i]
		color.a *= opacity

		if included.size() > _MAX_PIECES_FOR_SMOOTHING:
			for t in included.keys():
				var piece := _clipped_triangle_points(triangles[t], threshold)
				if piece.size() >= 3:
					draw_colored_polygon(piece, color)
			continue

		for raw_loop in _band_loops(triangles, adjacency, included, threshold):
			var loop: PackedVector2Array = _dedupe_points(raw_loop)
			if loop.size() < 3 or absf(_polygon_area(loop)) < min_region_area_px2:
				continue
			var smoothed: PackedVector2Array = _dedupe_points(_chaikin_smooth(loop, smoothing_iterations))
			# Smoothing a tight concave notch can occasionally fold the
			# boundary over itself; fall back to the un-smoothed (but still
			# deduped) union loop, and only skip this one region, this one
			# frame, if even that fails -- never let a degenerate polygon
			# reach draw_colored_polygon (see _triangulates' doc comment).
			var to_draw: PackedVector2Array = smoothed
			if not _triangulates(to_draw):
				to_draw = loop
				if not _triangulates(to_draw):
					continue
			draw_colored_polygon(to_draw, color)
			if draw_band_outlines:
				draw_polyline(to_draw + PackedVector2Array([to_draw[0]]), outline_color, outline_width, true)
