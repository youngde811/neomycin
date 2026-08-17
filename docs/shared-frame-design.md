# Shared frame of discernment — a design proposal

> **UPDATE 2026-08-17 — decisions settled and phase 0 has run. Read
> `docs/shared-frame-phase0-results.md` alongside this.** David settled §11 as: D1
> unconditional, D2 keep Barnett, D3 measure both, D4 add `:other-organism`, D5 phase
> 0 sufficient. Phase 0 then measured the corpus and found that §9.4 (independence) is
> not a caveat but the blocking problem: the corpus's rules are not independent bodies
> of evidence, which manufactures conflict up to `K = 0.84` and inverts the
> pseudomonas/klebsiella ranking on culture-1. Every other prediction in this document
> held exactly. **A phase 0.5 now sits in front of phase 1** — see the results doc §7.
> Sections §6.3, §7 and §9.4 below are superseded by measurements.

> **Status: proposal, no code (2026-08-17).** Written in response to
> `docs/belief-conditional-audit.md` and David's reply to it. That audit found five
> rules answering the wrong conditional and three class beliefs answering none, and
> proposed a `:conditional` provenance keyword plus a property test to guard it. This
> proposal argues those are symptoms of one representational choice, and that the
> keyword would document the workaround rather than remove the cause.
>
> Nothing here is committed. §11 lists the five decisions that have to be made before
> any of it is built, and §10 puts a measurement phase in front of all of them.

## 1. What is proposed

Replace the per-hypothesis belief representation with one mass function per organism
entity, defined over a declared frame of the organisms that entity could be.

Concretely: today each concluded organism carries its own `[Bel, Pl]` interval over
its own private two-element frame `{H, not-H}`. Under this proposal, each `organism`
entity carries one sparse mass function over `Θ = {the 17 leaf identities, plus a
catch-all}`, and a rule contributes mass to a **set** of organisms rather than a
number to one organism.

The certainty-factor system is untouched.

## 2. The defect this addresses

`src/belief-systems/dempster-shafer/dempster-shafer.lisp:28-33` states the current
model plainly:

> Each interval is a basic probability assignment over the dichotomous frame
> `{H, not-H}` … Restricting the frame to a single hypothesis and its negation (the
> Barnett simplification) keeps combination O(1) and avoids power-set mass functions.

`docs/next-steps-llm-integration.md:193` records the deferral:

> Full power-set DS (set-valued / taxonomic hypotheses) remains deferred; the
> dichotomous-frame simplification is the right cost/benefit point for now.

The consequence is that **two organisms' beliefs never interact.** E. coli's interval
and Klebsiella's interval are computed on different frames, so evidence for one has no
arithmetic effect on the other.

That is visible in the project's own published expected output. `CLAUDE.md` states
that culture-1 produces pseudomonas 0.76 and klebsiella 0.40 — on the same organism
entity `o1` (`neomycin/rules/drivers.lisp:34`, one `(organism (id o1))`). Those are
mutually exclusive hypotheses about one organism, and their beliefs sum to 1.16. The
system does not notice. Culture-1a is worse: 0.88 + 0.688 = 1.568.

`neomycin/test/scenarios.lisp:134` asserts this as a desirable property:

```lisp
(deftest ds-confirmatory-keeps-full-plausibility ()
  ;; No rule argues *against* anything in culture-1, so every hypothesis keeps
  ;; pl = 1.0
```

Under a shared frame that test fails, and should. If mass 0.76 sits on
`{pseudomonas}`, then Klebsiella's plausibility is at most 0.24 — no rule has to say
so.

Everything the audit found follows from this:

| Audit finding | Why the representation causes it |
|---|---|
| 8 of 13 confirming rules justify their belief by *rival organisms* | With no shared frame, the author has to compute the split among rivals by hand and hide the result in a scalar. The frame does that arithmetic. |
| 5 rules use a sensitivity where a posterior is required | Same cause, done wrong instead of right. |
| 3 class beliefs are "carried over" from retired rules and answer no conditional | A class has no representation as a *set*, so it is reified as a pseudo-organism with its own private frame. There is nothing for its number to be a conditional of. |
| 16 disconfirming rules exist as a separate rule kind | The only way to make evidence argue against an organism is to author a rule that does it, because the algebra will not. |

