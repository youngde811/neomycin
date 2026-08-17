# Shared frame, phase 0 — measured results

> **Status: measurement complete (2026-08-17). No engine code changed, no belief
> changed, no golden moved, suite untouched.** This is the phase 0 called for by
> `docs/shared-frame-design.md` §10, run under the decisions David settled on
> 2026-08-17: D1 unconditional, D2 keep Barnett, D3 measure both, D4 add
> `:other-organism`, D5 phase 0 sufficient to decide.
>
> Code: `docs/frame-algebra-spike.lisp` (throwaway, not in any ASDF system).
> Reproduce with `(load "docs/frame-algebra-spike.lisp")` then `(frame-spike:report)`
> from an SBCL REPL with `:neomycin` loaded.

> **Phase 0.5 followed on the same day and is appended below from §10.** Its result
> changes the recommendation: the blocking problem is not the combination operator but
> the *width of the rules' focal sets*, which phase 0 deliberately held fixed. One
> corrected focal set restores every ranking under both operators. Read §10–§13 for
> that; §1–§9 are the phase 0 record and stand as written.

## Verdict

**The representation works. The corpus is not ready for it.**

Every arithmetic prediction in the design held exactly. Free exclusion is real and
large. Set-valued mass appears natively. But the frame also exposes a defect the
current representation hides: **the corpus's rules are not independent bodies of
evidence, and Dempster's rule requires that they be.** Correlated evidence
manufactures enormous conflict — up to `K = 0.84` — and in culture-1 and culture-1a it
inverts the ranking between pseudomonas and klebsiella.

**Recommendation: do not proceed to phase 1 as specified.** Insert a phase 0.5 that
settles how correlated rules combine. §7 says what that is.

## 1. How it was run

No number below is hand-transcribed. The harness:

1. Runs the real scenario on the real engine under DS.
2. Reads every firing that contributed belief out of the engine's **derivation
   table** — the same authoritative record `/why` narrates from.
3. Derives each rule's focal set **mechanically from the compiled rulebase** via the
   exported introspection API: a confirming rule concluding `organism-identity V` maps
   to `{V}`; one concluding `organism-class C` maps to the class subset; a
   disconfirming rule maps to `Θ ∖ (its member-test list)`.
4. Feeds those into the standalone sparse mass algebra and reads out both ways.

So the spike is not a second copy of the corpus. If a rule changes, the spike follows.

**Held fixed, deliberately.** Confirming rules get **singleton** focal sets even where
design §4.2 argues they should be wider (the e-coli/klebsiella case). Widening them is
an authoring change and belongs to phase 2. This measures the representation change
alone.

**Dedupe.** A disconfirming rule fires once per raised hypothesis today —
`red-pigment-argues-against-non-serratia` produces five derivation records. Under a
frame that is one observation contributing one mass assignment, so firings are deduped
by (rule, entity).

## 2. Results

`current` is what the engine reports today. `Dempster` and `Yager` are the two
readouts of the same accumulation. `D1-off` re-runs the identical firings with
conditional composition (`species = class × rule`) instead of unconditional, isolating
D1 from the representation.

| scenario | organism | current | frame/Dempster | frame/Yager | D1-off/Dempster |
|---|---|---|---|---|---|
| culture-1 | pseudomonas | [0.760, 1.000] | **[0.241, 0.316]** | [0.076, 0.784] | [0.275, 0.362] |
| | klebsiella | [0.400, 1.000] | **[0.380, 0.759]** | [0.120, 0.924] | [0.290, 0.725] |
| culture-1a | pseudomonas | [0.880, 1.000] | **[0.227, 0.258]** | [0.035, 0.885] | [0.314, 0.357] |
| | klebsiella | [0.688, 1.000] | **[0.619, 0.773]** | [0.096, 0.965] | [0.472, 0.686] |
| culture-2 | bacteroides | [0.689, 0.956] | [0.462, 0.642] | [0.219, 0.830] | [0.462, 0.642] |
| | pseudomonas | [0.611, 0.946] | [0.329, 0.508] | [0.156, 0.767] | [0.329, 0.508] |
| culture-3 | s. pneumoniae | [0.525, 1.000] | [0.638, 0.851] | [0.225, 0.947] | [0.394, 0.750] |
| culture-4 | s. pyogenes | [0.595, 1.000] | [0.764, 0.899] | [0.213, 0.972] | [0.535, 0.899] |
| | s. pneumoniae | [0.216, 0.412] | [0.101, 0.135] | [0.028, 0.759] | [0.101, 0.192] |
| culture-5 | s. agalactiae | [0.740, 1.000] | [0.910, 1.000] | [0.910, 1.000] | [0.740, 1.000] |

