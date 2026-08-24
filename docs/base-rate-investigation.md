# Is the corpus missing a base-rate rule?

**Status: INVESTIGATION, findings recorded in v0.14.0. The defect it describes is
DISCLOSED but NOT FIXED** — see §5 for the four options, none of which has been chosen.
The disclosure shipped: the four rules' `:note`s and the system prompt both say these
rules are not independent evidence.

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
