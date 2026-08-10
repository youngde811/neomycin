# Growing the MYCIN corpus — a sketch

*Exploratory. Parked behind the antibiogram overlay — not scheduled work.* This
captures **why** a larger rulebase would carry weight, **what** to reconstruct
next, and **how** it lands on the existing class/`defrule` structure, so the
thinking survives until we choose to act on it.

> **⚠️ NOT FOR CLINICAL USE.** Anything reconstructed here is a research
> illustration of 1970s clinical logic, not current guidance. Provenance notes
> below are about *fidelity to historical MYCIN*, never about clinical validity.

---

## 1. Two axes, not one

The tempting framing — "more rules ⇒ the solver sees more cases" — bundles two
things that scale differently, and the distinction should drive what we build:

- **Knowledge breadth (the corpus).** How much of MYCIN's differential space is
  reachable. Today: **50 rules** (6 one-hop leaves, 5 tier-1 organism-class rules,
  19 tier-2 chained species, 5 host-factor modifiers, 16 disconfirming) reaching **17**
  organism-identity values across **four** organism-classes. *(Was 27 rules / ~13
  identities / 1 class before the gram-positive increment — see
  `gram-positive-cluster-design.md`.)* Breadth was the genuine bottleneck for realistic
  scenarios and — more to the point for this fork — for making the CF-vs-DS divergence
  *empirically* interesting; at 8 conflicting rules the DS ignorance intervals barely
  got exercised. At 16, with two clean partitions (hemolysis three ways, coagulase two)
  among the new siblings, they do.
- **Engine capability (the mechanism).** The Rete network, conflict resolution,
  and belief combination are *already* exercised by 50 rules. Adding rule #200
  runs the **same code paths** — more coverage and scaling pressure, not new
  reasoning. A bigger flat rulebase alone does not make the engine reason
  differently.

The one place these axes *touch* is **rule chaining** — and that is the pivotal
decision below (§3). Everything else in a corpus increment is breadth; chaining
is the only thing that also grows what the engine is asked to do.

---

## 2. What already exists (the substrate)

The current rulebase is a clean, small foundation that a larger corpus extends
without redesign:

- **A context tree** — `patient → culture → organism` — with identity carried by
  plain `id` values so Rete joins by ordinary variable equality
  (`mycin.lisp:28`). New rules join through the same lineage; **no new context
  machinery is needed** for most of what follows.
- **Parameters are `param-mixin` subclasses** scoped by an `of` slot. Adding a
  clinical parameter = one `defclass` + rules that read it. Cheap and uniform.
- **`(:belief x)` is belief-system-neutral.** The active system interprets it;
  the same rule runs under CF and DS unchanged. A corpus author never touches the
  belief algebra.
- **The disconfirming pattern is established** (`mycin.lisp:264`): key off a live
  hypothesis + a contradicting parameter on the same organism, re-assert with a
  negative `:belief`. This is the DS-stressing shape (§6), and it already has a
  worked template to copy.
- **The `conclusion` rule scales for free** (`:salience -10`) — it reports every
  surviving `organism-identity`, however many rules produced them.
- **The test harness fires each rule in isolation** with hand-verified goldens.
  That strategy is what does *not* scale (§8) — the one piece a big corpus forces
  us to rethink.

---

## 3. Pivotal decision — flat breadth vs. an intermediate-abstraction layer

> **✅ DECIDED (2026-07-25):** go with **(B)** — the first corpus increment is one
> **chained organism-family cluster** (§5.1: enterobacteriaceae family, evidence →
> derived `organism-class` → competing sibling species), built on the **Lisa/Rete
> symbolic engine**. The DL/classifier alternative (§3.1) is **parked** — right lens
> for *thinking* about the cluster, wrong substrate to build on. Engine enhancement
> to support chaining is a deferred future option, not a prerequisite. Parked behind
> the antibiogram overlay. The analysis below is retained as the rationale.

Every current rule goes **one hop**: raw evidence → `organism-identity`. Real
MYCIN chained through intermediate abstractions. This is the fork in the road.

- **(A) Keep expanding flat.** More 1-hop rules, more identities. Simple,
  additive, and each rule stays independently testable. But it grows breadth
  *only* — the engine keeps doing exactly what it does now, and the rulebase
  stays a lookup table wearing an inference engine's clothes.
