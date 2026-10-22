# PLUME: Darcy's Curse — Game Concept & Development Brief

> Working project specification for Claude Code. Treat this as the source of truth for the initial Godot prototype, not a request to implement every feature immediately.

## 1. Elevator pitch

**Plume: Darcy's Curse** is a turn-based, 2D pixel-art strategy/puzzle game where the player embodies a groundwater contaminant plume. The plume migrates according to geology, groundwater hydraulics and contaminant chemistry. The player makes constrained strategic choices while an environmental-engineering opponent attempts to investigate, contain and remediate the contamination.

**Design pillar:** *Physics creates the puzzle.* Players should learn hydrogeology through visible cause and effect, rather than through quizzes or arbitrary movement powers.

## 2. Audience and experience

- Indie strategy/puzzle players; students and practitioners of geology, hydrogeology and environmental engineering.
- Short, readable turns (roughly 1–2 minutes), with meaningful trade-offs and replayable scenarios.
- Playful, slightly ominous tone; scientific fidelity where it affects decisions, simplified where necessary for clarity.
- Initial target: desktop PC. Browser/mobile are possible later, not Phase 1 commitments.

## 3. Gameplay loop

1. **Inspect:** View geological units, hydraulic heads/gradients, contaminant distribution and vulnerable receptors.
2. **Plan:** Choose one limited plume-side action or strategy (e.g. exploit a pathway, time a release from a sorbed reservoir, or select a source release schedule where scenario rules permit). Actions must respect the contaminant's actual properties and environmental conditions.
3. **Hydraulic update:** Rainfall/recharge, pumping, boundary conditions and geological heterogeneity determine heads and intercell water fluxes.
4. **Transport/reactions:** Mass migrates by advection/dispersion and may sorb, desorb, degrade or transform according to the scenario.
5. **Engineer response:** AI (later potentially another player) investigates and deploys monitoring, pumping or treatment within a budget.
6. **Feedback:** Animate the plume and update mass balance, concentration map, flow arrows, objectives and a brief explanation of *why* it moved.
7. **Repeat** until the receptor-risk or remediation objective is resolved.

The player **does not steer contamination freely** or magically change intrinsic chemical properties. Strategic actions should modify physically defensible controls or choose among feasible pathways. For the first prototype, a temporary 'boost flow' mechanic can be used to test fun, but should ultimately be replaced by a defensible scenario action (e.g. changing a permitted source-release rate or exploiting an existing pumping/recharge event).

## 4. Core systems

### World and grid

- Hexagonal **plan-view grid**; each cell represents an area of aquifer.
- Each cell has geological and hydraulic properties; adjacent cells exchange water and dissolved contaminant mass through shared faces.
- Start with **one saturated layer**. Plan for 3–5 vertical layers later, with selectable depth slices and a draggable plan-to-cross-section A–A′ view.
- Separate **simulation data** from **Godot rendering**.

### Cell data (candidate fields)

| Field | Meaning |
|---|---|
| `geology_id` | Geological unit / visual type |
| `top_elevation_m`, `bottom_elevation_m` | Cell/layer geometry |
| `K_m_s` | Hydraulic conductivity; may become a tensor later |
| `porosity` | Effective/mobile porosity for transport |
| `specific_yield` | Unconfined storage response, if applicable |
| `head_m` | Hydraulic head, not automatically equal to water-table elevation |
| `recharge_m_s` | Applied at the upper boundary/surface |
| `bulk_density_kg_m3` | For sorption calculations |
| `dispersivity_L_m`, `dispersivity_T_m` | Longitudinal/transverse dispersivity |
| `mass_kg_by_species` | Contaminant inventory, with phase-specific pools added later |

Hydraulic head is a dynamic state variable, not an immutable geological property. Water-table elevation applies to an unconfined system; deeper confined cells carry hydraulic head. Sorption coefficients belong to **species–material pairs**, not universally to a cell.

### Groundwater flow

- MVP: impose boundary heads and solve for internally consistent heads when `K` is heterogeneous; a prescribed linear head field is valid as a simple uniform-`K` benchmark, but generally does not conserve water across heterogeneous cells.
- Next: solve a conservative steady-state groundwater-flow balance with fixed-head/no-flow boundaries, recharge and well sinks/sources.
- Darcy flux `q = -K ∇h`; pore-water velocity approximately `v = q / n_e`.
- Recharge influences heads and flow only through an appropriate water-balance/boundary formulation, not by directly 'pushing' all contaminants one tile.
- Display equipotential contours and flow arrows as learning aids.

