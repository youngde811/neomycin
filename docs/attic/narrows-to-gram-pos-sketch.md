# Sketch — the gram-positive cluster as narrows-to rules

> **📦 ATTIC — historical record.** Design sketch for converting the gram-positive cluster to narrows-to rules. **The conversion happened**; the corpus is the authority now. Kept as the record of the argument.

> **Design sketch for review. No code.** Follows `docs/attic/narrows-to-spike.lisp`, which
> showed the shape reproduces culture-4's shipped numbers exactly with no disconfirming
> rules, no frame declaration and no hidden pool.
>
> Scope: everything gram-positive — 15 cluster rules, 4 host-factor rules, and the 8
> ruling-out rules that touch them. **27 rules in, about 20 out.**

## 1. The shape

One kind of rule. It says what its evidence narrows the answer to, asserts that as a
fact, and carries a belief.

```lisp
(defrule coagulase-neg-narrows-to-coagulase-negative-staph
    (:belief 0.85)
  (organism (id ?o))
  (gram (value pos) (of ?o))
  (morphology (value coccus) (of ?o))
  (growth-conformation (value clumps) (of ?o))
  (coagulase (value negative) (of ?o))
  =>
  (assert (candidates (value '(:staphylococcus-epidermidis
                               :staphylococcus-saprophyticus))
                      (of ?o))))
```

Nothing is excluded by being named. S. aureus falls out because
`{epidermidis, saprophyticus}` intersected with anything claiming aureus is empty.

## 2. `organism-class` does not survive — and nothing needs to replace it

**A class is a candidates set.** `:staphylococcus` *is*
`{aureus, epidermidis, saprophyticus}`. Asking "is this a staphylococcus?" is asking
Bel and Pl of that set, which the algebra already answers. There is nothing left for a
separate `organism-class` fact to do.

Three consequences, all good:

- **The three carried-over class beliefs stop existing.** 0.7 / 0.7 / 0.8 were
  inherited from retired rules and answered no conditional — the finding that started
  this whole investigation. As narrows-to beliefs they answer a real question: *how
  reliably does "gram-positive coccus in clumps" mean one of these three?*
- **The two-tier class/species structure collapses.** No chaining, no composition law,
  no belief flowing "through" an intermediate.
- **Nothing enumerates a taxonomy.** The sets are written where they are used.

### What gates a species rule, if not the class?

Its own evidence, in almost every case — the discriminating test is already specific
to the group:

| rule | gated by | class needed? |
|---|---|---|
| coagulase ± | coagulase is a staphylococcal test | no |
| novobiocin | requires coagulase-negative anyway | no |
| hemolysis + bacitracin | streptococcal | no |
| hemolysis + optochin | streptococcal | no |
| **sorbitol / arabinose** | sugar fermentations — used on many genera | **yes** |
| **respiratory site** | pure context, no bench finding at all | **yes** |

The two that need it don't need a *class fact* — they need the evidence that would
have derived it. Sorbitol/arabinose gate on `bile-esculin +` and `salt-tolerance`
(the enterococcal discriminators); the respiratory-site rule gates on gram +
morphology + conformation. Explicit, and one less indirection to follow.

**A note on what happens if a rule fires on nonsense** — coagulase asserted on a
streptococcus, say. It contributes `m({aureus})`, which conflicts with the
streptococcal set and drives `K` up. The math complains loudly rather than being
silently wrong. That is a feature, but it is a *diagnostic*, not a guard.

## 3. All 8 ruling-out rules become confirming rules

Every one has a natural "what does this narrow to" reading. None survives as a
separate kind of thing.