## 3. What "shared frame" means in this corpus

**The frame.** One per `organism` entity. Elements are the 17 leaf identities the
corpus can conclude, plus `:other-organism` (see §9.3). Facts are already scoped by
entity — every rule matches `(organism (id ?o))` and concludes `(… (of ?o))` — so a
per-entity frame is the existing scoping, not a new one. Polymicrobial cultures are
already modelled as multiple `organism` entities, so mutual exclusivity within one
frame is correct.

**Focal sets.** A mass function assigns mass to subsets. Only subsets that some rule
names ever get mass, so the representation is a sparse alist of `(set . mass)`, not a
power set. The corpus names:

- 17 singletons (one per leaf identity),
- 4 organism-class subsets (enterobacteriaceae, staphylococcus, streptococcus,
  enterococcus),
- Θ itself,
- the complements named by the 16 disconfirming rules — which are already written out
  by hand today, e.g. `(test (member ?value '(:klebsiella :enterobacter :salmonella
  :serratia)))` in `neomycin/rules/disconfirming.lisp:148`.

That is roughly 40 sets, not 131,072. Repeated combination can create new focal sets
by intersection; §9.4 covers the bound and why it needs measuring rather than
asserting.

**Combination.** Dempster's rule over sparse focal sets: for each pair `(A, B)`,
mass `m1(A)·m2(B)` lands on `A ∩ B`; mass landing on `∅` is conflict `K`; survivors
are renormalized by `1 - K`. This is the same rule `ds-combine` already implements,
generalised from two-element sets to arbitrary ones.

**Read-out.** For any organism X:

```
Bel(X) = m({X})
Pl(X)  = 1 − Σ { m(A) : A ∩ {X} = ∅ }
```

`/conclusions` reports these. It additionally reports the non-singleton focal
elements with their mass — mass sitting on `{enterobacteriaceae}` means "it is in this
family, the evidence does not say which member," which is a statement the current
system cannot make.

## 4. What changes for a rule author

This is the section that matters if a human is going to maintain the corpus.

### 4.1 What the author has to do today

Writing a confirming rule today requires four things, only one of which is a fact
from a lab manual:

1. Observe that a marker suggests an organism. *(Clinical.)*
2. Enumerate, in your head, every other organism in the corpus that shares the
   marker. *(Not clinical. Requires knowing the whole corpus.)*
3. Reduce that enumeration to a single number expressing how much of the marker's
   support survives after the rivals take their share. *(Bayes, done mentally, result
   not recorded.)*
4. Decide whether to also write a disconfirming rule, and if so, against which
   organisms and at what strength. *(No principled criterion exists.)*

Steps 2 and 3 are where the audit's five errors are. Step 4 is what David's reply
called a kludge, and it is: `red-pigment-argues-against-non-serratia`
(`disconfirming.lisp:119`) exists solely because
`enterobacteriaceae-red-pigment-suggests-serratia` cannot, on its own, lower anything.
The pair encodes one clinical fact twice, in two rules, with two hand-picked numbers
(0.75 and −0.8) that nothing forces to be consistent.

Step 4 has a further trap. A disconfirming rule matches an existing
`organism-identity` fact and re-asserts it, so it only bites hypotheses some
confirming rule already raised. `property-tests.lisp` has a guard for exactly this —
"no disconfirming rule names an identity no confirming rule concludes" — because the
`member` lists go stale when a species is retired.

### 4.2 What the author does instead

Declare the set the evidence actually identifies.

```lisp
(defrule enterobacteriaceae-lactose-pos-indole-pos-suggests-e-coli
    (:belief 0.9
     :supports (:e-coli :klebsiella)      ; ← the focal set
     :provenance (...))
  (organism (id ?o))
  (organism-class (value :enterobacteriaceae) (of ?o))
  (lactose (value fermenter) (of ?o))
  (indole (value positive) (of ?o))
  =>
  (assert (organism-identity (value :e-coli) (of ?o))))
```