Conflict and entanglement:

| scenario | firings | K | entangled evidence components | K if each component contributes once |
|---|---:|---:|---:|---:|
| culture-1 | 4 | 0.6840 | **1** | 0.0000 |
| culture-1a | 5 | 0.8448 | **1** | 0.0000 |
| culture-2 | 4 | 0.5264 | 2 | 0.1008 |
| culture-3 | 3 | 0.6475 | 2 | 0.5250 |
| culture-4 | 4 | 0.7219 | 3 | 0.6375 |
| culture-5 | 3 | 0.0000 | 2 | 0.0000 |

## 3. The design's predictions all held

The algebra self-test checks the hand arithmetic in design §6 and the churn
predictions in §7. All twelve pass:

- §6.1 exactly: class 0.8 + species 0.8 gives `Bel(e-coli) = 0.80` (not 0.64),
  `m(family) = 0.16`, `Pl(klebsiella) = 0.20` with no disconfirming rule, `K = 0`.
- Free exclusion: pseudomonas 0.76 alone caps `Pl(klebsiella)` at 0.24.
- **§7 confirmed: a confirming rule in isolation still yields `[belief, 1.0]`, and a
  disconfirming rule in isolation still yields `[0.0, 1−belief]`.** So `check-rule`'s
  50 per-rule DS assertions survive the change, as predicted.
- Conjunctive accumulation is order-independent, so Rete firing order does not affect
  the result — the reason for accumulating conjunctively and normalizing at readout.

## 4. Free exclusion is real, and large

This is the payoff the design argued for, and it is bigger than expected.

Culture-1 squeezes **15 organisms no rule mentions**: ten to `pl = 0.076`, five
(the enterobacteriaceae siblings) to `pl = 0.380`. Culture-5 squeezes 16, thirteen of
them to `pl = 0.027`. Today every one of these sits at `pl = 1.0`.

Set-valued mass appears natively, exactly as §8 predicted. Culture-1 carries
**0.3038 on the six-member enterobacteriaceae set** — "it is in this family, the
evidence does not say which member." That is what `family-backstops` constructs by
hand in `neomycin/therapy/bridge.lisp`; here it falls out of the arithmetic.

`Pl(:other-organism)` (D4) is now a live number: 0.076 in culture-1, 0.027 in
culture-5. It answers "could this be something the corpus does not know about," which
today has no representation at all. **Both of those values are too low to be
credible** on the strength of three or four illustrative rules, which is another face
of the finding in §5.

## 5. The finding: the corpus's rules are not independent

Dempster's rule requires that the evidence being combined comes from independent
sources. **It does not.**

Culture-1, measured:

```
GRAM=NEG            read by 3 rules
MORPHOLOGY=ROD      read by 3 rules
COMPROMISED-HOST=T  read by 2 rules

entangled evidence components: 1 (from 4 firings)
```

All four firings are one connected body of evidence — no two of them read disjoint
observations. The two pseudomonas rules (0.4, 0.6) and the enterobacteriaceae class
rule (0.8) are all reading the same gram-negative rod. Combining them as independent
sources double- and triple-counts one observation.

The consequence is measurable: `K = 0.684`, and collapsing each entangled component to
a single contribution drops it to `K = 0.000`. **Essentially all of culture-1's
conflict is an artifact of counting one observation three times.** Culture-1a is the
same, at `K = 0.845 → 0.000`.

Not all conflict is artifact. Culture-3 (`0.648 → 0.525`) and culture-4
(`0.722 → 0.638`) keep most of theirs after collapsing, because there the disagreement
is between genuinely distinct observations — that conflict is real and is what the
frame is supposed to surface.

*(The collapsed column is a diagnostic bound on `K`, not a candidate answer. Keeping
one firing per component throws away real rules; it is there to separate artifact from
genuine disagreement, nothing more.)*

## 6. The consequence that would reach a clinician

**Culture-1 and culture-1a invert the ranking.**

Today: pseudomonas 0.76 ahead of klebsiella 0.40. Under the frame: pseudomonas
**0.241 behind** klebsiella **0.380**. Culture-1a is worse — 0.227 against 0.619.

