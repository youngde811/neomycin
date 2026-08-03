# WHY/HOW explanation & provenance facility — design & slice plan

> Status: **approach locked, implementation not started.** This doc opens the
> feature (branch `feature/why-how-provenance`), the way
> `chaining-belief-spike.md` opened the chained cluster. Logged as
> `corpus-expansion-sketch.md` §5 candidate 7.

## 1. Why (the credibility problem)

Today a clinician driver can see *which* rules fired (`/rule-trace`), the resulting
`{bel, pl, ignorance}` (`/conclusions`), and near-firing rules (`/partial-matches`).
What it **cannot** get from the engine:

1. **The belief derivation.** The engine returns the *final* interval, not
   "e-coli 0.64 = enterobacteriaceae-class 0.8 × rule 0.8" or "pseudomonas 0.76 =
   Dempster-combine(rule-A 0.4, rule-B 0.6)." When the LLM narrates that arithmetic,
   it is **reconstructing it from memory** — and could be subtly wrong.
2. **The citations.** Each rule's provenance (genuine-MYCIN / PAIP / neomycin
   extrapolation + literature cite) lives **only as source comments** in
   `neomycin/rulebase.lisp`. The bridge surfaces none of it, so when the LLM cites
   "IMViC / NBK8035" it is recalling, not quoting — it could fabricate a citation.

