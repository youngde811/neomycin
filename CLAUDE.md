# neomycin (research fork of Lisa)

> **This repo is `neomycin`** — forked from Lisa 4.2.0 (full history preserved; the
> engine here is now 4.5.1). See `README.md`. **Research only; NOT FOR CLINICAL USE.**
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
  clinician-samples/  — saved driver transcripts
docs/                 — design docs, runbook, clinician scenarios, therapy demo

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
  test-rules.sh       — end-to-end rule-catalogue bridge test (curl): /rules corpus summary, one
                        cluster, one rule in full, and every ruling-out rule's targets
```

## Bridge Endpoints (port 8090)

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/health` | GET | Health check |
| `/assert-fact` | POST | Assert a fact: `{fact_type, value, entity?, entity_class?, confidence?}` |
| `/run-inference` | POST | Fire rules (captures rule trace) |
| `/conclusions` | GET | Organism-identity results + belief factors, and the active `belief_system`. Per organism it reports `conflict` (K) **with `margin`**, the gap between `leading_answer` and `margin_against` (the nearest answer that *contradicts* the leader — a coarser answer that still admits it is not a rival). The pair is interpretable and neither half is: K counts rival mass **overruled**, so it rises as the winner strengthens. Measured: burn-ICU `K=0.557, margin=0.740` (decisive) vs respiratory-strep `K=0.562, margin=0.000` (dead tie). Under the default shared-frame system it adds a `frame` block: the frame's `elements` and `subsets`, then per organism entity the `operator` and `normalization` in force, the unnormalized conflict `K`, `m(Θ)`, **every** hypothesis with `{bel, pl, ignorance}` whether or not a rule concluded it, and the `set_valued` focal masses ("one of this family, unsaid which"). Emitted only under `frame` — never a stale projection |
| `/rule-trace` | GET | Get which rules fired last run |
| `/partial-matches` | GET | Rules one fact from firing (goal-directed dialogue) |
| `/rules` | GET | The rule catalogue, read from the compiled rulebase: per rule its `narrows_to` (the organisms its evidence leaves standing), `resolution` (that set's size), `belief`, `premises`, and `:provenance`; plus a corpus `summary` — the rule count, every organism the corpus can name, the `parameters` it can *hear*, and the distribution of `resolutions`. `summary.parameters` is the corpus's INPUT vocabulary, computed from rule premises: a parameter or value absent from it is **inert** — assertable, accepted, and matched by no rule. Filters (ANDed): `?name=`, `?names=<organism>` (every rule whose answer admits it), `?premises=`. Needs no inference — it describes the corpus, not working memory. **Served from `neomycin/bridge.lisp`** |
| `/why` | GET/POST | Authoritative explanation for an organism (`?organism=` or `{organism}`): the `argument` — every answer given about the culture, each with the set it `narrows_to`, its belief, the `rules` that said it with two-axis `:provenance` (origin + verified `evidence` + `belief_basis`), and an `admits` flag. **Answers that do NOT admit the organism are returned deliberately**: nothing argues against anything, so a hypothesis loses plausibility only because other evidence named something else, and the explanation has to show that. Plus `intersection`, `bel`/`pl`, `conflict` with `margin` / `leading_answer` / `margin_against` (same pairing as `/conclusions`), and a quotable plain-language `narrative`. Nothing chains, so there is no nested derivation. **Served from `neomycin/bridge.lisp`** |
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

The suite, `bin/*.sh` and `prompt-tests.lisp` each test ONE layer. None of them puts
the model in the loop, and that gap is how three `tools.json` descriptions once went
stale while the suite stayed green. **Before tagging a release, run the whole stack
once** — prompt + tool schemas + bridge + engine — and check the narrated numbers
against a pinned golden:

```bash
# bridge up (see Build & Load), then:
python src/llm/claude/driver.py --plain --no-transcript
# work a scenario from docs/clinician-scenarios.md and confirm the figures the model
# quotes match the corresponding golden in neomycin/test/candidates-tests.lisp
# (frame-tests.lisp was deleted with the declared-frame system in v0.11)
```

A worked example, with the goldens it reproduces, is
`neomycin/clinician-samples/v011-burn-icu-release-check.md`, which carries the
golden table it was checked against. (The older `frame-end-to-end-burn-icu.md`
reproduces goldens from the declared-frame system deleted in v0.11.)

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

Coverage (~1430 assertions / 192 tests):

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
- **Eighteen corpus-wide invariants** (`property-tests.lisp`), which introspect the
  compiled rulebase so a new rule is covered the moment it is authored. Recent ones:
  14 (a graded rule asserts exactly what its `:belief` declares), 15 (a context rule
  gates on what its answer presupposes), 16 (a rule must not commit less than a
  same-support rule it subsumes), 17 (reciprocal readings are symmetric unless declared
  otherwise), 18 (every parameter the corpus can hear is explicitly scoped by the bridge).
- **The prompt and tool schemas** against the corpus (`prompt-tests.lisp`).

Certainty factors and the Barnett per-hypothesis DS system are exercised by **Lisa's own
suite** (`tests/`, against `examples/mycin.lisp`), not by neomycin's — neomycin's corpus
has no rules they can reason over.

If a belief computation changes intentionally, re-capture and update the goldens in
`neomycin/test/candidates-tests.lisp`.

**Corpus-wide property tests** (`neomycin/test/property-tests.lisp`, sketch §8) complement
— never replace — the hand goldens. They introspect the compiled rulebase, so they cover a
new rule automatically: belief in range; disconfirming rules follow the ruling-out template;
**no disconfirming rule names an identity no confirming rule concludes** (the staleness
guard — `member` lists go stale silently when a species is retired or promoted to a class);
no dead-end organism-classes in either direction; **every concluded identity is treatable**
(directly or by KB family roll-up, so a new species cannot land without its therapy wiring);
and disconfirming rules stay above 20% of the corpus (a drift alarm for §6's "shape is the
spec"). The "confirming rule contributes exactly its `:belief`, CF = DS-bel, pl = 1.0" law
is deliberately *not* restated there — `check-rule` already enforces it per rule.

## Key Packages

- `lisa` / `lisa-user` — Core engine and user-facing DSL (defrule, assert, run, reset)
- `belief` (nickname for `lisa.belief`) — pluggable belief protocol: CF, Barnett DS, and
  shared-frame systems; `belief-factor`, `combine-beliefs` / `ds-combine`,
  `normalize-belief`, `ds-belief` accessors; and the frame layer — `make-frame`,
  `resolve-mask`, `evidence-pool` / `pool-add` / `pool-mass` / `pool-conflict`,
  `mass-belief` / `mass-plausibility` / `mass-set-valued`, `*frame-operator*`
  (`:cautious` default, `:conjunctive` for comparison), `*frame-normalization*`
  (`:dempster` / `:yager`)
- `lisa-bridge` — identification HTTP bridge (start, stop, reset-session)
- `neomycin-therapy` (nickname `therapy`) — therapy phase: solver protocol, KB abstraction,
  `def*` authoring, the antibiogram overlay, and the `/recommend-therapy` glue

## LLM Integration Status

Identification and therapy both run end to end:

- **Phase 1 — HTTP Bridge**: Hunchentoot server exposing the inference engine as REST endpoints (assert-fact, run-inference, conclusions, rule-trace, partial-matches, why, rules, reset) plus the therapy endpoint (recommend-therapy). Belief-system-aware: startup-configurable via `LISA_BELIEF_SYSTEM` and per-session overridable via `/reset`.
- **Phase 2 — Claude Tool-Use**: Python driver (`src/llm/claude/driver.py`) running a tool-call dispatch loop between Claude and the bridge. Tool schemas for all endpoints (assert_fact, run_inference, get_conclusions, explain_conclusion, …, recommend_therapy), a system prompt carrying the MYCIN clinical ontology and the corpus's *shape* (the rulebase itself is queried via `describe_rules`, not transcribed — see "Rule catalogue" below), uncertainty-mapping, **WHY/HOW explanation** (the LLM queries `explain_conclusion` for authoritative belief derivations + verified citations rather than reconstructing them) **and** therapy/antibiogram narration guidelines, goal-directed dialogue via `/partial-matches`, and session transcript capture.
- **Rule catalogue**: the system prompt no longer transcribes the rulebase. `/rules` reads the compiled corpus — each rule's answer, resolution, premises and provenance, plus a summary of which organisms the corpus can name at all — and the LLM queries it via `describe_rules` instead of recalling. The prompt keeps only the corpus's *shape* (a rule states the SET its evidence narrows to; exclusion is what remains after intersection, never authored; a genus IS a set; the per-cluster discriminator panels), which is what governs how it narrates rather than what it looks up. This removes the second source of truth that used to drift on every rulebase change, and `prompt-tests.lisp` guards the little the prompt still asserts. Design: `docs/rule-catalogue-design.md`.
- **WHY/HOW explanation & provenance**: rules carry a machine-readable `:provenance` (two-axis: `:origin` lineage + adversarially-verified clinical `:evidence` + `:belief-basis :illustrative`; Lisa-core engine change), and the engine records at fire time which rules produced each answer. `/why` composes both into the ARGUMENT — the answers given, who gave them, which still admit the organism and which do not, and what they intersect to — so the LLM narrates from queried fact, not memory. There is no arithmetic to quote because nothing composes one belief through another. Design: `docs/why-how-provenance-design.md`.
- **Therapy phase**: a deterministic **exact** set-cover solver (`neomycin/therapy/`) picks a minimum covering regimen over the schematic KB, honoring contraindications and the coverage gate; susceptibilities are belief-valued and optionally refined by an opt-in site-local **antibiogram overlay**. The LLM requests and narrates a regimen via `recommend_therapy` but never chooses a drug. **The objective is the third policy dial** (`*objective*`, alongside the belief system and the coverage gate): `:lexicographic` (default — drug count, then susceptibility × belief; this is *not* stewardship and has no notion of spectrum) or `:spectrum-sparing` (narrowest-first over declared `:spectrum` tiers). Turning it changes the recommendation and the narration must state the trade — narrower agents have lower coverage floors, and breadth is blind to WHO AWaRe reserve status. Design + the measured divergence table: `docs/exact-solver-design.md` §§1, 1.1, 3.6.

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