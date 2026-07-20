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

**neomycin** is a public research fork of [Lisa](https://github.com/youngde811/Lisa)
that reconstructs Stanford's MYCIN/EMYCIN as *forward-chaining* rules over Lisa's
Rete engine, driven by an LLM. It splits reasoning into two layers, after
Clancey's NEOMYCIN:

- **Domain knowledge + belief propagation** — the Rete rulebase
  (`neomycin/rulebase.lisp`) plus a pluggable belief system. This is deterministic
  and auditable.
- **Diagnostic strategy** — an LLM decides what to ask next and narrates results,
  the role MYCIN's backward chaining once played.

Two belief algebras run over the same rulebase: **Dempster-Shafer** (the default —
it exposes ignorance as a `{bel, pl, ignorance}` interval) and **certainty
factors** (Shortliffe-Buchanan). Their divergence on disconfirming evidence is a
headline research artifact.

---

## What's built so far

| Area | Status |
|------|--------|
| Rete engine + MYCIN rulebase (keyword vocabulary) | ✅ `neomycin/rulebase.lisp` is the canonical rulebase |
| Belief systems (CF + DS), pluggable | ✅ DS default, CF via env/`/reset` |
| HTTP bridge (Hunchentoot) | ✅ assert / infer / conclusions / trace / reset / partial-matches |
| LLM driver (Claude tool-use) | ✅ `src/llm/claude/driver.py` |
| **Therapy phase — solver** | ✅ greedy weighted set-cover, pluggable protocol |
| **Therapy phase — knowledge base** | ✅ `def*` authoring macros + canonical KB (11 drugs) |
| **Therapy phase — `/recommend-therapy` endpoint** | ✅ glue + serializer + handler |
| **Therapy phase — LLM `recommend_therapy` tool** | ⏳ next increment |
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

`POST /recommend-therapy` takes `{"patient": [state-tokens], "solver": "greedy"}`
(both optional) and returns `regimen`, `items_to_treat`, `excluded`, `uncovered`,
and echoes `belief_system` + `solver`. Patient state tokens are contraindication
triggers, e.g. `"allergy-cephalosporin"`.

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

As of this writing the suite is **195 assertions / 60 tests, all green.** It covers:

- **Both belief algebras** (CF and DS) directly, and all `culture-*` scenarios
  under each, with hand-verified golden values.
- **Each MYCIN rule fired in isolation** (confirming rules contribute their belief;
  disconfirming rules drop plausibility below 1.0).
- **The therapy solver** in isolation — coverage, minimality, belief gating,
  contraindications, uncoverable organisms, deterministic tie-breaks, and the
  belief-valued (DS-interval) susceptibility path.
- **The therapy bridge glue end to end** — drive `culture-1` through the real
  engine, read conclusions off working memory, recommend over the canonical KB,
  and serialize to JSON.

> The golden scenario/rules tests run against **`neomycin/rulebase.lisp`** — the
> canonical rulebase. (Lisa's `examples/mycin.lisp` is Lisa-proper and is never
> used by neomycin; `neomycin/test/setup.lisp` points the shared harness at
> neomycin's rulebase.)

### Live bridge smoke tests

With the bridge running (see above), two curl scripts exercise the whole HTTP path:

```bash
./bin/test-culture-1.sh    # identification: culture-1 → pseudomonas + enterobacteriaceae ...
./bin/test-therapy.sh      # therapy: culture-1 → a regimen; + a contraindication case
```

`test-therapy.sh` asserts the culture-1 findings, runs inference, then calls
`/recommend-therapy` twice — once with no patient state, once with a cephalosporin
allergy — checking the regimen and the recorded exclusion. It exits non-zero on
any mismatch.

---

## What the results mean

### Identification (`/conclusions`)

Each organism-identity hypothesis carries a **belief factor** from the active
belief system:

- **Certainty factors:** a single number in `[-1, 1]`. Positive is confirming,
  negative disconfirming; independent rules combine by the Shortliffe-Buchanan
  formula.
- **Dempster-Shafer:** an interval `{bel, pl, ignorance}` where `bel` is committed
  support, `pl` (plausibility) is `1 − mass-against`, and `ignorance = pl − bel` is
  the unassigned mass. Confirming evidence alone keeps `pl = 1.0`; **conflicting
  evidence drops `pl` below 1.0** — the interval widens and lowers, making
  uncertainty visible in a way CF cannot.

### Therapy (`/recommend-therapy`)

A recommendation is an auditable object — nothing here is inferred by a model:

- **`items_to_treat`** — organisms significant enough to cover: those whose belief
  clears `*coverage-threshold*` (default 0.2). Each carries its identification
  belief.
- **`regimen`** — the drugs chosen by the greedy weighted set cover: the fewest
  drugs that cover every item (minimality = stewardship), ties broken
  deterministically. Each entry lists what it `covers`, its `dose`, and per-organism
  `susceptibility`.
- **`excluded`** — drugs ruled out, with a `reason` (e.g. `contraindication`).
- **`uncovered`** — items no candidate drug could cover, surfaced honestly rather
  than dropped.

A worked example (culture-1 under Dempster-Shafer, no contraindications): three
gram-negative identities — pseudomonas `{bel 0.76}`, enterobacteriaceae `{bel
0.80}`, klebsiella `{bel 0.50}` — are all items to treat, and a single broad agent
(`meropenem`) covers all three, so the regimen is one drug and `uncovered` is
empty. Add `"allergy-cephalosporin"` to the patient state and `ceftazidime` and
`ceftriaxone` move to `excluded`, while meropenem still covers everything.

The thresholds (`*coverage-threshold*`, `*susceptibility-threshold*`) are
per-session **stewardship policy dials**, not clinical constants — conservative
(low) covers more, aggressive (high) covers narrower.

---

## Where we're headed

- **LLM `recommend_therapy` tool** — the next increment: a tool schema + driver
  dispatch + system-prompt guidance so Claude can request a regimen and **narrate**
  it. The bright line holds: the deterministic solver chooses; the LLM never picks
  a drug.
- **Antibiogram overlay** — fold site-local resistance into susceptibilities.
- **Drug–drug interactions** — a pairwise constraint in the set cover.
- **Exact solver** — an optional second solver behind the same protocol, as a
  correctness oracle for the greedy one.

See [`therapy-phase-design.md`](therapy-phase-design.md) §10 for the locked design
decisions behind all of the above.