# End-to-end session — the shared frame, narrated

**Captured 2026-08-17 against the live stack**: `system-prompt.md` + `tools.json` →
Claude → the HTTP bridge → the engine, under the default shared-frame belief system.
Run with `driver.py --plain --no-transcript`; the clinician turns are verbatim below.

This is the release check that the layers agree with each other. The unit suite tests
the engine, `bin/*.sh` tests the bridge, and `prompt-tests.lisp` tests the prompt's
text — but none of them puts the model in the loop, and it was that gap which had let
three `tools.json` descriptions go stale while the suite stayed green.

**The numbers the model narrated match the pinned goldens exactly.** Compare
`frame-culture-1a` in `neomycin/test/frame-tests.lisp`: pseudomonas
`[0.482759, 0.689655]`, klebsiella `[0.310345, 0.517241]`, `K = 0.420000`.

What this confirms the model does with the new payloads, none of which existed before
v0.9.0:

- reports **conflict K** as a reason to treat figures as unstable, rather than
  quoting a renormalized number as settled;
- reports the **set-valued mass** — "family-level support is strong, species-level
  discrimination isn't" — as the honest headline;
- answers *"could it be something you don't model?"* from **`other-organism`**
  plausibility, naming Acinetobacter and Stenotrophomonas as realistic gaps;
- says plainly that **nothing argues against Klebsiella** — the inference the old
  prompt got wrong, where a lowered plausibility was taken as proof a ruling-out rule
  had fired.

**One narration nuance worth fixing.** The model describes the three pseudomonas rules
as belief "climbing" 0.4 → 0.6 → 0.7. The derivation records do show those successive
projections, so it invented nothing — but under cautious accumulation the three do not
combine: they read the *same* gram-negative rod, so the operator keeps the strongest
and discards the rest. "Climbed" implies accumulation where the truth is "the
strongest won." A clearer composition string would remove the ambiguity.

---

Clinician: 
Assistant: Now let me check what partial matches exist before running full inference, to see what additional facts would help.

Assistant: Here's what the evidence supports so far.

**Facts asserted:** serious burn, immunocompromised host, hospital-acquired (ICU), blood culture at 3 days, aerobic gram-negative rod.

## Conclusions (Dempster-Shafer, shared frame)

**Pseudomonas** — belief 0.48, plausibility 0.69 (ignorance 0.21)
Three rules combined here (`explain_conclusion` shows the chain):
- **"gram-neg-rod-in-burn-patient-suggests-pseudomonas"** (rule belief 0.4) — burns are a classic setup for *P. aeruginosa* bacteremia (StatPearls NBK557831; NCBI Bookshelf NBK8326)
- **"gram-neg-rod-in-compromised-host-suggests-pseudomonas"** (0.6) — Pseudomonas as a major opportunist in immunocompromised hosts
- **"hospital-acquired-aerobic-gram-neg-rod-suggests-pseudomonas"** (0.7) — nosocomial aerobic GNR pathogen, especially ICU bacteremia/VAP

These three combined to a belief of 0.48 with plausibility capped at 0.69 — the ceiling isn't 1.0 because some of that evidentiary mass is shared with rival Enterobacteriaceae hypotheses.

**Klebsiella** — belief 0.31, plausibility 0.52 (ignorance 0.21)
This one chains through a derived **enterobacteriaceae** class: the aerobic-gram-negative-rod finding first committed 0.8 mass to "one of {E. coli, Klebsiella, Salmonella, Enterobacter, Serratia, Proteus, Pseudomonas, other-organism}" (a family-level rule, neomycin-extrapolation, NCBI Bookshelf NBK8035). Off that class, two rules then refined toward Klebsiella specifically:
- **"hospital-acquired-enterobacteriaceae-in-compromised-host-suggests-klebsiella"** (0.6) — Klebsiella as a leading nosocomial pathogen in immunocompromised inpatients (Podschun & Ullmann, Clin Microbiol Rev 1998; StatPearls NBK519004)
- **"enterobacteriaceae-in-compromised-host-suggests-klebsiella"** (0.5) — same association, host-factor alone

## Important caveats

