# Belief propagation through the `organism-class` intermediate — spike findings

*Spike for the chained enterobacteriaceae cluster (corpus sketch §3B/§5.1),
tier 2. Read this before we author species-refinement rules.* Captures **the
question**, **what the engine actually does**, **the empirical proof**, and **what
it means for tier-2 design**.

> **⚠️ NOT FOR CLINICAL USE.** Reconstruction of 1970s clinical logic for research
> into uncertain reasoning; nothing here is clinical guidance.

---

## 1. The question

Tier 2 turns the derived family class into competing sibling species: a rule with
`organism-class :enterobacteriaceae` on its **left**-hand side concluding e.g.
`:e-coli` on the right. For that to be *real* chaining — belief flowing *through*
the intermediate — the species belief must **depend on the belief sitting on the
class**, not merely on the species rule's own declared `:belief`.

We went in suspecting the opposite: that Lisa assigns a conclusion the **rule's**
declared belief and ignores how strongly its premises are held (rule-belief
ownership). Every existing rule appears to behave that way — in `culture-1` each
confirming rule contributes *exactly* its `:belief`. If that were the true
mechanism, a naive tier-2 rule would make `organism-class` **decorative**:
structural chaining with no belief composition.

**That suspicion was wrong.** The engine already propagates premise belief. This
doc shows why, and proves it.

---

## 2. Answer (TL;DR)

- **Belief flows through the intermediate, multiplicatively, with no engine
  change.** A species rule of belief `r` firing off a class held at strength `s`
  yields species strength `s · r`.
- **The `culture-1` "exactly its `:belief`" behavior is an artifact**, not the
  mechanism: raw evidence facts carry `nil` belief, so they contribute nothing to
  the premise combination and the conclusion falls through to the rule's own
  belief. A *rule-concluded* premise (like `organism-class`) carries real belief
  and **does** compose.
- **This is MYCIN-faithful.** Chained certainty factors multiply; DS carries the
  premise plausibility forward. Tier 2 is therefore corpus work, **not**
  engine-axis work — contrary to what we flagged as a possibility.
- **Consequence for authoring:** a species rule's declared `:belief` is a
  *conditional* strength — "given the family, how strongly this evidence points to
  this species" — because it gets multiplied by the family's belief. Author and
  read the goldens with that in mind.

---

## 3. What the engine actually does

Three layers, all already in the tree:

### 3.1 `adjust-belief` during rule firing — `src/core/rete.lisp:213`

When a rule asserts a fact **without** an explicit `:belief` (the normal case —
our rules never pass `:belief` on the RHS `assert`), the `(belief-factor t)`
method runs:

```lisp
(defmethod adjust-belief (rete fact (belief-factor t))
  (when (in-rule-firing-p)
    (let ((rule-belief (belief-factor (active-rule)))
          (facts (remove fact (token-make-fact-list *active-tokens*) :test #'eq)))
      (setf (belief-factor fact)
            (belief:adjust-belief facts rule-belief (belief-factor fact))))))
```

`facts` is **the matched premise facts** (the activation's token, minus the
conclusion fact itself). So premise beliefs are handed to the belief system, every
time a rule fires. (The `remove fact` guard is what lets a disconfirming rule key
off an already-present hypothesis without its *own* prior belief driving the
ruling-out force — see the rule-belief section below.)

### 3.2 The combination policy — `src/belief-systems/protocol.lisp:105`

```lisp
(defun adjust-belief* (matched-facts rule-belief old-belief)
  (let* ((premise-beliefs (remove nil (mapcar #'belief-factor matched-facts)))
         (conjoined (when premise-beliefs (conjoin-beliefs system premise-beliefs)))
         (new-belief (cond
                       ((and conjoined rule-belief) (weaken-belief system conjoined rule-belief))
                       (rule-belief                 (normalize-belief system rule-belief))
                       (conjoined                    conjoined)
                       (t nil))))
    ;; combine-beliefs with old-belief if the conclusion already had one
    ...))
```

