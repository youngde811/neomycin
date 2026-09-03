# neomycin (research fork of Lisa)

> **This repo is `neomycin`** — forked from Lisa 4.2.0 (full history preserved; the
> engine here is now 4.5.2). See `README.md`. **Research only; NOT FOR CLINICAL USE.**
>
> **neomycin BEGAN as a reconstruction of MYCIN/EMYCIN and is no longer one.** The
> divergence accumulated one representational problem at a time and is now large enough
> that MYCIN's results are not a correctness criterion for this system — a rule states
> the SET its evidence narrows to rather than making an organism "more likely";
> exclusion falls out of intersection and is never authored; epidemiological rules
> GRADE their answers over several focal sets; there are no organism classes and nothing
> chains; and there is a therapy phase — an exact set-cover solver with policy dials and
> an antibiogram overlay — that MYCIN's illustration did not have. **This is not a claim
> to be better.** It answers different questions, over a corpus a fraction of the size.
> Do not evaluate a change by whether it reproduces the PAIP answer.
>
> This is a *substantive* fork: the `lisa` engine is intentionally *not* renamed and is
> kept close to upstream where that costs nothing, but **engine-level modifications to
> better serve neomycin are fair game when they genuinely move the chains** — e.g.
> deepening Dempster-Shafer support beneath the corpus layer, or hosting
> classification/recognition. Treat these as engine-axis work (real reach, real cost):
> reach for them when they meaningfully advance the project, not for cosmetic gains —
> and don't treat "a Rete engine used as-is" as a constraint that forecloses them.
>
> **Dempster-Shafer over an open frame is the only belief system neomycin's corpus can
> use.** Certainty factors and per-hypothesis DS remain in the Lisa substrate for Lisa's
> own examples and suite; they have no set algebra, and a neomycin answer is a set. The
> CF-vs-DS comparison is reproducible on the **v0.10.0** tag and not after it. The Lisa
> engine documentation below describes the substrate as it currently stands.

# Lisa — Lisp-based Intelligent Software Agents

Forward-chaining expert system shell in Common Lisp (Rete algorithm, CLOS/MOP, pluggable belief systems). neomycin drives it through a Claude tool-use layer for natural-language bacterial identification and therapy selection.

## Build & Load

Requires SBCL with Quicklisp. From the SBCL REPL at project root, the easy way:

```lisp
(load "neomycin.lisp")   ; loads the :neomycin system and starts the bridge on 8090
```

Or explicitly — which is all that convenience file does:

```lisp
(load "lisa.asd")
(load "neomycin.asd")
(load "lisa-bridge.asd")
(asdf:load-system :neomycin)   ; loads neomycin/rules/ + the therapy system
                               ; (:neomycin depends on :lisa and :lisa-bridge)
(lisa-bridge:start)            ; port 8090
```

To stop: `(lisa-bridge:stop)`

neomycin's canonical rulebase is **`neomycin/rules/`** (the keyword-vocabulary MYCIN
reconstruction, loaded by the `:neomycin` ASDF system). It was a single
`neomycin/rulebase.lisp` through v0.5.0 and was split by cluster once it passed 40
rules; `rules/context.lisp` defines every class the rule files use and **must load
first**. Lisa's `examples/mycin.lisp` is Lisa-proper and is **never** used by
neomycin — don't load it over the neomycin rulebase.

### Choosing a belief system

**Dempster-Shafer over an OPEN frame is the default**, and it is what the rulebase is
written against:

```bash
LISA_BELIEF_SYSTEM=candidates sbcl ...  # DS over an open frame (DEFAULT)
LISA_BELIEF_SYSTEM=ds sbcl ...          # DS per hypothesis (Barnett)
LISA_BELIEF_SYSTEM=cf sbcl ...          # certainty factors
```

**`ds` and `cf` are Lisa substrate, not neomycin options.** They remain because Lisa's
own examples use them (`examples/mycin.lisp`, `examples/cf.lisp`) and its suite tests
them, but neomycin's corpus has no rules they can reason over: a candidate-set answer
is a SET, and neither has a set algebra. The **declared-frame** system of v0.9-v0.10
was neomycin-specific and has been deleted outright. The three-algebra comparison the
fork maintained through v0.10.0 is reproducible on the **v0.10.0 tag** and not after
it.

**How it works.** Every rule states an ANSWER — the set of organisms its evidence
narrows the question to — and asserts it as a `candidates` fact with a belief.
Nothing accumulates during inference; `neomycin:consensus` combines those answers by
intersection when a client reads working memory. Θ is never enumerated, so nothing
declares a frame and nothing has to be kept in step with the rulebase.

**Evidence strength discounts the answer.** A rule's `:belief` says how strongly its
answer follows FROM its premises; it does not say how strongly those premises were
believed. So each firing's answer is DISCOUNTED (Shafer) by the conjoined belief of the
premises that fired it — read from the snapshots the engine already captures in the
derivation table, per firing, because the conclusion fact's own belief is the combined
result of every contributor and cannot be decomposed per rule. A hedged Gram stain
therefore narrows less far than one read outright, and `confidence` on `/assert-fact`
reaches the differential. **It did not until v0.16**: evidence belief stopped at the
`candidates` fact, and culture-2 returned a bit-identical differential whether the stain
was called 80% negative, 50/50, or 80% POSITIVE. culture-2 is the only scenario that
hedges a fact and the only one whose goldens moved. Guarded by
`candidates-evidence-discount`, which pins the RELATION rather than a number.

