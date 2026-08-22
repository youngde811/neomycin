# Clinician sample transcripts

Saved end-to-end driver sessions (Claude ↔ bridge), kept as illustrative captures
of the identification + therapy narration. They are **verbatim records of real runs
on the dates shown**, not living documentation — the output is preserved as captured
rather than re-synced, so an older one can lag the current rulebase.

> **⚠️ Every transcript here that recommends therapy predates v0.8.0, and its therapy
> narration is superseded.** Each calls a single broad-spectrum agent the
> *"stewardship-optimal"* answer. That was wrong: the solver optimised drug **count**
> and had no notion of spectrum, so "fewest drugs" was never "narrowest drugs"
> (`docs/exact-solver-design.md` §1) — and in a later session that same reasoning
> produced a false statement to a clinician (§1.1). The files carry the same warning
> inline and are **left exactly as captured**, because they are evidence of what the
> system said and editing them would falsify it. Treat the therapy passages as
> specimens, not as models to imitate. The identification and DS-narration passages
> are unaffected, and are what these captures are kept for.
>
> For current therapy narration — including the `objective` dial and the
> `alternative_agents` reporting that closes §1.1 — see `docs/clinician-scenarios.md`
> Scenario 15 and `docs/runbook.md` demo 6.

> **⚠️ Every transcript below `v011-burn-icu-release-check.md` predates v0.11.0**
> (2026-08-18), which replaced the representation wholesale. They narrate **negative
> beliefs**, **ruling-out rules** and an **organism-class** — none of which the corpus
> still has. A rule that "argues against" something at −0.75 is not a thing that can
> happen now: a rule states the SET its evidence narrows to, and exclusion is what
> remains after intersecting. Read them as records of what the system said on the date
> shown, not as descriptions of how it works. The same applies as for therapy above —
> they are specimens, kept because editing them would falsify the record.

## Current

- **`v011-burn-icu-release-check.md`** (2026-08-22) — the burn-ICU case under v0.11
  candidate sets, run as the **release check** and checked figure-by-figure against
  independently computed goldens (the table is in the file). Shows the three
  narrations the 2026-08-18 audit added: `conflict` read together with `margin` (a
  high K with a wide margin is a decisive overrule, not an unstable tie), a
  below-threshold organism reported *with* the coverage it still gets, and a
  negative-polarity bench reading that now fires a rule. It also caught a live
  defect on its first run — `?premises=` could not be queried by parameter name, and
  the model consequently made a false statement about the corpus to a clinician.
  The best current example of what the narration should look like.


- **`strep-hemolysis-conflict-rule-catalogue.md`** (2026-08-11) — a respiratory
  gram-positive case where the bench reading **contradicts** the clinical site: the
  respiratory site refines S. pneumoniae off the streptococcus class, then beta
  hemolysis fires `beta-hemolysis-argues-against-non-beta-streptococci` (−0.75) and
  pulls it to **[0.216, 0.412]** while S. pyogenes sits at 0.595 with plausibility
  still 1.0. Claude reports **both bounds** and says plainly that pneumococcus is *not
  ruled out*, only capped — the narration this corpus exists to make possible. The
  follow-up (*"which single test best discriminates within the streptococci, and how
  heavily does the system weight it?"*) exercises the **rule catalogue**: Claude calls
  `describe_rules` with `cluster=streptococcus` and answers with exact rule beliefs and
  the provenance *rationale* — "only 0.70 because groups C/G are also
  bacitracin-resistant" — read from the compiled rulebase rather than recalled. The
  first sample recorded after the system prompt stopped carrying a copy of the corpus.

- **`why-how-klebsiella-explanation.md`** (2026-08-03) — a burn / immunocompromised
  case yielding Pseudomonas + Klebsiella, then a *"why Klebsiella, and how confident?"*
  follow-up that exercises the **WHY/HOW facility**: Claude answers from the engine's
  authoritative derivation (`explain_conclusion` → `/why`), quoting the composition
  arithmetic (`0.800 (class) composed with the 0.500 rule = 0.400`), walking the
  chain into the organism-class, citing the verified NCBI sources, and stating plainly
  that the certainty numbers are *illustrative* (the citations verify the association,
  not the value). Ends with a therapy recommendation under a carbapenem allergy.
  Reflects the post-C2 rulebase and the provenance facility.

## Historical (pre-C2 captures)

> **⚠️ These predate the enterobacteriaceae *chained cluster*** and are kept for the
> DS-narration / antibiogram illustrations only. Since they were recorded:
>
> - Klebsiella/Salmonella are now refined from a derived `organism-class`, so their
>   belief composes through the family (e.g. Klebsiella 0.50 → 0.40).
> - **Enterobacteriaceae is no longer a leaf identity (slice C2)** — it is that
>   `organism-class`. The `aerobic-gram-neg-rod-suggests-enterobacteriaceae` rule
>   these transcripts show firing has been **retired** in favor of the `-class` rule,
>   and "Enterobacteriaceae" no longer appears as a `/conclusions` identity (it reaches
>   therapy as a species, or as a family *backstop* when no species clears the gate).
>
> For current, verified values and the up-to-date rule set, see
> `docs/clinician-scenarios.md` and `neomycin/rules/`.

- `burn-patient-gram-flip-ds-collapse.md`
- `neutropenic-line-sepsis-antibiogram-overlay.md`
- `session-20260725-202820.md`