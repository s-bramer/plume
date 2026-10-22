# Backlog

Ideas deliberately parked rather than built now -- either because they depend on state/systems that don't exist
yet, or because building them now would mean guessing at a mechanic before its real shape is known. Not a
roadmap or a decision record (see `docs/DECISIONS.md` for those); just things not to lose track of.

## Subsurface "x-ray" view, with fog-of-war tied to characterization

Raised by the user 2026-10-20, alongside the request for a flow-vector overlay (`scripts/rendering/flow_overlay.gd`,
`docs/DECISIONS.md`'s 2026-10-20 entry) -- that overlay was deliberately built as a simple, always-fully-revealed
layer on the existing map, NOT this.

The idea: a separate view/mode, distinct from the beautiful surface terrain, that shows the player's *current
understanding* of the subsurface -- geology, groundwater head/levels, flow vectors, contaminant plume -- styled
to feel like an x-ray (per the brief SS6's "geology / hydraulic head / flow / concentration / remediation" overlay
toggles and "per-cell inspector" idea). Two things make this more than "the flow overlay but styled differently":

1. **Fog-of-war, driven by characterization.** The subsurface is only as revealed as what's actually been
   measured (brief SS4/SS9: "the subsurface is fog-of-war by default -- you only know what you've measured").
   A cell's geology/head/flow should be hidden or uncertain until a borehole, pump test, or other characterization
   action has sampled it (or nearby it, with some falloff). This needs: a per-cell "known/confidence" state, an
   actual characterize action that sets it, and a budget/turn system to spend on that action -- none of which
   exist yet. Building the reveal mechanism before the action that drives it exists risks designing it twice.
2. **Difficulty-scaled reveal.** "Less or more revealing according to selected difficulty level" -- e.g. easier
   difficulties reveal a wider radius per characterization action, or show an approximate/blurred value before an
   exact one; harder difficulties require denser sampling or show nothing at all outside measured cells. Needs a
   difficulty setting to hang off of, which also doesn't exist yet.

**Suggested trigger to pick this up:** once the turn loop + characterize action land (brief SS8 Phase 1 steps
~6-9), revisit this. At that point `World.cell_info()` (already built, 2026-10-20) is the natural per-cell data
source to gate by a new `known`/`confidence` field, and `flow_overlay.gd`'s arrow-drawing code is directly
reusable for the flow layer inside the new view -- just don't always-show every cell any more.
