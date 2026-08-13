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
>
> **Amended 2026-08-12** with §1.1 — the carbapenem-first behaviour observed in a
> live clinician session, where it produced a false statement to the clinician. It
> changes no accepted decision, but it makes `alternatives` reporting a requirement
> rather than a nicety (§4).
>
> **Decisions taken (David, 2026-08-13):** `alternatives` moves into **slice 2**
> (§6). And a standing rule, applied first to the stale claims §1.1 exposed:
> **code and prompt must not describe behaviour that does not exist.** Noting a
> planned enhancement is fine; phrasing it as current behaviour is not.

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

### 1.1 Observed in a clinician session (2026-08-12)

The table above is synthetic. This is the same behaviour with somebody asking about
it. In a driver session on 2026-08-12 (`session-20260812-132259`; transcripts live
under the gitignored `sessions/`, so the quotes below are reproduced in full rather
than referenced) a clinician worked a blood culture down to **E. coli, bel 0.64** —
one specifically identified organism, no longer a family backstop — and then asked,
in as many words:

> *"No known allergies, Please see if there's a narrower first-line agent available."*

Greedy returned meropenem. The LLM re-ran it under the plausibility gate, got
meropenem again, and told the clinician:

> *"the schematic knowledge base this solver draws on doesn't have a narrower agent
> (e.g., a cephalosporin or fluoroquinolone) registered for E. coli that clears
> coverage here"*

**That is false.** E. coli carries no species-specific susceptibility entry and rolls
up to `:enterobacteriaceae` (`knowledge-base.lisp` §110), which **six** drugs cover —
every one of them clearing the 0.5 `*susceptibility-threshold*`:

| Drug | susceptibility `[bel, pl]` | tiebreak weight (bel × 0.64) |
|---|---|---:|
| **meropenem** | [0.90, 0.99] | **0.576** ← chosen |
| ceftriaxone | [0.72, 0.92] | 0.461 |
| piperacillin-tazobactam | [0.70, 0.92] | 0.448 |
| ceftazidime | [0.66, 0.88] | 0.422 |
| gentamicin | [0.64, 0.90] | 0.410 |
| ciprofloxacin | [0.62, 0.90] | 0.397 |

Five narrower agents cleared the gate and none was mentioned. Under the plausibility
gate the ordering is unchanged (meropenem leads on 0.99), so the second run could not
have answered the question either — and `gate` was the only dial the narration had to
reach for, because narrowness has none.

Three things this adds to §1:

1. **The anti-pattern reached a clinician**, on the case where it is least defensible.
   A carbapenem for a *family-level* backstop is at least arguable; the same
   carbapenem after the family has been resolved to a species is the textbook
   de-escalation failure, and the solver does not de-escalate because nothing in its
   objective knows that resolution happened.

2. **The narration inherited the mismatch, and reasoned from the docstring rather
   than the code.** The LLM justified its answer as *"greedy set-cover, which is built
   to minimize the drug set, not maximize spectrum, would have surfaced it."* That is
   the header's stated objective quoted back as though it were the implementation.
   Minimizing cardinality surfaces no alternatives at all, and the tiebreak that
   actually decided maximizes susceptibility. So §1's documentation gap is not only a
   docs problem: the prompt layer reads those claims and reasons *from* them, which
   converts a stale comment into a false statement to a clinician.

3. **The payload cannot answer the question.** `RECOMMENDATION` carries `regimen`,
   `excluded` (contraindications only) and `uncovered`. There is no field for *other
   drugs that also cover*. The LLM had no way to learn ceftriaxone was there. It then
   correctly refused to substitute a drug on its own authority — *"I'd be fabricating
   if I suggested 'try ceftriaxone instead'"* — which is exactly the right instinct,
   defeated by a payload that could not tell it ceftriaxone was real.

Point 3 promotes `alternatives` (§4) from a nicety to a requirement. Without it,
*"is there a narrower option?"* has no truthful answer at **any** slice — including
under `:spectrum-sparing`, since a clinician can always ask what was *not* chosen.
See the proposed slice amendment in §6.

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