Read the `cond`:

- **`premise-beliefs` drops `nil`s.** Raw evidence facts have `belief :initform
  nil` (`src/core/fact.lisp:35`) and are asserted at top level with no `:belief`,
  so they contribute **nothing**. This is the whole reason existing rules show
  "exactly their `:belief`": with no belief-bearing premises, `conjoined` is `nil`
  and the conclusion falls to the `(rule-belief …)` branch = `normalize(rule
  :belief)`.
- **When a premise *does* carry belief** (a rule-concluded fact like
  `organism-class`), `conjoined` is non-nil and the conclusion is
  `weaken-belief(conjoin(premises), rule-belief)` — **premise strength scaled by
  the rule**. This is the chaining path.
- **`combine-beliefs`** merges with any belief already on the conclusion (two rules
  concluding the same fact) — the ordinary convergent-evidence path, and the
  source of the double-count risk in §5.3.

### 3.3 The CF and DS combinators

| operator | CF (`certainty-factors.lisp`) | DS (`dempster-shafer.lisp`) |
|---|---|---|
| `conjoin-beliefs` (AND premises) | `(min …)` — weakest link (`:56`) | `[min bel, min pl]` (`:178`) |
| `weaken-belief` (rule factor `f`) | `belief · f` (`:53`) | `f>0`: `[bel·f, premise-pl]`; `f<0`: `[0, 1−bel·|f|]` (`:159`) |
| `combine-beliefs` (two for same H) | MYCIN CF combine (`:44`) | Dempster's rule (`:152`) |

So, one belief-bearing premise (the class at `[0.8, 1.0]`, strength `bel = 0.8`),
rule factor `r = 0.7`:

- **CF:** `conjoin = 0.8`, `weaken = 0.8 · 0.7 = 0.56`.
- **DS:** `conjoin = [0.8, 1.0]`, `weaken(+) = [0.8·0.7, carry-pl 1.0] = [0.56, 1.0]`.

---

## 4. The spike (empirical proof)

A throwaway tier-2 probe rule, added to the loaded rulebase, refining the derived
class to one sibling. The **only** belief-bearing premise is `organism-class`, so
whatever lands on `:e-coli` is exactly the composition through the intermediate:

```lisp
(defrule probe-class-to-ecoli (:belief 0.7)
  (organism (id ?o))
  (organism-class (value :enterobacteriaceae) (of ?o))
  =>
  (assert (organism-identity (value :e-coli) (of ?o))))
```

Driven with an aerobic gram-neg rod (which fires tier 1 → `organism-class
:enterobacteriaceae` at 0.8), under both algebras:

```
=== CF  (expect e-coli 0.56 = 0.8*0.7) ===
  organism-identity enterobacteriaceae => 0.8        ; existing leaf, untouched
  organism-class    enterobacteriaceae => 0.8        ; tier-1 intermediate
  organism-identity e-coli             => 0.56       ; <-- composed through the class

=== DS  (expect e-coli [0.56, 1.0]) ===
  organism-identity enterobacteriaceae => [0.80, 1.00]
  organism-class    enterobacteriaceae => [0.80, 1.00]
  organism-identity e-coli             => [0.56, 1.00]   ; <-- composed
```

Prediction met exactly. Belief composes through the intermediate; the class is
not decorative. (Spike script preserved in the scratchpad; not committed.)

---

## 5. What this means for tier 2

### 5.1 No engine change; author species rules as conditional strengths
Tier 2 is pure corpus work. Each species rule's `:belief` is a **conditional**
strength (given-the-family), because the engine multiplies it by the family
belief. A species rule at `0.7` never yields more than `0.8·0.7 = 0.56` here —
design the numbers and the DS goldens around the *composed* value.

