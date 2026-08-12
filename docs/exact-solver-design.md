# Exact therapy solver — design & objective comparison

> **Status: accepted, unimplemented (2026-08-12).** No code yet. Written to settle
> one question before any is written: *what should the solver optimize?* The exact
> search is the easy part.
>
> **Decisions taken** (David, 2026-08-12): the objective becomes a third policy dial
> rather than a choice between the two candidates (§3.5); `:lexicographic` ships
> first as an equivalence check against greedy, `:spectrum-sparing` second; spectrum
> breadth is **declared** on `defdrug`, not derived from KB coverage counts (§3.4).
> The slice plan in §6 is the agreed order of work.

## 1. Why — greedy does not optimize what the codebase says it does

`greedy-solver.lisp` states its objective in its header: *"fewest drugs (minimality
= stewardship)"*, and the system prompt tells the clinician *"narrow-spectrum
minimalism is antimicrobial stewardship."* Neither is what the solver does. Run it:

| Case | Greedy returns |
|---|---|
| culture-1 — pseudomonas 0.76 + klebsiella 0.40 | **meropenem** |
| pseudomonas 0.76 alone | **meropenem** |
| klebsiella 0.40 alone | **meropenem** |
| S. aureus 0.60 + klebsiella 0.50 | vancomycin, **meropenem** |

A carbapenem for a single organism is the textbook stewardship anti-pattern, and
the solver reaches for it every time. The mechanism is not a bug — it follows
directly from the objective:

- **Cardinality is vacuous at this scale.** With 1–2 organisms to treat, most
  candidate drugs cover the same number of items, so `n` ties immediately.
- **The tiebreak then *is* the policy.** `coverage-weight` sums
  susceptibility × identification-belief, so once cardinality ties, the drug with
  the highest declared susceptibility wins outright.
- **Breadth and susceptibility correlate by construction.** Meropenem's
  `:enterobacteriaceae` entry is `[0.90, 0.99]` — the highest in the KB — against
  ceftriaxone's `[0.68, 0.92]` for klebsiella and ceftazidime's `[0.64, 0.88]`. For
  klebsiella alone the weights are 0.90 × 0.40 = 0.36 vs 0.272 vs 0.256. Meropenem
  wins, and will keep winning, because the agents we reserve *are* the agents with
  the best coverage numbers.

So "fewest drugs" is not a stewardship objective. It is silent about which drug,
and the tiebreak that actually decides has never been stated as policy.

**That is the real reason to build an exact solver.** Not optimality — greedy's
answers here are already minimum-cardinality. Writing an exact solver forces the
objective to become an explicit, named, comparable thing, which is the same move
this fork already made for the belief algebra (CF vs DS) and the coverage gate
(belief / plausibility / midpoint).

## 2. Exact search is cheap at this scale

Minimum set cover is NP-hard; greedy is the standard `ln(n)` approximation. None of
that matters here.

- 11 drugs in the KB; ≤ 17 leaf identities; realistically 1–4 items after the
  belief gate.
- **Ascending-k**: test every 1-drug regimen, then every 2-drug, stop at the first
  size that covers. Terminates at k=1 or k=2 in nearly every real case.
- Worst case is 2¹¹ = 2048 subsets — trivial.
- Coverage sets fit in a fixnum, so a candidate's coverage is a bitmask, union is
  `logior`, and "covers everything" is one comparison.
- **Dominance pruning**: drop any drug whose coverage is a subset of another's that
  also wins the objective. Usually collapses the candidate set before search.

A page of code. The KB would have to grow by two orders of magnitude before the
algorithm mattered.

## 3. The objective — the actual decision

### 3.1 Option A — lexicographic drop-in

*Minimize drug count; tie-break by maximum Σ(susceptibility `bel` × identification
belief); tie-break by name.*

This is **exactly what greedy does today**, promoted from an implementation detail
to a declared objective and computed exactly rather than approximately.

**For**
- Zero behaviour change. Every existing therapy golden stays valid; the exact
  solver is a pure equivalence check.
