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

Early. The forked Lisa substrate carries an 18-rule MYCIN identification subset
(`examples/mycin.lisp`), the pluggable belief protocol (DS default, CF retained),
the HTTP bridge, and the Claude driver. The neomycin work — scaling the rule
corpus, systematizing the patient -> culture -> organism context tree, and
deciding where the therapy-recommendation phase lives — builds on top of that.

## Provenance & license

Forked from [Lisa](https://github.com/youngde811/Lisa) at v4.2.0, preserving the
full commit history. Lisa and neomycin are both **MIT-licensed**, (c) David Young.
The underlying `lisa` engine packages are intentionally left un-renamed:
neomycin *uses* Lisa rather than absorbing it.

## Build & run

The build, bridge, and driver instructions are unchanged from the Lisa
substrate — see [`CLAUDE.md`](CLAUDE.md) and [`docs/runbook.md`](docs/runbook.md)
for the current, verified steps. Dempster-Shafer is the default belief system;
no environment variable is required.