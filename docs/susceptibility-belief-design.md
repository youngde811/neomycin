# Belief-valued susceptibilities (DS-interval antibiograms) — design

A follow-on increment to the therapy phase
([`therapy-phase-design.md`](therapy-phase-design.md)). The therapy design
*locked in* belief-valued sensitivities as intent (§3.2, §10.3), and the plumbing
to carry a belief object as a susceptibility already exists and is tested. What
was missing was (a) authoring the canonical KB with **genuine intervals**, (b)
**surfacing** the interval through to the recommendation so the LLM can narrate
it, and (c) deciding what an interval **means for coverage**. This doc scoped that
work and flagged one pivotal representation decision the naive path trips over.

> **⚠️ NOT FOR CLINICAL USE.** Everything here concerns a schematic, illustrative
> knowledge base. Susceptibility intervals are a *modeling* device for making
> data-sparsity visible — not real antibiogram statistics, and never a basis for
> prescribing.

---

## 0. Implementation status — SHIPPED

**Everything scoped "in" below (§9) is implemented and tested on
`feature/susceptibility-belief`** (pending the manual merge to `develop`). The
four increments landed as separate commits:

| Increment | Lands in | State |
|---|---|---|
| **(C)** decoupled susceptibility reduction | `greedy-solver.lisp` `susceptibility->scalar` | ✅ |
| **S1** interval-valued canonical KB | `knowledge-base.lisp` (all entries; documented width tiers) | ✅ |
| **S2** interval surfaced to JSON + narration | `bridge.lisp` `susceptibility-bounds`/`susceptibility-entry->json`; `system-prompt.md` | ✅ |
| **S3** coverage-gate dial | `protocol.lisp` `*susceptibility-gate*`; solver reduction; bridge `gate` field; `tools.json` | ✅ |

Test suite: **223 passed, 0 failed (68 tests)** via `(asdf:test-system "neomycin/test")`.

**Two findings from implementation, recorded so they are not re-litigated:**

1. **The (C) orthogonality principle extends to *serialization*, not just
   reduction** — see §4's addendum. S2 does **not** route susceptibility JSON
   through `lisa-bridge:belief->json-value` (as an earlier draft of §3 S2 loosely
   suggested); that helper serializes via the *active* belief system, so it renders
   a `ds-belief` susceptibility as `{bel, pl, ignorance}` under DS but drops
   `ignorance` under CF. A dedicated native renderer keeps the shape identical
   under both algebras — the same reason (C) exists for reduction.
2. **The honest-`UNCOVERED` case is the S3 payoff.** When contraindications strip
   out every *solid* agent for an organism, the conservative gate reports it
   uncovered rather than leaning on a provisional agent; the optimistic gate
   recovers that agent on plausibility. Same case, different regimen (§5).

**Deferred** (explicitly optional or out-of-scope, see §5/§6/§8): the
ignorance-aware tie-break in `coverage-weight`; the antibiogram overlay (§6, the
natural next feature); native-DS rule beliefs (§8).

The sections below are preserved as the **design record** (the reasoning behind
each choice); "will" language reads as the intent that was subsequently shipped.

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

> **✅ Implemented** in `knowledge-base.lisp`. Every susceptibility is now a
> `belief:make-ds-belief` interval, with a documented width scheme: **solid**
> (ignorance ~0.05–0.12), **typical** (~0.15–0.22), and **variable** (~0.25+,
> `bel` may fall below the gate — flagged `[PROVISIONAL]` inline). Every organism
> retains at least one solid covering agent, so coverage degrades gracefully; only
> secondary/variable agents (e.g. cipro/gentamicin vs pseudomonas, MSSA-only
> entries on broad gram-neg agents, VRE-era enterococcus) straddle the threshold.
> This is a deliberate, documented behavior change under the conservative default
> gate, and it is exactly the raw material S3 needs.

Replace scalar susceptibilities with intervals carrying deliberate ignorance,
e.g. `(defsensitivity :pseudomonas :meropenem (belief:make-ds-belief 0.70 0.95))`
= "at least 70% susceptible, up to 95%, 25% ignorance." Mechanically a data edit —
**but see §4 first**; the representation choice is not free.

### S2 — Surface the interval through to output

> **✅ Implemented** — with one correction to the plan below. The solver now keeps
> the **raw** susceptibility on the `regimen-item` (`greedy-solver.lisp`, no longer
> reducing it there), and the serializer renders `{organism, bel, pl, ignorance}`.
> **Correction:** it does **not** reuse `lisa-bridge:belief->json-value` as the
> next paragraph originally proposed — that helper routes through the *active*
> belief system and would drop `ignorance` under CF (see §4 addendum). Instead
> `bridge.lisp` gained a native `susceptibility-bounds` (a bare scalar becomes a
> degenerate zero-ignorance interval, so consumers see a uniform shape). The
> `system-prompt.md` `regimen` guidance now explains the interval, flags wide
> ignorance as provisional, and states coverage was gated on `bel`.

Today the interval is discarded *before* serialization: Phase B stores the
already-reduced scalar in the regimen item
(`greedy-solver.lisp:119-122`, `(cons o (scalar-of …))`), and the serializer emits
that scalar (`neomycin/therapy/bridge.lisp`, `regimen-item->json`). To narrate an
interval we must keep the raw belief object on the `regimen-item`
(`protocol.lisp:45`) and serialize it as `{bel, pl, ignorance}`.

~~Good news: the serializer already has the helper — `treat-item` beliefs are
rendered through `lisa-bridge:belief->json-value` (`bridge.lisp`, `treat-item->json`).
S2 reuses it for susceptibilities.~~ *(Superseded — see the addendum above and §4;
reusing that helper reintroduces the CF coupling (C) removed.)* Then update
`system-prompt.md` so Claude narrates a wide susceptibility interval as provisional.
This is small and is where most of the demonstrable value lands.