- **(B) Introduce a derived-parameter layer so rules chain.** *Recommended for at
  least one cluster.* Evidence → **intermediate abstraction** → identity (→
  therapy, already downstream). Example: evidence rules conclude a derived
  `organism-class` (e.g. *enterobacteriaceae family*), and a second tier refines
  class → species. This is the thing that makes MYCIN MYCIN, and it is the **only**
  corpus move that also exercises the engine in a new way: multi-hop Rete
  propagation and — the genuinely under-tested path — **belief flowing *through* a
  belief-valued intermediate**. Under DS a chained conclusion combines mass on an
  intermediate that already carries `[bel, pl]`; that composition is barely
  touched today and is exactly the kind of thing this fork exists to make visible.

**Recommendation:** default new breadth to (A) for speed, but deliberately build
**one** chained cluster via (B) — the taxonomic refinement in §5 is the natural
candidate — precisely to put the intermediate-belief path under load. Treat (B)
as a spike with its own DS goldens before scaling it.

> This is where §1's "engine capability" axis re-enters: chaining is corpus work
> that buys engine coverage. Flat breadth never does.

### 3.1 Alternative representation — this is *classification* (parked)

Step back from the rule encoding and (B) is, in KR terms, **instance recognition**:
an individual with observed features (`gram neg`, `rod`, facultative…) is recognized
as a member of the most-specific concept it satisfies (Enterobacteriaceae →
*E. coli*). That is the home turf of a **description-logic classifier** — the KL-ONE
lineage, and specifically **LOOM** (USC/ISI, Robert MacGregor; a Common-Lisp DL
*classifier* + instance *recognizer* fused with a production/rule layer). In a DL you
*declare* concepts by necessary-and-sufficient conditions and let the classifier
place both the concepts and the instance; §3(B) instead hand-codes that placement one
`defrule` at a time. Doing it in Rete is reinventing a small, manual classifier out
of production rules.

**The design question, if ever pursued.** Classical DLs are **crisp and monotonic** —
subsumption is boolean; LOOM/CLASSIC/KL-ONE have no belief layer. Neomycin's whole
thesis is the opposite. So the interesting split — and it lands exactly on §1's two
axes — is:

- **DL/classifier for the structure**: the organism taxonomy and *which* concepts an
  instance can fall under (the knowledge-breadth axis, declared not enumerated).
- **The belief system for the uncertainty**: `[bel, pl]` on the *recognition*, not on
  the subsumption. The taxonomy names the candidates; DS says how much we believe the
  instance is each. This un-welds "what are the possible identities" from "how
  confident am I" — which every current `defrule` conflates.

**Fidelity (§4).** A classifier would be a *modernization* — explicitly
neomycin-extrapolation, not historical MYCIN, which predates KL-ONE. The adjacent
*historical* thread is Clancey's NEOMYCIN and its explicit disease taxonomy —
next-door to a classifier, and the reason the naming rhyme keeps paying off.

**The substrate is not a hard constraint.** Lisa being a Rete production engine is
where we *start*, not a wall. This is a genuine fork, not a light re-skin: the
inference engine itself is fair game to extend **beneath the corpus layer** — to
serve DS reasoning more directly and, if ever, to host classification/recognition.
The honest frame is engine-axis work (§1) with real weight and real cost — *not*
"can't, it's Rete." Parking here is about **sequence** (overlay first), not about
foreclosing the idea.

---

## 4. Provenance policy — reconstruction, not invention

This is a *research reconstruction*; a larger corpus makes fidelity a first-class
concern, not an afterthought.

- **Cite the source per rule.** Historical MYCIN rules are documented — Shortliffe,
  *Computer-Based Medical Consultations: MYCIN* (1976); Buchanan & Shortliffe,
  *Rule-Based Expert Systems: The MYCIN Experiments* (1984), whose appendices list
  a substantial rule subset. The current base descends from the PAIP/EMYCIN subset
  (`mycin.lisp:25`). Proposal: a lightweight comment or `:provenance` convention
  marking each rule as **genuine-MYCIN** (with citation), **PAIP-subset**, or
  **neomycin-extrapolation**. A reader must be able to tell curated history from
  our own additions in a diff.
