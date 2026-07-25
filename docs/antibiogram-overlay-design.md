# Antibiogram overlay (empirical interval width from isolate counts) — design

A follow-on to belief-valued susceptibilities
([`susceptibility-belief-design.md`](susceptibility-belief-design.md) §6) and the
therapy phase ([`therapy-phase-design.md`](therapy-phase-design.md) §3.1). S1–S3
made susceptibilities into Dempster-Shafer `[bel, pl]` intervals, but their
**width is hand-authored** — a modeling guess about how solid the antibiogram is.
This increment makes that width **empirical**: a site-local `(organism, drug) →
(n-susceptible, n-tested)` count becomes a susceptibility interval whose ignorance
shrinks as `n` grows. Few isolates → wide (provisional); many → narrow (solid) —
*by construction*, not by hand.

> **⚠️ NOT FOR CLINICAL USE.** The antibiogram counts here are schematic and
> illustrative — invented to exercise the machinery, not drawn from any real
> surveillance. Nothing here is a basis for prescribing.

---

## 1. Motivation

This is the feature §6 of the susceptibility doc deferred and named the "natural
next": *"a site-local `(organism, drug) → (n-susceptible, n-tested)` becomes a
susceptibility interval whose ignorance shrinks as `n` grows (a credal/Beta-style
read of the counts)."* It closes the loop on neomycin's thesis — **Dempster-Shafer
makes uncertainty visible** — on the treatment side, with the uncertainty now
*earned from data* rather than asserted.

