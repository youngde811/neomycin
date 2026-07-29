# neomycin (research fork of Lisa)

> **This repo is `neomycin`** — a research reconstruction of MYCIN/EMYCIN,
> forked from Lisa 4.2.0 (full history preserved). See `README.md`. **Research
> only; NOT FOR CLINICAL USE.** This is a *substantive* fork: the `lisa` engine
> is intentionally *not* renamed and is kept close to upstream where that costs
> nothing, but **engine-level modifications to better serve neomycin are fair
> game when they genuinely move the chains** — e.g. deepening Dempster-Shafer
> support beneath the corpus layer, or hosting classification/recognition. Treat
> these as engine-axis work (real reach, real cost): reach for them when they
> meaningfully advance the project, not for cosmetic gains — and don't treat "a
> Rete engine used as-is" as a constraint that forecloses them. Dempster-Shafer
> is the default belief system; certainty factors are retained for CF-vs-DS
> comparison. The Lisa engine documentation below describes the substrate as it
> currently stands.

# Lisa — Lisp-based Intelligent Software Agents

Forward-chaining expert system shell in Common Lisp (Rete algorithm, CLOS/MOP, certainty factors). Integrated with Claude via tool-use for natural-language medical diagnosis (MYCIN rulebase).

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
(asdf:load-system :neomycin)   ; loads neomycin/rulebase.lisp + the therapy system
                               ; (:neomycin depends on :lisa and :lisa-bridge)
(lisa-bridge:start)            ; port 8090
```

To stop: `(lisa-bridge:stop)`

neomycin's canonical rulebase is **`neomycin/rulebase.lisp`** (the keyword-vocabulary
MYCIN reconstruction, loaded by the `:neomycin` ASDF system). Lisa's
`examples/mycin.lisp` is Lisa-proper and is **never** used by neomycin — don't load it
over the neomycin rulebase.

### Choosing a belief system

The bridge honors `LISA_BELIEF_SYSTEM` at startup. **Dempster-Shafer is the
default** — it exposes ignorance intervals `{bel, pl, ignorance}` that the
LLM can narrate meaningfully. Override with the env var:

```bash
LISA_BELIEF_SYSTEM=cf sbcl ...   # certainty factors (Shortliffe-Buchanan)
LISA_BELIEF_SYSTEM=ds sbcl ...   # Dempster-Shafer (default)
```

Per-session overrides ride on `POST /reset` with body `{"belief_system":
"cf" | "ds"}`. `/conclusions` echoes the active system in its response
and emits `{bel, pl, ignorance}` payloads under DS.

## Project Structure

```
# --- neomycin layer (the fork's own code) ---
neomycin.asd          — :neomycin system (rulebase + therapy); depends on lisa, lisa-bridge
neomycin.lisp         — convenience loader: loads :neomycin and starts the bridge
neomycin/
  rulebase.lisp       — THE canonical MYCIN rulebase: 19 rules (15 confirming + 1 tier-1
                        organism-class chain rule + 3 disconfirming), keyword vocabulary,
                        culture-1/1a/2/3 demo drivers
  therapy/            — therapy-recommendation phase (own :neomycin-therapy package, nick :therapy)
    package.lisp      — package definition + exports
    protocol.lisp     — pluggable solver protocol, recommendation structs, policy dials
    kb.lisp           — therapy KB abstraction (drugs / sensitivities / contraindications /
                        antibiogram counts) + kb-susceptibility (applies the overlay)
    authoring.lisp    — def* macros (defdrug / defsensitivity / defcontraindication / defantibiogram)
    knowledge-base.lisp — canonical schematic KB (belief-valued susceptibilities)
    antibiogram.lisp  — counts→interval (IDM) + Bayesian combine-susceptibility
    antibiogram-data.lisp — schematic site-local counts; OPT-IN, NOT loaded by default
    stub-solver.lisp / greedy-solver.lisp — solvers (greedy weighted set-cover)
    bridge.lisp       — /recommend-therapy handler + recommendation→JSON (with provenance)
  test/               — neomycin/test system: therapy + antibiogram tests + repointed goldens
  clinician-samples/  — saved driver transcripts
docs/                 — design docs, runbook, clinician scenarios, therapy demo

