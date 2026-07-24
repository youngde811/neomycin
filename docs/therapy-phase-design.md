# Therapy-recommendation phase — design

> ## ⚠️ NOT FOR CLINICAL USE
> neomycin is a research artifact. Every drug, sensitivity, dose, and
> contraindication mentioned in this document is **illustrative and schematic**,
> chosen to exercise the algorithm — it is **not** clinically authoritative and
> must never be used to make a treatment decision for any human or animal. Real
> pharmacology data would have to be sourced and vetted (see §6).

Status: **design draft** (`feature/therapy-phase`). No implementation yet.

---

## Motivation — why bacterial therapy, and why now

A recurring framing (e.g. the 2020 Forbes retrospective on MYCIN) is that AI's
attention in infectious disease has moved "from bacteria to viruses." That is a
false either/or. Bacteria did not become less dangerous — many of our *drugs*
did. **Antimicrobial resistance (AMR)** makes automated reasoning about bacterial
therapy *more* pressing than in MYCIN's era, not a solved problem to leave behind.

Three facts drive this:

- **AMR is a top-tier, rising global health threat** — the WHO ranks it among the
  leading global public-health threats — fuelled by exactly the over-broad,
  over-long antibiotic use that disciplined *selection* is meant to prevent.
  (Specific epidemiological figures — attributable mortality, forward projections
  — should be sourced and vetted per this document's own data discipline, not
  asserted from memory.)
- **The pathogen landscape keeps changing** — new organisms, re-surfacing old
  ones, shifting resistance — faster than any hand-maintained knowledge base can
  track. That *is* the staleness failure that retired MYCIN.
- **Bacterial and viral threats must be monitored in parallel.** Concentrating the
  field's attention on one while the other quietly worsens is how resistance
  outruns the tooling.

Crucially, AMR is not motivation bolted on — it *shapes and validates* the design
that follows, in three concrete ways:

1. **Local resistance is a first-class entity, not an afterthought.** Resistance is
   local and time-varying: a *Pseudomonas* susceptibility in one ICU is not the
   one down the corridor. The site-local **antibiogram** overlay (§3.1) exists to
   fold current, place-specific resistance into selection — the very thing 1978
   MYCIN could not do.
2. **Minimality is stewardship.** The solver's objective — cover the significant
   organisms with the *fewest, narrowest* effective drugs (§4.3) — is not merely
   MYCIN fidelity; it is the modern **antimicrobial-stewardship** principle for
   slowing resistance. The optimisation target and the clinical goal coincide.