**Dempster is the readout, and that is a DECISION rather than a default.**
`candidates:*normalization*` is `:dempster`; `:yager` is available and both are
exercised by the suite. Measured across all eight drivers (2026-08-25), K is BIMODAL:
0.00–0.21 where the evidence is epidemiological, 0.53–0.68 where a bench finding
overrules it. The high half is not the pathological regime it resembles — culture-4's
0.626 is the graded respiratory answer being OVERRULED by a beta-hemolytic,
bacitracin-sensitive reading, and renormalizing it away is the correct answer, not a
hidden one. Yager would report pyogenes at 0.313 instead of 0.835 and push the
difference onto Θ, which reads as ignorance the evidence does not actually have.

The case that once argued for Yager was culture-2, where Dempster returned bacteroides
at 0.841 — above the 0.8 the clinician put on the stain. **That was not Dempster's
doing**: evidence belief never reached the arithmetic, and with discounting in place
K falls to 0.1228 and the answer to 0.7058, below its evidence as it should be. Revisit
only if a scenario produces high K between two answers of comparable strength, which
none currently does.

**Nothing is excluded by being named.** There are no ruling-out rules and no negative
beliefs anywhere in the corpus. `{pyogenes, agalactiae}` intersected with
`{pneumoniae}` is empty, and that emptiness *is* the exclusion.

**A genus is a set.** There is no `organism-class`: asking "is this a
staphylococcus?" is asking about `{aureus, epidermidis, saprophyticus}`, which the
algebra answers directly. Nothing chains and no belief is a product of two others.

**Graded answers — how epidemiology gets to rank without excluding.** A flat answer
treats its members as indistinguishable, which is right for a bench finding and wrong
for an epidemiological one: a burn makes Pseudomonas *likelier*, not Klebsiella
*impossible*. An answer SET can only express exclusion, so the corpus was stuck between
a singleton that lied and a wide set that said nothing — measured, and the wide set said
literally nothing: every organism at `bel 0.0000, pl 1.0000`. So a rule may instead
assert a **mass function over several focal sets**:

```lisp
(assert (candidates (value '((0.20 :pseudomonas)
                             (0.07 :klebsiella)
                             (0.05 :enterobacter)
                             (0.08 :e-coli :proteus :serratia)))
                    (of ?o)))
```

Nothing is excluded — the unclaimed 0.60 sits on Θ, where it also covers Acinetobacter
and everything else the corpus does not model — and Pseudomonas still leads. **Nine
epidemiological rules are graded; every bench rule is flat**, because a bench finding
really does admit or exclude. A rule's `:belief` must equal the total of its focal
masses (invariant 13), and each graded rule's total was held at the value it had
before, so the literature decided the SHAPE and nothing was recalibrated.
Survey and rationale: `docs/category-b-resolution-survey.md`.

**Redundant evidence: a rule may speak for a GROUP.** Rules that rest on the same
underlying evidence are not independent observations, and Dempster's rule assumes they
are. Such rules declare `:evidence-group` in their provenance, and **only the most
committed member contributes** — the rest are dropped before combination and are absent
from `/why` as well as from the arithmetic. This is the second axis of specificity:
subsumption drops a rule whose PREMISES another contains, this drops one whose EVIDENCE
another already carries, and subsumption cannot see the second case because it reads
premises rather than sources. The four gram-negative opportunist context rules are the
current group; burn and travel carry genuinely different distributions and are in none.
Invariants 19a/19b check the declaration from both directions. Measured:
`docs/base-rate-investigation.md`.

**Same-conclusion rules reinforce, unless one subsumes the other.** Two rules bringing
distinct evidence to one answer combine; a rule whose premises are a strict subset of
another's conditions on nothing extra and is dropped in favour of the specific one.
That is production-rule specificity applied to belief. **Subsumption is grouped by
answer SUPPORT**, not per fact — graded rules on nested premises assert different
distributions and so land on different facts, where a per-fact check would miss the
pair and double-count. Design: `docs/narrows-to-promotion-sketch.md`.

## Project Structure