The author's own note on this rule today reads *"K. oxytoca is also +/+, hence
conditional 0.8."* That sentence is the focal set, written in prose, with the split
already performed and discarded. Under `:supports` it is written as data: the test
reliably says "one of these two" (0.9), and which of the two it is gets decided by
other evidence, or is left as ignorance and reported as such.

The four steps become two:

1. Which organisms does this evidence narrow the answer to? → `:supports`
2. How reliably? → `:belief`

Both are answerable from a lab manual, by one person, without knowing the rest of the
corpus.

`:supports` defaults to the singleton the RHS asserts, so existing rules keep
working unchanged and the keyword is added only where the set is genuinely larger
than one.

### 4.3 "Should I write a disconfirming rule?"

The question stops existing. Evidence against an organism is mass on a set that
excludes it, which is the same mechanism as evidence for one. `:opposes` is sugar for
`:supports (complement)`:

```lisp
(defrule indole-pos-argues-against-indole-negative-species
    (:belief 0.6
     :opposes (:klebsiella :enterobacter :salmonella :serratia)
     :provenance (...))
  (organism (id ?o))
  (indole (value positive) (of ?o))
  =>)
```

Compare the current version (`disconfirming.lisp:138`): it needs a negative `:belief`,
an `(organism-identity (value ?value) (of ?o))` premise, a `member` test carrying the
same list, and an RHS that re-asserts the fact it matched. All four exist to route
around the missing frame. The new form has none of them, fires once instead of once
per raised hypothesis, and cannot go stale against a retired species because the frame
declaration is checked (§4.4).

The author's criterion becomes a lab-manual question: *does this test exclude
anything?* If yes, name what. If no, don't.

Many of the current 16 will simply disappear, because the exclusion they perform
becomes automatic. `red-pigment-argues-against-non-serratia` is one: once red pigment
puts mass on `{serratia}`, every other organism's plausibility drops without a second
rule. §10 phase 2 is where that gets decided rule by rule, from measured numbers
rather than from this paragraph.

### 4.4 The frame is declared, and checked

The frame goes in `neomycin/rules/context.lisp`, which already loads first and already
defines every class the rule files use:

```lisp
(deframe organism-frame
  (:elements :e-coli :klebsiella :salmonella :enterobacter :serratia :proteus
             :pseudomonas :bacteroides
             :staphylococcus-aureus :staphylococcus-epidermidis
             :staphylococcus-saprophyticus
             :streptococcus-pneumoniae :streptococcus-pyogenes
             :streptococcus-agalactiae :streptococcus-viridans
             :enterococcus-faecalis :enterococcus-faecium
             :other-organism)                       ; §9.3
  (:subset :enterobacteriaceae
           (:e-coli :klebsiella :salmonella :enterobacter :serratia :proteus))
  (:subset :staphylococcus
           (:staphylococcus-aureus :staphylococcus-epidermidis
            :staphylococcus-saprophyticus))
  (:subset :streptococcus
           (:streptococcus-pneumoniae :streptococcus-pyogenes
            :streptococcus-agalactiae :streptococcus-viridans))
  (:subset :enterococcus
           (:enterococcus-faecalis :enterococcus-faecium)))
```

That is the corpus's 17 leaf identities and 4 organism-classes exactly, as verified
against `neomycin/rules/`. The classes are already sets in the author's head; this
writes them down once, in the place the corpus already loads first.

The property test becomes: **every `:supports` and `:opposes` set is a subset of the
declared frame.** That is structural, not heuristic, and it replaces the current
staleness guard with something stronger — retiring a species breaks every rule that
still names it, at load time, instead of being caught by a test that had to be
specially written.

## 5. What changes in the engine

Belief currently lives on a fact: `(belief-factor fact)`, mutated by `adjust-belief`
in `src/core/rete.lisp:257-271`. Under this proposal belief lives on the session,
keyed by entity, and a fact's belief becomes a projection rather than storage.

