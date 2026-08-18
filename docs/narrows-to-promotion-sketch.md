# Sketch — promoting narrows-to from spike to the corpus

> **Design sketch for review. No code.** The spike now covers all 50 shipped rules
> (→ 44), settles the combination policy, and fixes three findings from
> `belief-conditional-audit.md` on the way. This is what it would take to make it the
> real thing.
>
> Read alongside `docs/narrows-to-gram-pos-sketch.md` (the rule shape) and the spike
> files themselves.

## 1. The headline: this is a net DELETION

The v0.9.0/v0.10.0 machinery exists to route belief around a representation that
couldn't hold set-valued answers. Once a rule *asserts* its answer and combination is a
*read* over working memory, most of that machinery has nothing to do.

**Deleted from the engine:**

| what | why it goes |
|---|---|
| `deframe`, `*frame*`, named subsets | Θ is symbolic; nothing enumerates a universe |
| `:supports` / `:opposes` / `:claims` rule properties | a rule's answer is its RHS, not a declaration |
| evidence pools on the `rete` instance | nothing accumulates during inference |
| fire-time accumulation, `*frame-evidence-contributed*` | no rule concludes nothing |
| `contribute-claims-per-hypothesis` | no per-hypothesis translation needed |
| `fact-hypothesis` / `fact-entity` protocol | reading candidates facts needs no protocol |
| `refresh-projections`, `project-onto` | belief is not mirrored onto facts |
| `rule-focal-set`, `rule-claims`, `claim` struct | rules carry a belief and a conclusion, as always |
| bitmask sets in `frame.lisp` | bitmasks need bit positions, which need an enumeration |

That is roughly **700 lines of engine**, including the two mechanisms I most regret:
belief mutating a hidden pool during inference, and rules whose RHS did nothing.

**Also deleted from the corpus:** `organism-class` entirely (a class *is* a candidates
set), and with it the two-tier chaining, the composition law, and the last of the
carried-over class constants.

**Added:** an open-frame set algebra (~150 lines — simpler than `frame.lisp`, since
sorted lists over a symbolic Θ replace bitmasks over an enumerated one), a
candidates-reading combiner (~50), and the specificity check (~30). Call it 250 in,
700 out.

## 2. What replaces `organism-identity`

Nothing asserts it. `/conclusions` projects from the combined mass instead:

- `Bel(x)` and `Pl(x)` for any organism a rule has named
- the set-valued conclusions, unchanged from today
- `K`, unchanged
- and — new — a defensible answer for an organism **no rule has mentioned**, which is
  `m(Θ)`

Downstream consumers keep their shape. The therapy solver takes
`((organism . belief) …)` and can be handed the projection exactly as it is handed
`organism-identity` beliefs today, so **phase 1 of promotion costs therapy nothing**.
Consuming set-valued conclusions directly stays a later, optional improvement.

## 3. `/why` gets better, not worse

Today it narrates a composition string. Under narrows-to it can narrate the actual
argument, because the answers are facts:

> *lactose fermentation said it was one of {E. coli, Klebsiella, Enterobacter,
> Serratia} at 0.70; indole production said one of {E. coli, Proteus} at 0.60; only
> E. coli is in both.*

That is the reasoning a clinician would recognise, read straight off working memory
rather than reconstructed. The recursive-chained-premise machinery is unnecessary
because nothing chains.

## 4. The decision this forces — CF and Barnett DS

**Narrows-to is inherently a Dempster-Shafer design.** A candidates fact is a set, and
the work is done by intersecting sets. Certainty factors have no set algebra; neither
does the per-hypothesis Barnett frame. Neither can reason over this corpus.

So the "same rulebase, three algebras" comparison that the fork has maintained since
the beginning **ends here**. Three ways to go:

1. **Retire CF and Barnett as active systems.** Keep the code and the current
   rulebase on a tag, so the comparison remains reproducible historically. Honest, and
   the smallest ongoing burden.
2. **Keep them, degraded** — they would see candidates facts and combine duplicates,
   but could not intersect, so they would report something that is not the corpus's
   meaning. I would argue against this: it is a payload that looks like a comparison
   and is not one.
3. **Keep the old corpus alongside** as `neomycin/rules-classic/`, loadable for CF and
   Barnett. Preserves a real comparison at the cost of two rulebases to maintain, and
   they will drift.

**My recommendation is (1)**, with the note that this is a genuine loss and should be
recorded as one: the CF-vs-DS contrast has been a real part of what the project
demonstrates. But it is a comparison between two ways of scoring the *same* rules, and
the rules themselves are now the thing that changed.

**This is yours to decide, not mine to infer.**

## 5. What moves

| area | change |
|---|---|
| `neomycin/rules/` | all 50 rules rewritten as 44; `organism-class` and `organism-identity` gone; `disconfirming.lisp` deleted outright |
| `src/belief-systems/` | `frame/` replaced by the open-frame algebra; CF and Barnett per §4 |
| `src/core/` | the deletions in §1; `rule-introspection.lisp` loses the focal-set half |
| goldens | **all move.** Every scenario, under the specificity policy |
| property tests | frame/focal-set invariants go; new ones for candidates sets (non-empty, no singleton-only corpus, subsumption pairs flagged) |
| `/conclusions`, `/why`, `/rules` | reshaped per §2–3 |
| therapy | unchanged in phase 1 (§2) |
| prompt + `tools.json` | rewritten; the end-to-end check from v0.10.0 becomes mandatory before tagging |

## 6. Staging

**A — algebra and rules, no engine deletion.** Land the open-frame algebra and the 44
rules as a *parallel* belief system, leaving v0.10.0's intact. Capture new goldens.
Nothing is removed, so nothing can regress silently, and both can be run side by side.

**B — make it the default**, once A's numbers have been reviewed against real
scenarios. Bridge and prompt reshaped. This is where the published numbers change.

**C — delete.** Remove the machinery §1 lists, once nothing depends on it. Deliberately
last: deleting before the replacement is proven is how you lose the ability to compare.

**D — optional.** Set-valued conclusions to the therapy solver.

Each stage is independently green and independently revertable.

## 7. Risks, stated plainly

- **All goldens move, twice** — once at A, and again if the specificity policy is
  tuned. Only the *ranking* regressions (culture-1 pseudomonas ahead of klebsiella) are
  stable across policies, so those are the tests worth trusting during the transition.
- **The corpus is illustrative throughout, still.** None of this makes a belief a
  measured quantity. It removes reasons for beliefs to be *inconsistent with each
  other*, which is a smaller claim.
- **The merges bake in six judgement calls** — including three where two numbers
  disagreed. They are recorded in the rule comments, but they are judgements.
- **Category B is untouched.** The ~15 context-conditioned rules narrow
  epidemiologically, and no representation checks them. That was the original audit's
  step 3, and it survives all of this.
- **Size.** This is larger than v0.9.0 and v0.10.0 combined, and it follows two
  releases that moved the same numbers. There is a case for letting v0.10.0 sit, and a
  case for not shipping a representation twice when the second one is known better. I
  lean to the latter, but not strongly.