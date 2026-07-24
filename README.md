# neomycin

**neomycin 0.1.0 (research preview) · built on the [Lisa](https://github.com/youngde811/Lisa) 4.2.0 engine**

> **Not the antibiotic.** The name is an homage to William Clancey's *NEOMYCIN*,
> his 1980s re-representation of MYCIN that separated diagnostic *strategy* from
> domain *knowledge*. That separation is this project's whole architecture.

> ## ⚠️ NOT FOR CLINICAL USE
> neomycin is a **research artifact** exploring uncertain reasoning and
> LLM-driven consultation over a historical rulebase. It is **not** a medical
> device, decision aid, or diagnostic tool. Do not use it to make health
> decisions for any human or animal. No warranty; see [LICENSE](LICENSE).

## What this is

A research reconstruction of Stanford's **MYCIN / EMYCIN** expert system, built
as **forward-chaining rules** over the Lisa Rete engine (following the rule
translation Norvig popularized in *PAIP*), with reasoning under uncertainty
carried by a **Dempster-Shafer** belief system — certainty factors are retained
alongside it purely so the two algebras can be *compared* on the same corpus.

The distinguishing bet, and the reason the LLM matters: classic MYCIN used
backward chaining largely to *drive the clinical interview* — deciding which
question to ask next. neomycin splits those roles:

| Role | Classic MYCIN | neomycin |
|------|---------------|----------|
| Diagnostic strategy / what to ask next | Backward chaining | **LLM** (via the bridge) |
| Domain knowledge + belief propagation | CF over a context tree | **Lisa/Rete + Dempster-Shafer** |

The engine stays a data-driven belief calculator; the LLM plays the goal-directed
role, using the bridge's `/partial-matches` endpoint to see which rules are one
fact away from firing — a forward-chaining reconstruction of "what's worth
asking next."

## Why Dempster-Shafer

Every hypothesis carries a `[Bel, Pl]` interval; the width `Pl − Bel` is
*explicit ignorance*. Disconfirming rules inject mass on `¬H`, so conflicting
evidence produces real Dempster conflict (`K > 0`) that lowers belief **and**
pulls plausibility below 1.0 — an ambiguous Gram stain becomes a visibly
widened, lowered interval instead of collapsing to a single number. CF cannot
express that; keeping both is what makes the comparison worth publishing.

## Status

Early, but both halves of a consultation now run end to end. On the
**identification** side: an 18-rule MYCIN subset (neomycin's own
`neomycin/rulebase.lisp`), the pluggable belief protocol (DS default, CF
retained), the HTTP bridge, and the Claude driver.

The **therapy-recommendation phase** now exists too, and it reuses the same
strategy/knowledge split. A deterministic greedy weighted **set-cover solver**
(`neomycin/therapy/`) picks the fewest drugs covering every above-threshold
organism from a schematic antimicrobial knowledge base, honoring patient
contraindications; the LLM requests a regimen through the `recommend_therapy`
tool and **narrates** it, but never chooses a drug. The engine reasons; the model
translates and explains — on the treatment side exactly as on the diagnostic one.
See [`docs/therapy-demo.md`](docs/therapy-demo.md) for an end-to-end walkthrough.

Still ahead: scaling the rule corpus, an antibiogram overlay, drug–drug
interaction constraints, and an exact-solver oracle for the greedy one.

## Provenance and license

Forked from [Lisa](https://github.com/youngde811/Lisa) at v4.2.0, preserving the
full commit history. Lisa and neomycin are both **MIT-licensed**, (c) David Young.
The underlying `lisa` engine packages are intentionally left un-renamed:
neomycin *uses* Lisa rather than absorbing it.

## Build and run

Bring up the engine, bridge, and driver with
[`docs/getting-started.md`](docs/getting-started.md); then take the guided
identification tour in [`docs/runbook.md`](docs/runbook.md) and the therapy tour
in [`docs/therapy-demo.md`](docs/therapy-demo.md). [`CLAUDE.md`](CLAUDE.md) holds
the substrate-level build notes. Dempster-Shafer is the default belief system; no
environment variable is required.
