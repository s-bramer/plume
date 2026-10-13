# PLUME: Darcy's Curse — Game Concept & Development Brief

> Working project specification for Claude Code. Treat this as the source of truth for the initial Godot prototype, not a request to implement every feature immediately.

## 1. Elevator pitch

**Plume: Darcy's Curse** is a turn-based, 2D pixel-art strategy/puzzle game. The player is an environmental engineer/hydrogeologist racing to characterize, contain and remediate a contaminant plume before it reaches a vulnerable receptor — in the flagship scenario, a family farm's drinking-water well at the bottom of the map. The plume itself is not a second player; it's an unforgiving physical process that keeps migrating according to real geology, groundwater hydraulics and contaminant chemistry whether or not anyone is fighting it.

**Design pillar 1:** *Physics creates the puzzle.* Players should learn hydrogeology through visible cause and effect — watching a capture zone actually intercept a plume, watching a PRB actually run out of reactive capacity — rather than through quizzes or arbitrary "remediation power" buttons.

**Design pillar 2:** *A landscape worth protecting.* This is an environmental game, and the farm, the stream, the fields above the aquifer need to be genuinely lovely — the kind of place a player feels something about losing — not a diagram with sprites on it. Most educational games fail here; this one shouldn't. See §6 for how that bar is met without burying the science underneath it.

> **Revision note (2026-10-13):** earlier drafts had the player *embody* the plume, with an AI engineer as the opponent. That's retired as the primary mode — see §12 for the reasoning — but the asymmetric "play as the plume" idea is preserved as a possible later mode (§5), since the simulation core underneath is identical either way. A second revision (§12) elevates visual/audio quality from a Phase 3 afterthought to a first-class pillar, with its own tooling plan and an early, deliberately time-boxed "look-and-feel spike" ahead of Phase 1.

## 2. Audience and experience

- Indie strategy/puzzle players; students and practitioners of geology, hydrogeology and environmental engineering.
- Short, readable turns (roughly 1–2 minutes), with meaningful trade-offs and replayable scenarios.
- Playful, slightly ominous tone; scientific fidelity where it affects decisions, simplified where necessary for clarity.
- Initial target: desktop PC. Browser/mobile are possible later, not Phase 1 commitments.

## 3. Gameplay loop

