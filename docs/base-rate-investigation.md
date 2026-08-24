# Is the corpus missing a base-rate rule?

**Status: FIXED. Option 3 chosen and implemented** — see §7. §§1–6 are the
investigation as written, before a choice was made; §7 records what was done and why the
option that first looked most consistent with the corpus turned out to be wrong.

Raised while reviewing §6 of `docs/belief-coherence-survey.md`: if the compromised-host
and hospital-acquired rules are essentially restating the base rate of gram-negative
bacteraemia, then tuning their commitments papers over a structural gap rather than
fixing anything.

**The suspicion was right, and the defect is worse and more precise than "a missing
rule".**

## 1. Four rules are the same distribution wearing four labels

Every graded rule's focal masses, normalised by that rule's own commitment — so this is
each rule's *shape*, independent of how much it commits:

| rule | e-coli | klebsiella | pseudomonas | rest |
|---|---|---|---|---|
| `compromised-…` (0.60) | 0.467 | 0.267 | 0.133 | 0.133 |
| `hospital-acquired-…` (0.70) | 0.429 | 0.271 | 0.157 | 0.143 |
| `hospital-acquired-compromised-…` (0.70) | 0.400 | 0.300 | 0.171 | 0.129 |
| `neutropenia-…` (0.50) | 0.400 | 0.260 | 0.180 | 0.160 |
| **`burn-…`** (0.40) | 0.200† | 0.175 | **0.500** | 0.125 |
| **`tropical-travel-…`** (0.65) | 0.231 | 0.123 | — | salmonella **0.646** |

† burn's e-coli sits inside a three-member focal set, so this is the set's share.

**Four of the six have the same shape to within rounding.** They differ only in how much
they commit. Burn and travel are the only two whose evidence produces a genuinely
different distribution.

That shape — E. coli ~0.43, Klebsiella ~0.27, Pseudomonas ~0.15 — is the base rate of
gram-negative bacteraemia. Each of the four cites it honestly (E. coli 40.5% of
nosocomial gram-negative bacteraemia, 47% in solid-tumour patients, 39.5% of
gram-negatives in febrile neutropenia). **None of them is wrong on its own.** They are
all reporting the same underlying fact, and each is entitled to.

## 2. The concrete harm: they are counted as independent evidence

`compromised-host` and `neutropenia` are different premises and neither subsumes the
other, so a patient who is both fires both. Measured:

| | e-coli | klebsiella | pseudomonas | K |
|---|---|---|---|---|
| compromised alone | 0.2800 | 0.1600 | 0.0800 | **0.0000** |
| neutropenic alone | 0.2000 | 0.1300 | 0.0900 | **0.0000** |
| **both** | **0.3492** | 0.1933 | 0.1053 | **0.2096** |

Two things go wrong at once, and they point in opposite directions:

- **Spurious confidence.** E. coli rises to 0.3492 — well above either rule alone —
  because Dempster's rule treats the two as independent corroboration. They are not
  independent. They are one epidemiological fact reported twice.
- **Spurious conflict.** K jumps from 0.0000 to 0.2096 between two rules that *agree*
  about the shape of the answer. Their singleton focal sets are pairwise disjoint —
  `{e-coli}` from one against `{klebsiella}` from the other — so agreement about the
  distribution registers as disagreement about the organism.

A clinician reading that payload is told the case is both more settled *and* more
conflicted than the evidence supports.

## 3. So the diagnosis is not "a missing rule"

It is worth being precise, because three different defects are easy to confuse here.

**It is not that the corpus lacks a prior.** The open-frame design is *deliberately*
prior-free — a flat answer over seven organisms does not assert that they are equally
likely, it declines to say which, and the unclaimed mass sits on Θ as explicit
ignorance. That is the representation working as designed, and adding a base-rate rule
would undo it.

**It is not that any individual rule is mis-weighted.** Each of the four cites a real
figure for its own population, and §6's proposal to reorder their commitments would not
have touched this.

**It is that the four rules are not conditionally independent, and Dempster's rule
assumes they are.** That is the whole defect, and it is a familiar shape: *the
representation assumes something the domain does not supply* — the same form as the
Category B finding that an answer set can only express exclusion.

## 4. What §6 looks like from here

**§6 was addressing a symptom.** It proposed reordering the context rules' commitments
by evidence strength — but four of those commitments are attached to the same fact, so
"which context has stronger evidence" is not a well-posed question for them. The
ordering §5C observed is real, and it is not the thing that most needs fixing.

Declining §6 was right, and for a stronger reason than the one originally given.

## 5. Options, not recommendations

Presented in order of how much they change, and I would not pick one without discussion.

1. **Document and accept.** Record the dependence in the rules' notes and in the
   system prompt, so a narrator does not report double-counted confidence as
   corroboration. Cheapest; leaves the numbers wrong when two contexts co-occur.

