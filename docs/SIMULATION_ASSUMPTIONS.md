# Simulation assumptions

Per `PLUME_PROJECT_BRIEF.md` SS12.4: "Record assumptions, units, time step, grid resolution and tolerance."
This file is the single place those numbers live; `docs/DECISIONS.md` records the *why* behind design choices,
this file records the *current numeric values* a test or a future change should check against.

## Units

SI throughout: meters (m), seconds (s), kilograms (kg), cubic meters (m3). Hydraulic conductivity `K` in m/s,
concentration in kg/m3, pumping/leak rates in m3/s and kg/s respectively.

## Grid and geometry (`scripts/simulation/grid_model.gd`)

- Flat-top hex grid, axial `(q, r)` coordinates (`scripts/rendering/hex_math.gd`).
- `CELL_SPACING_M = 100.0` -- straight-line distance between adjacent cell centers. No real DEM/map extent
  exists yet; this is a placeholder so face fluxes have a concrete denominator.
- `CELL_THICKNESS_M = 10.0`, one saturated layer (brief SS4: "Start with one saturated layer").
- `CELL_AREA_M2 = CELL_SPACING_M^2`, `FACE_AREA_M2 = CELL_THICKNESS_M * CELL_SPACING_M`.
- Default map radius 8 (tests, `World`'s own export default) or 14 (`scenes/main.tscn`'s actual play scene).

## Geology and hydraulic conductivity

Three synthetic units (sand/silt/clay), deterministic function of `(q, r)` (`_geology_at`), standing in for a
real site survey until Phase 2 scenario data exists. Default `K` (m/s): sand `3.0e-4`, silt `2.0e-5`, clay
`5.0e-8` (a ~6000x contrast, deliberately large so a clay lens visibly matters). Porosity: sand 0.30, silt 0.25,
clay 0.12. All Inspector-tunable on `World` (`sand_k_m_s`/`silt_k_m_s`/`clay_k_m_s`/`*_porosity`), live-refreshed
into a running `GridModel` -- see `DECISIONS.md`'s entries on live-tuning.

## Groundwater flow (`scripts/simulation/flow_solver.gd`, Gate A)

- **Governing equation:** steady-state Darcy flow, `q = -K * dh/dL` per face; finite-volume water balance,
  zero net flow at every non-Dirichlet cell: `sum(C_ij * (h_i - h_j)) + fixed_sink_i = 0`.
- **Face conductance:** harmonic mean of the two cells' K (`C_ij = 2*K_a*K_b/(K_a+K_b) * FACE_AREA_M2 / CELL_SPACING_M`),
  the correct averaging for two media in series.
- **Boundary conditions:**
  - Dirichlet (fixed head): every cell in the north row (`r == -radius`), value `BASE_HEAD_M - HEAD_GRADIENT_M_PER_ROW * r`
    (`BASE_HEAD_M = 50.0`, `HEAD_GRADIENT_M_PER_ROW = 0.8`). The domain's upgradient inflow boundary.
  - Specified flux (fixed, head-independent sink): every open south-outflow face (`_SOUTH_OUTFLOW_OFFSETS`),
    `Q = K(cell) * HEAD_GRADIENT_M_PER_ROW / CELL_SPACING_M * FACE_AREA_M2` -- the downgradient outflow boundary,
    continuing the same regional gradient past the map edge.
  - Specified flux: the capture well's `well_pumping_rate_m3_s` at `well_axial`, when configured.
  - No-flow: every other missing-neighbor face, by omission.
- **Solver:** Gauss-Seidel with successive over-relaxation (SOR), `relaxation = 1.9`, `tolerance_m = 1.0e-5`
  (largest single-cell head update per sweep), `max_iterations = 4000`. Converges in practice in well under a
  few hundred iterations for radius 8-14 maps (confirmed via `last_head_solve["converged"]`, exercised by every
  head-solve test in `tests/run_tests.gd`). Chosen because the assembled matrix is symmetric positive definite
  (every conductance positive, unknown cells connected to the Dirichlet boundary), the standard condition under
  which Gauss-Seidel/SOR is guaranteed convergent -- no external linear-algebra library is available in plain
  GDScript for a direct sparse solve.
