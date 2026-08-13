# Which question does a rule's belief answer? — a corpus audit

> **Status: findings only, no code, no belief changed (2026-08-13).** Written to be
> read and argued with before anything is renumbered. Every classification below is a
> judgement about a rule's *stated rationale*, and several are genuinely arguable —
> §7 lists the ones I want checked.
>
> This is the audit called for by the standalone finding in
> `docs/ds-grounded-beliefs-design.md`, which was retained when that work was deferred
> on 2026-08-11: *"some illustrative beliefs may encode the WRONG conditional
> (sensitivity, not posterior) — worth auditing."* This is that audit. It does not
> resume the grounding project.

## 1. The finding: confirming and disconfirming rules need opposite conditionals

A **confirming** rule fires on evidence and concludes an organism. Its belief has to
answer:

> Given that I am looking at this marker, how much does it support *this* organism?
> — **P(organism | marker)**, a posterior.

A **disconfirming** rule fires on evidence and argues *against* an organism. Its
belief legitimately answers a different question:

> Does this organism ever show this marker?
> — **P(marker | organism)**, a sensitivity. If it is ≈ 0, seeing the marker is
> evidence against the organism.

Both are correct reasoning — for their own rule kind. The trap is that **the same
clinical fact serves one and ruins the other**, and the corpus does not distinguish
them anywhere: not in the rule form, not in `:provenance`, not in the property tests.

The canonical instance is red pigment. *"Many clinical isolates of Serratia are
non-pigmented"* is:

- **the right reason** for a disconfirming rule to be less than absolute, and
- **irrelevant** to a confirming rule that has already observed red pigment.

`enterobacteriaceae-red-pigment-suggests-serratia` cites exactly that fact to justify
holding its belief down to 0.75. It is a confirming rule. The grounded posterior in
the deferred design work came out materially *higher*, ≈ 0.90.

## 2. Why this matters more here than it would elsewhere

The project's entire pitch is that uncertainty is **visible** — DS intervals rather
than a single number, ignorance surfaced, derivations quotable. A belief that answers
the wrong question is invisible in exactly the way the design is meant to prevent. It
does not look uncertain. It looks like a measurement.

And it does not stay local. Chained species compose multiplicatively through their
class, so a class rule's number multiplies into every species beneath it, and `/why`
narrates the arithmetic to a clinician as an authoritative derivation.

Worse than uniform error would be **mixed** error, because a systematic offset at
least preserves the ordering between rules. §3 finds mixed error.

## 3. The audit

**Method.** All 50 domain rules, classified by what their own `:provenance :note`
offers as justification for the number. This is deliberately an audit of *stated
rationale*, not of clinical correctness: the question is which quantity the author was
reaching for, and the notes are unusually explicit about it. Rules are counted as:

- **rival** — the note justifies the belief by *other organisms that share the
  marker* ("K. oxytoca is also +/+"). This is posterior reasoning. **Correct.**
- **sensitivity** — the note justifies it by *how often the organism shows the
  marker* ("many isolates are non-pigmented"). **Wrong conditional for a confirming
  rule.**
- **prevalence** — the note justifies it by how often this organism causes disease in
  this context. For a context rule this *is* the posterior. **Correct.**
- **carried-over** — the number is inherited from a retired rule; no conditional is
  claimed at all.

Counts reconcile against the source: 13 marker-based confirming + 4 class + 17 context
+ 16 disconfirming = **50 domain rules**, matching `grep -c '^(defrule'` across
`neomycin/rules/` (excluding the reporting rule in `conclusion.lisp`). Per-file:
enterobacteriaceae 9, gram-positive 15, disconfirming 16, host-factors 5,
gram-negative identity 5. The categories below are by **basis of the belief**, not by
what the rule concludes — see the note in §3.2, where those two came apart.

### 3.1 Marker-based confirming rules (13) — where the risk lives