- **Conflict (K) is 0.42** at the organism level — fairly high. That means the rules that fired genuinely disagree (burn/compromised/hospital-acquired evidence is being split between Pseudomonas and the Klebsiella-refined-from-Enterobacteriaceae reading), and the renormalized figures above should be treated as somewhat unstable rather than a settled differential.
- **A meaningful chunk of belief (0.166 mass) sits at the *set* level** — "one of {E. coli, Klebsiella, Salmonella, Enterobacter, Serratia, Proteus, Pseudomonas, other-organism}" — not resolved to a species. That's the honest state of the evidence right now: family-level aerobic-GNR support is strong, species-level discrimination isn't yet.
- Checking the full frame, **E. coli, Salmonella, Enterobacter, Serratia, and Proteus** are all still technically on the table (bel 0, but pl ≈ 0.21 each) — nothing has argued against them specifically, they simply haven't been positively supported yet.
- **Bacteroides is effectively excluded** (pl ≈ 0.04) — aerobic growth argues against an anaerobe.
- **"Other-organism"** (something this corpus doesn't model) still carries plausibility ≈ 0.21 — worth keeping in mind, not zero.

## What would sharpen this

To resolve the Enterobacteriaceae-vs-Pseudomonas question and pin down species, the most useful next tests are the family discriminators: **lactose, indole, motility, urease, pigment** (these split E. coli/Klebsiella/Enterobacter/Serratia/Proteus/Salmonella from each other). Also worth asking: **is the patient neutropenic?** There's a rule ("neutropenia-with-aerobic-gram-neg-rod-suggests-pseudomonas") that's one fact away from firing and would add further weight to Pseudomonas specifically if positive.

Would you like to supply any of those, or should I go ahead and check therapy coverage for the current differential (Pseudomonas + Klebsiella, plus the residual Enterobacteriaceae-family uncertainty)?

Clinician: 
Assistant: Good pair of questions — let me answer both from what the engine actually computed.

## Why Pseudomonas outranks Klebsiella

It comes down to **how many rules fired for each, and against what shared evidence pool.**

Pseudomonas picked up **three separate confirming rules**, each adding its own mass on top of the last (`explain_conclusion` shows the running belief):
1. `gram-neg-rod-in-burn-patient-suggests-pseudomonas` → committed 0.400 to {pseudomonas}
2. `gram-neg-rod-in-compromised-host-suggests-pseudomonas` → belief climbed 0.4 → 0.6
3. `hospital-acquired-aerobic-gram-neg-rod-suggests-pseudomonas` → belief climbed 0.6 → 0.7 (before renormalization against the pool, landing at 0.48 bel / 0.69 pl)

Every one of the patient's risk factors — burn, compromised host, hospital-acquired — has a rule that points **directly** at Pseudomonas by name.

Klebsiella, by contrast, only reaches the diagnosis **indirectly**: it first has to pass through the derived `enterobacteriaceae` class (the 0.8-mass rule that spreads belief across eight possible organisms — E. coli, Klebsiella, Salmonella, Enterobacter, Serratia, Proteus, Pseudomonas, and other-organism), and only *then* do two rules narrow that down toward Klebsiella specifically (`hospital-acquired-enterobacteriaceae-in-compromised-host-suggests-klebsiella` at 0.6, and `enterobacteriaceae-in-compromised-host-suggests-klebsiella` at 0.5). Because that first step spreads its mass eight ways rather than committing it all to one organism, Klebsiella's final belief (0.31) ends up lower than Pseudomonas's (0.48) even though the same clinical facts are feeding both chains.

So it isn't that anything argues *against* Klebsiella — nothing does. It's that Pseudomonas has direct-hit rules for every risk factor in this case, while Klebsiella has to share its supporting evidence with six other family members before narrowing back down. That's also the source of the **0.42 conflict (K)** I flagged earlier: the same burn/compromised/hospital-acquired facts are being claimed by both chains, and the engine had to renormalize away the portion that can't simultaneously belong to both.

## Could this be something the corpus doesn't model?

Yes — genuinely, not as a hedge. In the `frame.hypotheses` list, **`other-organism` sits at bel 0.0, pl 0.207**. That plausibility ceiling comes from the same family-level rule that spread mass across the eight-member set (E. coli, Klebsiella, Salmonella, Enterobacter, Serratia, Proteus, Pseudomonas, *and* other-organism) — the rule authors explicitly left room for "an aerobic gram-negative rod that isn't one of these seven" when they wrote that rule.

So as things stand: there's roughly a **21% plausibility ceiling** that this is some aerobic gram-negative rod outside the 17 named organisms this corpus can identify (e.g., Acinetobacter, Stenotrophomonas — both realistic in a burn/ICU context but simply not in this knowledge base). It hasn't been *supported* (bel is 0), but it hasn't been excluded either, and I'd be overstating the system's reach if I implied the differential was limited to the two named organisms above.

If you want to shrink that residual uncertainty, the lactose/indole/motility/urease/pigment panel would help pin down whether this really is a named Enterobacteriaceae species or Pseudomonas specifically — narrowing the "other" possibility isn't something further biochemistry on the modeled panel can fully resolve, though, since it's a coverage gap in the corpus itself rather than a fact the rules are waiting on.

Clinician: 