- **Known, documented limitation:** on this specific finite hexagonal domain, a uniform-K solve does NOT exactly
  reproduce the hand-derived pure-linear-in-row head formula -- the hex's slanted east/west edges have cells
  whose "no-flow" treatment on a non-north/non-south face doesn't exactly match what the idealized 1D formula
  implies there, and because the governing equation is elliptic, that mismatch diffuses across the whole domain
  rather than staying local to the edge. Confirmed numerically (see `docs/DECISIONS.md`'s 2026-10-21 entry) and
  covered by `_test_grid_model_head_gradient_uniform_k_benchmark`, which checks the properties that DO hold
  (water balance, monotonic north-south decrease, small cross-column spread) rather than exact formula equality.
- **Well:** specified-RATE (not specified-drawdown) sink -- the rate is fixed regardless of the head there, the
  correct idealization for a pump operating within its capacity. It now participates in the head solve, so it
  measurably draws down head and bends flow toward it (brief SS12.4 test 9) -- resolved as of 2026-10-21; earlier
  versions of this project documented this as a deliberate, deferred limitation.

## Contaminant transport (Gate B)

- Conservative, one-layer, advection; upwind face concentration (brief SS12.2: "water flux x upwind aqueous
  concentration").
- Explicit time-stepping, substepped within a player turn (`World._advance_turn()`) so no single transport step
  exceeds `GridModel.max_stable_dt_s()`'s CFL stability bound -- the largest dt that keeps every cell's total
  outflow (interior faces + south boundary + well + diffusion) within its own current mass.

## Molecular diffusion (Gate C)

- **Governing equation** (brief SS12.3): `F_diff_face = -n_e * A_face * D_normal * (C_j - C_i) / distance` [kg/s],
  Fick's law applied face-to-face, exactly parallel to how advection already uses a face conductance.
  `G_diff_face = n_e_face * A_face * D_face / distance` [m3/s] is computed once per face
  (`GridModel._face_diffusion_conductance_m3_s`) and folded into the SAME delta/CFL accumulators advection uses.
- **D_face**: harmonic mean of the two cells' `diffusion_m2_s` (same "media in series" reasoning as K's harmonic
  mean in `face_flux_m_s` -- a low-diffusion cell should dominate the face, not get diluted by averaging).
- **n_e_face**: arithmetic mean porosity (a cross-sectional-area fraction, not a series resistance -- same
  averaging `pore_velocity_m_s` already uses for n_e).
- **D_m_effective, not split into D_m and tortuosity separately**: a single lumped per-geology coefficient (no
  site data to constrain them independently). Defaults (m2/s): sand `1.0e-9`, silt `7.0e-10`, clay `4.0e-10` --
  a DELIBERATELY narrow range (~2.5x) compared to K's 6000x sand:clay contrast. This is real physics: free-water
  diffusion coefficients are roughly solute-dependent, not strongly medium-dependent; only tortuosity (a mild,
  few-x effect) reduces it in porous media, unlike K's much more severe dependence on pore-throat geometry. All
  three Inspector-tunable on `World` (`sand_diffusion_m2_s`/`silt_diffusion_m2_s`/`clay_diffusion_m2_s`),
  live-refreshed via the same `apply_geology_parameters` hot-swap path as K/porosity.
- **Direction**: unlike advection (upwind, follows the flow field), diffusion always moves from higher to lower
  concentration, independent of head/flow -- confirmed by a dedicated test with a perfectly flat head field
  (zero advection) where mass still spreads via diffusion alone (brief SS12.4 test 5).
- **Scope of this first pass**: interior cell-to-cell faces only. The open south boundary and the capture well do
  NOT yet diffuse (both still only move mass via their existing advective/specified-rate terms) -- deferred
  deliberately: diffusion across an open boundary needs its own documented external-concentration assumption that
  doesn't have a clear answer yet, and nothing in brief SS12.4's required test list needs it to exist yet.
- **Not yet implemented**: mechanical dispersion (the velocity-dependent, longitudinal/transverse tensor term --
  a separate, later addition to Gate C), sorption, reactions (Gate D).
- Mass bookkeeping: `mass_kg` (in-domain, per cell) + `escaped_mass_kg` (south open boundary) + `captured_mass_kg`
  (well) must always sum to everything ever seeded (`World._total_seeded_mass_kg`, which itself accounts for the
  one-time initial seed and the continuing leak). Checked by multiple tests and shown live in the mass-balance
  HUD panel.
- `contamination_full_scale_kg_m3` (overlay/inspector display scale) and `receptor_contamination_threshold_kg_m3`
  (the actual win/loss limit) are deliberately SEPARATE numbers, even though they share a default (0.03 kg/m3) --
  see `World`'s own doc comments.

## Not yet implemented (tracked against brief SS12.2/SS12.6, do not assume otherwise)

Mechanical dispersion (the velocity-dependent longitudinal/transverse term -- molecular diffusion, above, is now
implemented; dispersion is still a separate, later addition), equilibrium/kinetic sorption, biodegradation/
reactions, source dissolution, volatilisation, matrix diffusion, geochemical speciation, density-dependent/
multiphase flow, transient (storage-based) flow, recharge, and multiple vertical layers are all explicitly out of
scope until their respective gates (C/D/E/F). `World`'s "boost flow"-style mechanics do not exist in this build.
