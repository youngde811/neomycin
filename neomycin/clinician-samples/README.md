# Clinician sample transcripts

Saved end-to-end driver sessions (Claude ↔ bridge), kept as illustrative captures
of the identification + therapy narration. They are **historical records of real
runs on the dates shown**, not living documentation — the output is preserved
verbatim rather than re-synced, so it can lag the current rulebase.

> **⚠️ Pre-chaining / pre-C2 captures.** These sessions predate the enterobacteriaceae
> *chained cluster*. Since they were recorded:
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
> `docs/clinician-scenarios.md` and `neomycin/rulebase.lisp`.