| today (excludes) | becomes (narrows to) |
|---|---|
| `coagulase-neg-argues-against-staph-aureus` | `{epidermidis, saprophyticus}` |
| `coagulase-pos-argues-against-coagulase-negative-staph` | `{aureus}` |
| `catalase-neg-argues-against-staphylococci` | `{4 strep, 2 enterococci}` |
| `beta-hemolysis-argues-against-non-beta-streptococci` | `{pyogenes, agalactiae}` |
| `alpha-hemolysis-argues-against-beta-hemolytic-streptococci` | `{pneumoniae, viridans}` |
| `optochin-sensitive-argues-against-viridans` | `{pneumoniae}` |
| `bile-esculin-neg-argues-against-enterococci` | `{4 streptococci}` |
| `arabinose-pos-argues-against-e-faecalis` | `{faecium}` |

`catalase-neg` is the one worth noticing: today it can only say "not a
staphylococcus." As a narrows-to rule it says what it actually establishes — a
catalase-negative gram-positive coccus is a streptococcus or an enterococcus. Same
observation, more information, and the exclusion still happens.

## 4. Four merges — and each exposes two numbers for one fact

This is where the shape pays for itself beyond tidiness. Once a finding is stated
once, pairs that were written twice have to agree, and three of them do not:

| finding | confirming today | excluding today | disagreement |
|---|---|---|---|
| coagulase **positive** | 0.85 → aureus | 0.85 → not coag-neg | none — merge at 0.85 |
| coagulase **negative** | **0.55** → epidermidis+saprophyticus | **0.85** → not aureus | **0.55 vs 0.85** |
| optochin **sensitive** | **0.85** → pneumoniae | **0.70** → not viridans | **0.85 vs 0.70** |
| **alpha** hemolysis | (none at this granularity) | 0.75 → not beta-hemolytic | becomes 0.75 → `{pneumoniae, viridans}` |

The coagulase-negative case is the instructive one. The 0.55 was justified in its own
note — *"coagulase-negativity identifies the GROUP, not this species"* — which is
exactly right, and exactly why the number was wrong: it was discounted for naming a
species when it should have named the **group**. As a set claim it is the 0.85 the
ruling-out rule already used. **Merging fixes an error rather than papering over one**,
and it is the same error `belief-conditional-audit.md` found by hand.

## 5. Rules after conversion — about 20

- **6 narrowing-by-stain / group**: clumps→staph, chains→strep+enterococci,
  catalase-neg→strep+enterococci, bile-esculin+salt→enterococci, bile-esculin-neg→strep,
  and the blood/compromised context rule→enterococci
- **8 narrowing-by-bench-test**: coagulase ±, novobiocin, hemolysis ×2, bacitracin ×2,
  optochin ×2, sorbitol/arabinose ×2 *(some collapse in the merges above)*
- **5 narrowing-by-context**: hospital-acquired, respiratory site, neonate, prosthetic
  material, IV drug use, urinary source

Context rules narrow to a small set with modest belief — `m({aureus}) = 0.55`,
`m(Θ) = 0.45`, which is precisely what "IV drug use makes S. aureus likely" means. They
do not resist the shape. What they *do* produce is honest conflict against a bench
finding pointing elsewhere.

## 6. What this would test, and what it would not

**Would answer.** Whether `organism-class` can go; whether all 8 ruling-out rules
convert; whether the merges expose real number disagreements; whether context rules
work in the shape; and whether culture-3, 4 and 5 still land somewhere defensible
against goldens we already have.

**Would not answer.** Whether the enterobacteriaceae cluster behaves the same (it has
deeper chaining and more cross-disconfirmation); what the therapy layer consumes when
conclusions are sets rather than species; or how `/why` narrates a candidates fact.
Those come after, if this holds.

**Still a spike.** `docs/` only. No engine change, no corpus change, master untouched.

## 7. The one thing I would flag before building

Section 4's merges mean **choosing a number** where the corpus currently holds two.
Those are clinical judgements, not mechanical ones. My inclination is to take the
higher of each pair, because in every case the lower number was discounted for naming
a species when the honest claim was the group — but that is a judgement about
microbiology, and it is the one part of this I would rather you set than infer.