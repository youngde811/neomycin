# Slice D — focal-set width audit, and what to change

> **Status: proposal for review (2026-08-17). No rule edited, no belief changed, no
> golden moved; suite green at 1475/209.** Phase 1 slice D of
> `docs/shared-frame-design.md`, promoted out of phase 2 by
> `docs/shared-frame-phase0-results.md` §13.
>
> Audit tool: `docs/focal-width-audit.lisp` (throwaway, not in any ASDF system).
> Reproduce with `(load "docs/focal-width-audit.lisp")` then `(focal-audit:report)`.

## 1. The question, and how it was answered

For each of the 50 rules: **is its focal set as wide as its premises license?**

Phase 0.5 found that co-triggered rules concluding *disjoint* sets from *one*
observation is what manufactures conflict, and that correcting a single focal set
restored culture-1's ranking. This audits the other 49 for the same defect.

**The corpus is its own source of truth.** Rather than working from recall about
which organisms are gram-negative, the tool derives an organism/property table from
the compiled rulebase in both directions:

- **Positive** — a rule requiring `gram=neg` whose focal set is `S` tells us every
  member of `S` is gram-negative. For a class rule that is the whole family.
- **Negative** — a ruling-out rule saying `gram=pos` argues against `L` tells us no
  member of `L` is gram-positive.

Then `licensed(rule)` = every frame element **not known to contradict** one of the
rule's organism-intrinsic premises. Unknown never excludes: if the corpus does not
record an organism's indole reaction, an indole premise cannot rule it out. That
makes the licensed set an upper bound and the audit conservative — it flags a focal
set as too narrow only on evidence the corpus itself supplies.

**One domain judgement, stated rather than buried.** Only *organism-intrinsic*
premises exclude anything. Burns, neutropenia, hospital acquisition and culture site
change how *likely* an organism is; they do not make any organism impossible. The
tool lists both sets explicitly (`*intrinsic-params*`, `*context-params*`).

## 2. Results

| | rules |
|---|---:|
| **Overclaim** — focal set contains an organism the rule's own premises exclude | **0** |
| **Exact** — claims precisely what it licenses | 25 |
| **Context-only** — no intrinsic premise at all | 7 |
| **Too narrow** — premises license more than the rule claims | 18 |

**All 16 ruling-out rules are exact.** That is the third time the disconfirming half
of the corpus has come out clean — `belief-conditional-audit.md` §3.4 found the same,
and for the same underlying reason: a rule that reasons from *"this organism never
shows this marker"* is already reasoning about a set.

**Zero overclaims** is the reassuring half. No rule concludes something its own
premises forbid.

## 3. The criterion: deduction or prior?

The 18 do not all mean the same thing, and the distinction is the useful output of
this audit:

> **A rule with no context premise is making a deduction, and its focal set must
> equal what it licenses. A rule with a context premise is making a prior claim, and
> may name a narrower set.**

`gram-neg-rod-in-burn-patient-suggests-pseudomonas` licenses nine organisms on its
intrinsic premises alone — every gram-negative rod. It names one. That is not an
error: the burn is doing the narrowing, epidemiologically rather than deductively,
and widening the rule to nine would delete the only thing it says.

`aerobic-gram-neg-rod-suggests-enterobacteriaceae-class` has *no* context premise. It
is a pure deduction from three bench findings, and it names six of the seven
organisms those findings license. That *is* an error, and it is the one phase 0.5
measured.

Applying the criterion splits the 18 four ways.

## 4. Category A — widen (4 rules)

Pure deductions whose focal set is narrower than their premises license. **These are
the proposed changes.**