3. **A knowledge base that stays current is the whole point.** Keeping pace with
   emerging resistance and new agents is exactly what the versioned, human-vetted
   KB (principles #2 and #3) is for.

Scope honesty: neomycin is **not** a point-of-care clinical tool used on patients,
and will not become one. It aims instead to be a **research instrument** — a
sandbox in which physicians, researchers, and engineers can experiment with the
MYCIN rulebase, an LLM, solvers, dosing, and contraindications as a way to study
therapy reasoning under AMR. That distinction — a tool used *by* researchers to
experiment vs. a tool used *on* patients to decide — is the bright line we hold.
The design questions AMR forces — local resistance data, stewardship-as-
minimality, a knowledge base that can stay current — are the live ones for
infectious-disease tooling today; reconstructing MYCIN in that light is not a
period piece but a way to work current problems on a well-understood substrate.

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

- **Drug** — an antimicrobial agent: name, class, route, and a dosing model
  (simulated / best-guess for now; source-cited and marked non-clinical).
- **Sensitivity** — `(organism, drug) → susceptibility`, a **belief-valued**
  quantity read through the active belief system (an organism is *probably*
  sensitive) — never a boolean. *Decided:* belief-valued from the start, so the
  algebra flows end to end (evidence → identification → therapy).
- **Contraindication** — a constraint keyed on patient state (allergy, renal
  function, pregnancy, age) that excludes or down-weights a drug. The initial set
  will be *plausible but not clinically authoritative*.
- **Interaction** — a pairwise `(drug, drug)` relation that forbids or penalises
  co-prescribing; consumed by the solver as a combination constraint (§4.3).
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

*Decided:* the KB is authored as **`def*` forms**, not tables or a binary store.
The deciding axis is principle #3 — our update model is *LLM drafts a diff → human
vets it → it lands as a tracked commit* — which only works if the KB is
**reviewable in a diff**. `def*` text forms are; a sqlite/ndbm blob is opaque to
`git diff` and code review, breaking the exact property that makes human vetting
affordable. The "front-end tool to manipulate" a DB would need is precisely what
the LLM already is for text forms — and text forms *stay* reviewable, which a
DB-through-a-tool does not.

The `def*` macros populate a **KB abstraction** (an in-memory structure behind an
accessor API) that the solver queries, so the authoring surface and the storage
are decoupled: if we ever need a different backing store for scale, we swap the
loader, not the solver and not the format. This keeps the KB (a) reviewable as a
diff, (b) unit-testable in isolation, and (c) replaceable by a vetted update or a
local antibiogram without touching the solver — principles #2 and #3 made concrete.

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

- **DS:** cover every organism whose **plausibility ≥ `*coverage-threshold*`** (a
  hypothesis that cannot be plausibly ruled out must be covered). Use **belief** as
  the preference weight when choosing among drugs.
- **CF:** cover every organism whose **CF ≥ `*coverage-threshold*`**.

`*coverage-threshold*` is a **stewardship policy dial**, not a clinical constant:
conservative (low) covers more, aggressive stewardship (high) covers narrower. It
is belief-system-agnostic — the solver asks the active system for each organism's
factor and compares — and per-session tunable (§4.5). We ship a defensible default
and expose it; we do not dress it as literature-sourced.

### 4.3 Phase B — minimal regimen (weighted set cover)

**Set-cover formulation.** This step *is* set cover. The **universe** is the
items-to-treat `U` (§4.2); each non-contraindicated drug `d` contributes the
**set** `S_d` of organisms it covers (susceptibility ≥ `*susceptibility-threshold*`);
the **goal** is the fewest drugs whose union is `U` (minimality = MYCIN's ≤ 2–3-drug
preference = stewardship). Inputs: the gated conclusions (→ `U`), the KB
(sensitivities → the `S_d`, contraindications → the candidate filter, interactions
→ a constraint, dosing → output), and patient state.

**Complexity — the problem is NP-hard, the algorithm is not.** Minimum set cover
is NP-hard to solve *exactly*; the **greedy** algorithm instead runs in polynomial
time and *approximates* it, returning a cover at most `H(n) ≈ ln n + 1` times
optimal (n = |U|), with no poly-time algorithm beating `~ln n` unless NP is easier
than believed (Feige 1998). At our scale this gap is moot: a consultation has ~1–4
organisms, so even an exact minimum cover is trivially cheap. We start with greedy
not to dodge intractability but for **explainability** — each pick carries a
one-line justification the LLM narrates verbatim, and the step-by-step trace *is*
the audit. An exact solver is a drop-in second implementation behind the same
protocol (§4.5), and would double as a correctness oracle for greedy.

Choose the drugs by greedy weighted set cover:

1. **Candidate filter** — drop any drug excluded by a firing contraindication.
2. **Coverage** — a drug *covers* an organism if its susceptibility clears
   `*susceptibility-threshold*`.
3. **Greedy weighted set cover** — repeatedly pick the drug covering the most
   still-uncovered organisms, breaking ties by summed susceptibility × organism
   belief; stop when all items are covered. Prefer fewer drugs (MYCIN targeted
   ≤ 2–3). Greedy set cover is the natural, explainable algorithm here; exactness
   is not worth the opacity for a handful of organisms.
4. **Interaction check** — as each drug is added, reject (or penalise) it if it
   forms a forbidden pair with a drug already chosen (§3.1 Interaction). This makes
   the cover *combination-aware*, not just per-drug — the one place the algorithm
   grows beyond textbook set cover.
5. **Dosing** — attach a dose per selected drug from its dosing model, adjusted by
   patient parameters (weight, renal function). Simulated for now.

### 4.4 Output — an auditable recommendation object

```
{ regimen: [ { drug, dose, covers: [organisms], susceptibility } ],
  items_to_treat: [ { organism, belief } ],
  excluded: [ { drug, reason: contraindication | interaction } ],
  uncovered: [ organisms ] }   ; items no candidate drug could cover -- an honest
                               ; failure surfaced, never a silent partial cover
```

Every field is a fact the LLM can narrate and a reviewer can audit. Nothing is
inferred by the model.

### 4.5 The solver is pluggable (a protocol)

*Decided:* the solver lives in a new `neomycin-therapy` package and is reached
through a **protocol**, modelled directly on the existing belief-system protocol
(`belief:use-system` and the generic surface in `src/belief-systems/protocol.lisp`).
Define a small generic-function surface — e.g. `solve-regimen (conclusions kb
patient)` returning a recommendation object (§4.4) — plus a registry and a
`use-solver` selector. Greedy weighted set cover is the first implementation; an
exact/ILP solver, or an LLM-assisted proposer that still returns an auditable
object, can be registered and swapped later **without touching the bridge, the KB,
or the identification engine**. The same design that already lets CF and DS
coexist, applied to therapy — and the reason the thresholds are per-session
tunable rides naturally on top of it.

## 5. Decision #3 — belief gating (summary)

Belief enters therapy in two places, both above: **`*coverage-threshold*`** decides
*which* organisms must be treated (plausibility under DS — you must cover what you
cannot rule out), and **belief-weighted tie-breaking** decides *which* drug when several
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
- **Belief-gating tests** — `*coverage-threshold*` boundary behaviour; a low-
  plausibility organism dropped from items-to-treat; a wide DS interval broadening
  coverage.
- **Contraindication tests** — an allergy excludes the otherwise-preferred drug
  and forces an alternative.
- **Interaction tests** — a forbidden pair blocks a co-prescription and forces a
  different covering set.
- **Multi-organism test** — two organisms needing different drugs yield a
  covering set; two sharing a drug yield one drug (minimality).
- **Protocol test** — a second (stub) solver registered via `use-solver` is
  selected and returns a well-formed recommendation object.

## 9. Scope and non-goals

- **In:** organism → regimen selection; belief-valued sensitivities;
  contraindications; **drug–drug interactions**; belief gating; **simulated /
  best-guess dosing**; a pluggable solver protocol; an auditable recommendation
  object; the bridge endpoint + tool; golden tests. Pharmacology data is best-guess
  from citable internet sources, **source-cited and marked non-clinical** — enough
  to exercise the algorithm honestly.
- **Out (for now):** full dosing pharmacokinetics; the live LLM KB-update workflow
  (the KB *shape* supports it, but we don't build the loop yet); EHR/FHIR
  integration.
- **Never:** point-of-care clinical decision-making on real patients; autonomous
  KB modification; LLM-chosen drugs.

## 10. Resolved decisions

*(Were open questions; settled 2026-07-15.)*

1. **KB form:** `def*` forms — decided on diff-reviewability (principle #3), not
   tables and not a binary store. The macros populate a KB abstraction so the
   backing storage stays swappable (§3.2).
2. **Thresholds:** `*coverage-threshold*` and `*susceptibility-threshold*` (renamed
   from θ_cover / θ_cover-drug for clarity). Per-session tunable, like the belief
   system; shipped with defensible defaults. Named honestly as stewardship policy
   dials, not literature constants (§4.2).
3. **Sensitivities:** belief-valued from the start — done right the first time, so
   the belief algebra runs end to end (§3.1).
4. **Solver location:** a new `neomycin-therapy` package behind a pluggable solver
   protocol modelled on the belief-system protocol; implementations swap without
   touching other code (§4.5).
5. **Vocabulary — keywords end to end** *(settled 2026-07-16).* Organism, drug,
   class, route, and contraindication-trigger identifiers are **keywords**, not
   plain symbols (a deviation from the illustrative symbol syntax shown in §3.2).
   Rationale: the organism vocabulary crosses the engine → conclusions → bridge
   (JSON) → therapy boundary and must be one shared object in every package;
   keywords are the package-independent, JSON-friendly answer with no
   import/export bookkeeping as the rule corpus scales. Chosen over a dedicated
   exported-symbol ontology package (more moving parts, no behavioural gain for
   inert tags) and over a boundary conversion seam. Consequently the **engine was
   migrated** to keyword `organism-identity` values (`(value :pseudomonas)`) and
   keyword ruling-out guards; the change is behaviour-preserving (the golden
   suite keys conclusions by `string-downcase`d `symbol-name`, identical for
   symbol and keyword, and stayed green). *Finding*-value vocabulary
   (`pos`/`neg`/`aerobic`, asserted via the bridge) was left as `:lisa-user`
   symbols — it never crosses into therapy. An authoritative organism registry
   (keyword → metadata) remains available as a later data-as-registry option.