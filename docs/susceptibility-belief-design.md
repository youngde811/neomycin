# Belief-valued susceptibilities (DS-interval antibiograms) — design

A follow-on increment to the therapy phase
([`therapy-phase-design.md`](therapy-phase-design.md)). The therapy design
*locked in* belief-valued sensitivities as intent (§3.2, §10.3), and the plumbing
to carry a belief object as a susceptibility already exists and is tested. What's
missing is (a) authoring the canonical KB with **genuine intervals**, (b)
**surfacing** the interval through to the recommendation so the LLM can narrate
it, and (c) deciding what an interval **means for coverage**. This doc scopes that
work and flags one pivotal representation decision the naive path trips over.

> **⚠️ NOT FOR CLINICAL USE.** Everything here concerns a schematic, illustrative
> knowledge base. Susceptibility intervals are a *modeling* device for making
> data-sparsity visible — not real antibiogram statistics, and never a basis for
> prescribing.

---

## 1. Motivation

neomycin's headline is that **Dempster-Shafer makes uncertainty visible** — an
ambiguous Gram stain widens and lowers a `[Bel, Pl]` interval instead of
collapsing to a point. Today that story stops at *identification*. On the
*treatment* side, a drug's susceptibility against an organism is a bare scalar
(`0.85`), which cannot distinguish "85% susceptible, and we're sure" from "85% is
our best guess from four isolates — treat as provisional."

A belief-valued susceptibility fixes that: a **narrow** interval means the local
data is solid, a **wide** interval means the antibiogram is thin or absent. Claude
can then narrate *"meropenem covers Pseudomonas, but our susceptibility data is
sparse (bel 0.70, pl 0.95) — regard this as provisional pending sensitivities."*
That is the same visible-uncertainty argument, extended to therapy, and it is the
natural home for the deferred **antibiogram overlay** (§6): few isolates → wide
interval, by construction.

---

## 2. What already exists

The *capability* is built and under test — this is not a from-scratch feature:

- **Authoring** accepts a belief object today. `defsensitivity`'s contract:
  *"SUSCEPTIBILITY is EVALUATED and belief-valued — a plain number, or a belief
  object such as `(belief:make-ds-belief bel pl)`"*
  (`neomycin/therapy/authoring.lisp:55`).
- **Storage** is representation-agnostic: `add-sensitivity` / `kb-susceptibility`
  store and return whatever they're given (`neomycin/therapy/kb.lisp:40,61,81`).
- **The solver** already reduces a belief-valued susceptibility to a scalar for
  thresholding and weighting via `scalar-of`
  (`neomycin/therapy/greedy-solver.lisp:40-47`).
- **Tests** prove the path end to end: `therapy-ds-interval-susceptibility` (a
  `(make-ds-belief 0.9 1.0)` susceptibility covers) and
  `therapy-ds-weak-interval-does-not-cover` (`0.3` does not)
  (`neomycin/test/therapy-tests.lisp:129,142`).

What ships in the **canonical** KB, though, is all scalars
(`neomycin/therapy/knowledge-base.lisp` — `(defsensitivity :pseudomonas
:meropenem 0.85)` …), and the interval, even where present, never reaches the
output. So the mechanism is real but currently inert.

---

## 3. The work, in three increments

### S1 — Author the canonical KB with intervals

Replace scalar susceptibilities with intervals carrying deliberate ignorance,
e.g. `(defsensitivity :pseudomonas :meropenem (belief:make-ds-belief 0.70 0.95))`
= "at least 70% susceptible, up to 95%, 25% ignorance." Mechanically a data edit —
**but see §4 first**; the representation choice is not free.

### S2 — Surface the interval through to output

Today the interval is discarded *before* serialization: Phase B stores the
already-reduced scalar in the regimen item
(`greedy-solver.lisp:119-122`, `(cons o (scalar-of …))`), and the serializer emits
that scalar (`neomycin/therapy/bridge.lisp`, `regimen-item->json`). To narrate an
interval we must keep the raw belief object on the `regimen-item`
(`protocol.lisp:45`) and serialize it as `{bel, pl, ignorance}`.