| rule | claims | should also license | why |
|---|---|---|---|
| `aerobic-gram-neg-rod-suggests-enterobacteriaceae-class` (0.8) | the 6 Enterobacteriaceae | `pseudomonas` | Pseudomonas is an aerobic gram-negative rod. Bacteroides is not — it is an anaerobe — so the licensed set is exactly the 7 already declared as `:aerobic-gram-neg-rods`. |
| `gram-pos-cocci-in-chains-suggests-streptococcus-class` (0.7) | the 4 streptococci | `enterococcus-faecalis`, `enterococcus-faecium` | Enterococci **are** gram-positive cocci in chains. Structurally identical to the row above, and undetected until now. |
| `staph-coagulase-neg-suggests-staph-epidermidis` (0.55) | `staphylococcus-epidermidis` | `staphylococcus-saprophyticus` | The rule's own note already says it: *"coagulase-negativity identifies the GROUP, not this species."* The set it describes in prose is the set it should declare. |
| `gram-pos-cocci-in-clumps-suggests-staphylococcus-class` (0.7) | the 3 staphylococci | `other-organism` only | Depends entirely on D6 (§7). No change if D6 says no. |

Proposed authoring, using the subsets already declared in `context.lisp`:

```lisp
(defrule aerobic-gram-neg-rod-suggests-enterobacteriaceae-class
    (:belief 0.8 :supports :aerobic-gram-neg-rods ...)

(defrule staph-coagulase-neg-suggests-staph-epidermidis
    (:belief 0.55 :supports (:staphylococcus-epidermidis
                             :staphylococcus-saprophyticus) ...)
```

The streptococcus row needs a new subset, since gram-positive cocci in chains is not
an organism-class the corpus concludes:

```lisp
(:subset :gram-pos-cocci-in-chains (:streptococcus-pneumoniae :streptococcus-pyogenes
                                    :streptococcus-agalactiae :streptococcus-viridans
                                    :enterococcus-faecalis :enterococcus-faecium))
```

Note what does **not** change: the rule still *asserts* `organism-class
:streptococcus`, so Rete chaining and every tier-2 species rule are untouched. Only
where the mass lands changes. That separation — the fact gates, the focal set carries
belief — is design §5.

### Measured effect

All four applied together, replayed through the phase 0.5 harness:

| scenario | | K (conj / caut) | ranking |
|---|---|---|---|
| culture-1 | as authored | 0.684 / 0.540 | ✗ inverted |
| | **widened** | **0.380 / 0.300** | **✓ restored** |
| culture-1a | as authored | 0.845 / 0.644 | ✗ inverted |
| | **widened** | **0.704 / 0.420** | **✓ restored** |
| culture-3 | as authored | 0.647 / 0.647 | — |
| | **widened** | **0.525 / 0.525** | — |
| culture-2, culture-4, culture-5 | either | unchanged | ✓ |

Culture-3 is the new information. Its conflict falls because the enterococcus rule no
longer contradicts the streptococcus class rule — once enterococci are inside the set
that "gram-positive cocci in chains" licenses, the two rules agree instead of
fighting. Nothing regressed anywhere.

## 5. Category B — leave narrow (8 rules)

Context premises are doing the narrowing. Widening these would delete their content.

`gram-neg-rod-in-burn-patient-suggests-pseudomonas` (0.4),
`gram-neg-rod-in-compromised-host-suggests-pseudomonas` (0.6),
`hospital-acquired-aerobic-gram-neg-rod-suggests-pseudomonas` (0.7),
`neutropenia-with-aerobic-gram-neg-rod-suggests-pseudomonas` (0.5),
`gram-pos-cocci-in-chains-in-blood-compromised-suggests-enterococcus` (0.7),
`prosthetic-material-with-coagulase-neg-staph-suggests-staph-epidermidis` (0.6),
`neonate-with-beta-hemolytic-strep-suggests-strep-agalactiae` (0.7),
`urinary-coagulase-neg-staph-suggests-staph-saprophyticus` (0.65).

Plus the 7 already classified context-only, which have no intrinsic premise at all.

**This is where the original audit's concern still lives.** These rules' beliefs are
posteriors conditioned on context, and nothing structural checks them — the frame
cannot help, because the narrowing is epidemiological rather than deductive. The five
wrong conditionals `belief-conditional-audit.md` found are step 3 of that audit, and
they remain step 3. The frame reduces the surface; it does not eliminate it.

