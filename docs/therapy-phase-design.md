# Therapy-recommendation phase — design

> ## ⚠️ NOT FOR CLINICAL USE
> neomycin is a research artifact. Every drug, sensitivity, dose, and
> contraindication mentioned in this document is **illustrative and schematic**,
> chosen to exercise the algorithm — it is **not** clinically authoritative and
> must never be used to make a treatment decision for any human or animal. Real
> pharmacology data would have to be sourced and vetted (see §6).

Status: **design draft** (`feature/therapy-phase`). No implementation yet.

---

## 1. Context and the gap

neomycin's identification phase is complete: forward-chaining rules over the
Lisa Rete engine map clinical evidence to `organism-identity` hypotheses, each
carrying a belief (CF number or DS `[Bel, Pl]` interval), scoped to an organism
in the patient → culture → organism context tree.

Therapy is a **different kind of reasoning**. MYCIN itself was two systems bolted
together: rule-based *identification*, then an **algorithmic** *therapy
selection* — a constraint-respecting optimisation, not a production-rule
fixpoint. "Pick the smallest drug regimen that covers the likely organisms,
subject to sensitivities and patient contraindications" has no natural expression
as forward-chaining rules; minimality is not something Rete converges to. So we
follow MYCIN's own architecture and make therapy a distinct phase.

## 2. Design principles

These fell out of a discussion of Buchanan & Shortliffe's 1984 retrospective on
why MYCIN was never deployed (liability/acceptability, workflow integration,
knowledge staleness). Each principle answers one of their concerns.

