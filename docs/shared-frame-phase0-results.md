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