The cause is §5. The class rule commits 0.8 to the six-member family from gram-neg +
rod + aerobic; the pseudomonas rules commit 0.4 and 0.6 from overlapping facts.
Treated as independent, the family's single larger mass beats the two smaller ones,
and pseudomonas — which is *not* in the family — takes the conflict.

This is not a rounding difference. It is the top-ranked organism changing, on the
project's flagship scenario, for a reason that has nothing to do with clinical
evidence. It would flow through `/conclusions`, `/why`, and into the therapy solver's
coverage gate.

**D1 amplifies it but does not cause it.** With D1 off the gap narrows to
0.275 vs 0.290 — still inverted, marginally. So the inversion is primarily the
independence artifact, with D1 making it worse.

## 7. Recommendation

**Insert phase 0.5: settle how correlated rules combine, before any engine work.**

The obvious response — "author one rule per body of evidence" — is not acceptable. The
corpus deliberately has several rules reading `gram=neg`, and that modularity is how a
rulebase stays maintainable. Requiring disjoint premises per rule would gut it, and it
would land the burden squarely back on the human author that design §4 set out to
relieve.

The promising direction is a combination operator that tolerates dependence. The
standard one is **Denœux's cautious conjunctive rule**, which is idempotent —
combining a source with itself changes nothing — and is designed exactly for
non-distinct bodies of evidence. It is engine-level work, which is in scope.

**I have not measured it.** That is what phase 0.5 is: implement the cautious rule in
the same spike, replay the same six scenarios, and check three things — does culture-1
recover the pseudomonas-over-klebsiella ranking, does `K` fall to something defensible,
and does culture-4 *keep* its genuine conflict.

If the cautious rule fixes it, phase 1 proceeds as designed with the operator swapped
in. If it does not, the shared frame is not viable over this corpus and the phase 0
cost is what the design promised it would be.

## 8. Answers to the open decisions

**D3 — Dempster or Yager?** Neither, while `K` is being manufactured. At `K = 0.68`
Dempster reports pseudomonas as `[0.241, 0.316]` — a narrow, confident-looking
interval produced by renormalizing away 68% of the mass. Yager reports
`[0.076, 0.784]`, which is wide and correctly says the evidence is a mess. Yager is
the more honest of the two *at high conflict*, and it never inflates. But the right
move is to stop manufacturing the conflict first and re-decide at realistic `K`.
**Recommend: keep both readouts (they cost one function each), report `K` always,
and defer the default until after phase 0.5.**

**D1 — unconditional?** The A/B is clean, and the case is mixed. Unconditional is
right in principle and behaves well where evidence is genuinely independent —
culture-4 sharpens s. pyogenes 0.595 → 0.764 while pushing s. pneumoniae 0.216 → 0.101,
which is the correct direction on both. But it inflates where evidence is correlated:
culture-5's s. agalactiae goes 0.740 → 0.910 on two rules that both read
`hemolysis=beta`. **That inflation is the §5 problem again, not a separate one.**
Recommend holding D1 as decided and re-checking it after phase 0.5.

**D2, D4 — unchanged.** Barnett stays as a third system; `:other-organism` is in the
frame and already earning its place (§4).

## 9. Why the numbers should be believed

Two independent checks that the harness is faithful:

- **Culture-5 with D1 off reproduces the current golden exactly**: 0.740, against
  `ds-culture-5`'s 0.7399. That scenario has `K = 0`, so the frame and the current
  dichotomous algebra must agree — and they do, to the printed precision.
- **Culture-2's D1-off column is identical to its D1-on column**, which is what must
  happen: culture-2's rules are all one-hop, so there are no derived premises for the
  conditional reading to discount.

Where the frame and the current system diverge, it is because of conflict between
disjoint sets — which is the thing being measured, not an error in measuring it.
---

# Phase 0.5 — how correlated rules should combine

> **Measurement only (2026-08-17). Same spike, same six scenarios, no engine code, no
> belief changed, no golden moved; suite re-run green at 1074/182.**

## 10. What was tested

Phase 0 recommended settling the combination operator. Four variants were measured, all
read out through Dempster:

- **(a) conjunctive** — the phase 0 baseline. Every rule an independent source.
- **(b) cautious** — Denœux's cautious conjunctive rule. Idempotent: combining a source
  with itself changes nothing.