```
# --- neomycin layer (the fork's own code) ---
neomycin.asd          — :neomycin system (rulebase + therapy); depends on lisa, lisa-bridge
neomycin.lisp         — convenience loader: loads :neomycin and starts the bridge
neomycin/
  rules/              — THE canonical rulebase: 46 rules, every one CONFIRMING. Each
                        states the SET its evidence narrows the answer to and asserts it
                        as a `candidates` fact. No ruling-out rules, no negative beliefs,
                        no organism-class, no declared frame. Nine EPIDEMIOLOGICAL rules
                        assert a GRADED answer instead — a mass function over several
                        focal sets, so they can say which member is likelier without
                        claiming the rest are impossible (see "Graded answers" below)
    context.lisp      — context tree, 31 clinical params, the `candidates` answer class.
                        LOADS FIRST
    candidates-gram-pos.lisp — 25 rules: the staphylococci, streptococci and enterococci,
                        their bench discriminators and their host factors
    candidates-gram-neg.lisp — 21 rules: the Enterobacteriaceae, Pseudomonas and
                        Bacteroides, the biochemical discriminators, and the two Gram
                        stain answers
    conclusion.lisp / drivers.lisp — reporting rule; culture-1/1a/1b/2/3/4/5/multi
                        drivers. culture-1b is the burn-ICU case from the 2026-08-18
                        clinician session. Its v0.12 headline -- adding `hospital-acquired'
                        SUPPORTS klebsiella while its Bel FALLS across the coverage gate --
                        NO LONGER REPRODUCES: that collapse needed {klebsiella} and
                        {pseudomonas} to be disjoint singletons fighting over one unit of
                        mass, and graded answers overlap, so klebsiella now RISES on the
                        same fact (0.1649 -> 0.2040). Support and share are still different
                        quantities; the case that still shows it is e-coli across
                        culture-1a -> culture-1b, where admitting mass rises 3.50 -> 3.90
                        while Bel falls 0.2800 -> 0.2402. `below_threshold' is still
                        exercised against real rules, now by enterobacter at 0.0246
  package.lisp        — the :neomycin package
  consensus.lisp      — the READ that turns answers into a differential: combines them
                        by intersection and applies rule SPECIFICITY (a rule whose
                        premises are a strict subset of another's is dropped in favour
                        of the specific one)
  bridge.lisp         — /conclusions. Domain knowledge, so it lives here rather than in
                        src/llm/bridge/, which loads first and knows no organisms
  therapy/            — therapy-recommendation phase (own :neomycin-therapy package, nick :therapy)
    package.lisp      — package definition + exports
    protocol.lisp     — pluggable solver protocol, recommendation structs, policy dials
    kb.lisp           — therapy KB abstraction (drugs / sensitivities / contraindications /
                        antibiogram counts) + kb-susceptibility (applies the overlay)
    authoring.lisp    — def* macros (defdrug / defsensitivity / defcontraindication / defantibiogram)
    knowledge-base.lisp — canonical schematic KB (belief-valued susceptibilities)
    antibiogram.lisp  — counts→interval (IDM) + Bayesian combine-susceptibility
    antibiogram-data.lisp — schematic site-local counts; OPT-IN, NOT loaded by default
    solver-common.lisp — SHARED phase A (belief gate, contraindication filter, the two
                        scalar reductions; the universe it returns now spans set-valued
                        obligations as well as named organisms) + alternative-agents
                        + below-threshold-for + discharge-obligations
                        (what the gate dropped, and what the chosen regimen covers there
                        anyway). Solver-independent, so every solver gates identically
                        and comparisons stay meaningful
    stub-solver.lisp / greedy-solver.lisp / exact-solver.lisp — solvers. `exact` is the
                        DEFAULT (ascending-k enumeration over coverage bitmasks); `greedy`
                        is the original approximation, kept because the equivalence
                        property is asserted against it
    bridge.lisp       — /recommend-therapy handler + recommendation→JSON (with provenance)
  test/               — neomycin/test system: therapy + antibiogram + exact-solver tests
                        (the latter carrying the greedy/exact equivalence property and the
                        §1.1 regression) + repointed goldens
                        + property-tests.lisp (corpus-WIDE invariants checked by
                        introspecting the compiled rulebase, so a new rule is covered the
                        moment it is authored — sketch §8) + prompt-tests.lisp (guards
                        system-prompt.md AND tools.json against the corpus: every rule name
                        quoted must exist, the counts stated must be the real ones, and
                        every fact value advertised must be one some rule premises on —
                        or be marked inert (†), which is checked in BOTH directions)
                        + paper-tests.lisp (guards docs/Neomycin.md, which nothing
                        guarded until v1.0.1 and which had drifted six ways in three
                        weeks. Recomputes every figure the paper quotes; its
                        load-bearing guard asks where a number CAME FROM rather than
                        whether it is still stated — release-check.py check 3 turned
                        on the document. A declared rule belief is admissible only at
                        1–2 decimal places and a computed reading only at 3–4, because
                        pooling them let a reading drifted to `0.500` pass on the
                        strength of some rule declaring 0.5)
  clinician-samples/  — saved driver transcripts
docs/                 — LIVE documentation only: anything cited as authority for how the
                        system behaves today (runbook, clinician scenarios, getting-started,
                        the therapy/solver/antibiogram designs, the surveys CLAUDE.md and the
                        rule notes cite, the demos). The paper lives here too
  attic/              — the record of what neomycin USED TO BE: the declared shared frame
                        (deleted v0.11), chaining and the organism-class, disconfirming rules
                        and negative belief, the narrows-to conversion working files, and
                        superseded plans and captures. NOTHING here is authority for current
                        behaviour; each file carries a banner naming the mechanism that is
                        gone, and files are left as written rather than corrected. The
                        boundary is CITED-AS-AUTHORITY, not age — see docs/attic/README.md

# --- Lisa substrate (used as-is; engine intentionally not renamed) ---
lisa.asd              — Lisa core (depends on log4cl)
lisa-bridge.asd       — Bridge system (depends on lisa, hunchentoot, jzon, bordeaux-threads)
src/
  core/               — Rete engine, rules, facts, conflict resolution
    rule-introspection.lisp — exported, domain-neutral queries over the COMPILED rulebase
                        (what a rule concludes / matches / believes). The read half of the
                        derivation table: that records what a rule DID when it fired, this
                        records what a rule IS. Consumed by /rules and by property-tests.
                        Also `corpus-premise-vocabulary`: what the whole rulebase can HEAR
                        — every literal premise value, by parameter. A value absent from it
                        is inert, and inertness is silent (the assert succeeds), which is
                        why the vocabulary has to be queryable rather than inferred
  belief-systems/     — Pluggable belief-system protocol
    protocol.lisp     — Generic function surface + dispatcher + use-system
    certainty-factors/— Shortliffe-Buchanan CF implementation
    dempster-shafer/  — [Bel, Pl] intervals + ds-combine (Dempster's rule) on the
                        per-hypothesis {H, ¬H} frame (Barnett). Retained for comparison
    candidates/       — THE DEFAULT: DS over an OPEN frame. An answer is the SET a rule's
                        evidence narrows to; answers combine by intersection and Θ is never
                        enumerated, so nothing declares a frame. Sparse mass functions on
                        arbitrary subsets, the unnormalized conjunctive rule, and Dempster /
                        Yager / none readouts of one accumulation. Bel/Pl for elements AND
                        sets. `conflict-of` (K) and `margin` are a PAIR: K counts rival mass
                        OVERRULED and so RISES as the winner strengthens — it is not a
                        reliability score — while `margin` measures the leader against the
                        nearest DISJOINT focal set, which makes a set-shaped rival count and
                        a coarser agreeing answer not count. Algebra only — knows nothing of
                        rules or facts
                        (the v0.9–v0.10 declared-frame system `frame/` was deleted in v0.11)
  rete/reference/     — Rete network nodes and compiler
  llm/bridge/         — identification HTTP bridge (:lisa-bridge package)
    session.lisp      — Entity registry, session reset
    server.lisp       — Hunchentoot start/stop; LISA_BELIEF_SYSTEM env var
    handlers.lisp     — REST endpoints (belief-system-aware)
  llm/claude/         — Claude tool-use integration
    driver.py         — Python client: tool-call loop; transcript capture
    tools.json        — Tool schemas (assert_fact, run_inference, describe_rules, recommend_therapy, …)
    system-prompt.md  — clinical system prompt (identification + therapy/antibiogram narration)
examples/
  mycin.lisp          — Lisa-proper MYCIN example; NOT neomycin's rulebase (unused by neomycin)
bin/
  test-culture-1.sh   — end-to-end identification bridge test (curl); run-mycin.sh is a legacy alias
  test-therapy.sh     — end-to-end therapy bridge test (curl)
  test-why.sh         — end-to-end WHY/HOW explanation bridge test (curl): /why for an admitted
                        organism, a reinforced one, and one no rule named. ASSERTS (exits non-zero)
  test-rules.sh       — end-to-end rule-catalogue bridge test (curl): /rules corpus summary,
                        then each filter — ?names= (every rule whose answer admits an
                        organism), ?name= (one rule in full), ?premises= (rules resting on
                        a finding). ASSERTS (exits non-zero)
```