- Makes greedy *auditable*: assert corpus-wide that greedy's regimen equals exact's
  for every scenario. A future KB that breaks greedy's approximation gets caught by
  a test rather than noticed by a clinician.
- No new knowledge required. Works from the KB exactly as it stands.

**Against**
- It formalizes carbapenem-first. The behaviour in §1 stops being an accident and
  becomes the specification.
- It leaves the codebase's stated intent — narrow-spectrum stewardship — still
  unimplemented, and now *provably* so.

### 3.2 Option B — spectrum-breadth stewardship

*Minimize drug count; then minimize summed spectrum breadth; then maximize
susceptibility; then name.*

**For**
- It is the objective the project already claims in two places. Implementing it
  makes the documentation true.
- It changes the answers, visibly and defensibly: klebsiella alone would move from
  meropenem to ceftriaxone; culture-1 from meropenem to ceftazidime.
- It is the clinically interesting comparison, and the one a demo audience
  recognizes — "the same case, under two stewardship policies" is a better story
  than "the same answer, computed exactly."
- It exercises the fork's thesis at the therapy layer: the point of making the
  policy dial explicit is that you can *turn it* and see what changes.

**Against**
- It needs a breadth measure the KB does not currently carry (§3.4).
- It can prefer a *less effective* drug. Ceftriaxone's klebsiella `bel` is 0.68 vs
  meropenem's 0.90 — narrowing spectrum costs coverage confidence, and the
  recommendation must say so rather than bury it.
- "Narrow" is context-dependent in reality (narrow for *this* organism vs narrow
  overall), and a single scalar flattens that.

### 3.3 Side by side

| | A — lexicographic | B — spectrum-breadth |
|---|---|---|
| Behaviour vs today | identical | changes most single-organism cases |
| New KB knowledge | none | a breadth axis (§3.4) |
| Existing goldens | all stay valid | several must be re-captured |
| Makes greedy testable | yes | yes |
| Implements the stated intent | no | yes |
| Risk | freezes a policy nobody chose | a wrong breadth number silently reshapes every regimen |

### 3.4 Where breadth data comes from — the crux

Two ways, and the choice matters more than the search algorithm.

**Derived** — count the organisms each drug has a susceptibility entry for, family
entries expanded. Computable today, no authoring:

| Drug | Covers (of 17) | | Drug | Covers |
|---|---:|---|---|---:|
| piperacillin-tazobactam | 17 | | ampicillin | 7 |
| meropenem | 15 | | ceftazidime | 7 |
| ceftriaxone | 13 | | ciprofloxacin | 7 |
| linezolid | 9 | | gentamicin | 7 |
| vancomycin | 9 | | nafcillin | 7 |
| | | | metronidazole | 1 |

The ordering is clinically plausible — metronidazole narrowest, pip-tazo and
meropenem broadest — which is reassuring but also a trap: **this measures breadth
*within a schematic 17-organism KB*, not breadth in medicine.** Ampicillin and
ceftazidime tie at 7 here; no clinician would call them equally broad. Adding one
species to the rulebase silently re-ranks drugs. A derived measure is an artifact
of KB curation masquerading as a clinical fact.

**Declared** — a `:spectrum` field on `defdrug`, alongside the existing `:class`,
`:route`, `:dose`. An ordinal tier (`:very-narrow :narrow :moderate :broad
:very-broad`) is honest about being a judgement, is stable under KB growth, and can
carry its own provenance note exactly as rule beliefs do — including the
`belief_basis: illustrative` caveat, which applies here with full force.

**Recommendation: declared. — ACCEPTED.** The derived measure is free and wrong in a way that
would be hard to see later; this project's whole posture is that schematic values
are labelled as such rather than smuggled in. Deriving breadth from coverage counts
is exactly the kind of number that looks measured and isn't.

### 3.5 Recommendation: make the objective the third dial — ACCEPTED

Not A or B — **both, selected by a parameter**, the way `*belief-system*` and the
coverage gate already work. The exact solver takes an `objective` (`:lexicographic`
| `:spectrum-sparing`), defaulting to `:lexicographic` so nothing changes until
asked.

