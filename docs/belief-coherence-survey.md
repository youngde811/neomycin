# Belief coherence — and the coverage-threshold dial

**Status: SURVEY. No code changes. Nothing here has been applied.**
Branch: `feature/belief-coherence`, from `develop` at v0.13.0.

## 1. Scope, and what this is not

This is **(b)-style calibration**: fixing places where the corpus's beliefs are
*inconsistent with each other*, given what the corpus itself says a belief means. It is
**not** an attempt to make the numbers measured, sourced, or clinically valid. They stay
`:belief-basis :illustrative`, the disclaimer stays loud, and the paper must still not
claim calibrated beliefs.

Everything proposed below is a **relative** judgement — this rule should not commit less
than that one — argued from evidence already cited in the corpus. Nothing here rests on
a new literature claim.

## 2. First, a check I got wrong

I began by testing what looked like the obvious law: **a rule that subsumes another
should commit at least as much.** It reported 13 violations, which should have been the
tell — a law that half the corpus breaks is usually the law's fault.

It was. `coagulase-positive-narrows-to-aureus` (0.85) subsumes
`clumps-narrows-to-staphylococci` (0.70), and there is nothing wrong with that. These
are not two estimates of one quantity that must agree. They are **independent pieces of
evidence**, each committing mass to its own set, combined by Dempster's rule — and the
algebra already guarantees `Bel({aureus}) ≤ Bel({the three staphylococci})` in the
combined result, whatever the individual rules say. The monotonicity I was checking for
is enforced downstream, not upstream.

Recording this because the corrected version is much narrower, and because a coherence
law that fires everywhere is worth distrusting before the corpus is.

## 3. What a `:belief` means here — and the one place the corpus disagrees with itself

The corpus's clearest statement is in `clumps-narrows-to-staphylococci`:

> *how reliably does clumping mean one of these three?*

So: **belief = the mass this evidence commits to this answer set.** How sure we are the
true organism is in there, given the premises. Under that reading, resolution and belief
are independent axes — a wide answer is a weaker *claim* but not a weaker *rule*.

**One rule's note contradicts this.** `urease-negative-narrows-to-non-proteus-rods`
justifies its 0.60 as:

> *0.6 reflects a real but narrow claim — one organism removed from eight — not a weak
> one.*

That reasons from **informativeness** ("how much did I narrow?") where the value means
**reliability** ("how sure am I the answer contains the truth?"). Those pull in opposite
directions: removing one organism from eight leaves a *wide* answer, which is easy to be
right about and should carry *high* mass. The note argues for a low number using a
premise that implies a high one.

This is the only place the confusion is written down, but it plausibly explains the two
asymmetries in §5.

## 4. The one hard violation

Checked across the corpus: **subsumption pairs whose answers have the same support.**
That is the only place the specificity policy actually swaps one rule for another, and
therefore the only place a belief inversion causes committed mass to be *lost*.

There are two such pairs. One is fine. The other:

| | rule | belief |
|---|---|---|
| specific | `hospital-acquired-compromised-aerobic-gram-neg-rod-narrows-to-opportunist-rods` | **0.60** |
| general | `hospital-acquired-aerobic-gram-neg-rod-narrows-to-opportunist-rods` | **0.70** |

The specific rule's premises are a strict superset, so when both fire the general one is
**dropped**. The corpus therefore commits **0.60 where it would have committed 0.70 with
strictly less information**: learning that a hospital-acquired patient is *also*
immunocompromised makes it less sure.

This is not a probability error — it is the specificity policy and the belief values
disagreeing. **It is the cleanest defect in this survey and the one I would fix even if
nothing else here is approved.**

**Proposed:** raise `hospital-acquired-compromised-…` to **0.70**, matching the strongest
rule it subsumes. A law worth encoding as an invariant: *a rule must not commit less than
any same-support rule it subsumes.*

## 5. Two reciprocal readings discounted without a reason

The corpus has a clear precedent for reciprocal pairs. `catalase-positive` (3-member
answer) and `catalase-negative` (6-member answer) both carry **0.70**, and the note says
why explicitly: *"the same partition read from the other side … the test is no more or
less reliable in one direction than the other."* **Equal belief, different resolution** —
exactly right under §3's reading. Beta/alpha hemolysis likewise, both 0.75.