### Contaminant transport

- Track **mass** and derive aqueous concentration from mobile-water volume, rather than simply coloring occupied tiles.
- Conservative face-to-face mass transfer, initially advection with upwind concentrations; add dispersion and reactions after validating mass balance.
- Time step must obey stability/nonnegative-mass constraints; substep within a player turn if required.
- Account for sorption using an appropriate equilibrium or kinetic model; avoid double-counting retardation when tracking sorbed mass explicitly.
- Reaction rates and products depend on species and geochemical conditions; avoid universal decay constants.
- Explicitly track mass remaining, mass extracted, mass degraded/transformed, and mass exiting boundaries.

### Contaminants / scenario archetypes

| Contaminant | Interesting behavior | Scientific caveat |
|---|---|---|
| Nitrate | Mobile plume, denitrification opportunities | Denitrification depends on redox/electron donors |
| Benzene | Dissolved plume, biodegradation, volatile phase | LNAPL behavior applies to petroleum mixtures/free product, not automatically to dissolved benzene |
| TCE / PCE | Persistent dissolved plume, daughter products | DNAPL migration requires a separate multiphase model; vinyl chloride can form under reductive dechlorination |
| PFAS | Persistent plume, variable sorption | Different PFAS have different mobility; treatment is often separation rather than destruction |
| Arsenic | Geochemically controlled mobilization | Redox/pH and mineral interactions are critical |
| Microbial pathogens | Filtration/attachment and inactivation | Survival and transport vary greatly with conditions |

**MVP: a synthetic conservative dissolved tracer first** (no sorption or reactions). Add nitrate as a separate scenario with redox-dependent denitrification later. Do not start with multiphase NAPL.

### Engineer defenses

- Monitoring wells: reveal concentrations at selected locations/depths.
- Pump-and-treat wells: alter hydraulic gradients and extract dissolved mass; capacity/cost constraints.
- Permeable reactive barriers: allow flow while reacting with appropriate contaminants, subject to residence time and capacity.
- Bioremediation: change suitable geochemical conditions, with potential byproducts.
- Containment walls and hydraulic control: redirect flow, potentially creating bypass pathways.
- Monitored natural attenuation: lower cost but dependent on evidence and timescale.

**Important:** A pumping well is a hydraulic sink and mass-extraction mechanism, not an impermeable blocking tile. A PRB is not a universal filter for every species.

## 5. Objectives and strategy

- Pollutant objective: reach a sensitive receptor (drinking-water supply, river, wetland) above a defined concentration/exposure threshold within a turn limit.
- Engineer objective: protect receptors and reduce/control the plume within budget and time constraints.
- Scoring: receptor risk, remediation cost, elapsed time, remaining mass, and scientific explanation/learning achievements.
- Later: asymmetric local multiplayer, scenario campaigns and optional 'engineer mode'.

## 6. Visual direction and UX

- **2D pixel art**, pointy-top hexes, dark aquifer blue `#0D1B2A`, toxic green `#9FE870`, sandy beige `#E6D2A3`, rust red `#B34040`, vapor grey `#C5C6C7`.
- Pixel-art terrain and geological patterns; concentration heatmap overlays; animated flow arrows and well influence.
- Godot 2D lights/shadows for mood, but never obscure critical simulation information.
- Rain particles, surface wetness and recharge pulse indicators. Rainfall affects recharge according to a scenario water budget, not one-to-one.
- Later: plan-view layer selector, vertical depth ruler, draggable A–A′ cross-section, per-cell inspector and mass-balance panel.
- Keep overlays toggleable: geology / hydraulic head / flow / concentration / remediation.

## 7. Technology and architecture

- **Engine:** Godot 4, standard edition with GDScript initially.
- **Mode:** 2D, not 3D. Use `TileMapLayer` for Godot 4.3+ projects; older tutorials may use deprecated `TileMap`.
- **Version control:** Git repository at the directory containing `project.godot`, hosted on GitHub; commit `.gd`, `.tscn`, `.tres`, artwork and project settings. Ignore `.godot/` cache. Use a Godot-specific `.gitignore` appropriate to the installed version.
- **Rendering vs simulation:** simulation is deterministic and testable without relying on scene nodes.
- **Coordinate convention:** explicitly document axial hex `(q,r)` coordinates, neighbor offsets, world-space conversion, cell geometry and map boundaries.

