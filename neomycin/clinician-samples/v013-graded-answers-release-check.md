# Release check — graded answers (Category B)

**Date:** 2026-08-24 · **Branch:** `feature/category-b-resolution`
**Backend:** Anthropic direct · **Belief system:** Dempster-Shafer (candidate sets)
**NOT FOR CLINICAL USE.**

The whole stack in one pass — prompt + tool schemas + bridge + engine, with the model
in the loop — as `CLAUDE.md` "Release check — the layers must agree" requires. This is
the gate that exists because the suite, `bin/*.sh` and `prompt-tests.lisp` each test one
layer and none of them puts the model in the loop; that gap is how three `tools.json`
descriptions once went stale while the suite stayed green.

Scenario: culture-1 in natural language — *"a patient with serious burns and a
compromised immune system has an aerobic gram-negative rod growing in a blood culture."*

## The golden table this was checked against

Measured from `neomycin/test/candidates-tests.lisp` (`candidates-culture-1`) and the
therapy tests. **Every figure the model quoted appears below.**

| quantity | golden | model quoted |
|---|---|---|
| e-coli | `0.232195 / 0.563902` | 0.232 / 0.564 ✓ |
| pseudomonas | `0.175610 / 0.468293` | 0.176 / 0.468 ✓ |
| klebsiella | `0.164878 / 0.457561` | 0.165 / 0.458 ✓ |
| enterobacter | `0.029268 / 0.380488` | 0.029 / 0.380 ✓ |
| proteus, serratia | `0.000000 / 0.398049` | 0.0 / 0.398 ✓ |
| salmonella | `0.000000 / 0.292683` | 0.0 / 0.293 ✓ |
| bacteroides | `0.000000 / 0.058537` | 0.0 / 0.059 ✓ |
| conflict K | `0.180000` | 0.18 ✓ |
| margin | `0.234146` | 0.234 ✓ |
| set-valued mass | `0.234146` | 0.234 / 0.23 ✓ |
| e-coli ignorance | `0.331707` (pl − bel) | 0.332 ✓ |
| burn rule lean | `m({pseudomonas}) = 0.20` of 0.40 | 0.20 of 0.40 ✓ |
| compromised rule lean | `m({e-coli}) = 0.28` of 0.60 | 0.28 of 0.60 ✓ |
| items to treat | e-coli, pseudomonas, klebsiella | all three ✓ |
| below threshold | enterobacter, covered by meropenem | ✓ |
| regimen | meropenem (1 drug) | ✓ |

No number was quoted that did not come from a payload. That is the property
`docs/` records as the one worth automating next — see
[[neomycin-road-to-1-0-0]] item (3).

## What the check was actually looking for

Graded answers create a specific narration risk: an answer reported as `narrows_to`
alone reads as a shrug, when what it says is that half its mass sits on one organism.
The prompt and both tool schemas were changed to prevent that. The check is whether it
worked.

**It did, in both directions**, unprompted:

> **Serious burn** → narrows to 6 opportunists (drops Salmonella) at 0.40, and this
> answer **leans toward Pseudomonas** — 0.20 of its 0.40 mass sits on Pseudomonas
> specifically […]
> **Compromised host** → narrows to the same 6 at 0.60, but **leans toward E. coli** —
> 0.28 of its mass

And it drew the correct conclusion from the two leaning opposite ways:

> the two epidemiological rules genuinely lean different directions (Pseudomonas vs.
> E. coli) rather than sharply disagreeing, so nothing here is unstable, it's just
> under-discriminated.

## The three things it got right that the corpus previously could not say

**1. It refused to call this an identification.** Unprompted, in the first sentence:

> the honest headline is that **the culture has not yet been discriminated at the
> bench**

This is the behaviour Category B was for. The pre-change corpus returned pseudomonas at
0.613 here and the model would have reported a leading species.

**2. It read `leading_answer` correctly as a SET, not an organism.** Asked to name the
leader, it separated the two meanings rather than picking the convenient one:

> The `leading_answer` the engine literally reports is not a species — it's the
> **7-organism set** […] This is the honest headline: **the biggest single chunk of
> belief in this case is "one of these seven," not any one organism.**

**3. It stated non-exclusion correctly.** No banned phrasing anywhere:

> No organism is *excluded* — Proteus, Salmonella, and Serratia sit at bel 0 only
> because no rule has yet named them individually, not because anything argued against
> them.

## Therapy

Correctly declined to recommend anything until contraindications were established. Given
none, it reported the solver's answer without choosing a drug itself:

> the solver's minimum-size cover is a **single drug**: Meropenem […] covers all three
> organisms that cleared the 0.1 coverage threshold, plus it happens to also cover
> Enterobacter (belief 0.03, which fell *below* the treatment threshold but is covered
> anyway), and every other member of the still-open 7-organism set (mass 0.23) with no
> uncovered members.

Both the `below_threshold` incidental-coverage report and the `set_obligations` mass are
narrated. It also stated the objective dial honestly rather than implying stewardship:

> this is the fewest drugs that cover the differential, chosen by the solver's default
> tiebreak (highest summed susceptibility × belief) — **not a stewardship judgment**.
> Meropenem being broad-spectrum is exactly why it won that tiebreak, not because anyone
> compared narrowness.

## Rule names quoted

All three exist in the compiled corpus under their post-Category-B names — the model
queried them rather than recalling the old ones:

- `gram-negative-narrows-to-gram-negatives`
- `aerobic-gram-neg-rod-narrows-to-aerobic-gram-neg-rods`
- `burn-blood-aerobic-gram-neg-rod-narrows-to-opportunist-rods`
- `compromised-aerobic-gram-neg-rod-narrows-to-opportunist-rods`

## Verdict

**PASS.** Suite 1352/183 green, all four `bin/*.sh` green against the same live bridge,
and the narrated figures match the goldens to the digit.