| Rule | Belief | Basis | Verdict |
|---|---|---|---|
| `lactose-pos-indole-pos-suggests-e-coli` | 0.8 | rival — *"K. oxytoca is also +/+, hence conditional 0.8"* | ✅ |
| `motile-lactose-pos-indole-neg-suggests-enterobacter` | 0.6 | rival — distinguishes motile Enterobacter from non-motile Klebsiella | ✅ (number unexplained) |
| `red-pigment-suggests-serratia` | 0.75 | **sensitivity** — *"many clinical isolates are non-pigmented, hence 0.75"* | ❌ grounded ≈ 0.90 |
| `urease-pos-swarming-suggests-proteus` | 0.8 | **sensitivity-shaped** — *"Proteus show characteristic swarming and strong urease"*; no rival offered | ⚠️ arguable |
| `staph-coagulase-pos-suggests-staph-aureus` | 0.85 | rival — separates it from the coagulase-negative species | ✅ |
| `staph-coagulase-neg-suggests-staph-epidermidis` | 0.55 | rival — *"coagulase-negativity identifies the GROUP, not this species"* | ✅ exemplary |
| `coag-neg-novobiocin-resistant-suggests-saprophyticus` | 0.8 | **posterior, explicitly** — *"93% positive predictive accuracy"* | ✅ exemplary |
| `beta-bacitracin-sensitive-suggests-pyogenes` | 0.85 | **mixed** — blends *"10% of S. pyogenes are resistant"* (sensitivity) with *"3-5% of C/G are susceptible"* (rival) | ❌ two quantities, one number |
| `beta-bacitracin-resistant-suggests-agalactiae` | 0.7 | rival — *"groups C and G are also bacitracin-resistant"* | ✅ |
| `alpha-optochin-sensitive-suggests-pneumoniae` | 0.85 | rival — separates from other alpha-hemolytic strep | ✅ |
| `alpha-optochin-resistant-suggests-viridans` | 0.65 | rival — *"defined largely by exclusion from S. pneumoniae"* | ✅ |
| `sorbitol-pos-arabinose-neg-suggests-e-faecalis` | 0.7 | **sensitivity** — quotes which species ferment what; 0.7 set by source-contestedness, not by any conditional | ❌ |
| `arabinose-pos-sorbitol-neg-suggests-e-faecium` | 0.7 | **sensitivity** — reciprocal of the above | ❌ |

**8 correct, 4 wrong, 1 arguable.**

Note the two exemplars. `staph-coagulase-neg-suggests-staph-epidermidis` reasons
about the residual field explicitly; `…novobiocin-resistant-suggests-saprophyticus`
cites a **positive predictive value**, which *is* P(species | test+) by definition.
The corpus already contains the right pattern, twice, stated plainly. This is not a
concept the project lacks — it is one it applies inconsistently.

### 3.2 Class-deriving rules from morphology/biochemistry (4) — a separate problem

*(A **fifth** rule also concludes an `organism-class` —
`gram-pos-cocci-in-chains-in-blood-compromised-suggests-enterococcus` — but derives it
from patient context rather than from a bench marker, so it is classified by its basis
in §3.3. Worth noting because "class rules" and "rules concluding a class" are not the
same set, and I had them confused until the arithmetic check below disagreed with me.)*

| Rule | Belief | Basis |
|---|---|---|
| `aerobic-gram-neg-rod-suggests-enterobacteriaceae-class` | 0.8 | **carried-over** — *"0.8 carried over from the retired one-hop enterobacteriaceae leaf"* |
| `gram-pos-cocci-in-clumps-suggests-staphylococcus-class` | 0.7 | **carried-over** — same formula |
| `gram-pos-cocci-in-chains-suggests-streptococcus-class` | 0.7 | **carried-over** — same formula |
| `bile-esculin-pos-salt-tolerant-suggests-enterococcus-class` | 0.8 | rival — salt tolerance distinguishes from non-enterococcal group D strep ✅ |

Three of the four numbers are **inherited from rules that no longer exist**. Whatever
they are, they are not conditionals of any kind, and they are the highest-leverage
numbers in the corpus: every chained species belief is `class × species-rule`, so 0.8
and 0.7 multiply into **19 tier-2 species beliefs** and into every `/why` narration
beneath them.

This was not on the radar before the audit. It may matter more than §3.1.

### 3.3 Context / prevalence rules (17) — mostly sound

These fire on patient or site context (burn, compromised host, hospital-acquired,
neutropenia, travel, site, age, device) and conclude an organism. Their belief is
P(organism | context) — an epidemiological posterior, and the right quantity by
construction. Spot-checks confirm the reasoning shape: `iv-drug-use…suggests-aureus`
cites *"60–70% of infective endocarditis cases in this population versus under a third
in non-users"*, which is the posterior, stated as a contrast against the base rate.

Two exceptions:

- ❌ **`enterobacteriaceae-in-blood-with-low-wbc-suggests-salmonella` (0.55)** — cites
  *"leukopenia/neutropenia in ~15–25%"*. That is P(low WBC | Salmonella), a
  sensitivity, for a rule that fires *on* low WBC. And 0.55 is not derived from it
  either — it is neither the cited quantity nor a posterior.
- ⚠️ **`neutropenia-with-aerobic-gram-neg-rod-suggests-pseudomonas` (0.5)** — already
  flagged in its own note as the *"WEAKEST CITATION IN THE CORPUS"*, because the
  sources support "antipseudomonal cover is standard" rather than "this organism is
  more likely to be Pseudomonas". Not a conditional error; an evidential one, already
  honestly declared. Left as-is.