| Site | Change |
|---|---|
| `src/belief-systems/` | New system alongside CF and the existing Barnett DS: sparse mass functions, general Dempster combination, `Bel`/`Pl` projection. |
| `src/core/rete.lisp` | A per-entity mass-function table on the `rete` instance, alongside the existing `derivation-table`. `adjust-belief` gains a branch: when the active system is frame-based, combine the rule's simple support function into the entity's mass function instead of mutating the fact. |
| `src/core/rete.lisp` (derivation) | `derivation-record` gains focal set, mass contributed, and the conflict `K` this firing introduced. `belief-before`/`belief-after` become mass-function snapshots or deltas. |
| `src/core/rule-introspection.lisp` | Expose `:supports` / `:opposes` so `/rules` and the property tests can read them. |
| `src/llm/bridge/handlers.lisp` | `/conclusions` projects the mass function; additionally reports non-singleton focal mass and `K`. `/why` narrates set-and-mass arithmetic instead of scalar composition. |
| `neomycin/rules/context.lisp` | `deframe`. |

**Chaining separates from belief.** Today a species rule matches the class fact *and*
inherits its belief multiplicatively. Under the proposal, the class rule still asserts
`(organism-class (value :enterobacteriaceae) (of ?o))` as a logical fact, because that
is what gates the species rules in Rete — but it contributes its mass independently,
and the species rule contributes its own. Dempster's rule composes them. The fact
gates *when the question is asked*; the mass function answers *how strongly*. These
are currently the same mechanism and should not be.

This is decision **D1** in §11, because it changes what a rule's `:belief` means.

## 6. Worked numbers

### 6.1 Chaining: the class corroborates instead of discounting

Class rule: `m₁({enterobacteriaceae}) = 0.8`, `m₁(Θ) = 0.2`.
Species rule: `m₂({e-coli}) = 0.8`, `m₂(Θ) = 0.2`.

Intersections (writing `F` for the family set):

| | `{e-coli}` 0.8 | `Θ` 0.2 |
|---|---|---|
| **`F` 0.8** | `{e-coli}` 0.64 | `F` 0.16 |
| **`Θ` 0.2** | `{e-coli}` 0.16 | `Θ` 0.04 |

`K = 0`. Result: `m({e-coli}) = 0.80`, `m(F) = 0.16`, `m(Θ) = 0.04`.

```
Bel(e-coli)    = 0.80        (today: 0.8 × 0.8 = 0.64)
Pl(e-coli)     = 1.00
Bel(klebsiella)= 0.00
Pl(klebsiella) = 1 − 0.80 = 0.20        (today: 1.00)
```

Three things to note. E. coli goes *up*, because family evidence agrees with it rather
than discounting it. Klebsiella's ceiling falls to 0.20 with no disconfirming rule.
And `m(F) = 0.16` — "it is an Enterobacteriaceae, the evidence does not say which" —
is exactly what `family-backstops` in `neomycin/therapy/bridge.lisp` currently
constructs by hand for the solver.

### 6.2 The composition law goes away

`neomycin/test/chain-tests.lisp` asserts, once per chained cluster, that species
belief = class belief × rule belief. Under this proposal that is false by design;
composition moves from multiplication at assert time to Dempster combination in the
mass function. The test is replaced, not repaired.

This is the largest single behavioural change and the main reason for the measurement
phase in §10.

### 6.3 Culture-1 becomes visibly conflicted

Today: pseudomonas 0.76, klebsiella 0.40, both at plausibility 1.0, sum 1.16.

Under a shared frame `{pseudomonas}` and the klebsiella-bearing sets are disjoint, so
combining them yields `K > 0`. The result is renormalized and both numbers move. What
they move *to* depends on D1 and cannot be stated here without running it — that is
phase 0's job. What can be stated: the conflict stops being invisible.

## 7. Predicted test churn

