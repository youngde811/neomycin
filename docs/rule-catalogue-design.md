# Rule catalogue (`/rules`) — design & slice record

> **Status: landed.** Written after the fact, against the code as built. Where the
> plan changed under contact with the corpus, the change and its reason are recorded
> rather than tidied away.

## 1. Why (the second-source-of-truth problem)

The LLM system prompt carried a hand-written catalogue of the entire rulebase: all
50 rules, their beliefs, their premises, their clinical rationale — 117 of the
prompt's 366 lines. Three separate problems, only one of which was size.

**It was an untested second source of truth.** `property-tests.lisp` exists because
this corpus has already lost a `member` list to a silently-retired species; that
class of drift is guarded on the Lisp side and was entirely unguarded in markdown.
Every slice paid a doc-sync tax by hand, and slice F paid it across 23 new rules.

**It contradicted the prompt's own honesty rule.** The WHY/HOW section (v0.4.0)
tells the model never to reconstruct arithmetic or recall a citation from memory —
`explain_conclusion` is ground truth, "your own recollection is not." The catalogue
directly beneath it handed over every belief and the composition arithmetic to
recall. The instruction was a request; the material undercut it.

**It was inert most of the time.** Most turns assert a fact or ask a question. The
corpus was in front of every one of them.

Measured, the catalogue was 6,361 tokens — 32% of the prompt's lines but **43% of
its tokens**, because rule names (`enterobacteriaceae-motile-lactose-pos-indole-neg-suggests-enterobacter`)
tokenize badly.

## 2. What replaced it

A `/rules` endpoint that reads the **compiled rulebase**, a `describe_rules` tool
over it, and ~40 lines of prompt describing the corpus's *shape* rather than its
contents.

The dividing line: **the prompt keeps what governs how the model talks; the engine
answers what it looks up.** Chaining and composition, class-is-never-a-leaf, what a
negative belief means, and the per-cluster discriminator panels shape narration and
question-selection, so they stay. Every per-rule fact is queried.

## 3. Design

### 3.1 Introspection belongs in the engine (`src/core/rule-introspection.lisp`)

`property-tests.lisp` already needed these queries and answered them by reaching
through `LISA::` — `rule-actions`, `rule-patterns`, `parsed-pattern-class`,
`belief-factor` — with private copies of the walkers. `/rules` needs the same
queries, and `lisa-bridge` cannot depend on `neomycin` (it is a dependency of it,
as `therapy/bridge.lisp` records). A second copy in the bridge, or a neomycin-side
module reaching through `LISA::` from shipped code, were both available; neither is
right for a query that is genuinely domain-neutral.

So the walkers moved into the engine and are exported. This is the read half of the
same idea as the derivation table: **the derivation table records what a rule DID
when it fired; introspection records what a rule IS, whether or not it ever has.**

Exported: `rule-belief`, `knowledge-rule-p`, `confirming-rule-p`,
`disconfirming-rule-p`, `rule-asserted-facts`, `rule-concludes-p`,
`rule-premise-classes`, `rule-premise-values`, `rule-member-test-values`,
`rule-premises-p`, and `get-rule-list`. All domain-neutral: they walk
`PARSED-PATTERN` and `RULE-ACTIONS` and know nothing about organisms. Domain meaning
is composed by callers — which is why the MYCIN vocabulary appears in the bridge's
serializer, exactly as it already does in `/conclusions` and `/why`.

### 3.2 What `/rules` returns

Per rule: `belief`, `kind`, `concludes`, `premises` (each with the literal values it
requires), `chained_from` when it refines off a derived organism-class, `targets`
for a ruling-out rule, and the full `:provenance` — including the `note`, which is
consistently more precise than the prompt's paraphrase of it ever was.

Every response also carries a corpus `summary`: counts, the derived classes, the
`clusters` map, and every leaf identity. That summary is what makes the prompt's
shape section short — it is orientation the model can fetch rather than carry.

Filters, ANDed: `name`, `kind`, `concludes`, `premises`, `cluster`.

### 3.3 `cluster` needed a third arm (found during implementation)

The obvious definition of a cluster — the rule concluding the class plus every rule
premising on it — returned 8 rules for `staphylococcus` and **none of the
discriminators**. Ruling-out rules key off the *identity* and never mention the
class, so "what separates the staphylococci?" was answered with only the rules
arguing *for* each species.

`rule-in-cluster-p` therefore has three arms: concludes the class, premises on it,
**or concludes/targets one of the identities refined from it**. That takes
staphylococcus to 12 and gives enterococcus its bile-esculin and arabinose
discriminators. This was the single most important correction in the slice: without
it the endpoint answers the easy half of the question a clinician actually asks.

### 3.4 What stayed in the prompt