- **Be honest about the numbers.** "~600 rules" is the commonly cited lifetime
  figure; the verbatim published listings are a subset, and much of the original
  base was therapy/context logic, not organism ID. We should not imply a fidelity
  we don't have — reconstruct a *cited* subset well rather than hand-invent a large
  set to hit a count.
- **The name is a citation too.** Clancey's **NEOMYCIN** (~1981) restructured
  MYCIN's rules to separate *diagnostic strategy* (metarules / task structure) from
  *domain knowledge*, for the GUIDON tutoring work — precisely the §1 "engine vs.
  corpus" split, made historical. If we ever pursue (B)/chaining and explicit
  strategy, that lineage is the reference point, and worth an honest nod given what
  this fork is named.

---

## 5. Candidate clusters to reconstruct next

Ranked by value-per-effort for *this fork's* goals (DS legibility + fidelity):

1. **Taxonomic refinement of the gram-neg rods** *(chaining, decision B).*
   ✅ **DELIVERED** as v0.3.0, and since **generalized**: the gram-positive increment
   applied the identical template to three more genera (staphylococcus, streptococcus,
   enterococcus), each of which had the same genus-masquerading-as-a-leaf-identity
   defect C2 fixed here. Four organism-classes across three chained clusters now. The
   pattern proved cheap to repeat — the second application cost far less than the
   first, which is the usual sign the abstraction was the right one.

   `enterobacteriaceae` is currently a leaf. Historically it's a family:
   *E. coli, Klebsiella, Enterobacter, Serratia, Proteus, Salmonella*. Evidence →
   `organism-class enterobacteriaceae` → competing **sibling species**. This yields
   the richest DS conflict material we can add (many near-tied hypotheses on one
   organism) *and* is the natural home for the §3(B) intermediate layer. Highest
   value.
2. **Significance / contaminant context.** MYCIN judged whether an organism was a
   real pathogen or a skin/collection contaminant (e.g. coagulase-negative staph
   from a single blood draw). A `significance` parameter at the **culture/organism**
   level, gating whether an identity should drive therapy at all. Maps cleanly onto
   the existing context tree; introduces a genuinely different *kind* of rule
   (context judgment, not identity).
3. **Portal-of-entry / site breadth.** Expand `infection-site` and `culture-site`
   coverage (urinary, csf, skin/soft-tissue, wound) with site-conditioned identity
   rules. Pure breadth (decision A), cheap, and directly widens realistic scenarios
   for the LLM driver.
4. **More disconfirming rules — esp. biochemical cross-disconfirmation among the
   enterobacteriaceae siblings.** ✅ **DELIVERED** (`feature/sibling-cross-disconfirmation`,
   design `docs/sibling-cross-disconfirmation-design.md`): four new cross-disconfirming
   rules (red pigment −0.8, indole+ −0.6, lactose-fermenter −0.7, lactose-non-fermenter
   −0.6) generalize the urease pattern, so the observed session case now pulls **both**
   E. coli and Serratia below `pl 1.0` (E. coli [0.26, 0.41], Serratia [0.375, 0.625]).
   Original sketch retained below for context.

   Adding contradiction rules across the new species
   (§6) is the cheapest way to keep ignorance intervals meaningful as breadth grows.
   The sibling discriminators are currently **confirming-only except urease** (the
   lone cross-disconfirming rule, `urease-pos-argues-against-urease-negative-organism`,
   from slice C1) — so two mutually-exclusive siblings can both sit at `pl 1.0`.
   **Observed live in a clinician session 2026-07-30** (`sessions/session-20260730-171510.md`):
   an aerobic gram-neg rod read lactose+/indole+ (E. coli, `bel 0.64`) and then red
   pigment (Serratia, `bel 0.60`), leaving **both at plausibility 1.0** with neither
   pulling the other down, even though one organism can't be both. Biologically the
   discriminators *are* mutually informative: red pigment argues **against** E. coli
   (E. coli makes no prodigiosin), and indole-positive argues **against** Serratia
   (typically indole-negative). Reconstructing those as negative-belief rules — the
   urease rule's pattern, generalized — would turn a contradictory biochemical into
   real DS conflict (`pl` dropping below 1.0 on the loser) instead of silent
   co-plausibility. Highest-fidelity, lowest-effort DS enrichment now that the family
   has six species. (The engine handles it already; this is pure corpus authoring +
   goldens.)
