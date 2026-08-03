# Biochemical cross-disconfirmation among the enterobacteriaceae siblings — design & slice plan

> Status: **DESIGN — awaiting David's review before any code.** Opens the feature
> (branch `feature/sibling-cross-disconfirmation`). Logged as
> `corpus-expansion-sketch.md` §5 candidate 4.

## 1. Why (the gap, observed live)

The enterobacteriaceae sibling discriminators are currently **confirming-only,
except urease**. Each biochemical rule *concludes* a species from a positive pattern
(lactose+/indole+ → E. coli, red pigment → Serratia, …), but almost none *argue
against* a competing species. So two mutually-exclusive siblings can both sit at
`pl 1.0` even when the biochemistry is internally contradictory.

Observed in a clinician session 2026-07-30
(`neomycin/clinician-samples/…` predecessor; logged in corpus-sketch §5 cand. 4): an
aerobic gram-neg rod read **lactose+/indole+** (E. coli, `bel 0.64`) *and* **red
pigment** (Serratia, `bel 0.60`) — and the differential came back with **both at
plausibility 1.0**, neither pulling the other down, even though one organism cannot
be both. The LLM correctly flagged it as clinically odd, but the *engine* could not
express the conflict.

The lone counter-example is `urease-pos-argues-against-urease-negative-organism`
(slice C1) — the single cross-disconfirming rule, and the model for this increment.
Generalizing that pattern is the **highest-fidelity, lowest-effort DS enrichment**
now that the family has six species: it turns a contradictory biochemical finding
into real Dempster conflict (`pl` dropping below 1.0 on the loser) instead of silent
co-plausibility. It is squarely on the fork's DS-legibility thesis.

## 2. The mechanism already exists

Disconfirming rules key off (a) a contradicting parameter value on `?o` **and** (b) a
live `organism-identity` on `?o`, then re-assert that identity with a **negative**
rule belief. Under Dempster-Shafer that negative mass lands on `¬H`, so meeting the
confirming mass produces conflict `K > 0`: `bel` falls **and** `pl` drops below 1.0.
Under CF it combines as a negative CF. The four current disconfirming rules
(`…rulebase.lisp`) all use this shape; the new rules are more of the same, keyed to
the biochemical discriminators. **No engine change** — this is pure corpus authoring
+ goldens (unlike the last two increments).

## 3. The biochemistry (authoritative, per NCBI NBK8035)

Reference profile for the family's members (Baron, *Medical Microbiology* 4th ed.
ch. 26, **NBK8035** — already the primary citation on these rules). `+`/`−`/`v`
(variable); the five discriminators are exactly our fact vocabulary:

| Species | lactose | indole | motility | urease | red pigment |
|---|---|---|---|---|---|
| **E. coli** | fermenter | **+** | motile | − | none |
| **Klebsiella** | fermenter | − | **non-motile** | + | none |
| **Enterobacter** | fermenter | − | motile | v | none |
| **Salmonella** | **non-fermenter** | − | motile | − | none |
| **Serratia** (marcescens) | v (slow) | − | motile | v | **red** |
| **Proteus** | **non-fermenter** | v* | **swarming** | **+** (rapid) | none |

*P. mirabilis indole−, P. vulgaris indole+ — so **Proteus is deliberately left out
of any indole-based disconfirmation** (honest: the marker is ambiguous for it).

## 4. Proposed cross-disconfirming rules

Each mirrors the existing disconfirming shape: `(discriminator value) + a live
organism-identity in a contradicting member set → re-assert with a negative belief`.
Beliefs are **illustrative** (schematic teaching figures, per the v0.4.0
`:belief-basis` convention); every rule carries two-axis `:provenance` (NBK8035 is the
evidence — the invariant test *requires* provenance on every rule). Magnitudes track
how cleanly the marker excludes.

**Core set (closes the observed gap + the classic Salmonella marker):**

1. **`red-pigment-argues-against-non-serratia`** (−0.7) — `pigment = red` argues
   against `{e-coli, klebsiella, salmonella, enterobacter, proteus}`. Prodigiosin is
   essentially Serratia-specific; seeing it makes a non-Serratia call unlikely.
   *(Closes half the session gap: red pigment now pulls E. coli down.)*
2. **`indole-pos-argues-against-indole-negative-species`** (−0.6) — `indole =
   positive` argues against `{klebsiella, enterobacter, salmonella, serratia}` (all
   characteristically indole-negative; Proteus excluded per §3). *(Closes the other
   half: indole+ now pulls Serratia down.)*
3. **`lactose-fermenter-argues-against-non-fermenters`** (−0.7) — `lactose =
   fermenter` argues against `{salmonella, proteus}`. The classic teaching point:
   Salmonella and Proteus are non-lactose-fermenters.