- **(c) average-within-component** — partition firings into entangled evidence
  components, average the mass functions inside each (Murphy-style), combine across
  components with Dempster.
- **(d) cautious-within-component** — same partition, cautious inside.

**The cautious rule is exact and cheap here.** In general it needs a Möbius transform
over the superset lattice, which is intractable on an 18-element frame. But every
operand is already a simple support function — a rule puts mass `s` on one set `A` and
`1−s` on `Θ`, which *is* `A^w` with weight `w = 1−s`, its own canonical decomposition.
So the cautious combination of a collection of SSFs is: per focal set take the minimum
weight (the maximum support), then conjunctively combine one SSF per set.

The metric is **ranking agreement**: does the variant preserve the current system's
belief ordering between organisms? That is what a clinician sees, and it is what
culture-1 broke in phase 0.

## 11. Results — no operator fixes it

| scenario | organisms | current | (a) conj | (b) cautious | (c) avg/cmpt | (d) caut/cmpt |
|---|---|---|---|---|---|---|
| culture-1 | klebsiella / pseudomonas | 0.40 / 0.76 | 0.38 / 0.24 ✗ | 0.43 / 0.13 ✗ | 0.13 / 0.25 ✓ | 0.43 / 0.13 ✗ |
| | *K* | — | 0.684 | 0.540 | 0.000 | 0.540 |
| culture-1a | klebsiella / pseudomonas | 0.69 / 0.88 | 0.62 / 0.23 ✗ | 0.51 / 0.16 ✗ | 0.22 / 0.26 ✓ | 0.51 / 0.16 ✗ |
| | *K* | — | 0.845 | 0.644 | 0.000 | 0.644 |
| culture-2 | bacteroides / pseudomonas | 0.69 / 0.61 | 0.46 / 0.33 ✓ | 0.55 / 0.20 ✓ | 0.22 / 0.25 ✗ | 0.55 / 0.20 ✓ |
| | *K* | — | 0.526 | 0.417 | 0.071 | 0.417 |
| culture-4 | s. pneumoniae / s. pyogenes | 0.22 / 0.60 | 0.10 / 0.76 ✓ | 0.10 / 0.76 ✓ | 0.37 / 0.27 ✗ | 0.10 / 0.76 ✓ |
| | *K* | — | 0.722 | 0.722 | 0.600 | 0.722 |
| culture-3 | s. pneumoniae | 0.52 | 0.64 | 0.64 | 0.66 | 0.64 |
| culture-5 | s. agalactiae | 0.74 | **0.91** | **0.70** | 0.70 | 0.70 |

**Every variant preserves ranking on exactly two of the four scenarios that have a
ranking to preserve.** (a), (b) and (d) fail culture-1 and culture-1a; (c) fixes those
and fails culture-2 and culture-4 instead.

Three things worth taking from the table:

- **(d) is identical to (b) everywhere.** Cautious is already idempotent and
  order-independent, so partitioning first adds nothing when no focal set spans two
  components. (d) can be dropped.
- **Cautious fixes the D1 inflation.** Culture-5's s. agalactiae went 0.740 → 0.910
  under (a), which phase 0 flagged as D1 over-crediting two rules that both read
  `hemolysis=beta`. Cautious returns it to 0.700 by taking `max(0.7, 0.7)` instead of
  compounding. That is exactly the behaviour wanted, and it is free.
- **Averaging is disqualified, not merely unsuccessful.** It makes belief a function of
  *how many rules an author happened to write*. Culture-2's bacteroides rule (0.9,
  alone) is averaged against two pseudomonas rules (0.4, 0.6) in the same component and
  loses: `0.9/3 = 0.30` against `(0.4+0.6)/3 = 0.33`. One strong rule is beaten by two
  mediocre ones. That is a worse authoring hazard than the one being fixed.

**Cautious lowers `K` in every scenario where it differs from conjunctive** (0.684 →
0.540, 0.845 → 0.644, 0.526 → 0.417) without ever making a ranking worse. It is doing
real work. It is just not sufficient — and the reason is structural: **it only
deduplicates rules that share a focal set.** Culture-1's problem is two rules
concluding `{pseudomonas}` and one concluding the six-member family — *different* sets,
so cautious cannot touch the interaction.

## 12. The actual cause: focal sets are too narrow