5. **Host-factor modifiers.** ✅ **DELIVERED** (`feature/gram-positive-cluster` slice D,
   design `docs/gram-positive-cluster-design.md` §3.3): five patient-level rules —
   neutropenia → Pseudomonas (0.5), prosthetic material → S. epidermidis (0.6), IV drug
   use → S. aureus (0.55), neonate → S. agalactiae (0.7), urinary → S. saprophyticus
   (0.65). Three further candidates (neutropenia → viridans, asplenia → pneumococcus,
   catheter → Proteus) were scoped and deferred to hold the corpus at 50.

   One honest finding from building it: **"modifier" describes intent, not mechanism.**
   These rules assert an `organism-identity` like every other confirming rule, so what
   they actually do is contribute an additional independent mass that *combines* with
   the existing one. A true modifier would scale a belief already held — which the
   engine does not express. That is engine-axis work (§1), noted and not done.

   Original sketch retained: age, steroids, neutropenia, prosthetic material —
   patient-level `param-mixin`s that shift beliefs rather than name organisms.
   Good CF-vs-DS material (weak modifying evidence), low structural risk.
6. **Clinical-syndrome conclusions (e.g. necrotizing fasciitis).** *A different
   conclusion TYPE, not just more organisms — logged 2026-07-26.* A syndrome sits
   *over* organisms: NF is Type II mono-microbial (*S. pyogenes* / Group A Strep),
   Type I polymicrobial (mixed anaerobes + Enterobacteriaceae), Type III *Vibrio
   vulnificus* (marine exposure). Modeling it needs (a) a new
   `syndrome`/`clinical-diagnosis` conclusion class distinct from
   `organism-identity`, and (b) a new evidence modality — clinical/lab signs (pain
   out of proportion, crepitus/gas, rapid progression, an LRINEC-style lab score)
   rather than Gram-stain morphology. This is the §3(B) abstraction layer seen from
   the *top* (syndrome as a higher conclusion), and it also stresses the therapy
   layer, whose real NF answer is urgent surgical debridement + empiric
   broad-spectrum + clindamycin — a *non-drug intervention* the set-cover solver
   can't yet represent. High concept value, real scope: a deliberate increment, not
   a bolt-on. **Verify clinical specifics against a source (e.g. Wikipedia) before
   authoring — do not work from memory.**
7. **WHY/HOW explanation & provenance facility** *(engine/bridge axis, not a corpus
   cluster — logged 2026-07-29).* MYCIN's single most famous feature, which neomycin
   has **not** reconstructed. Today a clinician can see *which* rules fired
   (`/rule-trace`), the resulting `{bel, pl, ignorance}` (`/conclusions`), and
   near-firing rules' beliefs (`/partial-matches`) — but (a) the per-rule **citations
   are invisible**: they live only as source comments in `rulebase.lisp`, surfaced by
   nothing, so the LLM never sees them; and (b) the belief **derivation is
   LLM-reconstructed, not engine-authoritative** — the engine returns the final
   interval, not "this = class 0.8 × rule 0.8, Dempster-combined from rules A,B," so
   the narration could be subtly wrong. The increment: promote provenance from
   comments to a machine-readable `:provenance` rule property (§4, §10.2) — genuine-
   MYCIN / PAIP-subset / neomycin-extrapolation + citation — and add an explanation
   payload (a `/why` endpoint, or provenance on `/conclusions`) returning the
   authoritative **composition arithmetic AND the citations**, so "how did you arrive
   at this belief?" becomes a first-class, trustworthy query the LLM narrates from real
   data. On-brand for the fork (DS legibility) and the NEOMYCIN name (Clancey's explicit
   strategy/explanation lineage). Strong candidate for the increment *after* the
   enterobacteriaceae chain lands.

*Deliberately deferred:* the full therapy-rule corpus (the therapy phase already
owns that surface); anything requiring numeric lab reasoning beyond the existing
`white-blood-count`-style categoricals.