| Suite | Expectation |
|---|---|
| CF goldens (`cf-culture-1`…`5`) | **Unaffected.** CF keeps the per-fact representation. |
| DS goldens (`ds-culture-1`…`5`) | **All move.** Re-captured after phase 0. |
| `ds-confirmatory-keeps-full-plausibility` | **Deleted.** It asserts the defect. |
| Composition-law tests (`chain-tests.lisp`) | **Replaced** (§6.2). |
| `check-rule`, 50 rules in isolation | **Predicted unchanged for confirming rules.** One rule alone puts mass `b` on its set and `1−b` on Θ, giving `Bel = b, Pl = 1.0` — the current assertion. Prediction, not a measurement; phase 0 confirms or refutes it. |
| Disconfirming rules in isolation | Predicted unchanged: `m(Θ∖{X}) = b` gives `Bel(X) = 0, Pl(X) = 1−b`, which is what `normalize-belief` produces for a negative belief today. |
| Therapy suite | **Unaffected in phase 1** (§8). |
| Property tests | Member-list staleness guard **replaced** by frame-membership (§4.4). Disconfirming-rules-above-20% drift alarm becomes meaningless once §4.3 lands and should be **retired**, not adjusted. |

## 8. Therapy

`conclusions-for-solver` (`neomycin/therapy/bridge.lisp:81`) hands the solver
`((organism-keyword . belief) …)`, and `scalar-of` reduces each belief through
`belief->number`. Projecting the mass function to per-organism `[Bel, Pl]` produces
exactly that shape, so **phase 1 costs the solver nothing** — no solver change, no
therapy golden change.

Phase 3 is the interesting one and is not required. Today `family-backstops`
hand-constructs a family entry when no member species clears the coverage gate. Under
a frame that entry already exists as `m({enterobacteriaceae})`, and passing set-valued
mass through to the solver would let it cover a set-valued hypothesis directly —
"treat empirically for the family," which is what a clinician actually does. That is
research payoff, not a migration requirement, and `family-backstops` can be deleted
when it lands.

## 9. What this does not fix, and what it breaks

### 9.1 It does not make illustrative beliefs non-illustrative

Every `:belief-basis :illustrative` stays illustrative. The claim is narrower: the
numbers become answers to a question an author can state and a reader can check
(*which organisms does this evidence narrow to, and how reliably*), instead of a
posterior computed mentally against a corpus the author has to hold in their head.
Grounding them against real data is still separate work.

### 9.2 Conflict normalization has known pathologies

Dempster's rule renormalizes by `1 − K`, and at high `K` that produces results people
find counterintuitive — the standard Zadeh counterexample. Today `K` is rare, because
it only arises when a disconfirming rule fires against a raised hypothesis. Under a
shared frame **any two rules supporting disjoint sets conflict**, so `K` becomes
routine.

This is a genuine new problem, and it is the strongest argument against the proposal.
Three responses, none of which fully dispose of it:

- **Report `K`.** Cheap, and it fits the project's stated position that uncertainty
  should be visible. A consultation that resolved 40% conflict away should say so.
- **Offer Yager's rule as a dial**, which moves conflict to Θ instead of
  renormalizing — more ignorance, no inflation. The existing total-conflict guard in
  `ds-combine` already makes this choice once, at `K ≥ 1`, and documents it as a
  Dempster-vs-Yager decision.
- **Accept that high `K` means the rules disagree**, which is information, not noise.

D3 in §11.

### 9.3 The frame must be exhaustive

`Bel` and `Pl` are only meaningful if Θ contains the true answer. Seventeen leaf
identities do not exhaust clinical microbiology. Without a catch-all, mass that should
sit on "something not in this corpus" gets distributed among the 17 and every number
is inflated.

Adding `:other-organism` fixes it and costs almost nothing. It also makes the read-out
honest in a way the current system cannot be: `Pl(:other-organism)` is a direct answer
to "could this be something the corpus does not know about," which today has no
representation at all.

### 9.4 Independence, and the size of focal-set growth

Dempster's rule assumes the combined evidence is independent. Gram stain and
morphology are not independent, and the corpus has rules that use both. The current
multiplicative chain is conservative enough to mask this; a shared frame will
over-concentrate mass on correlated evidence. The mitigation is a modelling
discipline — one rule per body of evidence, not per fact — and it is a real burden
that the proposal exposes rather than creates. It should be written into the authoring
guidance, not left implicit.