Suggested structure:

```text
PlumeDarcy/
├── project.godot
├── README.md
├── docs/
│   ├── GAME_DESIGN.md
│   └── SIMULATION_ASSUMPTIONS.md
├── scenes/
│   ├── main.tscn
│   ├── grid.tscn
│   └── ui/
├── scripts/
│   ├── simulation/
│   │   ├── grid_model.gd
│   │   ├── flow_solver.gd
│   │   ├── transport_solver.gd
│   │   └── mass_balance.gd
│   ├── rendering/
│   │   └── grid_view.gd
│   └── main.gd
├── autoload/
│   └── game_state.gd
├── data/
│   ├── geology/
│   ├── contaminants/
│   └── scenarios/
├── art/
├── audio/
└── tests/
```

Keep the architecture modest until the first playable build. Use typed GDScript where practical and stable data formats for scenarios.

## 8. Development roadmap

### Phase 1 — Gray-box playable prototype (target: 2–3 weeks, flexible)

1. Confirm Godot version, scene tree and existing hex TileSet; avoid rebuilding assets that already work.
2. Generate or register a small hex map (radius ~8), with click/hover and correct coordinate conversion.
3. Create data-backed cells with `K`, effective porosity, elevation and hydraulic head; visualize geology/head on the grid.
4. Validate face fluxes with a uniform-`K` linear-head benchmark; when introducing heterogeneous `K`, solve a conservative steady-state head balance with specified boundary conditions.
5. Seed a finite contaminant mass in one or more cells; implement conservative, one-layer, advection-only transport.
6. Add Next Turn (Space), turn counter, concentration overlay, mass-balance display and reset.
7. Add one physically defensible player choice and one simple engineer response (e.g. a capture well with specified pumping rate).
8. Add a receptor target, win/loss rules and a short on-screen explanation of each turn.
9. Write tests for zero-gradient transport, uniform gradient direction, mass conservation, nonnegative concentrations and boundary handling.

**Definition of done:** play 5–10 turns; changing heads/`K` changes migration; a pumping well changes capture; mass is accounted for; player can win or lose; no placeholder mechanic is mistaken for real physics.

### Phase 2 — Scientific depth and strategy

- Heterogeneous geology; solved steady-state heads; recharge and pumping; longitudinal/transverse dispersion and molecular diffusion; sorption; simple reactions; monitoring and PRBs; scenario configuration; AI response.
- Validate against simple analytical or benchmark cases before balancing for fun.

### Phase 3 — Vertical hydrogeology and presentation

- 3–5 depth layers, vertical exchange, layer-specific well screens, depth slices and A–A′ cross-section.
- Pixel-art terrain, dynamic 2D lighting, rainfall/weather and intuitive visual explanations.

### Phase 4 — Game feel and content

- Multiple contaminants with accurate scenario-specific mechanics; campaign levels; tutorial, audio, animations, progression and balancing.

### Phase 5 — Release preparation

- Save/load, accessibility, settings, profiling, playtests, distribution builds, Steam/itch.io store assets and release candidate.

## 9. Design guardrails

1. **Science first, fun through constraints.** Never let the player change a compound's solubility, density or sorption coefficient at will without an explicit, scientifically meaningful mechanism.
2. **Avoid misleading simplifications.** Label abstracted systems and explain limitations.
3. **Conserve mass.** Every transfer, sink, source and transformation must be accounted for.
4. **Decouple turn length from numerical timestep.** One game turn may require many solver substeps.
5. **Build one playable scenario before adding chemistry, vertical layers or weather VFX.**
6. **Make the reason visible.** Show gradients, geological barriers, source/sink terms and a clear before/after.
7. **Do not equate a plume front with one tile per turn.** Transport follows fluxes and concentration/mass.

## 10. Instructions for Claude Code

When working in this repository:

1. Inspect the existing Godot project, version, scenes, TileSet and scripts **before editing**.
2. Preserve the user's already aligned hex tiles and existing work.
3. Propose the smallest next implementation task; do not build the entire roadmap in one pass.
4. Prefer Godot 4-version-correct APIs (`TileMapLayer` if applicable), typed GDScript, short scripts and explicit units.
5. Separate numerical model, rendering, input and UI.
6. For any change to groundwater flow or transport, include a short explanation of the governing equation, assumptions and a reproducible test.
7. Use deterministic test scenarios and check mass balance at every step.
8. Keep a brief `docs/DECISIONS.md` record of consequential design/science simplifications.
9. After each change, state what changed, how to test it in Godot and the next small task.

