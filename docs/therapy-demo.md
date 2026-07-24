# neomycin — Therapy Demo & Increment Record

Carrying a case all the way through: from a clinician's plain-English description,
to organism identification under a belief algebra, to a **deterministic
antimicrobial regimen** that Claude requests and narrates but never chooses. This
is the companion to [`runbook.md`](runbook.md) (which stops at identification) —
it picks up where that leaves off and drives the therapy phase end to end through
the LLM.

> **⚠️ NOT FOR CLINICAL USE.** Every drug, dose, susceptibility, and
> contraindication in neomycin is illustrative and schematic — chosen to exercise
> the solver, not to be clinically authoritative. Nothing here may inform a
> treatment decision for any human or animal.

---

## Table of Contents

1. [What this increment delivered](#what-this-increment-delivered)
2. [The bright line](#the-bright-line)
3. [Bring-up](#bring-up)
4. [Three demonstrations](#three-demonstrations)
   - [1. One broad agent covers a gram-negative differential](#1-one-broad-agent-covers-a-gram-negative-differential)
   - [2. A contraindication reshapes the regimen](#2-a-contraindication-reshapes-the-regimen)
   - [3. A different organism, a different drug class](#3-a-different-organism-a-different-drug-class)
5. [Contraindication vocabulary](#contraindication-vocabulary)
6. [Reading the recommendation payload](#reading-the-recommendation-payload)
7. [Verifying without the LLM](#verifying-without-the-llm)

---

## What this increment delivered

Before this increment the therapy solver, its knowledge base, and the
`/recommend-therapy` HTTP endpoint were all built and tested — but the LLM layer
had no way to reach them. Claude could identify organisms and stop. This
increment wires therapy into the LLM path, so a clinician can go from symptoms to
a narrated regimen in one conversation:

| Piece | File | What changed |
|-------|------|--------------|
| Tool schema | `src/llm/claude/tools.json` | New `recommend_therapy` tool: optional `patient` (an enum of contraindication tokens) and optional `solver`. |
| Driver dispatch | `src/llm/claude/driver.py` | `recommend_therapy` → `POST /recommend-therapy` in `TOOL_TO_ENDPOINT`; added to the transcript's always-show call/result sets so the regimen and the contraindications passed are always captured. |
| System prompt | `src/llm/claude/system-prompt.md` | New **Therapy Recommendation** section: when to call, the bright line (solver chooses, LLM narrates), the plain-language → token translation table, and how to read `regimen` / `excluded` / `uncovered`. |

No Lisp or bridge changes were needed — the endpoint already existed and is
covered by `bin/test-therapy.sh` and the `neomycin/test` suite. This was purely
the LLM-facing glue.

With this in place, the therapy phase's LLM tool is **complete** — the last
`⏳ next increment` item in
[`getting-started.md`](getting-started.md#whats-built-so-far). What remains
(antibiogram overlay, drug–drug interactions, an exact-solver oracle) is design-doc
future work and is not required for the interactive demo.

---

## The bright line

The single most important property to demonstrate: **the deterministic solver
chooses the drugs; the LLM never does.** Claude's job in the therapy phase is
exactly what it is in identification — translate the clinician's words into
structured input (here, contraindication tokens), call the engine, and narrate
what comes back with full traceability. It does not pick, add, substitute, or
second-guess a drug. If you ask it to "just add vancomycin to be safe," the
correct behavior is to decline and explain that the regimen is the solver's
weighted set cover, not its own judgment.

This is what makes the recommendation *auditable*: every drug in it traces to a
covered organism and a susceptibility figure in the knowledge base, and every
excluded drug traces to a named contraindication.

---

## Bring-up

Follow [`getting-started.md`](getting-started.md#bringing-up-neomycin) to start
the bridge, then [`runbook.md`](runbook.md#start-the-driver) to start the driver.
In brief:

```bash
# Terminal 1 — the engine + bridge (Dempster-Shafer by default)
sbcl --load neomycin.lisp          # starts the bridge on :8090

# Terminal 2 — the Claude driver
export ANTHROPIC_API_KEY=...        # or an LMS / Vertex backend; see the runbook
python src/llm/claude/driver.py
```

You are now the clinician at the `Clinician:` prompt. Everything below is typed
there in plain English; Claude does the fact extraction, inference, and therapy
calls.

---

## Three demonstrations

Each demo has **paste-ready clinician lines** (italicized) — type them one at a
time. Expected regimens below are captured from the live solver under
Dempster-Shafer. (Belief values are shown rounded; raw payloads may carry
floating-point artifacts such as `0.24000001` — round them when you narrate.)

### 1. One broad agent covers a gram-negative differential

**Goal**: See identification flow straight into a minimal regimen — three
organisms, one drug.

Fresh session, then paste:

> *27-year-old burn patient, immunocompromised. Blood culture from three days
> ago: gram-negative rods, aerobic.*

Claude asserts the burn/compromised/blood/gram-neg/rod/aerobic facts and runs
inference, producing three gram-negative identities:

| Organism | Belief (DS) |
|---|---|
| enterobacteriaceae | `bel 0.80, pl 1.0` |
| pseudomonas | `bel 0.76, pl 1.0` |
| klebsiella | `bel 0.50, pl 1.0` |

Now ask:

> *What would you treat this with? No known allergies.*

Claude calls `recommend_therapy` with `patient: []`. All three organisms clear the
coverage threshold (0.2), and the greedy set cover finds that a **single**
carbapenem covers the whole differential:

```json
{
  "regimen": [
    {"drug": "meropenem", "dose": "1 g IV q8h",
     "covers": ["pseudomonas", "enterobacteriaceae", "klebsiella"],
     "susceptibility": [
       {"organism": "pseudomonas", "value": 0.85},
       {"organism": "enterobacteriaceae", "value": 0.95},
       {"organism": "klebsiella", "value": 0.95}]}
  ],
  "items_to_treat": [ ...three organisms... ],
  "excluded": [],
  "uncovered": []
}
```

**The teaching point**: one drug, not three. Minimality *is* the stewardship
signal — the solver won't stack agents when one covers the field. Ask Claude *"why
only one drug?"* and it should explain the weighted set cover: fewest drugs that
cover every above-threshold organism.

### 2. A contraindication reshapes the regimen

**Goal**: See a patient-state token move a drug from the regimen to `excluded`,
with the reason recorded — and the solver re-cover around it.

Same case as Demo 1, but this time tell Claude about an allergy before asking:

> *Same burn patient, but she has a documented cephalosporin allergy. What now?*

Claude calls `recommend_therapy` with `patient: ["allergy-cephalosporin"]`. The
two cephalosporins in the knowledge base are ruled out — but meropenem is a
carbapenem, so the regimen is unchanged and coverage stays complete:

```json
{
  "regimen": [
    {"drug": "meropenem", "dose": "1 g IV q8h",
     "covers": ["pseudomonas", "enterobacteriaceae", "klebsiella"]}
  ],
  "excluded": [
    {"drug": "ceftazidime", "reason": "contraindication"},
    {"drug": "ceftriaxone", "reason": "contraindication"}
  ],
  "uncovered": []
}
```

**The teaching point**: the exclusion is *explicit and reasoned* — ceftazidime and
ceftriaxone are named, each with `reason: contraindication`, rather than silently
dropped. Claude should say something like *"the cephalosporin allergy rules out
ceftazidime and ceftriaxone; meropenem still covers all three organisms, so the
regimen doesn't change."* That's the audit trail the bright line buys you.

### 3. A different organism, a different drug class

**Goal**: Confirm the solver tracks the *organism*, not a favorite drug — a
gram-positive case yields a gram-positive agent; an anaerobe yields an anaerobe
agent.

`reset`, then the anaerobe:

> *Post-op appendectomy patient, blood culture positive. Anaerobic
> gram-negative rods.*

Identification lands on **bacteroides** at near-certainty (`bel 0.98`), and therapy
picks the nitroimidazole:

```json
{"regimen": [{"drug": "metronidazole", "dose": "500 mg IV q8h",
              "covers": ["bacteroides"], "susceptibility": [{"organism": "bacteroides", "value": 0.95}]}],
 "excluded": [], "uncovered": []}
```

`reset` again, then the gram-positive:

> *Hospital-acquired bloodstream infection. Gram-positive cocci in clumps.*

Identification gives **staphylococcus-aureus** (`bel 0.80`) and **staphylococcus**
(`bel 0.70`); therapy picks the glycopeptide that covers both:

```json
{"regimen": [{"drug": "vancomycin", "dose": "15-20 mg/kg IV q8-12h",
              "covers": ["staphylococcus", "staphylococcus-aureus"]}],
 "excluded": [], "uncovered": []}
```

**The teaching point**: no carbapenem in sight for either case — the regimen is a
function of *what was identified*. Add *"she's also penicillin-allergic"* to the
staph case and watch nafcillin, ampicillin, and piperacillin-tazobactam move to
`excluded` while vancomycin (not a penicillin) still carries the coverage.

---

## Contraindication vocabulary

Claude translates plain language into these tokens and passes them in the
`patient` array. The full set the schematic knowledge base honors:

| Token | Rules out (in the demo KB) |
|---|---|
| `allergy-penicillin` | nafcillin, ampicillin, piperacillin-tazobactam |
| `allergy-cephalosporin` | ceftazidime, ceftriaxone |
| `allergy-carbapenem` | meropenem |
| `pregnancy` | ciprofloxacin, gentamicin |
| `pregnancy-first-trimester` | metronidazole |
| `age-pediatric` | ciprofloxacin |
| `renal-impaired` | gentamicin |
| `maoi-therapy` | linezolid |
| `alcohol-use` | metronidazole |

Anything outside this list is ignored by the solver. If the clinician hasn't
mentioned allergies, Claude should **ask** before recommending — contraindications
materially change the regimen.

---

## Reading the recommendation payload

Four parts, all worth narrating:

- **`items_to_treat`** — the organisms significant enough to cover (identification
  belief cleared the coverage threshold, default 0.2), each with its belief.
  Organisms below threshold are deliberately *not* treated.
- **`regimen`** — the drugs the greedy weighted set cover chose: the fewest that
  cover every item. Each lists `dose`, what it `covers`, and per-organism
  `susceptibility`.
- **`excluded`** — drugs ruled out, each with a `reason` (e.g.
  `contraindication`).
- **`uncovered`** — items no available drug could cover, surfaced honestly rather
  than dropped. The demo scenarios above all reach full coverage; `uncovered`
  becomes non-empty only when contraindications strip out every candidate for an
  organism, and Claude should flag it as a gap the schematic KB can't fill rather
  than gloss over it.

The response also echoes `belief_system` and `solver`, so a captured transcript is
self-describing.

---

## Verifying without the LLM

The whole therapy path is exercisable over plain HTTP, no API key required — handy
for CI or for confirming the engine independently of Claude. With the bridge
running:

```bash
./bin/test-therapy.sh
```

It asserts the culture-1 findings, runs inference, then calls `/recommend-therapy`
twice — once with no patient state, once with a cephalosporin allergy — and checks
the regimen, the item count, and the recorded exclusion, exiting non-zero on any
mismatch. That script is the ground truth the numbers in this document were
captured from. For the solver, KB, and bridge-glue unit tests, run the
`neomycin/test` suite (see
[`getting-started.md`](getting-started.md#running-the-tests)).