# --- Lisa substrate (used as-is; engine intentionally not renamed) ---
lisa.asd              — Lisa core (depends on log4cl)
lisa-bridge.asd       — Bridge system (depends on lisa, hunchentoot, jzon, bordeaux-threads)
src/
  core/               — Rete engine, rules, facts, conflict resolution
  belief-systems/     — Pluggable belief-system protocol
    protocol.lisp     — Generic function surface + dispatcher + use-system
    certainty-factors/— Shortliffe-Buchanan CF implementation
    dempster-shafer/  — [Bel, Pl] intervals + ds-combine (Dempster's rule)
  rete/reference/     — Rete network nodes and compiler
  llm/bridge/         — identification HTTP bridge (:lisa-bridge package)
    session.lisp      — Entity registry, session reset
    server.lisp       — Hunchentoot start/stop; LISA_BELIEF_SYSTEM env var
    handlers.lisp     — REST endpoints (belief-system-aware)
  llm/claude/         — Claude tool-use integration
    driver.py         — Python client: tool-call loop; transcript capture
    tools.json        — Tool schemas (assert_fact, run_inference, recommend_therapy, …)
    system-prompt.md  — clinical system prompt (identification + therapy/antibiogram narration)
examples/
  mycin.lisp          — Lisa-proper MYCIN example; NOT neomycin's rulebase (unused by neomycin)
bin/
  test-culture-1.sh   — end-to-end identification bridge test (curl); run-mycin.sh is a legacy alias
  test-therapy.sh     — end-to-end therapy bridge test (curl)
```

## Bridge Endpoints (port 8090)

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/health` | GET | Health check |
| `/assert-fact` | POST | Assert a fact: `{fact_type, value, entity?, entity_class?, confidence?}` |
| `/run-inference` | POST | Fire rules (captures rule trace) |
| `/conclusions` | GET | Get organism-identity results + belief factors |
| `/rule-trace` | GET | Get which rules fired last run |
| `/partial-matches` | GET | Rules one fact from firing (goal-directed dialogue) |
| `/recommend-therapy` | POST | Therapy regimen over the canonical KB (optionally overlaid with a site-local antibiogram): `{patient?, solver?, gate?}` → regimen with belief-valued (`{bel, pl, ignorance}`) susceptibilities, each carrying provenance (`source`, `n_tested`) |
| `/reset` | POST | Clear working memory and entity registry |

## Testing the Bridge

```bash
# Start the bridge first (see Build & Load above), then:
./bin/test-culture-1.sh     # identification: culture-1 → pseudomonas + enterobacteriaceae
./bin/test-therapy.sh       # therapy: culture-1 → a covering regimen with belief-valued susceptibilities
```

Expected (identification): culture-1 produces pseudomonas (0.6) and enterobacteriaceae (0.8).

## Running the Test Suite

Two dependency-free suites (golden-master + belief-algebra, no external framework):

- **`neomycin/test`** — neomycin's suite (`neomycin/test/`). Its `setup.lisp` repoints the
  shared LISA-TEST harness at `neomycin/rulebase.lisp` and adds the therapy + antibiogram
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

Coverage (~310 assertions / 93 tests): both belief algebras (CF and DS) directly; all four
`culture-*` scenarios under each system (against neomycin's rulebase) with hand-verified
golden values; DS clamp / total-conflict / malformed-input edge cases; **each of the 18
rules fired in isolation**; the therapy solver (greedy set-cover, coverage gating,
contraindications, belief-valued susceptibilities); and the **antibiogram overlay** (IDM
counts→interval, Bayesian combination under both algebras, JSON provenance). If a belief
computation changes intentionally, re-capture and update the goldens in `tests/scenarios.lisp`.

## Key Packages

- `lisa` / `lisa-user` — Core engine and user-facing DSL (defrule, assert, run, reset)
- `belief` (nickname for `lisa.belief`) — pluggable belief protocol: CF and DS systems,
  `belief-factor`, `combine-beliefs` / `ds-combine`, `normalize-belief`, `ds-belief` accessors
- `lisa-bridge` — identification HTTP bridge (start, stop, reset-session)
- `neomycin-therapy` (nickname `therapy`) — therapy phase: solver protocol, KB abstraction,
  `def*` authoring, the antibiogram overlay, and the `/recommend-therapy` glue

## LLM Integration Status

Identification and therapy both run end to end:

- **Phase 1 — HTTP Bridge**: Hunchentoot server exposing the inference engine as REST endpoints (assert-fact, run-inference, conclusions, rule-trace, partial-matches, reset) plus the therapy endpoint (recommend-therapy). Belief-system-aware: startup-configurable via `LISA_BELIEF_SYSTEM` and per-session overridable via `/reset`.
- **Phase 2 — Claude Tool-Use**: Python driver (`src/llm/claude/driver.py`) running a tool-call dispatch loop between Claude and the bridge. Tool schemas for all endpoints (assert_fact, run_inference, get_conclusions, …, recommend_therapy), a system prompt with the MYCIN clinical ontology (19 rules), uncertainty-mapping **and** therapy/antibiogram narration guidelines, goal-directed dialogue via `/partial-matches`, and session transcript capture.
- **Therapy phase**: a deterministic greedy weighted set-cover solver (`neomycin/therapy/`) picks a minimal covering regimen over the schematic KB, honoring contraindications and the coverage gate; susceptibilities are belief-valued and optionally refined by an opt-in site-local **antibiogram overlay**. The LLM requests and narrates a regimen via `recommend_therapy` but never chooses a drug.

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