**Reporting.** Two additions, both cheap once the search is exact — and the first is
now **required**, not optional (§1.1):
- `alternatives` — other regimens of the same minimum size, so the narration can say
  *"three equally minimal regimens exist; this one was chosen because…"*, which is
  the honest thing to say when an objective breaks a tie no clinician stated. §1.1 is
  the case for making it mandatory: with the chosen regimen as the payload's only
  content, *"is there a narrower agent?"* is unanswerable, and the observed failure
  mode is not a hedge but a confident false negative. Each entry should carry the
  same susceptibility intervals as `regimen`, so the trade a clinician is being asked
  to weigh — *narrower agent, lower coverage floor* — is visible in the payload
  rather than asserted in prose. **Lands in slice 2** (§6); see the open sub-question
  there on whether it enumerates alternative *regimens* or alternative *agents*.
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
- **The §1.1 regression**: E. coli alone at bel 0.64. Two assertions, one per slice.
  From **slice 2**: the payload names all five non-meropenem covering agents, so the
  *"no narrower agent exists"* answer becomes unstateable. Under B (slice 4): the
  regimen itself moves off meropenem. This is the case a clinician actually asked
  about, so it is the one worth pinning by name.

## 6. Slice plan

1. **Extract shared phase A** from greedy; suite green, no behaviour change.
2. **Exact solver, `:lexicographic`** + registration + goldens + the equivalence
   property test, **plus `alternatives` reporting** (moved here from slice 4; see the
   amendment below). No recommendation changes; the payload gains a field, and with
   it the narration guidance to use the field — shipping the data without the
   guidance would recreate §1.1 in miniature.
3. **`:spectrum` on `defdrug`** for all 11 drugs, with provenance notes and the
   illustrative caveat.
4. **`:spectrum-sparing` objective** + divergence goldens.
5. **Bridge/tool/prompt surface**: `solver` enum, `objective` parameter, narration
   guidance for stating the trade — *"narrower agent, lower coverage floor."*
6. Docs: scenario contrasting the two objectives on one case; runbook note.

**Amendment (David, 2026-08-13) — ACCEPTED.** `alternatives` moved from slice 4 into
slice 2 above. It costs almost nothing there: ascending-k already enumerates every
minimum-size cover, so reporting the losers is a serialization change, not a search
change. It needs none of the spectrum authoring in slices 3–4, and it is the only
part of this plan that fixes §1.1 *without changing any recommendation*. The price,
accepted knowingly: slice 2 is no longer a pure equivalence check — it is now "no
recommendation changes, but the payload stops implying the chosen drug is the only
one."

**Open sub-question for slice 2 — what `alternatives` ranges over.** Two readings,
and they differ in who gets the §1.1 fix:

| | Alternative *regimens* | Alternative *agents* |
|---|---|---|
| Definition | other drug sets of the same minimum size | other candidate drugs that cover a treated organism |
| Computed from | the exact search's enumeration | phase A output + a KB filter |
| Available to | `:exact` only | **both solvers**, greedy included |
| Answers §1.1's question | for the 1-organism case, yes | always |

The doc has assumed the first. But the default solver is `greedy`, and §1.1's session
ran on the default — so under the first reading the clinician who hit this bug still
would not get the fix unless `:exact` also becomes the default, which is not in the
accepted plan. The second reading is solver-independent and strictly cheaper.
They are not exclusive; the honest payload may want both, and for a single treated
organism they coincide. **Decide before writing slice 2.**

**Prompt- and code-side claims (David, 2026-08-13 — decided).** §1.1's point 2 is a
stale-claim failure that reached a clinician through the narration layer, so it is
fixed ahead of slice 1 rather than whenever the area is next touched. The standing
rule: **do not describe behaviour that does not exist.** A planned enhancement may be
noted *as planned*; it may not be phrased as current behaviour. Three sites, all
corrected:
- `greedy-solver.lisp`'s header — *"fewest drugs (minimality = stewardship)"*.
- `system-prompt.md` *"Fewer drugs is the point: narrow-spectrum minimalism is
  antimicrobial stewardship"* — conflates cardinality with spectrum, which is the
  precise error the narration then made.
- `system-prompt.md` *"If one broad agent covers everything… it's the
  stewardship-optimal answer"* — this one is not merely stale but actively
  instructs the failure. It is traceable to the session's *"this single
  broad-spectrum carbapenem is the stewardship-optimal answer here."*

Nothing guards these the way `prompt-tests.lisp` guards the prompt's rulebase claims;
a therapy-claim guard is worth considering once the objective is a named dial.

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