## 6. Category C — the corpus is missing a ruling-out fact (4 rules)

These look too narrow, but the rule is right and the *corpus* is incomplete. In each
case a discriminating test has **no ruling-out counterpart**, so the corpus cannot use
it to exclude anything.

| rule | flagged as also licensing | the missing fact |
|---|---|---|
| `enterobacteriaceae-urease-pos-swarming-suggests-proteus` (0.8) | `klebsiella`, `serratia` | Nothing records that they do not show **swarming** motility. |
| `enterobacteriaceae-motile-lactose-pos-indole-neg-suggests-enterobacter` (0.6) | `klebsiella`, `serratia` | Nothing records that Klebsiella is **non-motile** — which the rule's own note cites as the discriminator. |
| `staph-coagulase-neg-novobiocin-resistant-suggests-staph-saprophyticus` (0.8) | `staphylococcus-epidermidis` | Nothing records that S. epidermidis is **novobiocin-sensitive**. |
| `bile-esculin-pos-salt-tolerant-chains-suggests-enterococcus-class` (0.8) | the 4 streptococci | Nothing records that streptococci are **not salt-tolerant** — which the note cites as the discriminator. |

There are no disconfirming rules for `motility`, `novobiocin`, or `salt-tolerance` at
all. In three of the four cases **the rule's own `:note` names the discriminator the
corpus does not encode.**

This answers the question David asked at the start — *"how is a human author to know
when to write a disconfirming rule?"* Under the frame you do not guess. **The gap
shows up as a focal set wider than you intended, and the audit names the missing
fact.** The fix is one `:opposes` declaration each, e.g.:

```lisp
(defrule non-motile-argues-against-motile-enterobacteriaceae
    (:belief 0.7 :opposes (:enterobacter :serratia :proteus) ...)
  ... (motility (value non-motile) (of ?o)) ...)
```

**I am not proposing these yet.** Each is a new clinical claim needing its own
evidence and its own belief, which is corpus work rather than a focal-set correction.
Recommend a separate slice after phase 1 lands. Serratia is genuinely licensed in the
Enterobacter row regardless — it is motile and lactose-variable — so that one is
partly a real widening.

## 7. Category D and decision D6 — does `:other-organism` belong in focal sets?

Two rules (`anaerobic-gram-neg-rod-in-blood/abdomen-suggests-bacteroides`) are flagged
solely because they exclude `:other-organism`, as is the staphylococcus class rule.
This generalises, and it needs a decision.

Nothing in the corpus records anything about `:other-organism`, so **it is licensed by
every rule.** Two ways to go, and neither is free:

- **Never include it.** Every rule excludes it, so plausibility collapses — phase 0
  measured `Pl(:other-organism) = 0.027` in culture-5, on the strength of three
  illustrative rules. Not credible.
- **Always include it.** No evidence ever reduces it, so `Pl(:other-organism)` stays
  near 1 forever. Honest but useless.

**Recommendation: include it in coarse rules, exclude it from fine ones.** A
gram-negative rod could easily be an unmodelled gram-negative rod; an organism that is
enterobacteriaceae, lactose-positive and indole-positive is much more likely to be one
of the six the corpus models. Concretely, include it in the 4 organism-class rules and
the gram-stain-level identity rules; exclude it from species-level biochemical rules.

I hold this loosely. It is a judgement with no corpus evidence behind it, unlike
everything else in this document, and it should be measured before it is fixed.

## 8. What I propose to do

1. **Apply category A** — 3 focal-set corrections plus 1 new frame subset. Measured
   above: two rankings restored, one conflict reduced, nothing regressed.
2. **Leave category B**, and record in the design that context-conditioned beliefs
   remain unguarded by the frame.
3. **Defer category C** to its own slice, with the four missing facts listed as the
   work.
4. **Decide D6** before capturing any golden, since it moves every number.

Category A does not move a golden by itself, because the engine does not yet
accumulate through focal sets — that is slice E. Goldens move once, in slice G, with
every decision already made.