### S3 — Coverage semantics (the research question)

> **✅ Implemented** as `*susceptibility-gate*` (`protocol.lisp`), read by
> `susceptibility->scalar` in the solver, exposed per-request via the
> `/recommend-therapy` `gate` field (dynamically bound, echoed in the response) and
> the `recommend_therapy` tool. See §5 for the semantics.

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

> **✅ Implemented** as `susceptibility->scalar` (`greedy-solver.lisp`): `nil → 0.0`;
> a real → itself; a `ds-belief` → the gated interval point (§5), reduced natively
> and never through `belief:*belief-system*`. The three susceptibility call sites
> (`drug-covers`, `coverage-weight`, the regimen-item) use it; the two
> *identification*-belief sites keep using `scalar-of` (which correctly routes
> through the active algebra). Confirmed empirically that the old path errors:
> `(belief->number *cf-system* <ds-belief>)` → `NO-APPLICABLE-METHOD-ERROR`.
>
> **Addendum — the same orthogonality applies to SERIALIZATION.** The identical
> trap sits in the JSON path: `lisa-bridge:belief->json-value` renders through the
> *active* system, so a `ds-belief` susceptibility serializes as
> `{bel, pl, ignorance}` under DS but, under CF, falls through to jzon's incidental
> struct serialization — `{bel, pl}`, **silently dropping `ignorance`**. Because a
> susceptibility is a `ds-belief` regardless of the ID algebra (S1), its serialized
> shape must likewise be algebra-independent. S2 therefore renders it natively
> (`susceptibility-bounds` in `bridge.lisp`), not through that helper. Same
> principle, second surface: **susceptibility handling — reduction *and* display —
> is orthogonal to the identification algebra.**

---

## 5. Coverage semantics — the stewardship dial

> **✅ Implemented** as `*susceptibility-gate*` (default `:belief`, preserving prior
> behavior). Verified behaviorally: on the canonical KB, with every solid
> anti-pseudomonal contraindicated, pseudomonas is `uncovered` under `:belief` and
> covered by gentamicin (on its plausibility bound) under `:plausibility` — same
> case, different regimen. The **ignorance-aware tie-break below is deferred**
> (explicitly optional).

With intervals in hand, "does drug *d* cover organism *o*?" — currently
`scalar-of(susceptibility) ≥ *susceptibility-threshold*` using the lower bound
(`greedy-solver.lisp:54-60`, `protocol.lisp:76`) — becomes a policy choice worth
exposing as a dial, `*susceptibility-gate*`:

- **`:belief` (conservative, current behavior)** — gate on `bel`. "Only count it as
  covering if we're confident it's susceptible." Wide ignorance ⇒ harder to cover.
- **`:plausibility` (optimistic)** — gate on `pl`. "Count it unless we have
  evidence against." Wide ignorance ⇒ easier to cover.
- **`:midpoint`** — gate on `(bel+pl)/2`. A middle ground.

This is a real research artifact: the *same* KB and case yield different regimens
under conservative vs. optimistic gating, and the divergence is legible precisely
because the interval is explicit — the CF world cannot even pose the question.

Secondary, optional **(deferred — not yet implemented)**: make the tie-break
**ignorance-aware**. `coverage-weight` (`greedy-solver.lisp:62-67`) currently sums
susceptibility × belief; among equal coverage it could prefer the drug with the
*narrower* susceptibility ignorance (better-characterized agent wins). Kept
separable from the gate decision, and left for a follow-on.

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

**✅ Done** in `neomycin/test/therapy-tests.lisp` (the suite grew from 62 → 68 tests):

- **Reduction (C):** `therapy-cf-interval-susceptibility-covers` (a `ds-belief`
  susceptibility covers under CF — the case that errored before) and
  `therapy-cf-weak-interval-does-not-cover` (a low-`bel` interval under CF does not,
  proving the native reduction takes the lower bound).
- **Canonical KB:** `therapy-canonical-susceptibilities-are-intervals` (entries are
  DS intervals; solid `bel ≥` gate, provisional `bel <` gate with `pl > bel`); the
  ceftazidime assertion in `therapy-canonical-kb-loaded` updated to `[0.70, 0.90]`.
- **Coverage gate (S3):** `therapy-gate-flips-coverage` (the same case flips across
  `:belief` / `:plausibility` / `:midpoint` — the headline test),
  `therapy-canonical-gate-recovers-provisional` (canonical `:belief`-uncovered ↔
  `:plausibility`-covered), and `therapy-gate-default-is-conservative`.
- **Serialization (S2):** `therapy-susceptibility-serializes-as-interval` (a regimen
  item's susceptibility serializes to `{bel, pl, ignorance}` *identically under CF
  and DS*) and `therapy-scalar-susceptibility-serializes-as-degenerate-interval`.

Golden identification values are unaffected — this increment touched only the
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

- **In — ✅ all delivered:** decoupled susceptibility reduction (C) *and* its
  serialization counterpart; interval authoring in the canonical KB; interval
  carried to the recommendation + JSON; a coverage-gate policy dial (engine +
  bridge + tool); tests across both algebras.
- **Out (this increment):** the ignorance-aware tie-break (§5, deferred — optional);
  the antibiogram overlay itself (§6, the natural next feature); native-DS rule
  beliefs (§8, deferred); any change to identification goldens.
- **Always:** NOT FOR CLINICAL USE. Intervals model data-sparsity for research
  legibility; they are not real susceptibility statistics.