Good news: the serializer already has the helper — `treat-item` beliefs are
rendered through `lisa-bridge:belief->json-value` (`bridge.lisp`, `treat-item->json`).
S2 reuses it for susceptibilities. Then update `system-prompt.md` so Claude
narrates a wide susceptibility interval as provisional. This is small and is where
most of the demonstrable value lands.

### S3 — Coverage semantics (the research question)

See §5. This is the part with genuine design content: what does an interval *mean*
for the cover/don't-cover decision, not just the narration.

---

## 4. Pivotal decision — susceptibility uncertainty is orthogonal to the ID algebra

The naive S1 ("author `make-ds-belief` intervals") **breaks the CF path**, and
this is the most important finding in this doc.

`scalar-of` reduces via the *active identification belief system*:
`(belief:belief->number belief:*belief-system* val)`
(`greedy-solver.lisp:46`). But `belief->number` has applicable methods only for a
`number` or `null` in general (`protocol.lisp:69-70`); **only** the DS system adds
a method that understands a `ds-belief` struct (`dempster-shafer.lisp:178`). So
under `LISA_BELIEF_SYSTEM=cf`, a `ds-belief` susceptibility has *no applicable
method* — the solver **errors**. Authoring DS intervals into the canonical KB
would therefore make therapy unusable under certainty factors and kill the
CF-vs-DS comparison on the treatment side.

The deeper point: **an antibiogram's sparseness is not the same uncertainty as the
identification algebra.** CF-vs-DS governs how we combine *diagnostic rule*
evidence; how confident we are in a *susceptibility figure* is a separate fact
about the data, and should be represented the same way no matter which algebra
scored the diagnosis. Options:

- **(A) DS-only susceptibilities.** Canonical KB carries `ds-belief`; therapy is
  DS-only (forbid or project under CF). *Rejected* — it forfeits the CF/DS
  comparison the project exists to make.
- **(B) System-neutral susceptibility type + per-system reduction.** Give
  susceptibility its own small representation (a `(bel . pl)` pair or a dedicated
  struct) and add a reduction method under *each* belief system (CF → `bel` or
  midpoint; DS → `bel`). Faithful to the pluggable-protocol style, but spreads
  susceptibility logic across both belief systems.
- **(C) Dedicated susceptibility reduction, decoupled from `*belief-system*`.**
  *Recommended.* Reduce a susceptibility with a function that understands
  intervals natively (`ds-belief-bel`, or a policy-chosen point per §5), **not**
  routed through the active identification system at all. A raw scalar stays a
  scalar; an interval reduces by its own rule. This keeps susceptibility
  uncertainty independent of the diagnostic algebra — which is the correct model —
  and localizes the change to `scalar-of` (or a new `susceptibility->scalar`) in
  the solver, touching neither belief system.

**Recommendation: (C).** It is the smallest change, it fixes the CF break, and it
encodes the right conceptual separation. S1 depends on this decision — do not
author intervals until the reduction path is decoupled.

---

## 5. Coverage semantics — the stewardship dial

With intervals in hand, "does drug *d* cover organism *o*?" — currently
`scalar-of(susceptibility) ≥ *susceptibility-threshold*` using the lower bound
(`greedy-solver.lisp:54-60`, `protocol.lisp:76`) — becomes a policy choice worth
exposing as a dial, e.g. `*susceptibility-gate*`:

- **`:belief` (conservative, current behavior)** — gate on `bel`. "Only count it as
  covering if we're confident it's susceptible." Wide ignorance ⇒ harder to cover.
- **`:plausibility` (optimistic)** — gate on `pl`. "Count it unless we have
  evidence against." Wide ignorance ⇒ easier to cover.
- **`:midpoint`** — gate on `(bel+pl)/2`. A middle ground.

