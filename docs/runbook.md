# Lisa/LLM Runbook — Diagnostic Reasoning with Claude and the MYCIN Rulebase

## Table of Contents

1. [What you'll see](#what-youll-see)
2. [Prerequisites](#prerequisites)
3. [Start the bridge](#start-the-bridge)
4. [Start the driver](#start-the-driver)
5. [Tour: six demonstrations](#tour-six-demonstrations)
   - [1. Two rules that lean opposite ways](#1-two-rules-that-lean-opposite-ways)
   - [2. Partial-matches drive the next question](#2-partial-matches-drive-the-next-question)
   - [3. Asking the corpus what it knows — and what it cannot hear](#3-asking-the-corpus-what-it-knows--and-what-it-cannot-hear)
   - [4. Conflicting evidence — reading K with the margin](#4-conflicting-evidence--reading-k-with-the-margin)
   - [5. The abdominal anaerobe — narrowing ignorance](#5-the-abdominal-anaerobe--narrowing-ignorance)
   - [6. Turning the stewardship dial (therapy)](#6-turning-the-stewardship-dial-therapy)
6. [Checking a session mechanically](#checking-a-session-mechanically)
7. [Reviewing your session](#reviewing-your-session)
8. [Tuning the transcript](#tuning-the-transcript)
9. [Reference: fact vocabulary and rule catalog](#reference-fact-vocabulary-and-rule-catalog)
10. [Common pitfalls](#common-pitfalls)

---

## What you'll see

The system has two halves that talk over HTTP:

- **Lisa** — a forward-chaining, Rete-based expert system in Common Lisp. Its
  working memory holds *facts*; when facts satisfy a rule's premises, the rule
  fires and adds new facts with a belief. Every rule states an **answer** — the
  set of organisms its evidence narrows the question to — and belief is carried
  by a pluggable **belief system**. neomycin's is **Dempster-Shafer over an open
  frame**: answers combine by intersection and each hypothesis gets an interval
  `{bel, pl, ignorance}`, so what the corpus does *not* know stays visible.
- **Claude** — a large language model driving the conversation with the
  clinician. It doesn't guess diagnoses. It translates natural-language
  observations into structured facts, calls Lisa's endpoints as tool-use
  invocations, and narrates the results with full rule-level traceability.

The rulebase currently has **46 rules**, covering gram-stain morphology,
site-of-culture context, host status (burn / immunocompromised / hospital-acquired /
neutropenic), travel history, and the biochemical discriminators (lactose / indole /
motility / urease / pigment / catalase / coagulase / hemolysis / optochin / bacitracin
/ novobiocin / bile-esculin / salt tolerance / sorbitol / arabinose). Three properties
govern how every demonstration below reads:

- **Every rule is CONFIRMING.** Nothing carries a negative belief and no rule argues
  *against* an organism. Exclusion is what remains after answers are intersected:
  `{pyogenes, agalactiae}` and `{pneumoniae}` cannot both hold, and that emptiness
  *is* the ruling-out. When you see a plausibility below 1.0, no rule objected —
  mass went somewhere else.
- **A genus is a set.** There is no organism-class and nothing chains, so no belief is
  ever the product of two others and there is no derivation tree to unfold.
- **Nine rules state a GRADED answer.** Epidemiological evidence ranks organisms
  without excluding any, so those rules distribute their belief *across* their answer
  rather than evenly — see Demo 1, which is built entirely around reading one.

Don't take those counts on trust, here or anywhere else: `GET /rules` reads them off
the compiled rulebase, and the driver reaches it as `describe_rules`. See
[`docs/clinician-scenarios.md`](clinician-scenarios.md) for the full annotated
scenario catalog, re-captured against this engine.

**Dempster-Shafer over candidate sets is the belief system.** `cf` and `ds` remain in
the Lisa substrate for Lisa's own examples, but neomycin's corpus has no rules they can
reason over — a candidate-set answer is a SET, and neither has a set algebra.

---

## Prerequisites

- SBCL with Quicklisp (project loads via `lisa.asd` / `lisa-bridge.asd`)
- Python 3.10+ with the `anthropic`, `httpx`, and (recommended) `rich`
  packages. `rich` gives you properly rendered tables, bold, and headings
  in the terminal; without it the driver still works but Claude's markdown
  prints as raw text. `pip install anthropic httpx rich`
- One of the following LLM-backend configurations (the driver auto-detects
  in this order, or set `LISA_LLM_BACKEND=anthropic|lms|vertex` to force one):
  - **Anthropic direct (default for public users)**: `ANTHROPIC_API_KEY` in
    the environment. Optionally set `ANTHROPIC_BASE_URL` if routing through
    an internal Anthropic-protocol wrapper — the SDK reads it automatically.
  - **CVS LMS / Hyperion** (for CVS engineers): run `cvscode auth login`
    once. The driver reads `~/.cvscode/.lms-credentials.json` automatically
    — no env vars needed. Override the endpoint with `CVSCODE_BASE_URL` or
    the API key with `CVSCODE_API_KEY` if you need to.
  - **GCP Vertex AI**: run `gcloud auth application-default login` once,
    then set `ANTHROPIC_VERTEX_PROJECT_ID` and `CLOUD_ML_REGION`.

That's it — no other services required.

---

## Start the bridge

From the project root, in an SBCL REPL:

```lisp
(load "lisa.asd")
(load "lisa-bridge.asd")
(load "neomycin.asd")
(asdf:load-system :neomycin)     ; loads neomycin/rules/ (46 rules,
                                 ; culture-* drivers) + the therapy system
(lisa-bridge:start)              ; port 8090
```

(Or just `(load "neomycin.lisp")`, the convenience loader that does exactly the
above. Do **not** load Lisa's `examples/mycin.lisp` — that is Lisa-proper, and its
rules assert a different fact shape entirely.)

You should see:

```
Lisa bridge started on port 8090 (belief system: Dempster-Shafer (simplified)).
```

**Prefer certainty factors?** Set the env var before starting SBCL:

```bash
LISA_BELIEF_SYSTEM=cf sbcl
```

Then run the same load sequence. The startup line will read
`(belief system: Certainty Factors (Shortliffe-Buchanan))`.

Sanity check the bridge from another shell:

```bash
curl -s http://localhost:8090/health
# → {"status":"ok"}
```

To stop the bridge later: `(lisa-bridge:stop)` at the REPL.

---

## Start the driver

In another terminal, pick a backend:

```bash
# Direct Anthropic API (default when ANTHROPIC_API_KEY is set)
export ANTHROPIC_API_KEY=...

# — or — CVS LMS / Hyperion (for CVS engineers):
# cvscode auth login   (once; writes ~/.cvscode/.lms-credentials.json)
# no env vars required — the driver reads the creds file automatically

# — or — GCP Vertex AI:
# gcloud auth application-default login   (once)
# export ANTHROPIC_VERTEX_PROJECT_ID=your-gcp-project
# export CLOUD_ML_REGION=us-east5

python src/llm/claude/driver.py
```

The driver auto-detects the backend from what's present, or force it with
`LISA_LLM_BACKEND=anthropic|lms|vertex`. To pin a specific model regardless
of backend defaults, set `LISA_MODEL=claude-...`.

You'll get:

```
Lisa-Claude Diagnostic Assistant
Type 'quit' to exit, 'reset' to start a new case, 'help' for commands.
--------------------------------------------------
transcript: sessions/session-20260702-121500.md (verbosity=normal)
belief system: Dempster-Shafer (simplified)
--------------------------------------------------

Clinician:
```

You are now the clinician. Type case descriptions in plain English. Claude
will extract facts, call Lisa's endpoints, and narrate.

Meta-commands you can type at the `Clinician:` prompt:

| Command | Effect |
|---|---|
| `help` | Show the command list |
| `reset` | Wipe Lisa's working memory and start a new case (transcript continues with a marker) |
| `transcript on` / `off` / `where` | Runtime control of session capture |
| `quit` | Exit the driver |

---

## Tour: six demonstrations

Each demo below has a **paste-ready clinician script** — copy the italicized
lines one at a time into the driver. Some demos have branch points; take them
if you want to explore.

### 1. Two rules that lean opposite ways

**Goal**: See a **graded answer** — the shape epidemiological evidence takes in this
corpus — and watch two of them disagree without either excluding anything.

**Setup**: fresh session.

Paste:

> *I have a 27-year-old female burn patient. She's obviously immunocompromised
> from the burn. Blood culture from three days ago shows gram-negative rods,
> aerobic.*

Claude will assert `burn=serious`, `compromised-host=t`, `culture-site=blood`,
`culture-age=3`, `gram=neg`, `morphology=rod`, `aerobicity=aerobic`, then run
inference.

**Expected**: four answers. Two are flat — the stain and the aerobicity reading, which
genuinely have no view on which rod it is. Two are **graded**:

```json
"answers": [
  {"narrows_to": ["bacteroides", "e-coli", "enterobacter", "klebsiella",
                  "proteus", "pseudomonas", "salmonella", "serratia"],
   "belief": 0.7},
  {"narrows_to": ["e-coli", "enterobacter", "klebsiella",
                  "proteus", "pseudomonas", "salmonella", "serratia"],
   "belief": 0.8},
  {"narrows_to": ["e-coli", "enterobacter", "klebsiella", "proteus",
                  "pseudomonas", "serratia"],
   "belief": 0.4,
   "grading": [{"mass": 0.20, "organisms": ["pseudomonas"]},
               {"mass": 0.08, "organisms": ["e-coli", "proteus", "serratia"]},
               {"mass": 0.07, "organisms": ["klebsiella"]},
               {"mass": 0.05, "organisms": ["enterobacter"]}]},
  {"narrows_to": ["e-coli", "enterobacter", "klebsiella", "proteus",
                  "pseudomonas", "serratia"],
   "belief": 0.6,
   "grading": [{"mass": 0.28, "organisms": ["e-coli"]},
               {"mass": 0.16, "organisms": ["klebsiella"]},
               {"mass": 0.08, "organisms": ["pseudomonas"]},
               {"mass": 0.08, "organisms": ["enterobacter", "proteus", "serratia"]}]}
]
```

and the differential they combine to:

```json
"conflict": 0.180, "margin": 0.234, "ignorance": 0.018,
"hypotheses": [
  {"value": "e-coli",       "bel": 0.232, "pl": 0.564, "ignorance": 0.332},
  {"value": "pseudomonas",  "bel": 0.176, "pl": 0.468, "ignorance": 0.293},
  {"value": "klebsiella",   "bel": 0.165, "pl": 0.458, "ignorance": 0.293},
  {"value": "enterobacter", "bel": 0.029, "pl": 0.380, "ignorance": 0.351},
  {"value": "proteus",      "bel": 0.0,   "pl": 0.398, "ignorance": 0.398},
  {"value": "serratia",     "bel": 0.0,   "pl": 0.398, "ignorance": 0.398},
  {"value": "salmonella",   "bel": 0.0,   "pl": 0.293, "ignorance": 0.293},
  {"value": "bacteroides",  "bel": 0.0,   "pl": 0.059, "ignorance": 0.059}
],
"set_valued": [{"members": [...the seven aerobic rods...], "mass": 0.234}, ...]
```

**Four things worth noticing.**

*The last two answers cover the same six organisms and are not the same claim.* Read
`narrows_to` alone and they look identical. Read `grading` and one puts 0.20 of its
0.40 on Pseudomonas while the other puts 0.28 of its 0.60 on E. coli. **A graded answer
reported without its grading reads as a shrug when it is in fact an opinion** — this is
the single easiest way to misread a neomycin payload.

*Nothing is excluded.* Every rod keeps a plausibility. A burn makes Pseudomonas
likelier; it does not make Klebsiella impossible, and before v0.13 these rules claimed
exactly that by answering with one organism.

*`conflict: 0.180` is the two rules disagreeing.* The burn evidence and the
compromised-host evidence point at different organisms — both defensibly. That is what
K is measuring here, and it is a normal, healthy reading rather than a fault.

*The biggest single figure is not an organism.* `set_valued` holds **0.234** on the
seven aerobic gram-negative rods — "one of these, the evidence does not say which."
Often the honest headline, and here it is larger than the leading species.

Ask Claude a follow-up: *"Why E. coli, and how confident?"* — it calls
`explain_conclusion` and narrates the engine's authoritative record: each answer, which
rules gave it, whether it `admits` the organism, and for a graded answer the
`mass_for_organism` it contributed. Ask *"and what's that based on?"* and it quotes each
rule's verified `evidence` (NCBI Bookshelf / CDC citations) while flagging that the
beliefs are schematic teaching figures (`belief_basis: illustrative`), never measured
probabilities. **There is no arithmetic to quote** — nothing composes one belief through
another, so `/why` has no multiplication to report.

The honest closing question to ask it: *"has this actually identified anything?"* It
should say no. Every answer here is stain or epidemiology; a lactose or indole result is
what would discriminate.

### 2. Partial-matches drive the next question

**Goal**: Watch the engine name the fact it is waiting for, and see Claude ask for that
rather than guessing.

`reset`, then paste:

> *Blood culture from a post-op patient — gram-negative rods on the slide.
> That's all I have so far.*

Claude will assert `culture-site=blood`, `gram=neg`, `morphology=rod`. Before running
inference to a conclusion, it should call `get_partial_matches`. The top of that list:

```
anaerobic-gram-neg-rod-in-blood-narrows-to-bacteroides    5/6   missing: aerobicity (value=anaerobic)
aerobic-gram-neg-rod-narrows-to-aerobic-gram-neg-rods     3/4   missing: aerobicity (value=aerobic)
indole-positive-narrows-to-indole-producers               3/4   missing: indole (value=positive)
urease-positive-narrows-to-urease-producers               3/4   missing: urease (value=positive)
red-pigment-narrows-to-serratia                           3/4   missing: pigment (value=red)
```

**One rule is five conditions of six satisfied, waiting on a single fact.** Claude
should ask: *"Do you have the aerobicity yet?"* — not because a heuristic suggested it,
but because the engine said so. This is the goal-directed dialogue loop, and it is why
the driver calls `get_partial_matches` before settling.

Reply *aerobic* and let it complete. You get the two coarse answers only — 0.70 on the
eight gram-negatives, 0.80 on the seven aerobic rods — with **no organism holding any
belief of its own** and 0.80 of set-valued mass on the seven. That is a real conclusion
and Claude should report it as one: the culture is an aerobic gram-negative rod and
nothing so far separates the seven.

> **Try the reverse.** Answer *anaerobic* instead and the top rule fires:
> bacteroides at `bel 0.90`. One fact, and the case is essentially settled — because
> the corpus models exactly one anaerobic gram-negative rod. Ask Claude why it is so
> confident and a good answer will say that out loud: the narrowness is a fact about
> the corpus's coverage, not about the strength of the evidence.

### 3. Asking the corpus what it knows — and what it cannot hear

**Goal**: Query the rulebase itself, and meet the failure mode that has no error
message.

`reset` is not needed — this demo touches no working memory.

> *"Which single test best discriminates within the streptococci, and how heavily
> does the system weight it?"*

Claude calls `describe_rules`, which reads the **compiled** rulebase. The system prompt
deliberately does not contain the corpus, so a rule that is retired or re-weighted
cannot leave a stale copy behind in the narration. Look at the `resolution` column in
what comes back — it is the answer to the question, because it says how far each test
narrows the field. Hemolysis takes it from six organisms to two; the disc tests take it
from two to one.

**Now the part worth the demo.** Ask:

> *"The white count is low — 2.1. Does that change anything?"*

It does not, and Claude must say so. `white-blood-count` is **inert**: assertable,
accepted by the bridge, returned as success — and read by no rule in the corpus. The
rule that used to read it was retired as a wrong conditional (it fired *on* a low count
while citing a figure that answers the opposite question). **Nothing anywhere reports
that an assertion was inert**; the consultation looks exactly as it would if the test
had come back uninformative.

That is why `describe_rules` returns `summary.parameters` — the corpus's input
vocabulary, computed from rule premises — and why the fact tables in the system prompt
mark inert values with a dagger (†). A good answer here records the count for the chart
and then declines to narrate it as having moved anything. **Asking for one as a
discriminating test would be worse.**

> **Belief systems can still be switched** — `reset_session` takes a
> `{"belief_system": ...}`, and `LISA_BELIEF_SYSTEM` sets the bridge default — but
> there is nothing useful to switch *to*. `cf` and `ds` are Lisa substrate: neomycin's
> rules assert sets, and neither algebra has a set algebra. The three-way comparison
> this demo used to run is reproducible on the **v0.10.0 tag** and not after it.

### 4. Conflicting evidence — reading K with the margin

**Goal**: See evidential conflict surface as a number, and learn why that number is
uninterpretable on its own.

`reset`, then:

> *Same burn patient as before. Microbiologist is hedging — probably
> gram-negative rods, but possibly gram-positive. The stain wasn't great.
> Blood culture, anaerobic organism.*

Claude asserts two competing gram facts with confidence values: `gram=neg` at 0.8 and
`gram=pos` at 0.6. Both live in working memory at different strengths.

Three answers fire — the gram-negative reading (0.70 on eight organisms), the
gram-positive reading (0.70 on nine), and the anaerobe rule (0.90 on bacteroides). The
first two share **no member**, so intersecting them puts mass on the empty set:

```json
"conflict": 0.679, "margin": 0.776, "ignorance": 0.028,
"leading_answer": ["bacteroides"],
"margin_against": ["enterococcus-faecalis", "enterococcus-faecium",
                   "staphylococcus-aureus", ... the nine gram-positives ...],
"hypotheses": [
  {"value": "bacteroides", "bel": 0.841, "pl": 0.935},
  {"value": "e-coli",      "bel": 0.0,   "pl": 0.094},
  ... every other organism at bel 0.0, pl 0.094 ...
]
```

**No rule argued against anything.** The gram-positive reading simply names nine
organisms, none of which is Bacteroides, and the arithmetic does the rest. There are no
disconfirming rules in this corpus and no negative beliefs.

**Read K and the margin as a pair — neither is interpretable alone.** `conflict: 0.679`
says two thirds of the belief went to combinations that cannot hold. That sounds
alarming, and on its own it is unreadable: **K rises as a winner strengthens against a
rival**, so a high K can mean *decisive* just as easily as *unstable*. The companion is
`margin`, the gap between the leading answer and the nearest answer that genuinely
contradicts it. Here it is **0.776** — Bacteroides is a long way clear, and this case is
conflicted but not close. Compare Scenario 3 in the scenario catalogue, where K is
comparable at 0.525 but the margin is **0.084**: a near-tie. Same K, opposite clinical
situation.

`margin_against` names what the leader is being measured against — the nine
gram-positives — which matters because that rival is a **set** whose members each have
`bel 0.0`. Reading the `hypotheses` list alone, you would never find it.

**What to narrate**: *"Bacteroides is the only answer consistent with an anaerobic
gram-negative rod and it is well clear — but your stain is contradicting itself, and
two thirds of the belief in this run went to combinations that cannot both hold. Repeat
the Gram before relying on any of these numbers."*

> **A note on where this number came from.** Before v0.13 this case read `K = 0.900`
> with pseudomonas at `bel 0.228` — on an organism the corpus knows is an **anaerobe**.
> Two Pseudomonas context rules had never gated on aerobicity, so they fired here and
> asserted an obligate aerobe against the bacteroides answer. Part of the conflict this
> demonstration attributed to the hedged stain was the corpus contradicting itself. The
> gates were added and an invariant now enforces them; `K = 0.679` is the stain alone.

### 5. The abdominal anaerobe — narrowing ignorance

**Goal**: See DS combination *narrowing* the ignorance interval as
independent evidence accumulates. This is the mirror image of Demo 4.

`reset`, then:

> *Post-op appendectomy patient. Blood culture came back positive too.
> Anaerobic gram-negative rods.*

Claude should assert: `culture-site=blood`, `infection-site=abdominal` (on
the patient), `gram=neg`, `morphology=rod`, `aerobicity=anaerobic`.

Two bacteroides rules fire — the blood one (0.9) and the abdominal one (0.8). Both
answer `{bacteroides}`, and because they bring **distinct evidence** (a blood culture,
an abdominal site) they reinforce rather than being counted once:

```json
"conflict": 0.0, "margin": 0.980, "ignorance": 0.006,
"hypotheses": [
  {"value": "bacteroides", "bel": 0.98, "pl": 1.0,  "ignorance": 0.02},
  {"value": "e-coli",      "bel": 0.0,  "pl": 0.02, "ignorance": 0.02}
]
```

`bel = 0.98`, `ignorance = 0.02`, `K = 0`. Compare Demo 1, where the leading organism
sits at 0.232 with an ignorance of 0.332 — a differential rather than an
identification.

**Teaching moment**: combination *reduces* ignorance when independent evidence agrees,
and conflict stays at zero because the two answers are identical rather than rival.
Divergent evidence widens the interval instead (Demo 4). The two situations are
distinguishable from the output, which is the whole reason for reporting an interval
rather than a point.

> **Reinforcement is not automatic, and the exception is worth knowing.** Two rules
> reaching the same answer combine *unless one SUBSUMES the other* — that is, unless
> one's premises are a strict subset of the other's, so it fires whenever that one does
> and conditions on nothing extra. Such a rule is dropped rather than counted twice, and
> it is dropped from the **explanation** too, not merely from the arithmetic. Neither of
> these two subsumes the other: one reads the culture site, the other the infection
> site. Scenario 2 in the scenario catalogue is the case where subsumption does fire.

---

### 6. Turning the stewardship dial (therapy)

**Goal**: See one case produce two defensible regimens, and see the cost of the
narrower one stated in numbers rather than adjectives.

Paste these one at a time:

> *"Aerobic gram-negative rods in the blood. Lactose fermenter, indole positive.
> No host risk factors, no known allergies."*

> *"What would you treat with?"*

That gives **E. coli at `bel 0.884, pl 1.000`** — a genuine identification, and worth
contrasting with Demo 1, where nothing but stain and epidemiology was available and no
organism passed 0.24. Two bench findings did what four epidemiological answers could
not. The regimen is **meropenem** (susceptibility `bel 0.90`, `pl 0.99`, ignorance
`0.09`). Now ask the question the dial exists for:

> *"Is there a narrower agent? What would a narrow-spectrum policy pick instead?"*

Claude should read `alternative_agents` — already in the payload — and then call
`recommend_therapy` again with `objective: "spectrum-sparing"`, which returns
**gentamicin** (`bel 0.64`, `pl 0.90`, ignorance `0.26`).

**Teaching moment, and the reason this demo exists.** This is the case from
`exact-solver-design.md` §1.1, where an earlier build told a real clinician that no
narrower agent was registered for E. coli. Five were. The solver optimised drug
*count*, never breadth, and the payload carried only the winner — so the narration
inferred absence from silence and stated it as fact. Three things changed:

- `alternative_agents` puts what was passed over in the payload, under **both**
  solvers, so the false answer is no longer available to infer.
- `objective` makes the narrowness preference a real, selectable policy instead of a
  claim in a docstring.
- The trade is quantified: narrowing costs coverage floor (0.90 → 0.64) *and*
  certainty (ignorance 0.09 → 0.26).

Ask *"why is meropenem listed last now?"* to see the objective reorder
`alternative_regimens` — narrowest-first instead of strongest-first. The ordering is
the policy, visible in the data.

**Watch for the dial's honest failure.** On an enterococcus case, spectrum-sparing
moves from ampicillin (WHO AWaRe *Access*) to linezolid (AWaRe *Reserve*) — narrower,
and backwards as stewardship, because breadth cannot see reserve status. That was
shipped as measured rather than patched. If Claude presents a spectrum-sparing
regimen as simply *better*, that is a prompt bug worth reporting: it is required to
state the trade in both directions.

Full scenario: `docs/clinician-scenarios.md` Scenario 15.

---

## Checking a session mechanically

Everything above is a guided tour you read yourself. Before a release the same path is
walked by an assertion harness instead:

```bash
./bin/release-check.py            # bridge up, LLM backend configured
./bin/release-check.py --keep     # keep the transcripts under ./sessions/
```

It drives scripted consultations, captures the transcript with full tool payloads, and
then checks that **every number the model quoted appears in a payload it was actually
given** — plus that every rule name exists, every test named is one the corpus can hear,
and nothing was described as having "argued against" anything.

If you have a transcript already, `--transcript FILE` re-runs the checks over it for
free. That is a good way to see what the harness sees before spending API calls.
Design and limits: [`release-check-design.md`](release-check-design.md).

---

## Reviewing your session

Every session goes to `sessions/session-YYYYmmdd-HHMMSS.md` by default. It's
plain markdown — open it in any editor or paste it into a shared doc.

Structure:

```
# Lisa/Claude session transcript

- Started: 2026-07-02T12:15:00
- Model: `claude-sonnet-5`
- Bridge: `http://localhost:8090`
- Belief system: `Dempster-Shafer (simplified)`
- Verbosity: `normal`

---

## Clinician
<your message>

## Assistant
<Claude's narration>

### Tool call: `assert_fact`
```json
{ ... }
```

### Tool result: `get_conclusions`
```json
{ "conclusions": [...], "belief_system": "..." }
```
```

Reset markers in the file make it easy to find where each new case started.

---

## Tuning the transcript

Configuration precedence: **CLI > env vars > defaults**.

| Concern | CLI flag | Env var | Default |
|---|---|---|---|
| Enable/disable | `--transcript` / `--no-transcript` | `LISA_TRANSCRIPT` (`1`/`0`) | on |
| Output dir | `--transcript-dir PATH` | `LISA_TRANSCRIPT_DIR` | `./sessions/` |
| Filename pattern | `--transcript-file NAME` | `LISA_TRANSCRIPT_FILE` | `session-{ts}.md` |
| Verbosity | `--transcript-verbosity {minimal,normal,full}` | `LISA_TRANSCRIPT_VERBOSITY` | `normal` |

Verbosity levels:
- **minimal** — user turns + assistant text only. Best for sharing a
  conversation with a non-technical reader.
- **normal** — the above, plus tool call names, short input summaries, and
  full conclusion / rule-trace / partial-match payloads. Best for review.
- **full** — every tool call and result with complete JSON bodies. Best for
  debugging.

Runtime commands at the `Clinician:` prompt: `transcript on|off|where`. Useful
if a portion of a session is sensitive or exploratory and you don't want it
captured.

## Terminal rendering

Claude produces markdown: tables, bold, headings, lists. By default the
driver renders that markdown to the terminal using the `rich` package —
tables become properly aligned boxes, `**bold**` becomes actual bold text,
`###` becomes visible headings. Highly recommended for interactive use.

- `pip install rich` if you don't have it. Without `rich` the driver falls
  back to raw markdown output (functional but harder to read).
- `--plain` on the CLI or `LISA_PLAIN=1` in the environment disables rich
  rendering and prints raw markdown, useful when piping the driver's
  output to another tool or when the terminal doesn't handle ANSI well.

Transcripts always contain raw markdown regardless of terminal display —
that's what makes them portable to any viewer.

---

## Reference: fact vocabulary and rule catalog

**† marks an INERT value** — assertable, accepted by the bridge, and read by no rule
in the current corpus. Assert one when the clinician reports it, so the record stays
faithful; never solicit one as a discriminating test, and never narrate its result as
having moved the differential, because it did not.

**Organism facts** (attach to `organism-1`, `organism-2`, ...):

| Fact | Values |
|---|---|
| `gram` | pos, neg |
| `morphology` | rod, coccus |
| `aerobicity` | aerobic, anaerobic |
| `growth-conformation` | clumps, chains |
| `lactose` | fermenter, non-fermenter |
| `indole` | positive, negative |
| `motility` | motile, non-motile, swarming |
| `urease` | positive, negative |
| `pigment` | red, none† |
| `catalase` | positive, negative |
| `coagulase` | positive, negative |
| `hemolysis` | alpha, beta, gamma† |
| `optochin` | sensitive, resistant |
| `bacitracin` | sensitive, resistant |
| `novobiocin` | sensitive, resistant |
| `bile-esculin` | positive, negative |
| `salt-tolerance` | tolerant, intolerant† |
| `arabinose` | fermenter, non-fermenter |
| `sorbitol` | fermenter, non-fermenter |

**Patient facts** (attach to `patient-1`):

| Fact | Values |
|---|---|
| `burn` | serious |
| `compromised-host` | t |
| `hospital-acquired` | t |
| `recent-travel` | tropical |
| `white-blood-count` | low† |
| `infection-site` | respiratory, abdominal, urinary |
| `neutropenia` | t |
| `prosthetic-material` | t |
| `iv-drug-use` | t |
| `age-group` | neonate, infant†, adult†, elderly† |

**Culture facts** (no entity):

| Fact | Values |
|---|---|
| `culture-site` | blood |
| `culture-age` | integer (days)† |

**The rule catalogue is NOT in this document or in the system prompt.** It is read from
the compiled rulebase through `GET /rules`, which the driver reaches as
`describe_rules`. That is deliberate: a transcribed copy is a second source of truth
and it drifted on every rulebase change. Ask Claude *"which rules read a positive
urease?"* or *"what can this corpus name at all?"* and it queries rather than recalls.
The table above is a convenience copy of what `summary.parameters` computes, and
`summary.parameters` is the authoritative version.

For the full annotated fifteen scenarios with expected differentials, see
[`docs/clinician-scenarios.md`](clinician-scenarios.md).

---

## Common pitfalls

- **"Nothing got above 0.24 — is it broken?"** Almost certainly not. If your case is
  built from a stain plus host context and no bench findings, that *is* the answer:
  epidemiology ranks organisms, it does not identify one. Look at `set_valued` — the
  honest headline is usually there — and add a biochemical result to discriminate. See
  Demo 1 versus Demo 6 for the contrast.
- **"Two rules fired on the same organism but the belief didn't move."** One of them
  was probably **subsumed** — its premises a strict subset of the other's, so it
  conditions on nothing extra and is dropped rather than counted twice. It will be
  absent from `/why` as well. Scenario 2 in the scenario catalogue is the worked case.
- **"I asserted a fact and nothing happened."** Check it against
  `summary.parameters` from `describe_rules`. A value no rule premises on is **inert**:
  the assert succeeds, returns success, and fires nothing, with no error anywhere. See
  Demo 3.
- **"Claude ran inference too early."** Ask it to check partial matches
  first, or say something like *"before you run inference, what's still
  missing?"* — it will call `get_partial_matches` and describe what would
  discriminate the differential.
- **"Wide ignorance intervals under DS."** Wide intervals are correct when
  evidence is weak or contradictory. If you want them to narrow, add more
  facts that trigger additional rules concluding the same organism.
- **"The bridge won't start with `LISA_BELIEF_SYSTEM=bayes`."** Valid values are
  `candidates` (**the default, and the only one neomycin's corpus has rules for**),
  plus `cf` / `certainty-factors` and `ds` / `dempster-shafer`, which are Lisa
  substrate. Unknown values fail loudly on purpose — no guessing.
- **Session files piling up in `sessions/`?** They're gitignored. Delete at
  will, or set `LISA_TRANSCRIPT_DIR` somewhere ephemeral.
- **`ModuleNotFoundError: anthropic`.** Install driver deps in a venv:
  `python -m venv .venv && .venv/bin/pip install anthropic httpx rich`.
- **Tables and bold showing as raw markdown (`| a | b |`, `**bold**`).**
  You don't have `rich` installed. `pip install rich` and rerun the
  driver, or accept the raw output. See the [Terminal rendering](#terminal-rendering)
  section.

---

## What next?

- Read `docs/clinician-scenarios.md` for the other twelve scenarios, including the
  gram-positive cocci, the therapy antibiogram overlay, and the rule catalogue.
- Read `docs/lisa-llm-architecture.md` for the design rationale.
- Modify `examples/mycin.lisp` to add your own rules — the driver picks them
  up automatically after a bridge reset, no schema changes needed for rules
  that use the existing fact vocabulary.

Happy diagnosing.