2. **Make the redundant rules flat again.** If a context rule's shape is the base rate,
   its *distinguishing* content is zero — the honest answer is "one of these six" at its
   stated commitment, with no grading. Only burn and travel would stay graded, because
   only they reweight. Two flat answers over the same set reinforce cleanly and produce
   **no conflict at all**, which fixes both halves of §2. The cost: the corpus stops
   saying E. coli leads in a nosocomial case, which is true and useful.

3. **Extend the specificity policy to co-occurring contexts.** At most one
   opportunist-shape rule contributes — the most specific applicable one — even when
   premises do not nest. This generalises the machinery already in `consensus.lisp`
   from *nested premises* to *redundant evidence*, and keeps the grading. The cost: a
   new policy decision about which context wins when neither subsumes, and that is a
   clinical judgement rather than a structural one.

4. **Represent the dependence properly.** Cautious/idempotent combination for rules
   drawn from a shared source, rather than Dempster's rule. `*frame-operator*` already
   carried a `:cautious` setting in the v0.9–v0.10 line, so there is precedent in the
   codebase. Largest change, most principled, and would want its own release.

**My inclination is (3), with (1) done immediately regardless** — the notes should not
describe these as independent evidence while they are combined as such. But (2) is the
most consistent with how the corpus has resolved this kind of question before: when the
evidence does not distinguish, say so and stop.

## 6. One measurement that would sharpen the choice

Nothing in the corpus checks whether two rules' *shapes* are near-identical. That is a
mechanical test — normalise each graded rule and compare — and it would have caught this
when the four rules were authored in v0.13, one after another, from overlapping
literature. Worth adding whichever option is chosen.


---

# 7. Outcome — option 3, and why not option 2

**Added after implementation.** David chose **option 2** (make the redundant rules flat
again) on the strength of §5, and I had written there that it was "the most consistent
with how the corpus has resolved this kind of question before." Measuring it first
changed the decision, and the measurement is worth keeping.

## 7.1 What option 2 would actually have done

| compromised + neutropenic | e-coli | klebsiella | pseudomonas | K | mass on the six |
|---|---|---|---|---|---|
| as shipped | 0.3492 | 0.1933 | 0.1053 | 0.2096 | — |
| **option 2** (both flat) | 0.0000 | 0.0000 | 0.0000 | 0.0000 | **0.800** |
| **option 3** (strongest only) | **0.2800** | **0.1600** | **0.0800** | **0.0000** | 0.320 |

Option 2 removes the spurious conflict and the spurious per-organism confidence — both
real wins — but **it does not remove the double-counting, it relocates it.** Two flat
answers still combine as independent evidence, so the set-level belief inflates to 0.800
when neither rule alone claims more than 0.60. That figure drives the therapy
set-obligation gate.

It also discards information the citations support. For a patient whose only evidence is
host context, the corpus would say **nothing at all** about which organism — every
belief zero, everything at plausibility 1.0.

And it flips culture-1:

| culture-1 | e-coli | pseudomonas |
|---|---|---|
| as shipped | **0.2322** | 0.1756 |
| §6, declined | 0.1683 | **0.2675** |
| option 2 | **0.0000** | **0.2000** |

E. coli falls to *zero*, because the only rule giving it belief was the compromised-host
grading. That is the outcome §6 was declined for, reached more starkly by a different
route — and it would have arrived as a side effect rather than a decision.

## 7.2 Why the "consistency with precedent" argument was wrong

The precedent I appealed to is *when the evidence does not distinguish, say so and stop*
— which is how Category B resolved the singleton problem. **It does not apply here.** The
evidence *does* distinguish: E. coli genuinely does lead in these populations, and the
citations say so. The problem was never that the rules claimed too much. It was that two
of them claim the same thing twice.

**Option 2 solves a double-counting problem by discarding the thing being counted.**

## 7.3 What was implemented

A rule may declare `:evidence-group` in its provenance, meaning *these rules rest on the
same underlying evidence*. Within a group **only the most committed member contributes**
— ties broken by name for determinism — and the rest are dropped before combination and
are absent from the argument as well as the arithmetic.

This extends the specificity policy along its natural second axis. Subsumption drops a
rule whose *premises* are contained in another's; this drops a rule whose *evidence* is
another's. Subsumption cannot see the second case, because it reads premises rather than
sources.

Result: the pair gives exactly what the stronger rule gives alone — 0.2800 on E. coli,
`K = 0.0000`, no inflation at either level. **culture-1 is untouched**, because burn and
travel carry genuinely different distributions, are in no group, and still combine.

## 7.4 The check §6 asked for

Two invariants, both negative-tested, checking the declaration from each side:

- **19a** every member of a group must actually share a shape with the others —
  grouping rules that disagree would silently discard real evidence;
- **19b** any two graded rules that *do* share a shape must be in one group — the
  mechanical test §6 called for, which would have caught the original defect when the
  four rules were authored one after another from overlapping literature.

"Shape" is each focal mass as a fraction of its rule's own commitment; the tolerance is
loose on purpose, because it detects an omission rather than defining the semantics.

