# neomycin — Build, Test & State of Play

Where the project stands today, how to bring it up, how to run the test suite, and
how to read what comes back. This is the practical companion to the design docs:
[`lisa-llm-architecture.md`](lisa-llm-architecture.md) for the overall picture,
[`therapy-phase-design.md`](therapy-phase-design.md) for the therapy solver, and
[`runbook.md`](runbook.md) for the guided LLM-driven clinical tour.

> **⚠️ NOT FOR CLINICAL USE.** neomycin is a research instrument for studying
> MYCIN-style reasoning under uncertainty and antimicrobial stewardship. Every
> drug, susceptibility, dose, and contraindication in it is illustrative and
> schematic. It is not clinically authoritative and must never inform a treatment
> decision for any human or animal.

---

## Table of Contents

1. [What neomycin is](#what-neomycin-is)
2. [What's built so far](#whats-built-so-far)
3. [Prerequisites](#prerequisites)
4. [Bringing up neomycin](#bringing-up-neomycin)
5. [The bridge endpoints](#the-bridge-endpoints)
6. [Running the tests](#running-the-tests)
7. [What the results mean](#what-the-results-mean)
8. [Where we're headed](#where-were-headed)

---

## What neomycin is

**neomycin** is a public research fork of [Lisa](https://github.com/youngde811/Lisa):
*forward-chaining* rules over Lisa's Rete engine, driven by an LLM. It **began** as a
reconstruction of Stanford's MYCIN/EMYCIN and has diverged substantially — rules state
the SET their evidence narrows to rather than making an organism more likely, exclusion
is never authored, epidemiological rules grade their answers, and there is a therapy
solver MYCIN's illustration did not have. It is not better than MYCIN and should not be
evaluated against MYCIN's results; it answers different questions over a much smaller
corpus. See the README's "What Neomycin is now".

It splits reasoning into two layers, after Clancey's NEOMYCIN:

- **Domain knowledge + belief propagation** — the Rete rulebase
  (`neomycin/rules/`) plus a pluggable belief system. This is deterministic
  and auditable.
- **Diagnostic strategy** — an LLM decides what to ask next and narrates results,
  the role MYCIN's backward chaining once played.

The belief system is **Dempster-Shafer over an open frame** — an answer is the SET a
rule's evidence narrows to, answers combine by intersection, and Θ is never enumerated.
Beliefs are reported as `{bel, pl, ignorance}` intervals, so what the corpus does *not*
know is visible rather than implied. Certainty factors and per-hypothesis DS remain in
the Lisa substrate for its own examples, but neomycin's corpus has no rules they can
reason over.

---

## What's built so far

| Area | Status |
|------|--------|
| Rete engine + MYCIN rulebase (keyword vocabulary) | ✅ `neomycin/rules/` is the canonical rulebase |
| Belief systems (CF + DS), pluggable | ✅ DS default, CF via env/`/reset` |
| HTTP bridge (Hunchentoot) | ✅ assert / infer / conclusions / trace / reset / partial-matches |
| LLM driver (Claude tool-use) | ✅ `src/llm/claude/driver.py` |
| **Therapy phase — solver** | ✅ greedy weighted set-cover, pluggable protocol |
| **Therapy phase — knowledge base** | ✅ `def*` authoring macros + canonical KB (11 drugs) |
| **Therapy phase — `/recommend-therapy` endpoint** | ✅ glue + serializer + handler |
| **Therapy phase — LLM `recommend_therapy` tool** | ✅ tool schema + driver dispatch + system-prompt guidance ([demo](therapy-demo.md)) |
| Antibiogram overlay · drug interactions · exact-solver oracle | ⏳ deferred |

The therapy work lives on the `feature/therapy-phase` branch.

---

## Prerequisites

- **SBCL** with **Quicklisp** (for the bridge's dependencies: Hunchentoot, jzon,
  bordeaux-threads, log4cl).
- **Python 3** for the LLM driver and the curl smoke tests' JSON checks.
- `curl` for the shell smoke tests.

All paths below are relative to the repository root.

---

## Bringing up neomycin

From an SBCL REPL at the project root:

```lisp
;; Load the engine, the bridge, and neomycin (rulebase + belief systems + therapy).
(load "lisa.asd")
(load "lisa-bridge.asd")
(load "neomycin.asd")
(asdf:load-system :neomycin)

;; Start the HTTP bridge on port 8090.
(lisa-bridge:start)      ; => "Lisa bridge started on port 8090 (belief system: Dempster-Shafer ...)"
```

To stop it: `(lisa-bridge:stop)`.

There is also a convenience loader that does all of the above in one shot:

```bash
sbcl --load neomycin.lisp
```

**Choosing a belief system.** The bridge honors `LISA_BELIEF_SYSTEM` at startup
(`ds` — default — or `cf`), and each `/reset` can override it per session with a
`{"belief_system": "cf" | "ds"}` body.

```bash
LISA_BELIEF_SYSTEM=cf sbcl --load neomycin.lisp
```

> **Heads-up:** a bridge from a previous session can linger on port 8090 and cause
> `ADDRESS-IN-USE`. Clear it first with
> `lsof -tiTCP:8090 -sTCP:LISTEN | xargs kill`.

---

## The bridge endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/health` | GET | Liveness check |
| `/assert-fact` | POST | Assert a fact (auto-scoped to patient → culture → organism) |
| `/run-inference` | POST | Fire rules; capture the rule trace |
| `/conclusions` | GET | Organism identities + belief factors |
| `/rule-trace` | GET | Which rules fired last run |
| `/partial-matches` | GET | Rules partway to firing — drives what to ask next |
| `/reset` | POST | Clear working memory; optionally switch belief system |
| `/recommend-therapy` | POST | Regimen for the current conclusions (therapy phase) |

`POST /recommend-therapy` takes `{"patient": [state-tokens], "solver": "exact"}`
(both optional; `solver` defaults to `exact`, with `greedy` still selectable) and
returns `regimen`, `items_to_treat`, `excluded`, `uncovered`, `alternative_agents`,
`alternative_regimens`, and echoes `belief_system` + `solver`. Patient state tokens
are contraindication triggers, e.g. `"allergy-cephalosporin"`.

---

## Running the tests

The suite is a dependency-free golden-master + algebra + integration suite (no
external framework), run through the `LISA-TEST` harness. From an SBCL REPL:

```lisp
(load "lisa.asd")
(load "lisa-bridge.asd")
(load "neomycin.asd")
(asdf:load-system "neomycin/test")
(lisa-test:run-all)      ; => T iff all pass; prints the pass/fail tally
```

As of this writing the suite is **1368 assertions / 186 tests, all green.** It covers:

- **The belief algebras** directly, and all `culture-*` scenarios with hand-verified
  golden values.
- **Each rule fired in isolation** — every rule is CONFIRMING and contributes exactly
  its declared belief; a graded rule's focal masses must sum to that same figure
  (invariant 14).
- **Corpus-wide property tests** that introspect the compiled rulebase, so a new rule
  is covered the moment it is authored — including that a context rule gates on the
  stain, morphology and aerobicity its answer presupposes (invariant 15).
- **The therapy solver** in isolation — coverage, minimality, belief gating,
  contraindications, uncoverable organisms, deterministic tie-breaks, and the
  belief-valued (DS-interval) susceptibility path.
- **The therapy bridge glue end to end** — drive `culture-1` through the real
  engine, read conclusions off working memory, recommend over the canonical KB,
  and serialize to JSON.

> The golden scenario/rules tests run against **`neomycin/rules/`** — the
> canonical rulebase. (Lisa's `examples/mycin.lisp` is Lisa-proper and is never
> used by neomycin; `neomycin/test/setup.lisp` points the shared harness at
> neomycin's rulebase.)

### Live bridge smoke tests

With the bridge running (see above), four curl scripts exercise the whole HTTP path.
All of them ASSERT and exit non-zero on any mismatch:

```bash
./bin/test-culture-1.sh    # identification: the culture-1 differential
./bin/test-therapy.sh      # therapy: a regimen, a contraindication case, the objective dial
./bin/test-why.sh          # explanation: /why for an organism, with citations
./bin/test-rules.sh        # catalogue: /rules corpus shape and its filters
```

`test-therapy.sh` asserts the culture-1 findings, runs inference, then calls
`/recommend-therapy` twice — once with no patient state, once with a cephalosporin
allergy — checking the regimen and the recorded exclusion.

> **These live outside `asdf:test-system` and drift silently.** `test-therapy.sh` was
> red for two weeks before anyone noticed. Run them when touching the bridge or the
> therapy phase.

### The release gate

```bash
./bin/release-check.py     # needs the bridge AND a configured LLM backend
```

The four scripts above test the *bridge*. `release-check.py` tests the layer above it —
**what the model says about what the engine returned** — by driving scripted
consultations and asserting over the captured transcript: every rule name quoted exists,
every test named is one the corpus can hear, **every number quoted appears in a payload
received earlier in the same transcript**, and nothing is described as having "argued
against" or been "ruled out".

It costs API calls, so it is a release gate rather than something to run per commit.
Design, and an honest account of what it cannot catch:
[`release-check-design.md`](release-check-design.md).

---

## What the results mean

### Identification (`/conclusions`)

Every rule states an **answer** — the set of organisms its evidence narrows the
question to — and `/conclusions` reports what those answers combine to. Each
hypothesis carries an interval `{bel, pl, ignorance}`:

- **`bel`** is mass committed to that organism specifically.
- **`pl`** (plausibility) is its ceiling: everything not committed *elsewhere*.
- **`ignorance`** is `pl − bel`, the room the evidence has not settled.

**Nothing is ever excluded by being named.** No rule carries a negative belief and no
rule argues against an organism. A hypothesis loses plausibility because other answers
named something else and the sets could not both hold — that emptiness *is* the
ruling-out. So `pl < 1.0` does not mean something objected; it means mass went
elsewhere.

**Some answers are graded.** Epidemiological rules — a burn, a compromised host, an
infection site — distribute their belief *across* their answer rather than evenly,
because that evidence ranks organisms without excluding any. Nine rules in the corpus
do this; every bench rule is flat. A graded answer reports a `grading`, and reading a
graded rule as though it named one organism is the commonest way to over-read a
neomycin differential.

> **`cf` and `ds` are Lisa substrate, not neomycin options.** They remain because
> Lisa's own examples and suite use them, but neomycin's corpus has no rules they can
> reason over — a candidate-set answer is a SET, and neither has a set algebra. The
> three-algebra comparison the fork maintained through v0.10.0 is reproducible on the
> **v0.10.0 tag** and not after it.

### Therapy (`/recommend-therapy`)

A recommendation is an auditable object — nothing here is inferred by a model:

- **`items_to_treat`** — organisms significant enough to cover: those whose belief
  clears `*coverage-threshold*` (default **0.1** since v0.11). Each carries its
  identification belief. Set-valued answers clearing the same gate become coverage
  obligations in their own right, discharged **member by member**.
- **`regimen`** — the drugs chosen by the minimum set cover: the fewest
  drugs that cover every item, ties broken deterministically by summed
  susceptibility × belief. Each entry lists what it `covers`, its `dose`, and
  per-organism `susceptibility`. Note that fewest is *not* narrowest — the solver
  has no notion of spectrum, and at this KB scale the tiebreak usually decides,
  which tends to favour broad agents (`exact-solver-design.md` §1).
- **`alternative_agents`** — other drugs that also covered a treated organism but
  were not chosen, each in the same shape as a `regimen` entry. Name-sorted, not
  ranked: the solver never compared them. This is where "is there a narrower
  option?" is answered from.
- **`alternative_regimens`** — other complete regimens of the same minimum size
  that the tiebreak chose against. Populated by the `exact` solver only; `greedy`
  never enumerates, so it honestly reports none.
- **`excluded`** — drugs ruled out, with a `reason` (e.g. `contraindication`).
- **`uncovered`** — items no candidate drug could cover, surfaced honestly rather
  than dropped.
- **`below_threshold`** — organisms the coverage gate DROPPED, each with `covered_by`:
  the drugs in the chosen regimen that cover it anyway. Without this, a covered
  runner-up reads as untreated, because a `regimen` entry lists only what the solver
  was targeting.

A worked example (culture-1, no contraindications). Three identities clear the 0.1
gate — e-coli `{bel 0.232, pl 0.564}`, pseudomonas `{bel 0.176, pl 0.468}`, klebsiella
`{bel 0.165, pl 0.458}` — and so does something that is not an identity at all: 0.234
of mass sits on the SET of all seven aerobic gram-negative rods, naming no member. That
set is a coverage obligation in its own right, discharged member by member.

A single broad agent (`meropenem`) covers all seven, so the regimen is one drug,
`uncovered` is empty, and the set obligation reports no uncovered members.
`alternative_agents` lists the five drugs that also covered but were not chosen —
ceftazidime, ceftriaxone, ciprofloxacin, gentamicin, piperacillin-tazobactam — which is
where "is there a narrower option?" gets answered. Enterobacter, at 0.029, falls below
the gate and appears under `below_threshold`, covered by the chosen regimen anyway.

Add `"allergy-cephalosporin"` to the patient state and `ceftazidime` and `ceftriaxone`
move to `excluded`; meropenem still covers everything.

The thresholds (`*coverage-threshold*`, `*susceptibility-threshold*`) are
per-session **stewardship policy dials**, not clinical constants — conservative
(low) covers more, aggressive (high) covers narrower.

---

## Where we're headed

- **LLM `recommend_therapy` tool** — ✅ **done.** Claude can request a regimen and
  narrate it, but never chooses a drug: the deterministic solver decides, and the model
  reports what it decided. See [`therapy-demo.md`](therapy-demo.md) for a guided,
  end-to-end interactive walkthrough.
- **Antibiogram overlay** — ✅ **done.** Site-local resistance counts fold into
  susceptibilities as an interval, opt-in per session. See
  [`antibiogram-overlay-design.md`](antibiogram-overlay-design.md).
- **Exact solver** — ✅ **done, and now the default.** Ascending-k enumeration over
  coverage bitmasks; `greedy` is kept because the equivalence property is asserted
  against it. It also brought the `objective` dial (`:lexicographic` vs
  `:spectrum-sparing`). See [`exact-solver-design.md`](exact-solver-design.md).
- **Drug–drug interactions** — still open: a pairwise constraint in the set cover.

See [`therapy-phase-design.md`](therapy-phase-design.md) §10 for the locked design
decisions behind all of the above.