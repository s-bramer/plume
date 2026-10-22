extends RefCounted

## Steady-state groundwater-flow head solver (PLUME_PROJECT_BRIEF.md SS12.1/SS12.6
## Gate A: "conservative heterogeneous-K head solver"). Knows nothing about
## GridModel, geology, or well bookkeeping -- it solves a plain conductance
## network given to it, the same "separate the numerical model" discipline
## HexMath already follows for coordinate math (SS10.5).
##
## GOVERNING EQUATION: for every cell NOT held at a fixed (Dirichlet) head,
## steady-state continuity requires zero net flow in/out:
##   sum_over_existing_neighbors( C_ij * (h_i - h_j) ) + fixed_sink_i = 0
## where C_ij [m3/s per m head difference] is the face conductance between
## cells i and j (the caller supplies this -- GridModel uses harmonic-mean K,
## per Darcy's law q = -K dh/dL, exactly the same formula face_flux_m_s()
## already uses for a known head field). fixed_sink_i is any KNOWN,
## head-independent withdrawal at cell i (a specified-flux boundary, or a
## specified-rate well) -- NOT part of the matrix, since it doesn't depend on
## the unknown h_i itself.
##
## This is the standard 5-point (here: up-to-6-point, hex topology) finite-
## volume/finite-difference discretization of the steady groundwater-flow
## equation div(K grad h) = 0 plus sinks, assembled as a sparse linear system
## A*h = b. Every face not explicitly given a conductance entry is implicitly
## NO-FLOW (the caller simply omits it -- exactly how GridModel already
## treats a missing map-edge neighbor everywhere else in this project).
##
## SOLUTION METHOD: Gauss-Seidel with successive over-relaxation (SOR), not a
## direct sparse solve -- no linear-algebra library is available in plain
## GDScript, and this network's matrix is symmetric positive definite (every
## conductance is positive, and the unknown subgraph is connected to at least
## one fixed-head cell), which is exactly the condition under which
## Gauss-Seidel/SOR is guaranteed to converge monotonically to the unique
## solution. At each sweep, cell i's update is the local balance solved for
## h_i: h_i = (sum_j C_ij*h_j - fixed_sink_i) / sum_j C_ij -- a weighted
## average of its neighbors, nudged by any local sink. SOR (relaxation > 1)
## overshoots each update slightly toward where the sweep is already heading,
## converging markedly faster than plain Gauss-Seidel (omega=1) on this kind
## of diagonally-dominant elliptic network, without losing convergence (SOR
## stays convergent for 0 < omega < 2 on an SPD system).
##
## INTEGER-INDEXED, NOT Vector2i-KEYED: an earlier version kept everything in
## Vector2i-keyed Dictionaries, which is clearer to read but measurably
## slower here -- this solver's inner loop runs cells x faces x iterations
## times (hundreds of thousands to low millions of times for a real map), and
## Vector2i hashing on every single neighbor lookup dominated runtime (a
## radius-14 solve took ~60s). The caller (GridModel) does the axial<->index
## bookkeeping once, outside the hot loop; this solver only ever touches
## plain integers and Packed*Array storage.
const DEFAULT_MAX_ITERATIONS := 4000
const DEFAULT_TOLERANCE_M := 1.0e-5 # convergence: largest single-cell head update (m) in a sweep -- 6+ orders of magnitude below this domain's ~10s-of-meters head differences, comfortably tight for both flux/mass-conservation checks and the visible flow field, without chasing precision no test or display needs (see docs/SIMULATION_ASSUMPTIONS.md)
const DEFAULT_RELAXATION := 1.9 # close to the classical optimal SOR factor 2/(1+sin(pi/N)) for an NxN-ish Poisson grid at this project's typical map sizes (N~=2*radius) -- well clear of the omega>=2 instability boundary

## cell_count: total number of cells (both fixed-head and unknown), defining
##   the valid index range [0, cell_count).
## unknown_indices: PackedInt32Array of indices the solver must determine.
## neighbor_indices / neighbor_conductances: Array (one entry per index,
##   including fixed-head ones even though they're never iterated -- keeps
##   indexing uniform) of PackedInt32Array / PackedFloat64Array, one aligned
##   pair per EXISTING face. Only entries for unknown_indices are ever read.
## heads: PackedFloat64Array, length cell_count, PRE-FILLED by the caller:
##   fixed-head indices hold their true (never-updated) value, unknown
##   indices hold a starting guess. Returned (updated in place internally,
##   but Packed*Array has copy-on-write semantics across a function
##   boundary, so the solved array is handed back explicitly rather than
##   relied upon being mutated through the caller's own reference).
## fixed_sinks: PackedFloat64Array, length cell_count, m3/s withdrawn at each
##   index, independent of head (0.0 where nothing applies).
static func solve(
	unknown_indices: PackedInt32Array,
	neighbor_indices: Array,
	neighbor_conductances: Array,
	heads: PackedFloat64Array,
	fixed_sinks: PackedFloat64Array,
	max_iterations: int = DEFAULT_MAX_ITERATIONS,
	tolerance_m: float = DEFAULT_TOLERANCE_M,
	relaxation: float = DEFAULT_RELAXATION
) -> Dictionary:
	var iterations := 0
	var max_residual := INF
	var converged := false
	while iterations < max_iterations:
		max_residual = 0.0
		for idx in unknown_indices:
			var neighbors: PackedInt32Array = neighbor_indices[idx]
			var conductances: PackedFloat64Array = neighbor_conductances[idx]
			var weighted_sum := 0.0
			var total_conductance := 0.0
			for face_i in range(neighbors.size()):
				var c: float = conductances[face_i]
				weighted_sum += c * heads[neighbors[face_i]]
				total_conductance += c
			if total_conductance <= 0.0:
				continue # an isolated cell (no real neighbors at all) -- nothing to solve, leave its initial guess
			var gauss_seidel_h: float = (weighted_sum - fixed_sinks[idx]) / total_conductance
			var old_h: float = heads[idx]
			var new_h: float = old_h + relaxation * (gauss_seidel_h - old_h)
			heads[idx] = new_h
			max_residual = maxf(max_residual, absf(new_h - old_h))
		iterations += 1
		if max_residual < tolerance_m:
			converged = true
			break

	return {
		"heads": heads,
		"iterations": iterations,
		"max_residual_m": max_residual,
		"converged": converged,
	}