Three other pairs are asymmetric **with stated justification**, and should stay:
novobiocin 0.80/0.70, bacitracin 0.85/0.70, optochin 0.85/0.65. In each case the note
names a real asymmetry in the test.

Two are asymmetric **without one**:

### 5.1 Lactose — 0.70 / 0.60

| reading | answer | belief |
|---|---|---|
| fermenter | `e-coli, enterobacter, klebsiella, serratia` | 0.70 |
| non-fermenter | `proteus, pseudomonas, salmonella, serratia` | 0.60 |

Same test, **same-size answers**, and the same organism (Serratia) kept in both for the
same stated reason — its variability is symmetric and is already handled by widening. The
non-fermenter note opens *"The reciprocal"* and then never says why it is discounted.

**Proposed:** both **0.70**. Follows the catalase precedent exactly.

### 5.2 Urease — 0.70 / 0.60

| reading | answer | belief |
|---|---|---|
| positive | 5 members | 0.70 |
| negative | 7 members | 0.60 |

The negative reading is, if anything, the **stronger** one: the corpus's own note says
Proteus is *"rapidly and strongly urease-positive"*, so a negative result excludes it
crisply, whereas a positive result is muddy (Pseudomonas 72%, three others variable). The
sharper reading over the wider set carries the lower number, justified by the
informativeness/reliability confusion identified in §3.

**Proposed:** both **0.70**, and rewrite the note to stop arguing from narrowness.

## 6. §5C: the context rules commit in roughly the reverse order of their evidence

This is the item Category B recorded and deferred. Graded answers already encode *which
way* each context leans; what remains inconsistent is **how much each commits at all**.

| rule | commits | what the cited evidence supports |
|---|---|---|
| `burn-blood-…-opportunist-rods` | **0.40** | Pseudomonas 34–51% of burn gram-negative bacteraemia — a large, specific shift |
| `neutropenia-…-opportunist-rods` | 0.50 | **self-declared weakest citation in the corpus**; sources support empiric coverage, not likelihood |
| `iv-drug-use-clumps-narrows-to-aureus` | 0.55 | S. aureus ~70% of PWID endocarditis — the **best-evidenced** rule in the context set |
| `compromised-…-opportunist-rods` | 0.60 | E. coli ~40–47% — broad, and close to the gram-negative baseline |
| `hospital-acquired-compromised-…` | 0.60 | both of the above | 
| `tropical-travel-…-enteric-rods` | 0.65 | enteric fever strongly travel-associated — sharp and specific |
| `hospital-acquired-…-opportunist-rods` | **0.70** | E. coli 40.5%, Klebsiella 22.5% — broad, near baseline |
| `respiratory-chains-…` | 0.75 | pneumococcus the leading identified CAP pathogen |
| `hospital-acquired-clumps-narrows-to-aureus` | **0.80** | CoNS **comparable to or larger than** S. aureus in ICU bloodstream surveillance |

Two orderings are plainly backwards:

- **The best-evidenced rule commits the second-least** (iv-drug-use, 0.55) and **a rule
  its own surveillance contradicts commits the most** (hospital-acquired-clumps, 0.80).
- **A context that barely moves the distribution off baseline commits more than one that
  moves it a long way.** Hospital acquisition puts E. coli on top, which is roughly where
  it sits anyway; a serious burn puts Pseudomonas at a third to a half. Burn commits 0.40
  against hospital-acquired's 0.70.
- `neutropenia` commits 0.50 while its own note calls its citation the weakest in the
  corpus.

**Proposed** — a relative ordering by how sharply the context shifts the answer, and by
how well the shift is evidenced:

