# Frequency-grounded identification beliefs — design & slice plan

> **📦 ATTIC — historical record.** Deferred at v0.11 and never implemented; the branch was deleted. Retained for the argument, not as a plan.

> ## ⏸️ Status: DEFERRED (2026-08-11). Design retained; implementation retired.
>
> The `feature/ds-grounded-beliefs` branch was **deleted** in favour of other work.
> This document is kept on `develop` because the analysis below — particularly the
> LIGHT/FULL staging and the §8 protocol-surgery cost — is the expensive part and
> should not have to be redone.
>
> **What the retired branch had reached** (three commits, green at 530 assertions /
> 126 tests, all pre-v0.6.0):
>
> - Slice 0: this design doc.
> - Slice A: a `grounded` helper computing `s/(n+σ)`, applied to the single rule
>   red-pigment → Serratia, with `:belief-basis :frequency-derived` and a
>   `:grounding {susceptible, tested, sigma, source}` provenance block.
>
> **The one finding worth carrying forward.** Grounding that rule exposed that its
> illustrative `0.75` encoded the *wrong conditional* — it was reading as
> P(pigment | Serratia), the test's sensitivity, when the rule actually needs
> P(Serratia | pigment). The grounded figure came out materially higher (~0.90). That
> is a *correctness* argument for grounding, independent of the uncertainty-width
> argument this document is built around, and it may well apply to other illustrative
> beliefs in the corpus. Worth auditing for on its own.
>
> **Do not replay the branch.** It predates v0.6.0, which split `neomycin/rulebase.lisp`
> into `neomycin/rules/`, took the corpus to 50 rules and the suite to 858/152, and
> added corpus-wide property tests. Any revival is a fresh implementation against the
> current tree, not a rebase: the helper belongs in `rules/context.lisp`, the rule edits
> in `rules/chain-enterobacteriaceae.lisp` and `rules/disconfirming.lisp`, and every
> golden needs re-deriving from the engine.
>
> Original status line follows.

> Status: **IN PROGRESS (staged, LIGHT track).** Opens the feature (branch
> `feature/ds-grounded-beliefs`). Reopens, with a concrete need now in hand, the idea
> deferred in `docs/susceptibility-belief-design.md §8` ("Rules → native DS").
>
> **Review decisions (Q1–4, §8):** (1) **staged** — LIGHT now, FULL behind the Slice C
> gate; (2) first rule **red-pigment → Serratia**; (3) mechanism **authoring-time bake**
> (`:belief (grounded s n)`), so grounding a rule changes its number and re-captures its
> goldens — the swappable-overlay's "default corpus pristine" does NOT apply; (4) point
> estimate **s/(n+σ)** (IDM lower bound, σ=2), so LIGHT→FULL is additive.
>
> **⚠️ NOT FOR CLINICAL USE.** Any counts introduced here are schematic research
> artifacts, never real surveillance, and never a basis for prescribing.

## 1. Why (the gap, made vivid by the demo)

Every identification rule belief is `:belief-basis :illustrative` — a schematic
teaching figure, not a measured quantity. That honesty is a *feature*: in the demo
dry-run the LLM, reading provenance off the engine, said the quiet part out loud —

> *"Those rule weights are schematic teaching values, not measured probabilities …
> the precise figure should be read as 'strongly suggestive under this schematic
> scoring,' not a calibrated probability."*

That is the right thing to say **when the number is illustrative**. The question this
increment opens: for the rules where a defensible frequency *could* ground the number,
can we make the belief mean *"the observed conditional frequency of this identity given
this finding, with the sample size legible,"* — and let the honesty line shift from
"illustrative" to "grounded in N observations" exactly where that's true, and nowhere
else? The therapy side already does this for susceptibilities (the antibiogram). The
identification side has no equivalent. Closing that is squarely on the fork's
DS-legibility thesis.

## 2. What already exists (the substrate)

- **The IDM primitive.** `counts->interval` (`neomycin/therapy/antibiogram.lisp:63`)
  maps `(susceptible, tested)` to a belief interval `[s/(n+σ), (s+σ)/(n+σ)]` whose
  **ignorance `σ/(n+σ)` shrinks as n grows** — few observations read as provisional
  (wide), many as solid (narrow). This is precisely a frequency-with-sample-size
  reduction, and it is belief-system-agnostic arithmetic over `ds-belief` bounds.