1. **Characterize:** Spend budget/turns on monitoring wells, soil borings or geophysics to reveal geology, heads and concentrations that start hidden. The subsurface is fog-of-war by default — you only know what you've measured, same as a real site investigation.
2. **Plan:** Choose one remediation/control action within budget (a pump-and-treat well, a PRB, a bioremediation injection, monitored natural attenuation) — or choose to invest this turn in more characterization instead of action. Actions must respect the contaminant's and the site's actual properties.
3. **Hydraulic update:** Rainfall/recharge, pumping (yours, and any background pumping already on the map), boundary conditions and geological heterogeneity determine heads and intercell water fluxes.
4. **Transport/reactions:** Mass migrates by advection/dispersion and may sorb, desorb, degrade or transform according to the scenario — the plume keeps moving on its own physics regardless of what the player chose.
5. **Receptor check:** Evaluate concentration/exposure at the receptor against its threshold.
6. **Feedback:** Animate the plume and update mass balance, concentration map, flow arrows, objectives and a brief explanation of *why* it moved (and why a remedy did or didn't work).
7. **Repeat** until the receptor is protected (win) or its exposure threshold is exceeded, or the budget/turn limit runs out with risk unresolved (loss).

The player **does not get a magic "clean now" button**, and can't freely steer contamination or change intrinsic chemical properties. Every remediation action only works to the extent its own physics allow: a pumping well only captures the plume if it's positioned and pumped to generate adequate capture; a PRB only works if the contaminant's residence time in the barrier is long enough for the reaction; monitored natural attenuation only works if degradation/dilution genuinely outpaces the plume's advance. A poorly chosen action should visibly fail, not just under-perform. For the first prototype, a temporary 'instant capture' mechanic can be used to test fun, but should ultimately be replaced by a defensible capture-zone calculation (e.g. pumping rate vs. ambient gradient and conductance).

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

- MVP: imposed linear head gradient with heterogeneous `K`; compute face fluxes from head differences and conductance.
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

**MVP contaminant: nitrate as a conservative tracer first**, then introduce plausible denitrification as an advanced scenario. Do not start with multiphase NAPL.

### Player tools: characterization and remediation

- Soil borings / geophysics: reveal geology and K at a location, at a one-time cost. Primary way to lift fog-of-war on the subsurface before committing to a remedy.
- Monitoring wells: reveal concentrations at selected locations/depths, repeatedly over time (ongoing cost, not one-time).
- Pump-and-treat wells: alter hydraulic gradients and extract dissolved mass; capacity/cost constraints.
- Permeable reactive barriers: allow flow while reacting with appropriate contaminants, subject to residence time and capacity.
- Bioremediation: change suitable geochemical conditions, with potential byproducts.
- Containment walls and hydraulic control: redirect flow, potentially creating bypass pathways.
- Monitored natural attenuation: lower cost but dependent on evidence and timescale.

**Important:** A pumping well is a hydraulic sink and mass-extraction mechanism, not an impermeable blocking tile. A PRB is not a universal filter for every species.

## 5. Objectives and strategy

- **Player (engineer) objective:** protect the receptor — keep exposure below its defined threshold (drinking-water supply, river, wetland) — within budget and turn limits, while characterizing and remediating a plume that doesn't wait for you.
- **The plume is not played directly** in the core mode. It's governed by the scenario's geology/chemistry and, optionally, an uncertain or evolving source term (a tank that keeps leaking at an unknown rate, a seasonal recharge pulse, a neighbor's well shifting the gradient) — this keeps the "opponent" genuinely threatening without needing a smart adversarial AI.
- Scoring: receptor risk avoided, remediation cost, elapsed time/turns, remaining mass, characterization efficiency (information gained per dollar spent), and a scientific explanation/learning summary at the end of each scenario.
- Later: scenario campaigns, varied receptor types (public supply well, stream, wetland) with different thresholds, and an asymmetric local-multiplayer / "hard mode" that revives the original embody-the-plume idea — one player chooses source characteristics or release timing within realistic constraints, the other plays engineer — built on the same shared simulation core rather than a separate game.

## 6. Visual direction and UX

**The landscape is content, not chrome.** The surface world — the farm, its fields, the stream, the tree line — should read as a real, lived-in place the player grows attached to, well before any overlay is switched on. Budget actual art-direction effort here; don't treat it as a skin applied once the systems work.

- **2D pixel art**, pointy-top hexes, dark aquifer blue `#0D1B2A`, toxic green `#9FE870`, sandy beige `#E6D2A3`, rust red `#B34040`, vapor grey `#C5C6C7`. Reserve the saturated colors (toxic green, rust red) for contamination and alerts; keep the healthy landscape itself in warmer, calmer, slightly desaturated tones so the palette alone tells you when something's wrong.
- **Autotiled terrain.** Use Godot's terrain sets on `TileMapLayer` so geology types blend with transition tiles at their edges rather than snapping hard — hard edges read as a spreadsheet, blended edges read as a place. Budget base + edge-transition art per geology type, not just one tile per type.
- **The hardest visual problem in the brief: pretty art and legible data overlays fighting each other.** A detailed, busy hand-painted tile makes a semi-transparent concentration heatmap or contour line murky; a flat, calm tile lets the overlay read instantly. Resolve this by design, not by accident: keep the base terrain's value range and detail relatively restrained, and let overlays (heatmap, contours, flow arrows, well influence) carry the high-contrast, high-saturation information layer on top. Treat this specific risk as the first thing to test (§8, Phase 0), because it's the one thing hardest to fix after dozens of tiles already exist.
- **Ambient life, separate from data.** Idle animation (grass sway, water glint, birds, drifting dust/pollen) should run continuously and read as "alive," independent of simulation state — it's mood, not information, and should never be mistaken for a flow arrow or concentration cue.
- **Interaction feel.** Placing a well/PRB/monitoring point is a core, repeated verb — treat it like a AAA city-builder would: hover shows a ghost preview (and whether the placement is even valid), click confirms with a short, satisfying settle animation plus a sound cue, and a brief particle/ripple sells that something real just happened in the world. Removing or disabling a tool should feel just as deliberate, not an instant delete.
- **Sound as a second channel for information.** A quiet ambient bed (wind, water, birdsong) carries the "healthy farm" feeling; discrete SFX mark actions (placing a well, a borehole sample coming back, a remedy activating); a subtle, non-alarming audio shift near the receptor as risk rises keeps tension legible even when a player isn't staring at the numbers. Keep it tasteful — an "environmental" game shouldn't sound like a casino.
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

### Art, animation and audio tooling

All native to Godot 4 or free/cheap and widely used by solo devs — nothing exotic needed:

- **Pixel art authoring:** Aseprite (small one-time cost, industry-standard for pixel art + sprite-sheet animation, palette-lock and tile-aware, exports formats Godot imports cleanly). Worth owning if any meaningful amount of custom art is planned.
- **Terrain/autotiling:** Godot's built-in `TileMapLayer` terrain sets handle the edge-blending described in §6 natively — no plugin needed.
- **Animation/"juice":** `Tween` for procedural easing (hover ghosts, placement pop-and-settle, UI counters ticking); `AnimationPlayer` for sprite-sheet-driven ambient loops (grass sway, water glint); `GPUParticles2D` for ripples, dust, rain, contamination shimmer — all built in.
- **Overlay rendering:** a `canvas_item` (2D) fragment shader is the right tool for blending a heatmap/contour layer over terrain without baking it into tile art — approachable even with minimal shader experience, and it's the piece most worth prototyping first (§8, Phase 0).
- **UI:** Godot `Theme` resources for consistent, polished controls (buttons, tooltips, panels) without hand-styling each one.
- **Asset sourcing, so art doesn't block systems work:** Kenney.nl (CC0, free, very usable for prototyping and often good enough to ship with restyling) and itch.io's pixel-art asset marketplace (many affordable, cohesive farm/nature tilesets from dedicated pixel artists) are worth testing against *before* committing to fully custom art — see Phase 0. freesound.org and Kenney's audio packs cover CC0 SFX; loop-friendly ambient music is easy to find on itch.io or under Creative Commons (e.g. incompetech). Commission a custom tileset later, once the art direction is locked by the spike, not before.
- **Hex grid math reference:** Red Blob Games' "Hexagonal Grids" guide is the standard reference for axial/offset coordinates, neighbors and world-space conversion if §7's coordinate convention needs a refresher.

**Honest complexity note:** hitting all of §6's bar — lovely landscape, legible overlays on top of it, smooth interaction feel, layered sound — is realistically **comparable in effort to the simulation engine itself**, not a coat of paint applied afterward. Many shipped indie games spend the majority of total development time in exactly this category even when their systems are simple. That's not a reason not to do it — it's the brief's second design pillar now — but it should be budgeted as real scope, not squeezed into Phase 3/4 as originally drafted.

## 8. Development roadmap

### Phase 0 — Look-and-feel spike (time-boxed; recommended before Phase 1 systems work)

A deliberately small, disposable-if-needed prototype whose only job is to retire the biggest *unknowns* about the visual pillar before any simulation work or large art investment — not an open-ended sandbox to keep adding to, since that risks consuming the whole project with no definition of done. Time-box it (days, not weeks) and stop once these four questions are answered:

1. **Overlay legibility:** does a semi-transparent concentration heatmap/contour line actually read clearly over a candidate pixel-art terrain style, using real-shaped synthetic data (not a placeholder gradient)? This is the single highest-risk item in §6 — test it before producing a full tileset around a style that might not support it.
2. **Interaction feel:** build the hover-ghost → click-confirm → settle-animation → sound loop for placing one thing (a well). If this one verb doesn't feel good, nothing built on top of it will.
3. **Tile budget:** with autotiling, how many unique tiles/variants does a convincing landscape actually need? This sets a realistic art budget before committing to hand-drawing everything.
4. **Style source:** test 1–2 candidate off-the-shelf tilesets/palettes (Kenney, itch.io) against questions 1–3 before deciding whether to hand-draw custom art or reskin a purchased set.

Answering "yes, cleanly" on (1) in particular should gate whether Phase 1's gray-box prototype can carry already-charming (if not final) art, rather than true placeholder boxes — worth doing, since redoing a tileset after dozens of tiles exist is expensive, and your instinct that look-and-feel is crucial enough to test early is right. The risk in a sandbox isn't testing early, it's testing *without a stopping condition* — these four questions are that stopping condition.

### Phase 1 — Gray-box playable prototype (target: 2–3 weeks, flexible)

1. Confirm Godot version, scene tree and existing hex TileSet; avoid rebuilding assets that already work.
2. Generate or register a small hex map (radius ~8), with click/hover and correct coordinate conversion.
3. Create data-backed cells with `K`, effective porosity, elevation and hydraulic head; visualize geology/head on the grid.
4. Prescribe a simple head gradient and compute face fluxes using Darcy's law.
5. Seed a finite contaminant mass in one or more cells; implement conservative, one-layer, advection-only transport.
6. Add Next Turn (Space), turn counter, concentration overlay, mass-balance display and reset.
7. Add one physically defensible player remediation choice (e.g. a capture well with specified pumping rate) and one source behavior that keeps threatening the receptor without player input (e.g. a continuing release from the source).
8. Add a receptor target, win/loss rules and a short on-screen explanation of each turn.
9. Write tests for zero-gradient transport, uniform gradient direction, mass conservation, nonnegative concentrations and boundary handling.

**Definition of done:** play 5–10 turns; changing heads/`K` changes migration; a pumping well changes capture; mass is accounted for; player can win or lose; no placeholder mechanic is mistaken for real physics.

### Phase 2 — Scientific depth and strategy

- Heterogeneous geology; solved steady-state heads; recharge and pumping; dispersion; sorption; simple reactions; monitoring and PRBs; scenario configuration; AI response.
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
8. **Remediation is not an "I win" button.** Every defense (well, PRB, MNA) only works to the extent its own physics allow — a poorly placed or underpowered capture well should visibly do nothing, not just underperform.
9. **Information has a price.** Keep real geology, heads and concentration partially hidden until the player characterizes the site. Spending budget on investigation vs. action is itself the core strategic trade-off, and it mirrors how real site investigations are scoped.

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

> Read `PLUME_PROJECT_BRIEF.md` (player is the engineer protecting the receptor, not the plume), inspect my current Godot project and tell me which Phase 1 requirements are already implemented. Then propose the next three small tasks. Implement only the first task after explaining the planned files and acceptance test. Preserve my existing hex TileSet and scene setup.

## 11. Confidence and caveats

- **Concept and engine fit:** 0.95 — 2D hex-grid strategy is a strong match for Godot.
- **Prototype feasibility:** 0.85 — achievable if flow/transport scope is strictly limited.
- **Scientific fidelity:** 0.80 for a validated single-layer conservative model; lower for multiphase NAPL, complex geochemistry and unsaturated-zone flow without dedicated solvers.
- **Schedule:** 0.5 (revised down from 0.65) — the visual/audio quality bar in §6 is now explicit first-class scope, not a Phase 3/4 afterthought, and is realistically comparable in effort to the simulation engine (§7). Estimates still depend heavily on Godot familiarity, art/audio skill or budget, and available development hours.
- **Visual pillar feasibility:** 0.7 — the tools (§7) are all proven and widely used by solo devs, but marrying legible scientific overlays with genuinely charming pixel art (§6) is a real, untested design problem for this specific project, not just an execution risk. Phase 0 exists to de-risk it early rather than discover it late.

This is a design brief, not a verified groundwater model or a claim that all mechanics are scientifically validated.

## 12. Revision notes

**2026-10-13 — Player flipped from plume to engineer.** Originally the player embodied the contaminant, with an AI opponent playing the engineer. Changed so the player is the engineer/investigator protecting a receptor (flagship: a farm's drinking-water well) from a plume that's governed by physics and scenario events, not played by anyone. Reasons, in order of weight:

1. **Removes the hardest unsolved problem in the original design.** A competent adversarial "AI engineer" is a much harder build than the groundwater physics itself. An engineer-as-player / plume-as-physics design needs zero game-AI to be a worthy opponent — the opponent is just unforgiving transport equations, which this brief already specifies in detail.
2. **Better win-state tone.** "Win by poisoning a farm's well" is an uncomfortable payoff to design toward, even as a puzzle abstraction. "Protect the farm" carries the same stakes without that discomfort.
3. **Stronger pedagogical core.** "Characterize an unknown site under budget, then design a remedy that holds up against real capture-zone and reaction-kinetics physics" models the actual job of an environmental engineer/hydrogeologist, rather than teaching hydrogeology from the contamination side.
4. Added two concrete mechanics to keep cleanup-mode from collapsing into "click tool, win" (and to replace the tension the adversarial AI would have provided): **fog-of-war site characterization** (§3, §4, guardrail 9) and an explicit **remediation-can-fail** guardrail (guardrail 8).

**Not discarded:** the original "embody the plume" premise is a genuinely distinctive hook, so it's kept as a later asymmetric-multiplayer/hard mode (§5) built on the same simulation core — nothing about the shared architecture (§7) needed to change to support this later.

**2026-10-13 — Visual/audio quality elevated to a first-class pillar; added a Phase 0 spike.** Added design pillar 2 (§1), rewrote §6 around the risk of pretty art vs. legible data overlays fighting each other, added an art/animation/audio tooling list (§7), and added a time-boxed "look-and-feel spike" ahead of Phase 1 systems work (§8) to answer that risk — plus three other concrete unknowns (interaction feel, tile budget, style source) — before committing to a full tileset. Reasoning: the stated goal (a landscape the player feels protective of, smooth polished interactions, sound) is a real, distinct pillar from the simulation fidelity work, with its own failure modes (most educational games fail specifically here) — it needed its own section and its own early validation step rather than living implicitly inside "Phase 3 presentation." Schedule confidence (§11) revised down accordingly, and a new "visual pillar feasibility" caveat added rather than folding the risk silently into the existing schedule number.