*Near-term light taste (post-antibiogram, logged 2026-07-26):* drop in *S. pyogenes*
(NF Type II) and *Vibrio vulnificus* as ordinary `organism-identity` rules — the
latter pairing naturally with a new `marine-exposure` param (sibling to
`recent-travel`). This is honest **organism breadth only** (decision A), explicitly
*not* NF-the-syndrome (candidate 6): a fun, low-risk warm-up, not the syndrome model.

---

## 6. Shape over size — what actually stresses DS

A corpus weighted toward confirmatory 1-hop rules would grow breadth while leaving
the belief machinery idle. To make growth *earn* the DS thesis, weight it toward:

- **Competing hypotheses on one organism** (the §5.1 siblings) — this is where
  `pl` diverges from `bel` and ignorance becomes legible.
- **Disconfirming rules paired with each new confirming cluster** (§5.4) — keep
  `pl < 1.0` reachable, or DS collapses toward CF.
- **Belief-valued intermediates** (§3B) — the under-tested composition path.

500 confirmatory-only rules would barely move an ignorance interval. Fifty
well-shaped ones would move it a lot. **Shape is the spec; size is a byproduct.**

---

## 7. How it lands on the existing structure

Concretely, each cluster is additive against `mycin.lisp` as it stands:

- **New parameters** → new `param-mixin` subclasses at the right context level
  (`significance` on culture/organism; host factors on patient). One `defclass`
  each; no schema change.
- **New identities** → new `organism-identity` values; the `conclusion` rule
  reports them with no edit.
- **New intermediates (B)** → a new derived class (e.g. `organism-class`) that is
  *both* a rule conclusion and a rule premise. This is the only structurally novel
  piece — a `param-mixin`-like class that appears on both sides of `=>`. Worth
  isolating and DS-golden-testing on its own.
- **Disconfirming rules** → copy the `mycin.lisp:277` template with the new
  hypothesis value list.