Both are integrity gaps: the system's *explanations* aren't held to the same
"verify, don't assert" bar as its conclusions. Making provenance **engine-
authoritative** — queried, not narrated from memory — is the fix, and it is exactly
on-brand for the NEOMYCIN name (Clancey's strategy/explanation lineage over MYCIN).

## 2. Spike findings (2026-07-30, verified against the code)

**Q1 — Can `defrule` carry a `:provenance` property?** Not without a small,
additive engine change. The `rule` class (`src/core/rule.lisp:27`) has fixed CLOS
slots (`salience`, `belief-factor`, `comment`, …) — no generic property bag. Adding
one keyword threads cleanly through four pass-through points, all of which already
carry `:belief` the same way:

- `defrule` macro — `src/core/language.lisp:29`
- `redefine-defrule` — `src/core/rule-parser.lisp:302`
- `define-rule` — `src/core/rule-parser.lisp:292`
- `make-rule` (+ the `rule` slot, + `copy-rule`) — `src/core/rule.lisp:159,188`

Defaulting `:provenance` to `nil` disturbs no existing rule and no Lisa example.
This is engine-axis work the fork explicitly licenses (fork note: engine changes
are fair game when they move the chains; David is the Lisa author).

**Q2 — Does a concluded fact record its derivation?** No. At fire time the engine
has *everything*: the `activation` carries `rule` + `tokens`
(`src/core/activation.lisp:31`), and `adjust-belief (belief-factor t)`
(`src/core/rete.lisp:213`) composes the premise beliefs × the rule belief while
`*active-rule*` / `*active-tokens*` are bound. But it stores only the resulting
`(belief-factor fact)` — the rule, the premises, and the arithmetic are computed
transiently and discarded. The `fact` class (`src/core/fact.lisp:27`) has no
derivation slot. The TMS `dependency-table` (`src/core/tms-support.lisp:33`) records
supporting facts, but **only for `logical` rules** (ours aren't) and only for
retraction, without beliefs or the rule.

Two consequences shape the design:

- To be **authoritative** (the whole point), we must **record what the engine
  actually did at fire time**, not recompute it afterward from the trace.
- Because `*allow-duplicate-facts*` is `nil`, duplicate conclusions **accumulate
  belief across firings** (`assert-fact` → `adjust-belief` on the duplicate,
  `rete.lisp:226`). So a conclusion's derivation is **a list of contributing
  firings**, combined by the active belief algebra — e.g. pseudomonas 0.76 =
  Dempster-combine of two firings. The record is a *combination*, not a single
  product.

## 3. MYCIN WHY vs HOW — what we are (and aren't) building

MYCIN had two explanation directions: **HOW X** = the rules/sub-goals that concluded
X (downward through the support), and **WHY** (mid-consultation) = "why are you
asking me this?" (upward toward the goal rule). neomycin's LLM drives fact-gathering
itself, so classic interactive WHY maps onto the existing `/partial-matches`
(what's still needed and for which rule). The high-value, missing piece is **HOW +
provenance**: given a conclusion, the authoritative derivation tree *and* the
authority (citations) behind each rule in it. We keep the colloquial name `/why`
(per the backlog) but the doc is precise: it answers **"how was this belief derived,
and on what authority."**

## 4. Design

### 4.1 Provenance representation (`:provenance` rule property) — TWO AXES

Provenance has two distinct, complementary axes, and the schema records both
(decision 2026-07-30, David):

1. **Artifact lineage** (`:origin`) — *is this curated history or our addition?* Uses
   the taxonomy from `corpus-expansion-sketch.md` §4: `:genuine-mycin` | `:paip-subset`
   | `:neomycin-extrapolation`. Ground truth from git: the 18 rules present at Lisa
   **v4.2.0** (the fork point's PAIP/EMYCIN MYCIN illustration) are `:paip-subset`;
   only what neomycin added after the fork (tier-1 class rule, 4 biochemical species
   rules, urease disconfirming rule) is `:neomycin-extrapolation`. None are
   `:genuine-mycin` — claiming verbatim Shortliffe/Buchanan appendix rules would
   overclaim.
2. **Clinical evidence** (`:evidence`) — *what authoritative source verifies the
   medical association?* A list of **real, verified** citations (CDC / NIH-NCBI
   Bookshelf / WHO / IDSA / CLSI / standard clinical-microbiology references). This is
   what makes an explanation credible to a clinician, and it is the axis David asked
   for. Sources are researched and **adversarially verified**, never recalled — a
   fabricated citation is worse than none.

Critical honesty constraint — `:belief-basis`: the certainty-factor / DS **value**
(0.4, 0.8, …) is a PAIP teaching figure or a neomycin schematic estimate; it is **not**
derived from `:evidence`. `:evidence` verifies the *association*, not the *number*.
`:belief-basis :illustrative` marks this explicitly so a real citation never launders
an invented number. (Not-for-clinical-use is preserved throughout.)

```lisp
(defrule enterobacteriaceae-lactose-pos-indole-pos-suggests-e-coli
    (:belief 0.8
     :provenance (:origin :neomycin-extrapolation           ; artifact lineage
                  :evidence ("<verified source 1>" "<verified source 2>")  ; clinical association
                  :belief-basis :illustrative                ; the 0.8 is schematic, NOT from :evidence
                  :note "lactose+ AND indole+ is the classic E. coli pair; K. oxytoca also +/+, hence 0.8 not 1.0"))
  ...)
```

The inline citation comments become redundant once `:evidence` carries verified
sources (trimmed in Slice B).

### 4.2 Derivation capture (record-on-fire)

Add a rete-level `derivation-table` (keyed by the concluded fact), **paralleling the
existing TMS `dependency-table`** — a clean, faithful precedent, and it keeps the
`fact` class untouched. At the point `adjust-belief` sets a conclusion's belief
(`rete.lisp:213`), append a derivation record:

```
derivation-record:
  :rule            <qualified rule name>
  :rule-belief     <the rule's own :belief>
  :premises        (list of {fact-id, fact-name, value, belief})   ; the non-self tokens
  :belief-before   <fact belief before this firing>   ; nil on first firing
  :belief-after    <fact belief after this firing>    ; the combined result
```

Per fact: the ordered list of these. This captures combination (multiple firings)
and, because premises are themselves facts, lets `/why` **recurse** — a premise that
is a derived `organism-class` expands into its own derivation, surfacing the
multi-hop chain (e-coli ← class ← evidence). Reset clears the table alongside working
memory.

### 4.3 The `/why` (explain) endpoint

`GET /why?organism=e-coli` (or POST) → authoritative JSON:

```
{ "organism": "e-coli",
  "belief": {bel, pl, ignorance},          // echoes /conclusions
  "derivation": [                            // one entry per contributing firing
    { "rule": "…-suggests-e-coli", "rule_belief": 0.8,
      "composition": "0.8 (class) × 0.8 (rule) = 0.64",   // engine-computed, not narrated
      "premises": [ {"fact": "organism-class enterobacteriaceae", "belief": {…},
                     "derivation": [ … recursive … ] }, … ],
      "provenance": {origin, citation, note} } ],
  "belief_system": "…" }
```

The `composition` string and every number come from the recorded derivation, so the
LLM narrates from returned data. Provenance rides each rule node.

### 4.4 LLM integration

Add an `explain_conclusion` tool (→ `/why`) to `tools.json` + `driver.py`, and update
`system-prompt.md`: when asked "why/how did you conclude X" or when citing a figure,
the LLM must **call `explain_conclusion` and quote the returned arithmetic and
citations — never reconstruct them.** This closes the credibility loop end-to-end.

## 5. Slice plan (each green + committed separately)

- **Slice 0 — this doc.**
- **Slice A — `:provenance` rule property (engine, additive).** Slot + 4-point
  plumbing + `copy-rule`; default nil. Prove on 1–2 rules; test a rule carries its
  provenance; no behavior change. Lisa's own suite must stay green (135/41).
- **Slice B — populate provenance across all 23 rules.** Citations move from comments
  to `:provenance`. Pure data. Test: every rule has a well-formed provenance.
- **Slice C — derivation capture (engine).** `derivation-table` + record-on-fire in
  the `adjust-belief` path. Test: culture-1 → pseudomonas has 2 records (0.4, 0.6 →
  0.76); e-coli has 1 (class × rule → 0.64); combination + premise beliefs correct.
- **Slice D — `/why` bridge endpoint + serializer.** Recursive derivation + provenance
  JSON. Test (Lisp path, mirroring therapy-bridge-tests): `/why e-coli` returns the
  class→species chain with arithmetic and the NBK8035 citation.
- **Slice E — LLM wiring.** `explain_conclusion` tool schema + driver dispatch +
  system-prompt narration rule ("quote, don't reconstruct").
- **Slice F — docs + a clinician scenario** exercising an explanation query; sync
  CLAUDE.md endpoint table + runbook.

## 6. Non-goals / open questions

- **Non-goal:** interactive mid-consultation WHY (goal-directed question "why are you
  asking") — `/partial-matches` already covers that surface.
- **Open (resolve in Slice A):** exact `:provenance` value schema (plist vs a small
  struct); whether to keep or trim the now-redundant inline comments.
- **Open (Slice C):** whether disconfirming firings (negative belief, self-guarded)
  render cleanly in the derivation list — they should appear as belief-lowering
  records; verify against culture-2.
- **Open (Slice D):** endpoint verb/shape (`/why` GET with query vs POST body) — match
  the existing bridge conventions in `handlers.lisp`.