- **The opt-in schematic-data pattern.** `antibiogram-data.lisp` is a separate,
  swappable file of *invented* counts, **not loaded by default**, replaceable without
  touching the curated KB, stamped NOT FOR CLINICAL USE. The grounded-identification
  data should mirror this exactly.
- **The fact-level belief pipeline is already interval-capable.** `ds-belief` struct,
  `normalize-belief`'s `ds-belief` passthrough, `combine-beliefs`/`conjoin-beliefs`,
  and the numeric-assert routing all handle intervals on *facts* today
  (`dempster-shafer.lisp`). What is **not** interval-ready is the *rule-belief* input
  (see §5).
- **The prior assessment.** `docs/susceptibility-belief-design.md §8` weighed giving rule
  beliefs native `[bel, pl]` values and marked it **deferred/conditional** — *"pursue
  only if a concrete expressiveness need emerges that disconfirming rules genuinely
  cannot meet."* This doc argues the need has emerged (sample-size-legible *grounding*,
  which disconfirming rules do not address at all) and costs the work precisely.

## 3. What "grounded" means — the semantics (pin this first)

A grounded belief is a **conditional frequency read directly from stratified counts**:
among organisms already in the enterobacteriaceae class that exhibit this marker
pattern, the fraction that are species X — `P(species | pattern, class)` — expressed
as an IDM interval via `counts->interval`. `susceptible` = # matching the pattern that
are species X; `tested` = # matching the pattern.

**Why this and not sensitivity/specificity → mass (the likelihood-ratio caution).**
The tempting error is to read a marker's *sensitivity* — `P(marker+ | species)`, e.g.
"95% of E. coli are indole+" — as the belief. It is not: that is the wrong conditional.
Turning `sens`/`spec` into a posterior belief requires a prior (prevalence in the
differential) and Bayes' rule, and the choice of prior reintroduces exactly the
arbitrariness we are trying to remove — it would be "illustrative" wearing a lab coat.
Reading the **posterior conditional frequency** off stratified counts sidesteps the
transform entirely: the number *is* the thing the rule concludes, and its width *is*
the sample size. The cost is that stratified counts are harder to source than published
sensitivities — for the illustrative corpus we invent them (schematic, §6), and we say
so. **Non-goal:** any `sens`/`spec` → mass mapping. If only `sens`/`spec` exist for a
marker, that rule stays `:illustrative`.

**Chained composition stays coherent.** A grounded species belief is *conditioned on
class membership*, and the class rule contributes `P(class)` (0.8). Their existing
multiplicative composition (`weaken-belief`) yields `P(class) · P(species | class,
pattern)` — the right joint — so grounding a species rule does not double-count the
class. No change to the composition law.

## 4. The CF-vs-DS asymmetry (why this is harder than the antibiogram)

The antibiogram was cheap because susceptibility uncertainty was **deliberately
decoupled** from the identification algebra (`docs/susceptibility-belief-design.md §4`,
decision C): a `ds-belief` susceptibility reduces by its own rule, **never** routed
through `belief:*belief-system*`. A grounded **identification** belief cannot be
decoupled — it *is* the diagnostic quantity, so it must flow through CF-vs-DS (that is
what makes the chained composition and the cross-disconfirmation conflict work, and
what the whole fork exists to compare). And CF has **no interval representation**:
`belief->number` errors on a `ds-belief` under CF — the exact trap decision C was built
to avoid. So a grounded belief that carries width is naturally **DS-native**, and any
full solution needs a deliberate, lossy **CF projection** (project the interval to its
point `bel`, i.e. `s/n`). This asymmetry is the crux of the light-vs-full choice.

## 5. Pivotal decision — LIGHT vs FULL grounding

### Option LIGHT — grounded scalar + honest provenance (no engine change)