## Bridge Endpoints (port 8090)

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/health` | GET | Health check |
| `/assert-fact` | POST | Assert a fact: `{fact_type, value, entity?, entity_class?, confidence?}`. Always returns **`inert`** (true/false) and, when true, an **`inert_note`** naming what that parameter *can* hear. A value no rule premises on is accepted, recorded, and matches nothing — and used to be reported with a response byte-identical to a live one, which is how `age-group: elderly` was filed for an 82-year-old against a corpus that hears only `neonate`, and never mentioned again. Domain-neutral: computed from the compiled rulebase via `lisa:corpus-premises-value-p` |
| `/run-inference` | POST | Fire rules (captures rule trace) |
| `/conclusions` | GET | Organism-identity results + belief factors, and the active `belief_system`. Per organism it reports `conflict` (K) **with `margin`**, the gap between `leading_answer` and `margin_against` (the nearest answer that *contradicts* the leader — a coarser answer that still admits it is not a rival). **`margin_against` is real JSON `null` when nothing contradicts the leader**, and the leading answer is then unopposed rather than ahead of anything; it was the keyword `:null` until this was fixed, and jzon renders that as the *string* `"NULL"` — truthy in every client language, and duly misread. `leading_answer` is frequently a SET, and the margin then belongs to the set, not to any member. The pair is interpretable and neither half is: K counts rival mass **overruled**, so it rises as the winner strengthens. Measured on two CONSTRUCTED answer pairs, which is what these figures are — not consultations: `{pseudomonas}@0.928` vs `{klebsiella}@0.60` gives `K=0.557, margin=0.740` (decisive), `{pseudomonas}@0.76` vs `{klebsiella}@0.76` gives `K=0.578, margin=0.000` (dead tie). They were labelled burn-ICU and respiratory-strep until this was corrected, and the labels had gone stale: `docs/category-b-resolution-survey.md` predicted culture-1b's figures would "move most of all", and they did — it now runs `K=0.207, margin=0.036`. Pinned by `prompt-tests.lisp` in both directions. Under the default shared-frame system it adds a `frame` block: the frame's `elements` and `subsets`, then per organism entity the `operator` and `normalization` in force, the unnormalized conflict `K`, `m(Θ)`, **every** hypothesis with `{bel, pl, ignorance}` whether or not a rule concluded it, and the `set_valued` focal masses ("one of this family, unsaid which"). Emitted only under `frame` — never a stale projection |
| `/rule-trace` | GET | Get which rules fired last run |
| `/partial-matches` | GET | Rules one fact from firing (goal-directed dialogue) |
| `/rules` | GET | The rule catalogue, read from the compiled rulebase: per rule its `narrows_to` (the organisms its evidence leaves standing), `resolution` (that set's size), `belief`, `premises`, and `:provenance`; plus a corpus `summary` — the rule count, every organism the corpus can name, the `parameters` it can *hear*, and the distribution of `resolutions`. `summary.parameters` is the corpus's INPUT vocabulary, computed from rule premises: a parameter or value absent from it is **inert** — assertable, accepted, and matched by no rule. Filters (ANDed): `?name=`, `?names=<organism>` (every rule whose answer admits it), `?premises=`. Needs no inference — it describes the corpus, not working memory. **Served from `neomycin/bridge.lisp`** |
| `/why` | GET/POST | Authoritative explanation for an organism (`?organism=` or `{organism}`): the `argument` — every answer given about the culture, each with the set it `narrows_to`, its belief, the `rules` that said it with two-axis `:provenance` (origin + verified `evidence` + `belief_basis`), and an `admits` flag. **Answers that do NOT admit the organism are returned deliberately**: nothing argues against anything, so a hypothesis loses plausibility only because other evidence named something else, and the explanation has to show that. Plus `intersection`, `bel`/`pl`, `theta_mass` (m(Θ) for the consultation — **not** the organism's own ignorance, which is its `pl - bel`; they were both called `ignorance` until this was fixed, and were duly swapped), `conflict` with `margin` / `leading_answer` / `margin_against` (same pairing as `/conclusions`), and a quotable plain-language `narrative`. Nothing chains, so there is no nested derivation. **Served from `neomycin/bridge.lisp`** |
| `/recommend-therapy` | POST | Therapy regimen over the canonical KB (optionally overlaid with a site-local antibiogram): `{patient?, solver?, gate?, objective?}` → regimen with belief-valued (`{bel, pl, ignorance}`) susceptibilities, each carrying provenance (`source`, `n_tested`), plus `alternative_agents` (other drugs that covered but weren't chosen — always emitted, both solvers) and `alternative_regimens` (other equally-minimal regimens; `exact` only). Also `below_threshold` — the organisms the coverage gate DROPPED, each with `covered_by`: the chosen regimen's drugs that cover it **anyway**, with susceptibility. And `set_obligations` — the SET-valued answers the regimen had to cover ("one of these seven, unsaid which"), each with its `mass` and any `uncovered` members. A set clearing the gate is a coverage obligation in its own right, discharged **member by member** (never through a KB family, which can read covered while a member is not). A regimen entry's `covers` lists only what the solver was *targeting*, so without this a covered runner-up reads as untreated. Echoes `solver`, `gate`, `objective`, and the dials' values as `coverage_threshold` / `susceptibility_threshold` |
| `/reset` | POST | Clear working memory and entity registry |

## Testing the Bridge

```bash
# Start the bridge first (see Build & Load above), then:
./bin/test-culture-1.sh     # identification: culture-1 → e-coli + pseudomonas + klebsiella
./bin/test-therapy.sh       # therapy: culture-1 → a covering regimen, plus the objective dial
                            #   NB: bin/*.sh are NOT part of asdf:test-system and drift silently