**Suggested first prompt:**

> Read `PLUME_PROJECT_BRIEF.md`, inspect my current Godot project and tell me which Phase 1 requirements are already implemented. Then propose the next three small tasks. Implement only the first task after explaining the planned files and acceptance test. Preserve my existing hex TileSet and scene setup.


## 12. Scientific transport specification (priority: high)

**Non-negotiable:** Educational realism is a core game mechanic. The numerical model must represent physically meaningful processes, distinguish conceptual simplifications from established physics, and be verified before visual/gameplay polish.

### 12.1 Groundwater hydraulics

- **Darcy flow:** `q = -K ∇h` (specific discharge, m/s); in anisotropic media `K` is a tensor.
- **Pore-water velocity:** `v = q / n_e` for saturated mobile pore space; do not confuse Darcy flux with advective velocity.
- **Conservative cell water balance:** compute **one shared volumetric flux per cell face** using face conductance, geometry and head difference. Adjacent cells receive equal/opposite fluxes.
- **Boundary conditions:** fixed head, no-flow, and specified flux; wells are volumetric sources/sinks, not blocking tiles.
- **Recharge/discharge:** rainfall must be converted into effective recharge by a water-budget assumption, then applied as a flow source/boundary flux; rivers can gain or lose water depending on stage/head.
- **Heterogeneity:** different K values create preferential flow and deflection; do not assume an arbitrary imposed linear head field remains a solution for heterogeneous K.
- **Transient flow (later):** storage and specific yield/specific storage, evolving water table, pumping/recovery, seasonal recharge; confined head is not automatically water-table elevation.
- **Vertical flow (later):** stratigraphic layers, anisotropy, vertical conductance, well screens and leakage.

### 12.2 Transport processes, in implementation order

| Process | Governing idea | First implementation | Critical caveat |
|---|---|---|---|
| Advection | Solute mass carried by volumetric groundwater flux | Conservative upwind flux across each hex face | Use **water flux × upwind aqueous concentration**, not arbitrary tile jumps |
| Mechanical dispersion | Velocity variability causes spreading | Longitudinal and transverse tensor projected onto each face | Dispersivity is scale dependent; numerical dispersion is not physical dispersion |
| Molecular diffusion | Movement down concentration gradients | Effective pore-water diffusion, including at zero flow | Tortuosity and porosity matter |
| Equilibrium sorption / retardation | Mass partitions between water and solid | `R_f = 1 + rho_b * Kd / n` for linear equilibrium sorption | `Kd` depends on **species and sediment**; don't double-count sorbed mass |
| Kinetic sorption / desorption | Slow release from sorbed reservoirs | Separate dissolved and sorbed mass compartments | Important for tailing and rebound |
| Biodegradation / abiotic reaction | Transformation or removal depends on chemistry | Explicit species-specific rate and products | Track daughter products; mass of each compound is not conserved across transformation, but constituent mass should be accounted for |
| Source dissolution | NAPL/solid source replenishes dissolved plume | Boundary/source term with finite source inventory | Pure-phase NAPL migration is a separate, advanced model |
| Volatilisation / gas transport | Partitioning into soil gas | Add only with a vadose-zone/gas model | Never teleport dissolved mass across tiles |
| Matrix diffusion / back-diffusion | Storage in low-K zones and later release | Dual-domain exchange or resolved low-K cells | Major driver of long-term persistence |
| Geochemical speciation | pH/redox affect form, mobility, reactions | Scenario-specific reaction networks | Needed for arsenic/metals, not universal simple decay |
| Density-dependent and multiphase flow | Brines and free-phase LNAPL/DNAPL | Advanced separate solvers | **Dissolved TCE is not DNAPL** |

### 12.3 Governing equations and mass bookkeeping

For a simple homogeneous saturated domain with linear equilibrium sorption, a teaching form of the advection–dispersion–reaction equation is:

`R_f ∂C/∂t = ∇·(D ∇C) − v·∇C − λ R_f C + S_C`

Here `C` is dissolved concentration, `D` the hydrodynamic dispersion tensor, `v` pore-water velocity, and `S_C` a consistently normalised source term. The shown decay term assumes first-order loss of the combined equilibrium sorbed/dissolved inventory; other reaction assumptions require different terms. This simplified equation assumes suitable constant properties and divergence-free steady flow.