1. **The deterministic core decides and records; the LLM proposes and narrates.**
   Drug selection is a deterministic, auditable function. The LLM never chooses a
   drug — it gathers evidence, asks questions, and explains the recommendation.
   This is the *liability* answer: every regimen traces to specific organisms,
   sensitivities, and constraints. (Addresses B&S #1, acceptability.)

2. **Therapy knowledge is versioned data, outside the model's correctness path.**
   Drugs, sensitivities, contraindications, dosing, and the local antibiogram are
   declarative data — diffable, testable, `git`-tracked — not baked into rules.
   MYCIN went stale because sensitivities lived in opaque CF rules; data does not
   have that problem. (Addresses B&S #3, staleness — and lets a site drop in its
   own antibiogram, which 1978 MYCIN could not.)

3. **KB updates are LLM-drafted, human-vetted, source-cited — never autonomous.**
   The knowledge-acquisition bottleneck that capped 1980s expert systems is
   dissolved by moving the human from *author* to *editor*: the LLM drafts a
   sourced diff against the KB; a human reviews, corrects, and approves before it
   goes live. The human and the vetting stay; only the cost-per-update falls.

The through-line: **the LLM proposes and narrates; the deterministic, versioned
core decides and records.**

## 3. Decision #1 — Knowledge representation (KB as data)

A new, self-contained knowledge base, kept apart from the identification rulebase.
Everything below is *data*, loadable and replaceable.

### 3.1 Entities

- **Drug** — an antimicrobial agent: name, class, default dosing model, route.
- **Sensitivity** — `(organism, drug) → susceptibility`. Under DS this is itself a
  belief/interval (an organism is *probably* sensitive), not a boolean; this is
  where the belief algebra extends naturally into therapy.
- **Contraindication** — a constraint keyed on patient state (allergy, renal
  function, pregnancy, age) that excludes or down-weights a drug.
- **Antibiogram** — a site-local overlay adjusting susceptibilities to reflect
  local resistance patterns. Optional; overrides the base sensitivity table.

### 3.2 Shape (schematic — values illustrative only)

```lisp
;; therapy-kb.lisp  (data, not rules)
(defdrug ceftazidime   :class cephalosporin-3 :route iv)
(defdrug vancomycin    :class glycopeptide    :route iv)

;; (organism drug susceptibility)  -- susceptibility read by the active belief system
(defsensitivity pseudomonas        ceftazidime 0.9)
(defsensitivity enterobacteriaceae ceftazidime 0.8)
(defsensitivity staphylococcus     vancomycin  0.95)

(defcontraindication ceftazidime :when (allergy cephalosporin))
```

Representing the KB as `def*` forms (or plain tables) keeps it (a) reviewable as a
diff, (b) unit-testable in isolation, and (c) replaceable by a vetted update or a
local antibiogram without touching the solver. This is principle #2 made concrete.

## 4. Decision #2 — The selection algorithm (external Lisp solver, approach B)

After `run` produces the identification conclusions, a solver reads them and
returns a regimen. It mirrors MYCIN's two sub-phases.

### 4.1 Inputs

- The set of `organism-identity` facts, grouped by organism (via the `of` context
  id), each with its combined belief.
- Patient-level facts relevant to contraindications (allergy, renal function, …).
- The therapy KB (§3), including any active antibiogram overlay.

### 4.2 Phase A — items to treat (belief gating; Decision #3)

Select the organisms significant enough to warrant coverage:

- **DS:** cover every organism whose **plausibility ≥ θ_cover** (a hypothesis that
  cannot be plausibly ruled out must be covered). Use **belief** as the preference
  weight when choosing among drugs.
- **CF:** cover every organism whose **CF ≥ θ_cover**.

θ_cover is a tunable parameter, not a magic constant; it is where the belief
algebra directly shapes therapy. Belief-system-agnostic: the solver asks the
active system for each organism's factor and compares against the threshold.

### 4.3 Phase B — minimal regimen (weighted set cover)

Choose a small set of drugs covering all items-to-treat:

1. **Candidate filter** — drop any drug excluded by a firing contraindication.
2. **Coverage** — a drug *covers* an organism if its susceptibility clears a
   threshold θ_cover-drug.
3. **Greedy weighted set cover** — repeatedly pick the drug covering the most
   still-uncovered organisms, breaking ties by summed susceptibility × organism
   belief; stop when all items are covered. Prefer fewer drugs (MYCIN targeted
   ≤ 2–3). Greedy set cover is the natural, explainable algorithm here; exactness
   is not worth the opacity for a handful of organisms.
4. **Dosing** — attach a dose per selected drug from its dosing model, adjusted by
   patient parameters (weight, renal function). Schematic for now.

### 4.4 Output — an auditable recommendation object

```
{ regimen: [ { drug, dose, covers: [organisms], susceptibility } ],
  items_to_treat: [ { organism, belief } ],
  excluded: [ { drug, reason: contraindication } ] }
```

Every field is a fact the LLM can narrate and a reviewer can audit. Nothing is
inferred by the model.

## 5. Decision #3 — belief gating (summary)

Belief enters therapy in two places, both above: **θ_cover** decides *which*
organisms must be treated (plausibility under DS — you must cover what you cannot
rule out), and **belief-weighted tie-breaking** decides *which* drug when several
cover the same set. This is the natural extension of the identification belief
algebra into treatment, and a place DS's ignorance interval says something CF
cannot (a wide `[Bel, Pl]` argues for broader coverage).

## 6. The narration and update layers (LLM; approach C + principle #3)

- **Narration.** The bridge exposes the recommendation object; the LLM explains
  *why this regimen* — which organisms drove it, which drugs were excluded and on
  what contraindication — and handles the clinician dialogue. It never invents a
  drug: it reads the deterministic result.
- **KB curation (principle #3).** A separate, human-in-the-loop workflow: the LLM
  drafts a **sourced diff** against the therapy KB (e.g. "add cefepime, sensitivity
  to pseudomonas per <cited source>"); a human engineer/clinician reviews and
  approves; the change lands as a normal, tested, version-controlled commit. Never
  an autonomous write to the live KB. (Out of scope for the first implementation;
  noted here so the KB shape stays diff-friendly.)

## 7. Bridge / API surface

- New endpoint **`POST /recommend-therapy`** — runs the solver over current
  conclusions, returns the recommendation object (§4.4).
- New driver tool **`recommend_therapy`** — thin wrapper the LLM calls after
  `run_inference` / `get_conclusions`.
- No change to the identification endpoints.

## 8. Testing

- **KB unit tests** — sensitivities/contraindications load and query correctly.
- **Solver golden tests** — over the existing `culture-*` scenarios: given their
  known organism sets and beliefs, assert the selected regimen (deterministic, so
  golden-able) under both CF and DS. Reuse the dependency-free harness.
- **Belief-gating tests** — θ_cover boundary behaviour; a low-plausibility
  organism dropped from items-to-treat; a wide DS interval broadening coverage.
- **Contraindication tests** — an allergy excludes the otherwise-preferred drug
  and forces an alternative.
- **Multi-organism test** — two organisms needing different drugs yield a
  covering set; two sharing a drug yield one drug (minimality).

## 9. Scope and non-goals

- **In:** organism → regimen selection, contraindications, belief gating, an
  auditable recommendation object, the bridge endpoint + tool, golden tests.
- **Out (for now):** realistic pharmacology data (schematic only), full dosing
  pharmacokinetics, drug–drug interactions, the live KB-update workflow, EHR/FHIR
  integration.
- **Never:** clinical use; autonomous KB modification; LLM-chosen drugs.

## 10. Open questions

1. `def*` macros vs. plain tables vs. an external data file for the KB — which is
   most diff- and test-friendly?
2. Default θ_cover / θ_cover-drug values, and whether they are per-session tunable
   like the belief system is.
3. Do sensitivities themselves combine through the belief system (an organism is
   *probably* sensitive), or start boolean and add belief later?
4. Does the solver live in a new `neomycin` package/system, or alongside the
   bridge?