./bin/test-why.sh           # explanation: culture-1 → /why klebsiella (the argument + citations)
./bin/test-rules.sh         # catalogue: /rules corpus shape + ?names= and ?name= (no inference needed)
./bin/release-check.py      # THE RELEASE GATE: model in the loop, asserting over the
                            #   transcript. Costs API calls -- see "Release check" below
```

Expected (identification): culture-1 gives a three-way differential — e-coli
`[0.232, 0.564]`, pseudomonas `[0.176, 0.468]`, klebsiella `[0.165, 0.458]` — with
`K = 0.18` renormalized away as conflict, and 0.234 on the seven-member
aerobic-gram-negative-rod SET without naming a member, which is often the honest
headline. **Nothing has been excluded**, because the only evidence is a stain and two
patient facts: epidemiology ranks, it does not identify. `Pl` is answerable for an
organism no rule mentioned — it is the residual ignorance — including organisms the
corpus does not model at all.

## Release check — the layers must agree

The suite, `bin/*.sh` and `prompt-tests.lisp` each test ONE layer, and none of them
puts the model in the loop. That gap is how three `tools.json` descriptions went stale
while the suite stayed green, how a worked example quoted `K = 0.38` for a year after
the real figure moved, and how a stale coverage threshold was narrated to a clinician.
Every one was a number or a name the model produced from **memory** rather than from a
payload.

**`bin/release-check.py` asserts over the transcript instead of eyeballing it.** Run it
before tagging, with the bridge up and an LLM backend configured:

```bash
./bin/release-check.py                    # all scenarios
./bin/release-check.py --scenario therapy # just one
./bin/release-check.py --keep             # keep transcripts under ./sessions/
./bin/release-check.py --transcript FILE  # re-check a transcript without spending calls
```

It drives scripted consultations at `--transcript-verbosity full`, so every tool result
is captured alongside the prose, and then makes six assertions — all string processing,
no LLM judge:

1. **Rule names** — every rule the assistant quotes exists in the compiled corpus.
2. **Test names** — every microbiology test it names is in `summary.parameters`, so it
   never sends a clinician to the bench for a result the corpus cannot hear.
3. **Numbers** — **every number it quotes appears in a payload received EARLIER in the
   same transcript**, or in what the clinician said. Matching is by rounding, so quoting
   `0.23219512` as `0.23` is fine. *This is the check that matters*: it catches
   recall-from-memory structurally, and nothing else in the stack can.
4. **Phrasing** — no claim that something "argued against" or "ruled out" an organism.
   Negations are exempt, because *"nothing argued against it"* is the correct phrasing.
5. **Ignorance** — a stated `bel`/`pl`/`ignorance` triple for one organism must
   satisfy `ignorance = pl - bel`. Pure arithmetic. It caught a sentence quoting the
   consultation's m(Θ) as an organism's ignorance, in the same clause as the bel and
   pl that contradict it.
6. **A margin against nothing** — when the payload reports `margin_against: null`,
   nothing contradicts the leading answer, and the prose may not narrate the margin as
   a lead *over* a rival. The first STRUCTURAL check: not "is this token real" but
   "does the prose claim a relation the payload denies". Every number in the sentence
   that motivated it was real, so check 3 passed it.

**It is a release gate, not a commit hook** — it costs API calls and is
non-deterministic. Same cadence as the manual check it replaces.

**Read `docs/release-check-design.md` before trusting it**, in particular §5: it
verifies that names and numbers are *referenced* rather than invented, NOT that they are
used correctly. Misattribution, a right number in a wrong claim, an invented *mechanism*
(the v0.14 subsumption fabrication would not have been flagged), and omissions all pass.
It replaces the mechanical half of the manual check, not the judgement half.

When it fails, it names the scenario, the check and the offending text, and points at
the transcript. `--transcript` re-runs the assertions over a saved file for free, which
is how to iterate on a failure. It **warns when the transcript was captured at less
than `full` verbosity**: `describe_rules` results are elided at `normal`, so catalogue
figures have no payload to be checked against and check 3 passes them silently.

A worked manual example, with the golden table it was checked against, is
`neomycin/clinician-samples/v013-graded-answers-release-check.md`. The older samples
reproduce mechanisms that no longer exist — see that directory's README.

## Running the Test Suite

Two dependency-free suites (golden-master + belief-algebra, no external framework):

- **`neomycin/test`** — neomycin's suite (`neomycin/test/`). Its `setup.lisp` repoints the
  shared LISA-TEST harness at neomycin's own rulebase and adds the therapy + antibiogram
  tests. **This is the suite to run for neomycin work.**
- **`lisa/test`** — the Lisa substrate suite (`tests/`), run against Lisa's own
  `examples/mycin.lisp`.

From an SBCL REPL at project root:

```lisp
(load "lisa.asd") (load "lisa-bridge.asd") (load "neomycin.asd")
(asdf:test-system "neomycin/test")       ; runs the suite; errors on any failure
;; or, for the raw report / interactive use:
(asdf:load-system "neomycin/test")
(lisa-test:run-all)                      ; => T iff all pass; prints pass/fail counts
```

Coverage (~1859 assertions / 239 tests):

- **The candidates algebra** directly — sparse masses over arbitrary subsets, the
  unnormalized conjunctive rule, Dempster vs Yager readout, order-independence,
  idempotence, total-conflict and malformed-input edge cases, and `conflict`/`margin`
  as a pair.
- **Every `culture-*` scenario** with hand-verified golden values, including the
  culture-1 ranking regression and the graded-answer goldens re-captured at v0.13/v0.14.
- **Both therapy solvers** (coverage gating, contraindications, belief-valued
  susceptibilities) plus the **greedy/exact equivalence property** — same regimen size,
  gated items and uncovered set across 12 conclusion sets × 3 patient states, so a KB
  change that breaks greedy's approximation is caught by a test rather than by a
  clinician; the `:spectrum-sparing` divergence goldens; and the **antibiogram overlay**
  (IDM counts→interval, Bayesian combination, JSON provenance).
- **The payload builders** — `/why`, `/rules` and `/conclusions` are called by tests, not
  merely by the bridge, after `/why` once 404'd for every organism through a green suite.
- **Corpus-wide invariants** (`property-tests.lisp`), which introspect the compiled
  rulebase so a new rule is covered the moment it is authored. They are numbered 1 and
  11–21; **2–10 were retired with the disconfirming rules they governed**, and the gap
  is left in the numbering deliberately so a reader does not go looking for them. Some
  invariants carry a companion "is-live" test that fails if the invariant has stopped
  having anything to check — a vacuous pass is a silent one. Recent: 14 (a graded rule
  asserts exactly what its `:belief` declares), 15 (a context rule gates on what its
  answer presupposes), 16 (a rule must not commit less than a same-support rule it
  subsumes), 17 (reciprocal readings are symmetric unless declared otherwise), 18 (every
  parameter the corpus can hear is explicitly scoped by the bridge), 19a/19b (an evidence
  group is exactly the set of rules sharing a shape, checked from both directions), 20
  (every rule's `:provenance` is a well-formed plist), 21 (a system's declared
  `:version` and the version keyword it pushes onto `*features*` agree, and no stale
  one lingers beside it — neomycin's announced `0.10.0` for six releases while
  `:version` said `0.16.1`, which a `#+` conditional would have read silently wrong).
- **The prompt and tool schemas** against the corpus (`prompt-tests.lisp`).

Certainty factors and the Barnett per-hypothesis DS system are exercised by **Lisa's own
suite** (`tests/`, against `examples/mycin.lisp`), not by neomycin's — neomycin's corpus
has no rules they can reason over.

If a belief computation changes intentionally, re-capture and update the goldens in
`neomycin/test/candidates-tests.lisp`.

**Corpus-wide property tests** (`neomycin/test/property-tests.lisp`, sketch §8) complement
— never replace — the hand goldens. They introspect the compiled rulebase, so they cover a
new rule automatically: belief in range; **every organism an answer names is treatable**
(directly or by KB family roll-up, so a new species cannot land without its therapy
wiring); no two rules share identical premises; subsumption is detected where it exists
and NOT claimed where premises merely overlap; a marker that is VARIABLE for an organism
may not exclude it; every inert value is a recorded decision; graded masses are
well-formed and total exactly the declared `:belief`; context rules gate on what their
answer presupposes; and evidence groups are exactly the rules that share a shape.

**This paragraph used to describe four invariants that do not exist** — that disconfirming
rules follow a ruling-out template, that no disconfirming rule names an unconcluded
identity, that there are no dead-end organism-classes, and that disconfirming rules stay
above 20% of the corpus as a drift alarm. Those were invariants 2–10, retired along with
the disconfirming rules and the organism-classes themselves. **The corpus has neither.**
Read the `deftest` names in the file rather than this list if the two ever disagree
again.

## Key Packages

- `lisa` / `lisa-user` — Core engine and user-facing DSL (defrule, assert, run, reset)
- `belief` (nickname for `lisa.belief`) — the pluggable belief PROTOCOL, and nothing
  algebra-specific: `belief-factor`, `use-system`, `valid-belief-p`, the four operations
  a system must implement (`combine-beliefs`, `conjoin-beliefs`, `weaken-belief`,
  `normalize-belief`), the fire-time entry point `adjust-belief`, the readouts
  (`belief->number` / `belief->english` / `belief->json`), and the Barnett accessors
  (`ds-belief`, `ds-combine`, `ds-ignorance`). The system objects themselves are
  `*candidates-system*` (the default), `*cf-system*` and `*ds-system*`.

  **The set algebra lives in `candidates`, not here** — `answer`, `graded-answer`,
  `combine-two`, `discount`, `bel` / `pl`, `conflict-of`, `margin`, `*normalization*`.
  It knows nothing of rules or facts. This bullet used to list a `frame` layer —
  `make-frame`, `evidence-pool`, `*frame-operator*` and eight more — that was deleted
  with the declared-frame system at v0.11. Not one of those names existed for five
  releases, which is why `claude-md-tests.lisp` now checks every symbol this file names.
- `lisa-bridge` — identification HTTP bridge (start, stop, reset-session)
- `neomycin-therapy` (nickname `therapy`) — therapy phase: solver protocol, KB abstraction,
  `def*` authoring, the antibiogram overlay, and the `/recommend-therapy` glue

## LLM Integration Status

Identification and therapy both run end to end:

- **Phase 1 — HTTP Bridge**: Hunchentoot server exposing the inference engine as REST endpoints (assert-fact, run-inference, conclusions, rule-trace, partial-matches, why, rules, reset) plus the therapy endpoint (recommend-therapy). Belief-system-aware: startup-configurable via `LISA_BELIEF_SYSTEM` and per-session overridable via `/reset`.
- **Phase 2 — Claude Tool-Use**: Python driver (`src/llm/claude/driver.py`) running a tool-call dispatch loop between Claude and the bridge. Tool schemas for all endpoints (assert_fact, run_inference, get_conclusions, explain_conclusion, …, recommend_therapy), a system prompt carrying the MYCIN clinical ontology and the corpus's *shape* (the rulebase itself is queried via `describe_rules`, not transcribed — see "Rule catalogue" below), uncertainty-mapping, **WHY/HOW explanation** (the LLM queries `explain_conclusion` for authoritative belief derivations + verified citations rather than reconstructing them) **and** therapy/antibiogram narration guidelines, goal-directed dialogue via `/partial-matches`, and session transcript capture.
- **Rule catalogue**: the system prompt no longer transcribes the rulebase. `/rules` reads the compiled corpus — each rule's answer, resolution, premises and provenance, plus a summary of which organisms the corpus can name at all — and the LLM queries it via `describe_rules` instead of recalling. The prompt keeps only the corpus's *shape* (a rule states the SET its evidence narrows to; exclusion is what remains after intersection, never authored; a genus IS a set; the per-cluster discriminator panels), which is what governs how it narrates rather than what it looks up. This removes the second source of truth that used to drift on every rulebase change, and `prompt-tests.lisp` guards the little the prompt still asserts. Design: `docs/rule-catalogue-design.md`.
- **WHY/HOW explanation & provenance**: rules carry a machine-readable `:provenance` (two-axis: `:origin` lineage + adversarially-verified clinical `:evidence` + `:belief-basis :illustrative`; Lisa-core engine change), and the engine records at fire time which rules produced each answer. `/why` composes both into the ARGUMENT — the answers given, who gave them, which still admit the organism and which do not, and what they intersect to — so the LLM narrates from queried fact, not memory. There is no arithmetic to quote because nothing composes one belief through another. Design: `docs/why-how-provenance-design.md`.
- **Therapy phase**: a deterministic **exact** set-cover solver (`neomycin/therapy/`) picks a minimum covering regimen over the schematic KB, honoring contraindications and the coverage gate; susceptibilities are belief-valued and optionally refined by an opt-in site-local **antibiogram overlay**. The LLM requests and narrates a regimen via `recommend_therapy` but never chooses a drug. **The objective is the third policy dial** (`*objective*`, alongside the belief system and the coverage gate), and it has THREE settings over TWO axes: `:lexicographic` (default — drug count, then susceptibility × belief; *not* stewardship, and no notion of spectrum), `:spectrum-sparing` (narrowest-first over declared `:spectrum` tiers), and `:stewardship` (cheapest-first over declared `:stewardship` WHO AWaRe tiers). **Breadth and stewardship cost are different questions and neither subsumes the other**: vancomycin is narrow-spectrum *and* an agent to protect, which is why `:spectrum-sparing` returns it for a group A strep where `:stewardship` returns ampicillin. Turning any of them changes the recommendation and the narration must state the trade — narrower agents have lower coverage floors, and breadth is blind to AWaRe. **Cardinality is primary under all three**, so none can trade one Reserve drug for two Access drugs, and when a Reserve agent is the only single-drug cover it is still what you get (culture-3, measured). The AWaRe tiers are the only values in the therapy KB that are *not* illustrative — the classification is published. Design + the measured divergence tables: `docs/exact-solver-design.md` §§1, 1.1, 3.6, 3.7.

### Running the Clinician Driver

The driver supports three LLM backends. **Anthropic direct API is the
default**; CVS engineers can transparently use the LMS/Hyperion gateway
via `cvscode auth login`, or GCP Vertex AI if they prefer.

```bash
# --- Path A: direct Anthropic API (default for public users) ---
export ANTHROPIC_API_KEY=...
# Optional: point at an internal Anthropic-protocol wrapper
# export ANTHROPIC_BASE_URL=https://internal-wrapper.example.com
python src/llm/claude/driver.py

# --- Path B: CVS LMS/Hyperion (via cvscode auth login) ---
# `cvscode auth login` writes ~/.cvscode/.lms-credentials.json — the driver
# reads it automatically. No env vars required for the common case.
python src/llm/claude/driver.py     # auto-detects LMS when creds file exists

# --- Path C: GCP Vertex AI ---
# gcloud auth application-default login   (once)
export ANTHROPIC_VERTEX_PROJECT_ID=your-gcp-project
export CLOUD_ML_REGION=us-east5
python src/llm/claude/driver.py
```

Backend selection precedence:
1. `LISA_LLM_BACKEND=anthropic|lms|vertex` (explicit override).
2. Auto-detect in order:
   - `ANTHROPIC_API_KEY` set → anthropic
   - `~/.cvscode/.lms-credentials.json` exists **or** `CVSCODE_API_KEY` set → lms
   - `ANTHROPIC_VERTEX_PROJECT_ID` set → vertex
3. Otherwise, error with a hint listing all three options.

LMS specifics:
- Endpoint defaults to `https://hyperion-lms-api.prod.cvshealth.com`.
  Override with `CVSCODE_BASE_URL` for dev/stage.
- API key preference: `CVSCODE_API_KEY` env var wins; otherwise reads
  `lmsApiKey` from `~/.cvscode/.lms-credentials.json`.

Model selection: `LISA_MODEL` overrides the per-backend default.
Defaults are `claude-sonnet-5` on Anthropic and `claude-opus-4-7`
on LMS and Vertex (matching `cvscode`).

**Session transcripts** are captured to `./sessions/session-YYYYmmdd-HHMMSS.md`
by default. Precedence is CLI > env vars > defaults:

| Concern | CLI flag | Env var | Default |
|---|---|---|---|
| Enable/disable | `--transcript` / `--no-transcript` | `LISA_TRANSCRIPT` (`1`/`0`) | on |
| Output dir | `--transcript-dir PATH` | `LISA_TRANSCRIPT_DIR` | `./sessions/` |
| Filename pattern | `--transcript-file NAME` | `LISA_TRANSCRIPT_FILE` | `session-{ts}.md` |
| Verbosity | `--transcript-verbosity {minimal,normal,full}` | `LISA_TRANSCRIPT_VERBOSITY` | `normal` |

At the `Clinician:` prompt: `transcript on`, `transcript off`, `transcript where`, `help`.

**Terminal rendering**: install `rich` (`pip install rich`) for formatted
markdown output — Claude's tables, bold, and headings render properly instead
of appearing as raw pipes and asterisks. Fall back to plain text with
`--plain` or `LISA_PLAIN=1`. Transcripts always contain raw markdown
regardless of terminal display.

**Hands-on runbook** (start here for a guided tour): `docs/runbook.md`.

**Clinician scenarios** for exercising the rulebase (Scenarios 1–7) and the
therapy/antibiogram overlay (Scenario 8): `docs/clinician-scenarios.md`.

Architecture plan: `docs/lisa-llm-architecture.md`

## Style Notes

- Common Lisp conventions: kebab-case, `defvar` for specials with earmuffs
- ASDF for system definition, Quicklisp for dependency management
- Bridge uses jzon for JSON (not cl-json) — `com.inuoe.jzon:parse` / `com.inuoe.jzon:stringify`