Chaining and composition; class-is-never-a-leaf (with the therapy backstop);
negative-belief semantics and the plausibility consequence; the per-cluster
discriminator panels, which are needed *before* any fact exists and so cannot be
deferred to a query; and the instruction to quote rule names verbatim.

The two worked examples were rewritten. They had been reciting `0.8 × 0.5 = 0.40`
and `[0.22, 0.41]` from memory — demonstrating precisely what the surrounding text
forbids. They now show the tool calls that produce those figures.

## 4. Guards (`neomycin/test/prompt-tests.lisp`)

Retiring the catalogue removes most of the drift surface but not all of it: the
prompt still quotes rule names in its examples and still states the corpus counts.
Those are the only two claims about the rulebase it is now allowed to make from its
own text, and both are asserted against the compiled corpus:

- **`prompt-names-only-real-rules`** — every backticked token shaped like a rule name
  (`-suggests-` / `-argues-against-`) must be a rule that exists.
- **`prompt-states-the-real-corpus-counts`** — the three integers in "The engine holds
  N diagnostic rules — C confirming and D ruling-out" must be the real ones.

Both were verified by **breaking the prompt deliberately** — bumping the counts to
51/35/16 and inserting `` `retired-marker-suggests-atlantis` `` — and confirming each
fails with a precise message before restoring. A guard never seen to fail is not
known to be a guard.

`property-tests.lisp` deliberately does **not** adopt `knowledge-rule-p` for its
population. Selecting on "declares a belief" would make invariant 1 — every domain
rule declares a usable belief — true by construction, and a rule that forgot its
`:belief` would drop out of the population instead of failing.

## 5. Measured outcome

| | before | after |
|---|---:|---:|
| `system-prompt.md` | 14,640 | **9,042** (−38%) |
| `tools.json` | 3,875 | 4,743 (+868, `describe_rules`) |
| **fixed prefix** | 18,515 | **13,785** (−26%) |
| suite | 858 / 152 | 860 / 154 |

Counted with `messages.count_tokens` against `claude-opus-5`.

Note the token saving is now the *weakest* of the three motivations: prompt caching
(commit `0876c7c`) had already cut the repeat cost of the prefix by ~84%, so the
remaining per-case saving is small. Drift and attention are what justify the slice.

## 6. End-to-end validation

Two scripted driver sessions against the rewritten prompt, `claude-sonnet-5`:

- **Scenario 1 + 11 (burn patient, then "why Klebsiella?").** Went `assert_fact` ×6 →
  `get_partial_matches` → `run_inference` → `get_conclusions` → `explain_conclusion`
  ×2. Quoted the engine's composition string verbatim, kept the
  `belief_basis: illustrative` caveat, and sourced the one rule name it volunteered
  from the partial-matches payload rather than memory. `describe_rules` was **not**
  called — correctly, since nothing asked for corpus detail.
- **Scenario 12 (beta hemolysis contradicts the respiratory site), then "which single
  test best discriminates within the streptococci, and how heavily is it weighted?"**
  Reported both DS bounds (pyogenes 0.595/pl 1.0; pneumoniae [0.216, 0.412] — matching
  the documented goldens) and the "not ruled out" honesty line. The follow-up
  triggered `describe_rules` with `cluster=streptococcus`, and the answer quoted exact
  beliefs (−0.75, 0.85, 0.70, 0.65) **and the provenance rationale** — "only 0.70
  because groups C/G are also bacitracin-resistant" — which is `:note` content the old
  prompt carried only a paraphrase of.

## 7. Non-goals / open

- **~~The corpus spells conclusion values inconsistently~~ — retracted (2026-08-12).**
  This slice originally recorded a mixed keyword/symbol spelling across the rule
  files. It does not exist: an audit of the compiled rulebase found 105 literal
  conclusion and premise values, **all** keyword-spelled, the only non-keywords being
  the `?value` variable the 16 ruling-out rules match and re-assert. The claim came
  from comparing two introspection probes written with different format directives —
  `~A` prints `:klebsiella` as `KLEBSIELLA`, `~S` prints `:staphylococcus` intact.
  Left in place, struck through, because the commit messages and the v0.7.0 tag
  annotation carry the same error and cannot be amended; this is the correction of
  record. `value-name` is still right, for the reason below.
- **`/rules` is unauthenticated and unpaginated**, like every other bridge endpoint.
  Fine for a research artifact on localhost; not a posture for anything else.
- **The `-suggests-` / `-argues-against-` naming convention is load-bearing** for guard
  1. A rule named outside it is simply not guarded — acceptable while the convention
  holds corpus-wide, and worth revisiting if it stops.
- **No behavioural A/B.** The two sessions confirm the at-risk behaviours survive; they
  do not measure whether narration got better or worse. A real comparison would need
  the same scenarios under both prompts and a rubric.