Derive the rule's **scalar** belief as the IDM lower expectation **`s/(n+σ)`** (σ=2)
— the `bel` bound of `counts->interval`, chosen so LIGHT→FULL is *additive* (FULL only
reveals the upper bound; the committed belief does not jump) — and record the grounding
in a new provenance value `:belief-basis :frequency-derived` carrying `{susceptible,
tested, sigma, source}`. The scalar flows through the **existing** pipeline unchanged —
`normalize-belief`/`weaken-belief` map `s/(n+σ)` to `[s/(n+σ), 1.0]` under DS, compose
it with premises, and CF uses `s/(n+σ)` directly. (Implemented as `grounded` in
`neomycin/rulebase.lisp`; used at authoring time: `:belief (grounded 47 50)`.)

- **Cost:** corpus + provenance only. Zero engine change. No CF/DS break. Ships a
  defensible number and an honest, queryable "grounded in N observations, source …"
  that `/why` narrates instead of the illustrative disclaimer.
- **Limit:** the rule's own plausibility stays pinned at `1.0` (a confirming rule's
  ignorance is `1 − bel`). The **sample size is legible only in provenance, not in the
  belief interval itself** — a grounding from n=8 and one from n=800 produce the same
  `[s/n, 1.0]` if `s/n` matches. We get defensible *values*, not sample-size-legible
  *widths*, on the diagnostic side.

### Option FULL — interval-valued rule beliefs (the §8 engine-axis work)

Let a rule carry a native `[bel, pl]` (the IDM interval), so width — sample size — is
legible on the belief itself, meeting the antibiogram's legibility on the diagnostic
side. The engine map costs this precisely:

- **The one hard blocker:** the fire-time type dispatch at
  `belief-systems/protocol.lisp:93-98` admits only a `number` rule-belief to the
  composition arithmetic; a `ds-belief` falls to the `(rule-belief t)` method and is
  **silently dropped to nil**. Must be generalized.
- **Both `weaken-belief` methods** assume a scalar factor
  (`certainty-factors.lisp:53` `(* belief factor)`; `dempster-shafer.lisp:159`
  `coerce`/`minusp`). The **genuine design gap** is defining *how an interval rule
  belief composes with premise support* — not plumbing.
- **CF projection** (§4): under CF the interval must project to `s/n` (lossy but
  well-defined), preserving the duality.
- **What is already free:** storage (`rule.lisp:62`), parsing (`language.lisp:29`,
  `rule-parser.lisp:292`), and the `derivation-record` all pass the value through
  untyped — no change. This is a *contained* engine-axis change touching the belief
  protocol, not a broad substrate rewrite.