That ordering has a practical payoff: ship A first as a pure equivalence check
against greedy (no goldens move, the property test lands, the search is validated),
then add B as a second objective over machinery already proven. And the artifact at
the end is the comparison itself — the same case under two named policies, with the
divergence and its cost in coverage confidence both legible. That is a better
demonstration than either objective alone, and it is the same shape as the
CF-vs-DS and belief-vs-plausibility contrasts the project already trades on.

## 4. Design sketch

**Shared phase A.** The belief gate, contraindication filtering, and
`susceptibility->scalar` reduction are solver-independent and currently live inside
`greedy-solver.lisp`. Extract to a shared file so both solvers gate identically —
two solvers disagreeing about *what to treat* would make every comparison
meaningless.

**Search.** Candidates → bitmask coverage → dominance prune → ascending-k
enumeration → among all covers of minimum size, pick by the objective's comparator
→ deterministic name tiebreak last. Returns the same `RECOMMENDATION` struct; no
protocol change.

**Registration.** `(register-solver :exact (make-instance 'exact-solver))` — the
registry means no existing file changes. `tools.json` gains `"exact"` to the
`solver` enum; the prompt gains a line noting the solver is named in the response.

**Reporting.** Two additions worth making, both cheap once the search is exact:
- `alternatives` — other regimens of the same minimum size, so the narration can say
  *"three equally minimal regimens exist; this one was chosen because…"*, which is
  the honest thing to say when an objective breaks a tie no clinician stated.
- `objective` — echoed in the payload, like `gate` already is.

**Gate interaction.** The exact search can do something greedy structurally cannot:
optimize *across* gates. "Minimal under `belief` gating **and** still covering under
`plausibility`" is a well-defined query, and the Pareto frontier of (drug count ×
minimum coverage `bel`) is computable by re-running the search per gate. Worth a
follow-on slice, not this one.

## 5. Testing

- Per-scenario goldens for the exact solver, hand-verified as usual.
- **The equivalence property**: for every scenario, `exact(:lexicographic)` and
  `greedy` return regimens of the same size. Not the same *drugs* — a tie broken
  differently is legitimate — but a size difference means greedy's approximation
  lost, and that should be a documented counterexample rather than a surprise.
- **Determinism**: same inputs, same regimen, run twice, both solvers.
- Under B, a golden that pins the divergence: klebsiella alone → ceftriaxone, with
  the coverage-confidence cost (0.68 vs 0.90) asserted, so nobody can quietly
  "improve" the objective back to carbapenem-first.

## 6. Slice plan

1. **Extract shared phase A** from greedy; suite green, no behaviour change.
2. **Exact solver, `:lexicographic`** + registration + goldens + the equivalence
   property test. Nothing user-visible changes.
3. **`:spectrum` on `defdrug`** for all 11 drugs, with provenance notes and the
   illustrative caveat.
4. **`:spectrum-sparing` objective** + divergence goldens + `alternatives` reporting.
5. **Bridge/tool/prompt surface**: `solver` enum, `objective` parameter, narration
   guidance for stating the trade — *"narrower agent, lower coverage floor."*
6. Docs: scenario contrasting the two objectives on one case; runbook note.

## 7. Non-goals / open

- **Not clinical optimality.** Optimal against a schematic KB. The NOT FOR CLINICAL
  USE line matters more here than anywhere else in the project, because "exact" and
  "optimal" are words a reader will over-trust.
- **Drug-drug interactions** remain unhandled (design doc 4.3 step 4), in both
  solvers.
- **Cost and toxicity** are further objectives the same dial could carry; out of
  scope until there is a reason to author that data.
- **Open**: should `:spectrum-sparing` be allowed to *increase* drug count — two
  narrow agents instead of one broad one? Clinically that is sometimes right and
  sometimes absurd. Proposal: no for now (cardinality stays the primary key), and
  revisit with a `max-drugs` dial if it becomes interesting.