### 3.4 Disconfirming rules (16) — sound, and for the reason §1 gives

Every one reasons from sensitivity, which is **correct for this rule kind**:
*"Klebsiella, Enterobacter, Salmonella and Serratia are characteristically
indole-negative, so a positive indole argues against them."* Several are notably
careful about it — `bile-esculin-neg-argues-against-enterococci` holds itself to −0.6
*"because the test is shared with the non-enterococcal group D streptococci, making it
a stronger ruling-IN than ruling-out marker"*, which is precisely the right
consideration.

**No changes proposed here.** This half of the corpus is the one doing it right.

## 4. Summary

| Category (by basis of belief) | n | Correct | Wrong | Arguable |
|---|---:|---:|---:|---:|
| Marker-based confirming | 13 | 8 | 4 | 1 |
| Class-deriving (morphology/biochemistry) | 4 | 1 | — | 3 carried-over |
| Context / prevalence | 17 | 15 | 1 | 1 |
| Disconfirming | 16 | 16 | — | — |
| **Total** | **50** | **40** | **5** | **5** |

Five rules demonstrably answer the wrong question; three more assert a number with no
conditional behind it at all, and those three propagate furthest. The corpus is
**mixed**, which is the awkward case: the beliefs are not comparable with one another,
so no global correction exists.

## 5. Proposed response

Deliberately in three separable steps, cheapest and most honest first. Only step 3
moves a golden.

**1. Declare the conditional.** `:provenance` already carries a two-axis basis
(`:origin` + `:belief-basis :illustrative`). Add the discriminator the audit had to
infer from prose:

```lisp
:provenance (:origin ... :belief-basis :illustrative
             :conditional :posterior)     ; | :sensitivity | :prevalence | :carried-over
```

This converts an invisible error into a declared field. It is the same move the fork
has made repeatedly — the belief system, the coverage gate, the solver objective: take
the thing that was implicit and make it a named, queryable value.

**2. Guard it with a property test.** English cannot be parsed; a keyword can.
`property-tests.lisp` already asserts corpus-wide invariants by introspecting the
compiled rulebase, and this is the same shape:

- a **confirming** rule may not declare `:conditional :sensitivity`;
- a **disconfirming** rule may not declare `:conditional :posterior`;
- `:carried-over` is permitted but counted, and the count may not grow.

That last clause is the one that pays off later: it makes an unjustified number a
thing you must *opt into* in front of a test, rather than something that arrives
silently when a rule is retired.

**3. Then, separately, fix the five.** This changes beliefs, so it re-captures
goldens, and it should be its own decision with its own evidence — the grounding
method in `ds-grounded-beliefs-design.md` §§4–5 is the obvious source. Steps 1–2 are
worth doing even if step 3 never happens, because they stop the next one arriving.

**Not proposed: resuming the DS-grounding project.** That was deferred for reasons
that still hold. This audit narrows what grounding would have to cover from "every
belief" to "five rules and three inherited constants", which is a materially different
piece of work and possibly a tractable one.

## 6. What this does *not* claim

- **Not that the beliefs are clinically wrong.** They are declared illustrative
  throughout and this audit does not change that. The claim is narrower and worse:
  some of them answer a different question than the one the rule asks, so they are not
  comparable *to each other*.
- **Not that the numbers would move much.** Only one has been grounded (0.75 → ≈0.90).
  The others are unknown until someone does the work.
- **Not a criticism of the disconfirming half**, which is the part that got it right.

## 7. Where I want the classification checked

Genuinely arguable, and a second reader may land differently:

1. **`urease-pos-swarming-suggests-proteus` (0.8)** — I marked it sensitivity-shaped
   because the note offers only *"Proteus show characteristic swarming and strong
   urease"*. But swarming + strong urease is close to Proteus-specific among the
   Enterobacteriaceae, so a rival-based justification might land on the same 0.8. The
   *number* may be right for the *wrong stated reason* — which step 1 would expose
   without changing anything.
2. **`beta-bacitracin-sensitive-suggests-pyogenes` (0.85)** — I called it mixed rather
   than wrong. It cites both quantities and lands on one number, so it is
   unreconstructable rather than demonstrably mis-conditioned. Arguably the honest
   classification is "cannot tell".
3. **The three carried-over class beliefs** — I treated inheritance-from-a-retired-rule
   as its own category rather than as an error. If you would rather call that an error,
   the corpus's headline number is 8 wrong, not 5.
4. **Whether `:prevalence` deserves its own keyword** in step 1, or is just
   `:posterior` with an epidemiological rather than laboratory base. I lean toward
   keeping it distinct — the evidence source and its failure modes differ — but it does
   add a category whose only job is documentation.