This is real engine-axis work, which `CLAUDE.md` explicitly licenses ("deepening
Dempster-Shafer support beneath the corpus layer … when it genuinely moves the
chains"). It is also exactly the work §8 deferred — so choosing FULL is a deliberate
reopening, not an accident.

### Recommendation — **staged: LIGHT now (Slice A/B), decide FULL after**

Do LIGHT first: it ships a defensible number and the `:frequency-derived` honesty
today, builds the opt-in data plumbing, and carries **zero** risk to the existing
goldens or the CF/DS duality. Then evaluate — with the plumbing and a real example in
hand — whether sample-size *width on the diagnostic side* is worth the §8 protocol
surgery, and pursue FULL only as a separately-scoped, separately-approved engine-axis
slice. This avoids committing to substrate changes sight-unseen while still delivering
the honest-grounding win the demo made vivid.

## 6. Data source — an opt-in grounded overlay

Mirror `antibiogram-data.lisp`: a **separate file, not loaded by default**, of invented
stratified counts `(marker-pattern → identity) → (n-species . n-pattern)`, replaceable
without touching the rulebase, stamped NOT FOR CLINICAL USE. Keeping it opt-in means
**the default corpus and all existing goldens are unchanged** — grounding becomes a
demonstrable *overlay* (illustrative-vs-grounded, and under LIGHT vs eventually FULL),
the same way the antibiogram overlays susceptibility. Open question below on the
mechanism (authoring-time helper vs post-load rule re-definition).

## 7. Slice plan (each green + committed separately)

- **Slice 0 — this doc.**
- **Slice A — LIGHT grounding, one rule, end to end. ✅ DONE.** Added the `grounded`
  helper (`s/(n+σ)`, σ=2) in `rulebase.lisp`; grounded **red-pigment → Serratia** from
  schematic stratified counts (47/50); added the `:belief-basis :frequency-derived`
  provenance value + `:grounding {susceptible, tested, sigma, source}`. Tests: `grounded`
  is the IDM lower expectation; the rule's baked-in belief equals `grounded(47,50)`; the
  provenance invariant now accepts `:frequency-derived` and validates `:grounding`. Because
  the mechanism is authoring-time bake, the Serratia goldens **re-captured** (compose
  0.60 → ≈0.7231; the red-pigment conflict CF 0.0 → 0.3077, DS [0.375,0.625] →
  [0.5109,0.7065]) — hand-verified, engine-confirmed. 530/126 green. (Grounding surfaced
  that the old illustrative 0.75 encoded the wrong conditional — `P(pigment|Serratia)`,
  sensitivity — for a rule that fires *on* pigment; the grounded `P(Serratia|pigment)`
  runs higher.) `/why` narration of the grounding is Slice B.
- **Slice B — LIGHT grounding, the biochemical cluster + narration.** Extend to the
  remaining groundable discriminators; teach `system-prompt.md` to narrate a grounded
  belief ("the observed frequency in N isolates", `s/(n+σ)`) distinctly from an
  illustrative one. **Docs re-capture from Slice A's Serratia change** (do not miss):
  `docs/clinician-scenarios.md` Scenario 9 (Serratia composed 0.60 → ≈0.7231; the
  cross-disconfirmation table Serratia [0.375,0.625] → [0.5109,0.7065]) and the
  **`docs/demo-runsheet.md` cheat-sheet** Serratia kicker row (bel 0.375 → 0.5109, pl 0.625 →
  0.7065; E. coli row unchanged; qualitative "both < pl 1.0 / E. coli falls further"
  still holds). The runsheet lives on `develop`, so this matters once the feature merges
  — before next month's demo.
- **Slice C — DECISION GATE on FULL.** Written evaluation (is diagnostic-side width
  worth the protocol change?); if yes, a scoped engine-axis design for interval-valued
  rule beliefs (generalize `protocol.lisp:93-98`; define interval-compose-with-premises
  in both `weaken-belief`s; CF projection; goldens). **Not** begun without explicit
  approval — this is the §8 reopening.

## 8. Open questions (for review)

1. **LIGHT-vs-FULL sequencing.** Staged (LIGHT now, FULL behind a decision gate) as
   recommended — or do you want to commit to FULL up front because sample-size width on
   the diagnostic side *is* the point and LIGHT-without-it feels half-done?
2. **Which rule to ground first (Slice A).** A biochemical discriminator is the natural
   pick (a stratified marker→species frequency is at least conceptually sourceable).
   Lactose/indole → E. coli, or the red-pigment → Serratia we just worked? (Lean:
   whichever has the cleanest "textbook" frequency to schematize.)
3. **Overlay mechanism.** Authoring-time (`:belief #.(grounded s n)` bakes the number
   into the rule at load) vs a post-load overlay that re-defines specific rules' beliefs
   (keeps the default corpus pristine, truer to the antibiogram's swappable model). Lean:
   the swappable overlay, but it is more mechanism — worth your call.
4. **σ for identification.** Reuse the antibiogram's `σ = 2` (Walley IDM default), or
   does the diagnostic side want its own concentration knob? (Only bites under FULL,
   where width is visible; noting it now.)

## 9. Scope & non-goals

- **In (this increment, LIGHT):** an opt-in grounded-data overlay; one→several
  biochemical rules grounded to `s/n`; `:frequency-derived` provenance + narration; the
  FULL decision gated behind Slice C. Default goldens untouched.
- **Out / deferred:** interval-valued rule beliefs (FULL / §8) unless Slice C approves;
  any `sens`/`spec` → mass mapping (§3, rejected as un-defensible); grounding the
  epidemiological *context* rules (burn → pseudomonas, etc.), whose per-rule frequency is
  far harder to source than a biochemical marker's — they stay `:illustrative`.
- **Always:** NOT FOR CLINICAL USE. Grounded intervals model schematic frequencies for
  research legibility; they are not real clinical statistics.

---

*Aside surfaced during the engine trace (not part of this increment): `copy-rule`
(`src/core/rule.lisp:199-214`) does not copy the `belief-factor` slot. Harmless if
`copy-rule` is unused on belief-bearing rules, but worth a look independently.*