**Implementation should instead use a conservative finite-volume mass balance**, with cell inventories and face fluxes:

- `V_water = n_e * V_saturated_cell` [m³].
- `M_aqueous = C * V_water` [kg].
- `F_adv_face = Q_face * C_upwind` [kg/s].
- `F_disp_face = -n_e * A_face * D_normal * (C_j - C_i) / distance` [kg/s], with appropriate face averaging and sign convention.
- `D_L = alpha_L * |v| + D_m_effective`; `D_T = alpha_T * |v| + D_m_effective`. Use a tensor and face-normal projection for general flow directions.
- For equilibrium sorption, either represent total equilibrium inventory with retardation **or** explicitly track dissolved/sorbed pools; do not apply both independently.
- Track `M_initial + M_sources = M_aqueous + M_sorbed + M_NAPL + M_extracted + M_exported + M_transformed + residual`, with constituent/species accounting defined consistently.
- Keep concentration nonnegative, use stability-limited numerical substeps, and report mass-balance error.
- **Do not use an arbitrary contaminant “speed boost”** as a real physics mechanic. Players can control scenario-authorised source timing or environmental interventions; contaminant intrinsic properties remain fixed.

### 12.4 Numerical verification before expanding features

Build automated, deterministic tests for:

1. **No-flow/no-gradient:** no advective transport; diffusion only if concentration gradients exist.
2. **Uniform flow:** correct advective direction, velocity and travel time.
3. **Conservation:** internal transfers cancel exactly; external sinks/sources reconcile with inventory.
4. **Nonnegative mass:** no negative concentrations after substeps.
5. **Pure diffusion:** plume spreads at zero groundwater velocity.
6. **Longitudinal vs transverse dispersion:** elongation follows flow direction and broadening follows transverse dispersivity.
7. **Retardation:** breakthrough delayed by expected factor for an equilibrium linear sorption benchmark.
8. **Decay and daughter products:** known first-order analytical behavior; constituent mass tracked through transformation.
9. **Well capture:** pumping changes flow field and removes dissolved mass by extracted-water concentration.
10. **Heterogeneous K:** solved head field obeys water balance; preferential paths emerge without arbitrary rules.

Compare simple one-dimensional advection–dispersion breakthrough curves with analytical solutions; later compare suitable benchmark cases with established groundwater-flow/transport software. Record assumptions, units, time step, grid resolution and tolerance in `docs/SIMULATION_ASSUMPTIONS.md`.

### 12.5 Educational user interface

Make **cause and effect inspectable**:

- Toggle geology/K, hydraulic head/equipotentials, water-flux arrows, dissolved concentration, sorbed inventory, reactions and remediation.
- Inspect each cell's geology, K, porosity, head, fluxes, concentration and mass.
- Display **source → pathways → receptor**, travel time and breakthrough curves.
- Offer prediction-before-simulation prompts, then explain observed migration.
- Display simulation time separately from game turns, and show a mass-balance panel.
- Label simplified mechanics explicitly; avoid presenting approximate results as field predictions.

### 12.6 Revised milestone gates

- **Gate A — verified flow:** uniform-K benchmark plus conservative heterogeneous-K head solver.
- **Gate B — verified transport:** conservative tracer advection with stable time stepping and mass accounting.
- **Gate C — physical plume:** effective molecular diffusion and anisotropic longitudinal/transverse dispersion.
- **Gate D — reactive transport:** sorption/retardation, degradation, species transformations and reaction accounting.
- **Gate E — coupled scenarios:** recharge, pumping, river boundaries, monitoring and physically credible remediation.
- **Gate F — vertical/advanced:** 3–5 layers, cross-sections, matrix diffusion and optional multiphase physics.

**Claude Code working rule:** Implement one gate at a time. For each physics feature, provide governing equations, dimensional checks, numerical method, assumptions, automated tests and a visible diagnostic before calling it complete.

## 11. Confidence and caveats

- **Concept and engine fit:** 0.95 — 2D hex-grid strategy is a strong match for Godot.
- **Prototype feasibility:** 0.85 — achievable if flow/transport scope is strictly limited.
- **Scientific fidelity:** 0.80 for a validated single-layer conservative model; lower for multiphase NAPL, complex geochemistry and unsaturated-zone flow without dedicated solvers.
- **Schedule:** 0.65 — estimates depend heavily on Godot familiarity and available development hours.

This is a design brief, not a verified groundwater model or a claim that all mechanics are scientifically validated.
