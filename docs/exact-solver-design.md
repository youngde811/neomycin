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
- It changes the answers, visibly and defensibly: culture-1 would move from meropenem
  to ceftazidime. *(Written before the tiers were authored. Measured in §3.6:
  culture-1 → ceftazidime holds, but klebsiella alone goes to **gentamicin**, not the
  ceftriaxone guessed here.)*
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

### 3.6 What the authored tiers actually imply — measured, not predicted

Slice 3 authored the eleven tiers; slice 4 built the objective. This table is the
real solver under both settings on the canonical KB — every row a golden in
`exact-solver-tests.lisp`.

These are **solver-level** runs over hand-specified conclusion sets, not engine-driven
scenarios: they isolate the objective from what the rulebase happens to conclude.
Some rows are not reachable end to end — see the note after finding 3.

> **Corrected 2026-08-13.** The first version of this table was produced by a
> throwaway simulation before slice 4 existed, and its `:lexicographic` column was
> wrong: the script sorted one list destructively and then read the aliased original.
> On that basis it claimed bacteroides + S. aureus as a spectrum-sparing win. It is
> not — the default already returns metronidazole + vancomycin there. The corrected
> row is pinned by a test named for the mistake, and the real wins are in the table
> below. Findings 1 and 3 survive; finding 3 turned out to be worse than reported.

| Case | `:lexicographic` | `:spectrum-sparing` | |
|---|---|---|---|
| E. coli 0.64 (§1.1) | meropenem | **gentamicin** | diverges |
| klebsiella 0.40 alone | meropenem | **gentamicin** | diverges |
| enterobacteriaceae 0.80 | meropenem | **gentamicin** | diverges |
| pseudomonas 0.76 alone | meropenem | **ceftazidime** | diverges |
| culture-1 pair | meropenem | **ceftazidime** | diverges |
| salmonella 0.65 | meropenem | **ciprofloxacin** | diverges |
| S. pneumoniae 0.70 | meropenem | **vancomycin** | diverges |
| enterococcus 0.60 | ampicillin | **linezolid** | diverges |
| S. aureus + klebsiella | meropenem, vancomycin | **gentamicin**, vancomycin | diverges |
| three organisms | meropenem, vancomycin | **ceftazidime**, vancomycin | diverges |
| S. aureus 0.60 alone | vancomycin | vancomycin | same |
| bacteroides + S. aureus | metronidazole, vancomycin | metronidazole, vancomycin | same |

Three findings, and two of them are problems:

**1. §3.2's prediction was half right.** culture-1 and pseudomonas-alone do move to
ceftazidime, as guessed. But klebsiella alone moves to **gentamicin, not
ceftriaxone** — ceftriaxone is `:broad`, gentamicin is `:moderate`, so the breadth
objective goes past the cephalosporin entirely. The doc's worked example in §3.2 and
its golden in §5 both need rewriting against this.

**2. It prefers aminoglycoside monotherapy for gram-negative bacteraemia.** That is
narrow, and it is not better. This is §3.2's "can prefer a *less effective* drug"
objection arriving in a sharper form than anticipated: not merely a lower coverage
floor (gentamicin 0.64 vs meropenem 0.90) but a choice most clinicians would reject
outright on grounds the KB does not represent at all.

**3. Breadth cannot see reserve status — and this one actually fires.** Reported
first as a latent risk; the measured runs show it changing answers.

- **enterococcus: ampicillin → linezolid.** Ampicillin is WHO AWaRe **Access** and
  `:moderate`; linezolid is AWaRe **Reserve** and `:narrow`. Linezolid genuinely *is*
  the narrower agent, so the objective is working correctly and the outcome is still
  backwards: narrowing spectrum and escalating reserve status are different things,
  and optimising the first can worsen the second.
- **S. pneumoniae: meropenem → vancomycin.** Narrower, and not what a steward wants
  reached for first.
- **S. aureus alone** does not change, but only by luck: vancomycin and nafcillin are
  both `:narrow`, so breadth ties and susceptibility decides (0.88 vs 0.72). The
  reserved agent wins a tie it should lose.

`knowledge-base.lisp` annotates AWaRe per section; nothing encodes it, and this tier
must not be read as though it did.

**Reserve-blindness is not exclusive to `:spectrum-sparing`** — found by driving the
enterococcus case end to end through the bridge rather than the solver alone. The
engine does not produce enterococcus in isolation: the bile-esculin/salt-tolerance
rule fires alongside the gram-positive-cocci-in-chains rule, so working memory
carries **both** `streptococcus` 0.7 and `enterococcus` 0.8, and the regimen must
cover both. Linezolid and ampicillin each cover the pair; linezolid wins on
susceptibility (1.094 vs 1.038) — so **`:lexicographic` also reaches for the Reserve
agent**, and `:spectrum-sparing` merely agrees with it for a different reason.
Ampicillin appears in `alternative_regimens`, which is exactly the case for having
that field.

The lesson generalises: a solver-level golden can isolate an objective, but only an
engine-driven run shows which conclusion sets the rulebase actually produces. The
single-organism rows above are legitimate solver tests and several of them are not
reachable through the corpus as it stands.

The genuine wins are **salmonella → ciprofloxacin**, **culture-1 and pseudomonas →
ceftazidime**, and **three organisms → ceftazidime + vancomycin** — real
de-escalations off a carbapenem, which is what the objective was wanted for. Note
that the anaerobe pair is *not* among them: `:lexicographic` already picks
metronidazole + vancomycin there, because the narrow agents happen to carry the best
susceptibility figures. The objective gets no credit for an answer the default
already gives.