Separately: repeated combination generates new focal sets by intersection, so the
~40 declared sets are a lower bound on what appears at runtime, not an upper one. The
intersection closure of the corpus's sets is finite and probably small, but that is a
guess. Phase 0 should measure it and, if needed, prune focal elements below an epsilon
mass. I would not build phase 1 on the assumption that it stays small.

### 9.5 The CF-vs-DS comparison weakens

The fork retains certainty factors specifically to compare against DS. If DS moves to
a shared frame and CF does not, the two systems differ structurally, not just
numerically, and "same rulebase, two algebras" stops being true.

Mitigation: keep the current Barnett implementation as a third system
(`:dempster-shafer-barnett`) rather than replacing it. The comparison then runs three
ways, and the Barnett-vs-frame pair isolates the effect of the frame itself, which is
a more interesting comparison than either has today. That costs one file kept alive
and one more system in the `ecase` in `use-system`. D2 in §11.

## 10. Staging

**Phase 0 — measure, build nothing.** Implement the sparse mass algebra as a
standalone file with no engine hooks. Hand-feed it the focal sets and beliefs the
existing rules imply, replay culture-1 through culture-5, and print the resulting
`Bel`/`Pl` per organism plus `K` and the focal-set count. Compare against the current
goldens side by side.

This produces the numbers §6.3 cannot state, tests the §7 predictions, measures the
§9.4 growth, and costs nothing that has to be kept. **Decide from that table, not from
this document.** If the numbers are bad, phase 0 is the whole cost.

**Phase 1 — engine, rules unchanged.** New belief system, per-entity mass function on
the rete instance, `:supports` defaulting to the asserted singleton, projection
read-out. Every existing rule keeps working. DS goldens re-captured. Therapy
untouched.

**Phase 2 — retire the disconfirming rule kind.** Rewrite the 16 as `:opposes`,
delete the ones the frame makes redundant, replace the staleness property test with
frame membership, retire the 20% drift alarm.

**Phase 3 — set-valued therapy.** Pass focal mass to the solver; delete
`family-backstops`. Optional.

Phase 0 is the only commitment being asked for.

## 11. Decisions required

1. **D1 — does a chained rule's `:belief` discount by its class, or not?** Today
   species = class × rule, which reads the belief as a conditional. Dempster
   composition reads it as unconditional support that happens to be gated by the class
   fact. These give materially different numbers (§6.1: 0.64 vs 0.80).
   *Recommend unconditional*, because the biochemical evidence stands on its own and
   the Rete premise already handles "only ask this in context." The counterargument is
   that the corpus's beliefs were authored under the conditional reading and reusing
   them unchanged would inflate every chained species. Phase 0 quantifies that.

2. **D2 — keep the Barnett implementation as a third system?** *Recommend yes* (§9.5).

3. **D3 — Dempster or Yager normalization by default, and is `K` reported?**
   *Recommend Dempster as default, Yager as a dial, `K` always reported* (§9.2).

4. **D4 — add `:other-organism` to the frame?** *Recommend yes* (§9.3).

5. **D5 — is phase 0 sufficient to decide, or does anything else need settling
   first?**

## 12. Relationship to the conditional audit

`docs/belief-conditional-audit.md` proposed three steps: declare a `:conditional`
provenance keyword, guard it with a property test, then fix the five rules.

**This proposal supersedes steps 1 and 2.** The keyword would record which flavour of
mental arithmetic an author performed, and the property test would enforce that they
performed the right one. Both are only necessary because the author is doing the
arithmetic. `:supports` replaces the arithmetic with a declaration, and frame
membership is a stronger check than the keyword guard.

**Step 3 is unaffected and still needed.** Grounding the numbers is separate work
under either representation. What changes is that under a frame there are fewer of
them to ground and each one answers a question with a checkable form.

The audit's finding stands. Its proposed fix does not, and its instinct that three
carried-over class constants "may matter more than the five" was right for a reason it
did not identify: those constants exist because a class has no representation as a
set. Give it one and they stop being constants.