- **Scale/organization** → at ~50+ rules, split the single file into a small
  `rules/` directory by cluster (identity-gram-neg, identity-gram-pos, context,
  host-factors), loaded together. Diff-reviewability (therapy design principle #3)
  is the reason to split before it gets unwieldy.
  > ✅ **DONE** (slice E), at 50 rules / 1312 lines — so the ~40 guess in §10.3 was
  > about right. Eight files: `context` (must load first), `identity-gram-neg`,
  > `chain-enterobacteriaceae`, `chain-gram-pos`, `host-factors`, `disconfirming`,
  > `conclusion`, `drivers`. One thing the sketch did not anticipate: because rules had
  > accumulated in *authoring* order, the split had to **reorder** as well as cut. That
  > is safe here — both belief combinators are commutative — and the suite returning
  > byte-identical results proved it, but it is worth knowing that the cut is not
  > purely mechanical. Grouping by cluster rather than by date is most of the value.

No new context tree, no belief-algebra changes, no bridge changes for the identity
side. The overlay/therapy layer is untouched.

---

## 8. The testing problem a big corpus forces

Today's harness fires **each rule in isolation against a hand-verified golden**
(`tests/scenarios.lisp`). That is excellent and does **not** scale to hundreds of
rules — nobody hand-verifies 200 belief goldens, and doing so by capturing engine
output just tests the engine against itself.

A larger corpus needs a **complementary** strategy, not a replacement:

- Keep hand goldens for a **representative core** (the current 18 + a few per new
  cluster).
- Add **property/invariant tests** that hold for *any* rule: a single confirming
  rule contributes exactly its `:belief`; a disconfirming rule drops `pl` below
  1.0; CF and DS agree absent conflict and diverge under it. These already exist as
  behavioral tests — generalize them to run across the whole corpus mechanically.
- For chained clusters (§3B), add **targeted** DS goldens for the
  intermediate-belief composition specifically — that path is worth hand-verifying
  because it's new.

Flag this early: the moment we pass ~30–40 rules, the golden-per-rule model is the
thing that breaks first.

> ✅ **DONE** (gram-positive increment, slice E). `neomycin/test/property-tests.lisp`
> holds the corpus-wide invariants, checked by introspecting the compiled rulebase so
> a new rule is covered the moment it is authored. The hand goldens were *kept* — all
> 50 rules are still fired in isolation — exactly as this section proposed.
>
> The prediction held, but the failure mode was not the one anticipated here. Nobody
> struggled to hand-verify 50 goldens; what actually rotted was **cross-references
> between rules**. Ruling-out rules name their targets in literal `(test (member ?value
> '(...)))` lists, and those go stale *silently* when a species is retired or promoted
> to a class — the rule still compiles, still fires, and simply never matches the dead
> value again. No golden notices, because a disconfirming rule that has stopped
> disconfirming still passes every test that does not exercise it. That happened three
> times in this increment and once in C2. The staleness guard is now the most valuable
> test in the file, and the §10.4 question ("which invariants are truly universal?")
> is answered in practice: the universal ones are about *consistency between* rules,
> not about any rule in isolation.

---

## 9. Scope & non-goals (for whenever this is picked up)

- **In (a first increment):** one chained cluster (§5.1, decision B) with DS
  goldens; provenance convention (§4); enough disconfirming rules to keep DS honest
  (§6); the property-test generalization (§8).
- **Out:** the full historical therapy corpus (therapy phase owns it); explicit
  diagnostic *strategy*/metarules (Clancey-style — a separate, engine-level project,
  not corpus); numeric lab reasoning; any real clinical validation.
- **Always:** NOT FOR CLINICAL USE. Fidelity here means *faithful to documented
  1970s MYCIN*, never *clinically current*.

---

## 10. Open questions (resolve at a spike, if/when scheduled)

1. **How far to chain (§3).** One intermediate tier (class → species), or deeper?
   Recommend stopping at one tier for the first cut — enough to load the
   belief-through-intermediate path without a combinatorial rule explosion.
2. **Provenance mechanism (§4).** Comment convention vs. a real `:provenance` rule
   property the bridge could surface. Start with comments; promote only if the LLM
   narration would benefit from citing a rule's pedigree.
3. **File split threshold (§7).** At what rule count does `rules/` beat one file?
   Guess ~40; confirm by feel.
4. **Property-test coverage (§8).** Which invariants are truly universal across all
   rules vs. cluster-specific? Enumerate before generalizing the harness.

Suggested first step, when the antibiogram overlay is done and this rises to the
top: a §5.1 + §3B spike — reconstruct the enterobacteriaceae family as one chained
cluster with cited provenance and DS goldens for the intermediate composition. It's
the smallest thing that exercises breadth, fidelity, *and* the one engine path a
corpus can actually stress.

---

## 11. What the 27 → 50 increment actually taught us

Recorded because the answers differed from the guesses above, and the next increment
should start from the answers.

1. **Q10.1 — how far to chain?** One tier still looks right, but the *number* of
   clusters matters more than their depth. Going from one chained cluster to three
   bought far more DS behaviour than a second tier would have, and cost less.
2. **Q10.2 — provenance mechanism?** Settled long since (the WHY/HOW facility promoted
   it to a real rule property), and it paid off unexpectedly here: `:provenance :note`
   became the natural place to record *source disagreement*, not just sources. The
   E. faecalis/faecium rules carry a note saying two references conflict on whether
   arabinose alone discriminates — which is why those rules require a reciprocal sugar
   pair and sit at 0.7 rather than 0.8. A comment convention could not have surfaced
   that to the LLM.
3. **Q10.3 — file-split threshold?** ~40 was a good guess; 50 was comfortable. See §7.
4. **Q10.4 — which invariants are universal?** Answered in §8: the ones about
   *consistency between* rules, not about rules in isolation.
5. **New, unanticipated: verify the biology before pricing the belief.** Two rule
   beliefs ended up calibrated to figures found during citation checking rather than
   chosen by feel — bacitracin → S. pyogenes at 0.85 because up to 10% of S. pyogenes
   are bacitracin-resistant, novobiocin → S. saprophyticus at 0.8 against a reported
   93% positive predictive accuracy. Neither number is invented. Doing the citation
   pass *before* authoring, rather than as documentation afterwards, is what made that
   possible, and it also killed one planned rule shape outright.
6. **New: the identification/therapy seam is where silent holes appear.** Seven species
   were added across two slices and none was treatable until the genus `deffamily`
   entries landed — no error, just a regimen quietly failing to cover them. There is
   now a property test asserting every concluded identity is treatable.