| rule | now | proposed |
|---|---|---|
| `neutropenia-…` | 0.50 | **0.40** — its note says it is the weakest; make the number agree |
| `compromised-…` | 0.60 | **0.55** — broad, near-baseline |
| `hospital-acquired-…` | 0.70 | **0.60** — broad, near-baseline |
| `hospital-acquired-clumps-…-aureus` | 0.80 | **0.65** — surveillance does not support the joint-highest belief in the corpus |
| `burn-blood-…` | 0.40 | **0.65** — a large, specific, well-cited shift |
| `tropical-travel-…` | 0.65 | 0.65 — unchanged |
| `iv-drug-use-clumps-…` | 0.55 | **0.70** — best-evidenced rule in the set |
| `hospital-acquired-compromised-…` | 0.60 | **0.70** — §4, must not fall below what it subsumes |
| `respiratory-chains-…` | 0.75 | 0.75 — unchanged |

> ### The risk in §6, stated plainly
>
> **This will push Pseudomonas back ahead of E. coli in culture-1**, because burn rises
> from 0.40 to 0.65 while compromised-host falls from 0.60 to 0.55. That is the PAIP
> answer, and the answer this corpus gave before v0.13.
>
> I want to be explicit that **restoring it is not the goal and must not become the
> test.** The argument for each row above is evidence-strength ordering, made without
> reference to what it does to culture-1; the ranking is a consequence. But it would be
> very easy to fool ourselves here, and if you would rather see §4 and §5 land on their
> own — where the arguments are structural and the outcome is not something anyone has
> an opinion about — that is a completely defensible place to stop. **§6 is the one part
> of this survey I would not ship without you looking hard at it.**

## 7. The coverage-threshold dial

`neomycin/therapy/protocol.lisp` currently claims:

> *0.1 IS NOT A TASTE, it is where the corpus is flat. Measured across every scenario,
> this gate decides exactly five figures — the runner-up organisms, at 0.242, 0.228,
> 0.194, 0.153 and 0.101. Nothing else in the corpus is affected by any value between
> 0.05 and 0.20.*

**None of those five figures exists any more**, and the flatness claim is false. Measured
across all eight drivers, every organism belief and every set-valued mass — 39 gated
figures:

| gate | figures clearing |
|---|---|
| 0.05 | 32 of 39 |
| 0.075 | 25 |
| **0.10** | **23** |
| 0.125 | 20 |
| 0.15 | 18 |
| 0.20 | 12 |

Moving the dial across the range the docstring calls inert changes the outcome for **20
of 39 figures**. And the figures immediately around 0.1 are dense — 0.0800, **0.1000**,
0.1050, 0.1105, 0.1263 — with `culture-1a`'s Pseudomonas sitting *exactly* on the gate.
That knife edge is what made the float-comparison bug reachable at all.

The widest gaps in the plausible range are now **0.1400 → 0.1649** and **0.1985 →
0.2322**.

**Proposed: do this in two steps, and do not choose a number yet.**

1. **Now:** delete the false claim from the docstring and replace it with what is
   actually true — that 0.1 was chosen against a corpus that no longer exists, and the
   justification is pending re-measurement. Leaving a false measured claim in source is
   the thing to fix first, and it is fixable without touching behaviour.
2. **After §4–§6 land:** re-run the sweep, because every belief change moves these
   figures, and *then* pick a value sitting in a real gap. Choosing now would just mean
   choosing twice.

## 8. What I am not proposing

- **No absolute calibration.** Nothing here claims a number is correct, only that one
  number should not be lower than another.
- **No change to the graded distributions.** The focal masses set in v0.13 follow cited
  proportions; only rules' *totals* move, and invariant 14 will keep each distribution
  summing to its declared belief.
- **No change to the bench rules other than §5**, which is two reciprocal pairs.
- **No new citations.** Every argument above uses evidence already in the corpus.

## 9. Blast radius

§4 and §5 move a handful of goldens. §6 moves nearly all of them, including the README's
worked example and the release-check sample. Same shape as v0.13: re-capture from the
engine rather than editing by hand, re-run `bin/*.sh` against a live bridge, and run the
model-in-the-loop release check before tagging.

Three new invariants are worth adding whatever is approved:

1. a rule must not commit less than any **same-support** rule it subsumes (§4);
2. reciprocal readings of one marker must carry equal belief **unless the rule's note
   states an asymmetry** (§5);
3. the coverage threshold's docstring must not assert a plateau that the corpus does not
   have — best enforced by a test that re-measures the sweep and fails if the claimed
   flat range is not flat (§7).