### 5.2 Chaining attenuates — keep it one tier deep
Multiplicative composition means depth compounds (`class · r_species ·
r_subspecies · …`). The sketch's §10.1 "stop at one tier (class → species)"
recommendation is now quantitatively motivated: a second chained hop would shrink
beliefs fast. One tier.

### 5.3 The double path is a real double-count — re-parent (DECIDED)
> **✅ DECIDED (David, 2026-07-28):** re-parent. The system must **not**
> double-count: the existing one-hop leaves are retired in favour of the chained
> class → species path, not kept alongside it. This is the (a)/(b) question from
> the increment kickoff, now closed on (b) — cleaner, more faithful, and it
> eliminates the arithmetic double-count below. Only the *scope* of the re-parent
> (which/how many siblings in the first increment) remains open (§6.3).

If both the chained path **and** the old one-hop leaf conclude the same species,
`combine-beliefs` merges them. Concretely, chained `:e-coli` at `0.56` plus a
hypothetical leaf `:e-coli` at `0.7` would CF-combine to `0.56 + 0.7 − 0.56·0.7 =
0.868` — inflated from the *same* underlying evidence counted through two
structural routes. This is exactly why Klebsiella and Salmonella (today's leaves)
must be **re-parented** under the class, retiring their one-hop rules, rather than
left alongside the chain (the decision-(a)/(b) question, now with a number behind
it). Re-parenting deliberately perturbs their goldens — re-capture is part of the
deliverable.

### 5.4 Plausibility, disconfirming rules
Positive chaining carries the premise `pl` forward (DS `weaken` keeps
`premise-pl`), so with the class at `pl = 1.0` the species stays at `pl = 1.0`
until something argues against it. The existing disconfirming pattern still
applies at the species level. Note `conjoin` takes **min pl** across
belief-bearing premises: if a future intermediate ever carries `pl < 1.0`, that
ceiling propagates into the species — worth a targeted golden when it first
happens.

### 5.5 Only belief-bearing premises compose
A species rule's *discriminating* evidence (e.g. a `lactose` finding) asserted at
top level carries `nil` belief and contributes **nothing** to the composed
strength — only `organism-class` does. That keeps composition clean and
predictable (one belief-bearing premise in, one scaled belief out), but it also
means discriminator *uncertainty* isn't modeled unless a discriminator is itself
asserted with a `:belief`. Probably fine for tier 2; flagged so it's a choice, not
a surprise.

---

## 6. Open questions to settle before authoring

1. **Sibling set and discriminators.** Which of *E. coli / Klebsiella /
   Enterobacter / Serratia / Proteus / Salmonella* to include first, and what
   distinguishes them? Options: reuse existing contextual params (Klebsiella ←
   hospital-acquired + compromised; Salmonella ← travel / low-WBC — already in the
   corpus), vs. introduce new discriminators (lactose fermentation, urease, etc.).
   Reusing existing params avoids inventing biochemistry and keeps provenance
   honest; new params add breadth but need citation.
2. **Species `:belief` values.** Conditional-on-family strengths. Reuse the
   existing leaf values where a species already has a rule (Klebsiella 0.5–0.6,
   Salmonella 0.55–0.65) or re-derive now that they compose off 0.8? Don't invent —
   pin each to something citable or to an existing corpus value, and let the
   composed goldens document the result.
3. **Re-parent scope.** Re-parenting itself is **decided** (§5.3, no double path);
   the open part is *how far* in the first increment: re-parent only the two
   existing leaves (Klebsiella, Salmonella), or model the whole family uniformly
   (add E. coli/Enterobacter/Serratia/Proteus as new species) at once? Smaller =
   safer spike; larger = the richer DS conflict material §5.1 wants.
4. **Golden strategy.** Hand-verify the *composed* species values (the `0.56`-style
   numbers) as the new DS goldens, and add a class→species conflict golden (two
   siblings near-tied) — the §6 "competing hypotheses on one organism" DS workout.
```