**DECIDED (David, 2026-08-13): (a) — ship it as measured.** Slice 4 implements
`:spectrum-sparing` exactly as tabled above, gentamicin and linezolid included, with
the narration required to state the trade. The three options considered:
- **(a) Ship it as measured.** `:spectrum-sparing` means what it says, gentamicin
  included, and the narration states the trade. Honest, and arguably the most useful
  demonstration: the objective is a *dial*, and this is what turning it does.
- **(b) Add reserve status as a second key** — an AWaRe tier on `defdrug`, ordered
  Access < Watch < Reserve, applied before or after breadth. Fixes finding 3, does
  nothing for finding 2, and doubles the authoring judgement.
- **(c) Keep the objective but constrain candidates** — e.g. a per-drug
  "not-for-monotherapy" flag. This is the honest name for encoding finding 2, and it
  is a large step further into clinical assertion than anything else in the KB.

My reading: **(a)**, with §3.6 quoted in the narration guidance. (b) and (c) both
answer "the objective gave a clinically odd answer" by teaching the KB more medicine,
which is the direction where a schematic research artifact starts implying an
authority it does not have. A dial that visibly does the wrong thing for a stateable
reason is a better teaching object than one quietly patched until it looks sensible.

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

**Search.** Candidates → bitmask coverage → ~~dominance prune~~ → ascending-k
enumeration → among all covers of minimum size, pick by the objective's comparator
→ deterministic name tiebreak last. Returns the same `RECOMMENDATION` struct; no
protocol change.

*Dominance pruning was dropped when slice 2 was written.* Pruning discards a drug
whose coverage is a subset of another's — which is exactly a drug that belongs in
`alternative_agents` or `alternative_regimens`. Since reporting those completely is
the point of the slice, an optimization that silently removes them would trade the
slice's purpose for speed the search does not need (2¹¹ worst case). If the KB ever
grows enough to want it, prune the *winner* search only and enumerate alternatives
separately.

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
- Under B, a golden that pins the divergence, so nobody can quietly "improve" the
  objective back to carbapenem-first. Per the measured table in §3.6 this is
  **klebsiella alone → gentamicin** (coverage floor 0.64 vs meropenem's 0.90), not
  the ceftriaxone this line assumed before the tiers existed. Pin the
  bacteroides + S. aureus row too — metronidazole + vancomycin instead of a
  carbapenem is the case where the objective clearly earns its keep, and it deserves
  a golden as much as the awkward one does.
- **The §1.1 regression**: E. coli alone at bel 0.64. Two assertions, one per slice.
  From **slice 2**: the payload names all five non-meropenem covering agents, so the
  *"no narrower agent exists"* answer becomes unstateable. Under B (slice 4): the
  regimen itself moves off meropenem. This is the case a clinician actually asked
  about, so it is the one worth pinning by name.

## 6. Slice plan

**Status: slices 1–5 are DONE (2026-08-13).** Suite 860/154 → 1074/182. Only slice 6
(docs) remains. §3.6 was decided (a): ship the objective as measured.

1. **Extract shared phase A** from greedy; suite green, no behaviour change.
2. **Exact solver, `:lexicographic`** + registration + goldens + the equivalence
   property test, **plus `alternatives` reporting** (moved here from slice 4; see the
   amendment below). No recommendation changes; the payload gains a field, and with
   it the narration guidance to use the field — shipping the data without the
   guidance would recreate §1.1 in miniature.
3. **`:spectrum` on `defdrug`** for all 11 drugs, with provenance notes and the
   illustrative caveat. *Authored data only — deliberately not exposed on the bridge
   or mentioned in the prompt, since nothing consumes it and describing an axis the
   solver does not use is the §1.1 failure in advance.*
4. **`:spectrum-sparing` objective** + divergence goldens, per §3.6 decision (a).
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

**Sub-question — what `alternatives` ranges over — RESOLVED (David, 2026-08-13):
both.** `alternative_agents` (solver-independent, so greedy reports it too) and
`alternative_regimens` (exact only). The two readings, and why doing only the first
would have left the §1.1 clinician unfixed:

| | Alternative *regimens* | Alternative *agents* |
|---|---|---|
| Definition | other drug sets of the same minimum size | other candidate drugs that cover a treated organism |
| Computed from | the exact search's enumeration | phase A output + a KB filter |
| Available to | `:exact` only | **both solvers**, greedy included |
| Answers §1.1's question | for the 1-organism case, yes | always |

The doc had assumed the first. But the default solver was `greedy` and §1.1's session
ran on the default, so the first reading alone would not have reached the clinician
who hit the bug. Both shipped; for a single treated organism they coincide, which is
visible in the §1.1 regression test (five alternative agents, five alternative
single-drug regimens, same five drugs).

**The default solver is now `:exact`** (David, 2026-08-13), flipped at the end of
slice 2 and gated on the equivalence property being green — 12 conclusion sets × 3
patient states, agreeing on regimen size, gated items, and uncovered organisms. The
reasoning is worth keeping: exact never loses to greedy, since where they differ it
is greedy's approximation that lost; and only the exhaustive search can report
`alternative_regimens`. `:greedy` stays registered and selectable — it is what the
equivalence property is asserted *against*, so retiring it would delete the evidence
for the flip.

Note what the flip does **not** fix. `exact(:lexicographic)` is greedy's objective
computed exactly, so it returns meropenem for the §1.1 case too: carbapenem-first is
a property of the objective, not of the approximation. Only `:spectrum-sparing`
(slice 4) changes that answer. What slice 2 fixes is the *false statement* — the
payload now carries what else covered, so "no narrower agent exists" is no longer
something a reader can conclude from silence.

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