It is also the thing 1978 MYCIN structurally could not do (therapy design §3.1,
principle #2): reflect *this ward's* resistance patterns rather than a global
average. "Pseudomonas here is 68% ciprofloxacin-susceptible across 50 isolates"
is a different, and more actionable, statement than a textbook point estimate —
and the interval makes the *sample size* legible: 68% from 50 isolates is solid;
68% from 3 is a coin toss dressed up as a number.

---

## 2. What already exists (the substrate)

S1–S3 built exactly the substrate this needs, so the overlay is additive:

- **The solver consumes intervals unchanged.** `susceptibility->scalar`
  (`greedy-solver.lisp`) already reduces any `ds-belief` susceptibility; the
  coverage-gate dial already decides `bel`/`pl`/`midpoint`. The overlay only needs
  to **produce** intervals — it touches neither the solver nor the gate.
- **Susceptibility handling is decoupled from the identification algebra**
  (decision C). Whatever the overlay produces reduces and serializes identically
  under CF and DS. **This constrains the overlay too — see §4.**
- **The KB is behind an accessor.** `kb-susceptibility` (`kb.lisp`) is the single
  read point the solver uses; the overlay slots in *there*, so the authoring
  surface and storage stay decoupled (therapy design §3.2).
- **`def*` authoring keeps the KB reviewable as a diff** (principle #3). The
  antibiogram is authored the same way, in its own file, so a site swaps it in as
  a tracked commit.

---

## 3. The counts → interval mapping (the core)

Given `s` susceptible of `n` tested, produce `[bel, pl]`. The requirements are
sharp and they select the model:

1. `n = 0` → `[0, 1]` (no data = total ignorance / vacuous belief).
2. ignorance `pl − bel` **decreases monotonically** as `n` grows.
3. as `n → ∞`, the interval collapses to the point `s/n`.
4. `bel` is a lower bound we can act on conservatively; `pl` the optimistic ceiling.

**Recommended: the Imprecise Dirichlet Model (IDM) / credal-Beta reading.**

```
bel = s / (n + σ)
pl  = (s + σ) / (n + σ)
ignorance = pl − bel = σ / (n + σ)
```

where `σ > 0` is a concentration ("number of hidden trials") — a policy knob.
This satisfies all four requirements exactly: at `n = 0` it is `[0, 1]`; ignorance
`σ/(n+σ)` shrinks monotonically and → 0; the interval brackets `s/n` and collapses
to it. `σ = 1` is the light-prior choice; `σ = 2` is Walley's classic IDM default
(more cautious for small `n`). Expose `σ` as `*antibiogram-concentration*`,
defaulting to a documented value (proposed: `2`).

*Rejected alternatives:* frequentist confidence intervals (Wilson,
Clopper–Pearson) model *sampling* uncertainty, not belief, and don't cleanly give
`[0, 1]` at `n = 0`; a single Beta credible interval needs an arbitrary prior and
interval-width choice. The IDM is the DS-native fit — an interval of probabilities
*is* a credal set — and it is a one-line formula.

---

## 4. Pivotal decision — how the overlay COMBINES with the canonical susceptibility

The canonical KB (S1) already carries a hand-authored interval for most
`(organism, drug)` pairs. When a local antibiogram entry *also* exists, what wins?
This is the decision the naive path trips over.

- **(A) Replace where present.** The local interval overrides the canonical figure
  outright. Simple and predictable. But a tiny sample (`n = 2 → ~[0, 0.7]`) would
  *discard* a solid curated figure and replace it with near-vacuum — throwing away
  good reference information precisely when the local data is weakest.
- **(B) Dempster-combine canonical ⊕ local.** *Recommended.* Treat the canonical
  interval and the count-derived interval as two belief functions on the same
  single-hypothesis frame ("this organism is susceptible to this drug") and combine
  them with Dempster's rule. This has the property (A) lacks: **the overlay's
  influence auto-scales with `n`**. A vacuous local interval (small `n`, ≈ `[0,1]`)
  combines to leave the canonical figure essentially unchanged; a sharp local
  interval (large `n`) dominates. No magic threshold, and it is the *same algebra
  neomycin exists to showcase*, now on the treatment side.
- **(C) Threshold fallback.** Use local iff `n ≥ n-min`, else canonical. Crude, and
  it reintroduces the arbitrary constant (B) avoids.

**Recommendation: (B).** It is conceptually right and it **reuses tested
machinery** — the DS `combine-beliefs` already implements Dempster's rule on
exactly this frame (`dempster-shafer.lisp`).

> **⚠️ Decision C strikes a third time.** `combine-beliefs` is a method *on the
> active belief system* — so combining canonical ⊕ local *through it* would work
> under DS and **error under CF**, the identical trap decision C removed for
> reduction (`susceptibility->scalar`) and serialization (`susceptibility-bounds`).
> Susceptibility handling — reduction, display, **and now combination** — is
> orthogonal to the identification algebra. So the overlay must combine the two
> intervals **natively** (a susceptibility-specific Dempster combination over
> `ds-belief-bel`/`pl`, not routed through `belief:*belief-system*`). This is the
> single most important implementation constraint in this doc; budget a small
> `combine-susceptibility` helper for it, tested under both algebras.

A raw *scalar* canonical susceptibility (should any remain) has no interval to
combine; treat it as the degenerate `[s, s]` and combine, or short-circuit to the
local interval — decide during the spike.

---

## 5. Authoring & loading

A `def*` form in its own file (`antibiogram.lisp`), loaded like
`knowledge-base.lisp` and equally diff-reviewable:

```lisp
;; (organism drug :susceptible s :tested n) — schematic, site-local counts
(defantibiogram :pseudomonas :ciprofloxacin :susceptible 34 :tested 50)
(defantibiogram :pseudomonas :gentamicin    :susceptible 41 :tested 48)
```

`defantibiogram` populates a site-local table in the KB abstraction, keyed
`(organism, drug) → (s . n)`. Keeping it in a **separate file** from the canonical
KB is the point: a deployment swaps *its* antibiogram without touching the curated
reference table — therapy design principles #2/#3 made concrete. `kb-susceptibility`
becomes the integration point: if an antibiogram entry exists, derive its IDM
interval (§3) and combine with the canonical figure (§4); otherwise return the
canonical figure unchanged.

---

## 6. Surface & narration

Carry **provenance** into the recommendation JSON so the interval's *pedigree* is
narratable, not just its bounds. Extend the susceptibility entry (S2's
`susceptibility-entry->json`) with the sample size and source, e.g.:

```json
{"organism": "pseudomonas", "bel": 0.66, "pl": 0.78, "ignorance": 0.12,
 "n_tested": 50, "source": "local-antibiogram"}
```

This lets Claude say *"ciprofloxacin covers Pseudomonas at 68% across 50 local
isolates (belief 0.66) — reasonably solid"* versus *"reference estimate only, no
local isolates — treat as provisional."* A short `system-prompt.md` addition
teaches it to cite `n` and distinguish local from reference. `n = 0` / absent means
"reference only," which is the pre-overlay behavior.

---

## 7. Testing

- **Mapping (§3):** golden `[bel, pl]` for representative `(s, n)` — `n = 0 →
  [0, 1]`; `s = n` large → narrow near 1; `s = 0` large → narrow near 0; ignorance
  strictly decreasing in `n`; sensitivity to `σ`.
- **Combination (§4) under BOTH CF and DS** — the decision-C-strikes-again test:
  vacuous local leaves canonical ≈ unchanged; sharp local dominates; and it does
  **not** error under CF.
- **Integration:** an `(organism, drug)` with an antibiogram entry gets the overlaid
  interval; one without falls back to canonical; the solver's coverage decision
  reflects the overlaid `bel` under the default gate.
- **Serialization (§6):** the JSON susceptibility carries `n_tested`/`source`;
  absent overlay ⇒ reference shape.

Identification goldens are untouched — this stays in the therapy layer.

---

## 8. Scope & non-goals

- **In:** IDM counts→interval (`σ` dial); `defantibiogram` authoring in its own
  file; native combination with the canonical figure (§4) into `kb-susceptibility`;
  provenance (`n`, source) in JSON + narration; tests across both algebras.
- **Out (this increment):** real surveillance data (schematic only); time-decay or
  recency-weighting of isolates; stratification by patient subpopulation; exposing
  `σ` as a per-request bridge dial (start with a session var, promote later if
  wanted); the exact-solver oracle and drug–drug interactions (separate features).
- **Always:** NOT FOR CLINICAL USE. Counts model data volume for research
  legibility; they are not real antibiogram statistics.

---

## 9. Open questions (resolve during a short spike, before S-increments)

1. **`σ` default** — `1` (lighter) vs `2` (Walley IDM, more cautious for small `n`).
   Proposed `2`; confirm against how wide small-`n` intervals *feel* in a demo.
2. **Combination (§4)** — confirm **(B) native Dempster** holds up on real examples
   (does a solid canonical figure + a thin local sample combine to something a
   clinician would find sane?), with **(A) replace** as the documented fallback.
3. **Scalar canonical** — degenerate `[s, s]` combine vs short-circuit to local.
4. **Provenance depth** — just `n` + source, or also the raw `s`/`n` and the
   pre-combination local interval for full auditability?

Suggested first step once these are settled: a `combine-susceptibility` +
`counts->interval` spike with the §7 mapping/combination tests, mirroring how
decision (C) landed before S1 authored data.