This is a real research artifact: the *same* KB and case yield different regimens
under conservative vs. optimistic gating, and the divergence is legible precisely
because the interval is explicit — the CF world cannot even pose the question.

Secondary, optional: make the tie-break **ignorance-aware**. `coverage-weight`
(`greedy-solver.lisp:62-67`) currently sums susceptibility × belief; among equal
coverage it could prefer the drug with the *narrower* susceptibility ignorance
(better-characterized agent wins). Keep this separable from the gate decision.

Whatever we pick, the thresholds and the gate stay **stewardship policy dials, not
clinical constants** (`protocol.lisp:66-77`).

---

## 6. Antibiogram tie-in

The deferred antibiogram overlay (therapy design §3.1) is where interval *width*
would come from empirically: a site-local `(organism, drug) → (n-susceptible, n-tested)`
becomes a susceptibility interval whose ignorance shrinks as `n` grows (a
credal/Beta-style read of the counts). Under decision (C) this overlay simply
produces susceptibility intervals; the solver consumes them unchanged. S1–S3 are
the substrate that makes the overlay narratable — worth building first, with the
overlay as the follow-on that supplies real width instead of hand-authored width.

---

## 7. Testing

Extend `neomycin/test/therapy-tests.lisp`:

- **Reduction (C):** an interval susceptibility reduces correctly under **both**
  CF and DS (the current gap — the CF case would error today).
- **Canonical KB:** at least one interval-valued entry covers / doesn't cover as
  expected, under each belief system.
- **Coverage gate (S3):** the same case flips coverage across `:belief` /
  `:plausibility` / `:midpoint` — the headline behavioral test.
- **Serialization (S2):** a regimen item's susceptibility serializes to
  `{bel, pl, ignorance}`, mirroring the treat-item belief test.

Golden identification values are unaffected — this increment touches only the
therapy layer.

---

## 8. Rules → native DS (a harder idea we may or may not pursue)

Separately, we discussed giving **rule beliefs** native DS values. Recording the
assessment so it isn't re-litigated from scratch:

The rules *already emit* DS intervals on their conclusions — `normalize-belief`
maps a scalar `:belief 0.4` to `[0.4, 1.0]`, and disconfirming rules place mass on
¬H to pull plausibility below 1.0 (`dempster-shafer.lisp:83-95,145-162`). What
they *cannot* express is an **independent per-rule plausibility**: a single
confirming rule's `pl` is pinned to `1.0` and its ignorance is exactly `1 − bel`.
Letting a rule declare a native `[bel, pl]` pair is **moderate-to-hard** and
carries real costs:

- It reaches into the **Lisa rule compiler** and `weaken-belief`, which assume a
  scalar factor — i.e. it edits the *un-renamed substrate*, against the
  light-touch-fork principle in `CLAUDE.md`.
- It **breaks the CF/DS duality**: CF has no independent plausibility, so a
  native-DS rule would not round-trip to certainty factors without a lossy
  projection.
- neomycin already achieves per-hypothesis conflict through **separate
  disconfirming rules**, which is arguably more MYCIN-authentic than folding doubt
  into one rule — so this may re-solve, more invasively, a problem already solved.

**Disposition: deferred / conditional.** Pursue only if a concrete expressiveness
need emerges that disconfirming rules genuinely cannot meet. Unlike the
susceptibility work, there is no cheap, already-tested substrate to build on here.

---

## 9. Scope and non-goals

- **In:** decoupled susceptibility reduction (C); interval authoring in the
  canonical KB; interval carried to the recommendation + JSON; a coverage-gate
  policy dial; tests across both algebras.
- **Out (this increment):** the antibiogram overlay itself (§6, follow-on);
  native-DS rule beliefs (§8, deferred); any change to identification goldens.
- **Always:** NOT FOR CLINICAL USE. Intervals model data-sparsity for research
  legibility; they are not real susceptibility statistics.