**Optional (round out the lactose axis; decide in review):**

4. **`lactose-non-fermenter-argues-against-fermenters`** (−0.6) — `lactose =
   non-fermenter` argues against `{e-coli, klebsiella, enterobacter}` (strong
   fermenters). Serratia excluded (slow/variable lactose — honest).

**Deliberately *not* proposed** (keeping scope tight and honest):
- Motility-based disconfirmation (`non-motile` vs the motile species). Motility is the
  messiest marker (Klebsiella's non-motility is the only clean signal, already used
  *positively* for Enterobacter); a disconfirming rule here would be weak and
  error-prone. Parked.
- A full discriminator×species matrix. We reconstruct a *cited, defensible subset*,
  not an invented exhaustive table (provenance policy, corpus-sketch §4).

## 5. What it buys — DS conflict made legible

Re-run the session case (**lactose+ / indole+ / red pigment**) under the core set:
- **E. coli** — confirmed at 0.64 by lactose+/indole+, then **disconfirmed by red
  pigment** (rule 1): `bel` falls, `pl` drops below 1.0.
- **Serratia** — confirmed at 0.60 by red pigment, then **disconfirmed by indole+**
  (rule 2): `bel` falls, `pl` drops below 1.0.

Both siblings now carry a **plausibility ceiling below 1.0** — the engine says, in
its own algebra, *"these two are mutually contradictory; the biochemistry doesn't
cleanly fit either."* That is exactly the honest, legible output the flat `pl 1.0`
could not give — and via `/why` (v0.4.0) the clinician can see *which* finding pulled
*which* species down, with citations. It also strengthens the CF-vs-DS contrast: CF
collapses each to a single lowered number; DS shows the conflict as a widened,
lowered interval.

## 6. Affected goldens (expected re-capture)

Adding rules re-captures goldens; the affected ones are known and small:
- **`chain-sibling-urease-conflict-*`** (chain-tests.lisp) drives
  lactose+/indole+/urease+/swarming → E. coli + Proteus. Rule 3 (`lactose fermenter`)
  now **also disconfirms Proteus** (Proteus is a non-fermenter), so Proteus's `pl`
  drops below 1.0 in that scenario too — a *more* complete conflict demonstration, but
  new numbers. Re-capture (hand-verify the DS arithmetic, as before).
- Per-rule isolation tests for the four species fire a **single** species with no
  competing identity present, so the new disconfirming rules do **not** fire there —
  those goldens are unaffected. (Verify empirically, don't assume.)
- Scenario/therapy goldens (culture-1/1a/2/3) use no biochemical discriminators →
  unaffected.

## 7. Slice plan (each green + committed separately)

- **Slice 0 — this doc.**
- **Slice A — the cross-disconfirming rules.** Add the core set (rules 1–3; rule 4 per
  review) with two-axis `:provenance` (origin `:neomycin-extrapolation`, evidence
  NBK8035, `:belief-basis :illustrative`). Per-rule isolation tests (each fires and
  lowers only its member species). The provenance invariant test must stay green
  (every rule has provenance) and the rule count updates.
- **Slice B — the conflict goldens.** A new two-sibling golden: lactose+/indole+/red
  pigment → E. coli and Serratia **both `pl < 1.0`**, hand-verified DS arithmetic
  (CF + DS), plus the behavioral property (a contradictory marker drops the
  contradicted sibling's plausibility, leaves the consistent one's at 1.0). Re-capture
  `chain-sibling-urease-conflict-*`.
- **Slice C — docs sync.** Rule count (23 → 26/27) in CLAUDE.md/runbook/system-prompt/
  corpus-sketch; the disconfirming-rules section of `system-prompt.md` (the LLM should
  narrate a dropped plausibility as "the red pigment argues against E. coli"); extend
  Scenario 9's sibling variation in `clinician-scenarios.md`; mark corpus-sketch §5
  candidate 4 delivered.

## 8. Open questions (for review)

1. **Scope:** core set (rules 1–3) only, or include rule 4 (lactose-non-fermenter)?
   Recommendation: include rule 4 — it's symmetric with rule 3 and equally clean.
2. **Belief magnitudes:** proposed −0.6/−0.7. Red pigment (rule 1) could arguably be
   −0.8 (prodigiosin is very specific). Tune against the goldens.
3. **Salmonella/Klebsiella reach:** they're chained off host/travel context, not
   biochemistry, so they rarely co-fire *with* a biochemical species in one organism.
   The disconfirmation still applies if they do (e.g. a Salmonella call meeting a
   lactose+ reading) — worth a golden, or leave to the natural scenarios? (Lean: one
   targeted golden.)