Phase 0 held focal sets at the width the rules were authored with, to change one
variable at a time. That turned out to be the variable that matters.

`aerobic-gram-neg-rod-suggests-enterobacteriaceae-class` fires on
`gram=neg ∧ morphology=rod ∧ aerobicity=aerobic` and commits 0.8 to the six
Enterobacteriaceae. But **that premise does not license that conclusion.** An aerobic
gram-negative rod is one of *seven* organisms in this frame — the six family members
**and pseudomonas**. (Bacteroides is excluded: it is an anaerobe.) Concluding only the
family was always an overstatement. The current representation simply had no way to say
the correct thing, because "one of these seven" is not a hypothesis it can hold.

Correcting that one focal set — nothing else, no operator change, no belief change:

| scenario | | K (conj / caut) | conjunctive | cautious |
|---|---|---|---|---|
| culture-1 | as authored | 0.684 / 0.540 | 0.380 / 0.241 ✗ | 0.435 / 0.130 ✗ |
| | **widened** | **0.380 / 0.300** | **0.194 / 0.613 ✓** | **0.286 / 0.429 ✓** |
| culture-1a | as authored | 0.845 / 0.644 | 0.619 / 0.227 ✗ | 0.506 / 0.157 ✗ |
| | **widened** | **0.704 / 0.420** | **0.324 / 0.595 ✓** | **0.310 / 0.483 ✓** |
| culture-2 | either | 0.526 / 0.417 | 0.462 / 0.329 ✓ | 0.552 / 0.198 ✓ |
| culture-4 | either | 0.722 / 0.722 | 0.101 / 0.764 ✓ | 0.101 / 0.764 ✓ |

*(columns are klebsiella / pseudomonas, bacteroides / pseudomonas, s. pneumoniae /
s. pyogenes)*

**All four scenarios now preserve ranking under both operators.** Conflict falls
substantially on the two that were broken (culture-1 `0.684 → 0.380` conjunctive,
`0.540 → 0.300` cautious). Culture-2 and culture-4 are untouched, because the corrected
rule does not participate in them.

For contrast, the alternative repair does not work. Sweeping the class rule's *belief*
down while leaving its focal set narrow needs it at **0.3 or below** before both
operators agree on culture-1 — from a declared 0.8. That is not a tuning adjustment,
and 0.3 is not a defensible number for "how often is an aerobic gram-negative rod an
Enterobacteriaceae." The belief was never the problem; the *set* was.

## 13. Recommendation

**Proceed to phase 1, with two changes to the plan.**

1. **Adopt the cautious conjunctive rule as the accumulation operator.** It is exact
   and O(1)-per-set over simple support functions, it is idempotent and
   order-independent, it lowers conflict in every affected scenario, it never worsened
   a ranking, and it fixes the culture-5 D1 inflation for free. Keep the plain
   conjunctive accumulation available for comparison — same argument as D2.

2. **Move focal-set width from phase 2 to phase 1.** Design §4.2 treated `:supports` as
   an authoring convenience. It is not; it is the correctness fix, and the goldens
   cannot be captured before it. A rule's focal set must be *what its premises
   license*, and the audit for that is now the first task of phase 1 — starting with
   the four organism-class rules, whose premises are the broadest in the corpus.

**This also closes the loop on the original audit.** `belief-conditional-audit.md` §3.2
flagged three class beliefs as "carried over from retired rules, answering no
conditional at all," and guessed they might matter more than the five wrong
conditionals. They do — but not because the *numbers* are unjustified. It is because
the rules they belong to name a set narrower than their evidence supports, and under a
shared frame that is what manufactures conflict. Widen the set and the number stops
being load-bearing.

**Remaining honest caveats:**

- One rule was corrected. The other 49 have not been audited for focal-set width;
  phase 1's first task is that audit, and it may find more.
- `K` is lower but not low: 0.380 conjunctive / 0.300 cautious on culture-1. Whether
  that is defensible or still signals a corpus problem is not yet answerable, and D3
  (Dempster vs Yager as the default readout) should stay deferred until it is.
- Ranking agreement is a coarse metric — one organism pair per scenario in most cases.
  It catches the failure phase 0 found; it is not a proof of correctness.
- Absolute beliefs are lower than today's throughout (culture-1 pseudomonas 0.613
  against 0.76). That is expected: today's numbers are inflated by counting one
  observation several times. It still means every DS golden moves, as design §7 said.
