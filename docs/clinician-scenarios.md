# Clinician Scenarios for the MYCIN Rulebase

A curated set of vignettes for driving neomycin's 46-rule rulebase
(`neomycin/rules/` — **not** Lisa's `examples/mycin.lisp`) through the Claude driver
(`src/llm/claude/driver.py`) and the HTTP bridge. Each scenario is written the way a
clinician might present a case at the bedside, and each is annotated with:

- **Facts to extract** — what Claude should turn the vignette into
- **The answers given** — what each rule's evidence narrowed the question to, and how strongly
- **The differential** — belief, plausibility, and where relevant the conflict

**Every figure below was captured from the running engine**, not computed by hand. If
you re-run a scenario and get something else, the corpus has moved and this document
is the thing that is wrong.

> **Re-captured in full at v0.13**, after Category B replaced the singleton context
> rules with graded answers. Every scenario was re-run and every number re-read; the
> ones that moved are annotated with what they used to say and why. Scenario 5 changed
> character entirely (its rule was retired) and Scenarios 8 and 10 gained different
> regimens. Re-measuring rather than hand-editing found three defects that no test had
> caught — see the commit history for `docs/clinician-scenarios.md`.

## How the corpus answers

Read this once; it governs how every scenario below reads.

**A rule states an ANSWER** — the set of organisms its evidence narrows the question
to — and asserts it with a belief. `beta hemolysis` answers *"one of {S. pyogenes,
S. agalactiae}"* at 0.75. A single-organism answer is just a set of size one.

**Some answers are GRADED.** A bench finding treats its members as indistinguishable,
which is right — beta hemolysis really has no view on group A versus group B. An
**epidemiological** rule does have a view, and carries it as a distribution over the
set: the burn rule answers *"one of these six at 0.40, and 0.20 of that is on
Pseudomonas"*. Nine rules in the corpus are graded, all of them context rules. Two
consequences run through every scenario below:

  * **A graded answer excludes nothing.** A burn makes Pseudomonas likelier; it does not
    make Klebsiella impossible. Before v0.13 these rules answered with a single organism
    and therefore claimed exactly that, which the literature does not support.
  * **A graded answer is not an identification.** Leaning is not naming. Where a
    differential is built only from context rules, the honest headline is that the
    culture has not been discriminated — see Scenarios 1, 2 and 4.

**Exclusion is never authored.** No rule carries a negative belief and no rule argues
against anything. Organisms fall out because answers are combined by intersection:
{pyogenes, agalactiae} and {pneumoniae} cannot both hold, and that emptiness *is* the
ruling-out. So when a scenario below shows an organism's plausibility falling, look
for the answer that named something else — there is no rule that objected.

**A genus is a set.** There is no organism-class and nothing chains. "Is this a
staphylococcus?" is a question about {aureus, epidermidis, saprophyticus}, and the
algebra answers it directly. No belief is the product of two others.

**Coarse answers are conclusions, not way-stations.** When the evidence supports
"one of these seven" and nothing more, that is the finding — reported as `set_valued`
mass. Several scenarios below have their honest headline there rather than on any
single organism.

**Conflict (K) is a reading, not an error.** It measures belief committed to
combinations that cannot all be true. When it is high the evidence genuinely disagrees
with itself, and every figure from that run should be given with that caveat.

## What the scenarios cover

Scenarios 1–7 work the gram-negative base. 9 and 10 cover the biochemical
Enterobacteriaceae discriminators and the therapy family-backstop. 11 exercises the
WHY/HOW explanation facility and 14 the rule catalogue. 12 and 13 cover the
gram-positive cocci. 8 and 15 are therapy: the antibiogram overlay and the objective
dial.

**Scenario 5 changed character at v0.13** and is worth reading for that reason: the rule
it used to demonstrate was retired as a wrong conditional, so it now demonstrates
**inert vocabulary** instead — a fact the clinician can report, the bridge will accept,
and no rule will read.

**If you only run two:** Scenario 9 and Scenario 12. Scenario 9 shows five answers of
different resolutions *agreeing* — nested sets, conflict zero, belief climbing to
0.88. Scenario 12 shows two answers that cannot both hold, conflict at 0.72, and a
hypothesis losing plausibility without anything having argued against it. Together
they are the whole representation in two cases.

## How to Run

Start the bridge:

```bash
# Dempster-Shafer over an open frame (the default, and what the corpus is written for)
sbcl --load lisa.asd \
     --eval '(load "lisa-bridge.asd")' \
     --eval '(load "neomycin.asd")' \
     --eval '(asdf:load-system :neomycin)' \
     --eval '(lisa-bridge:start)'
```

(Or simply `(load "neomycin.lisp")`, the convenience loader that does the above and
starts the bridge on 8090.)

`LISA_BELIEF_SYSTEM=cf` and `=ds` still select certainty factors and the Barnett
per-hypothesis frame, but **they are Lisa substrate, not neomycin options**: neither
has a set algebra, so neither can reason over a candidate-set answer. The
three-algebra comparison this document used to carry is reproducible on the
**v0.10.0 tag** and not after it.

Then start the driver in another shell:

```bash
export ANTHROPIC_API_KEY=sk-...
python src/llm/claude/driver.py
# transcripts land in ./sessions/session-YYYYmmdd-HHMMSS.md by default
```

Transcript flags: `--no-transcript`, `--transcript-verbosity {minimal,normal,full}`,
`--transcript-dir PATH`. See `driver.py --help`.

---

## Scenario 1 — PAIP culture-1 baseline

> "I have a 27-year-old female burn patient. She's obviously immunocompromised.
> Blood culture: gram-negative rods, aerobic, three days old."

**Facts to extract**:
`burn=serious` (patient-1), `compromised-host=t` (patient-1), `culture-site=blood`,
`culture-age=3`, `gram=neg` (organism-1), `morphology=rod`, `aerobicity=aerobic`.

**The answers given**:

| belief | narrows to | from |
|---|---|---|
| 0.70 | the eight gram-negatives | `gram-negative-narrows-to-gram-negatives` |
| 0.80 | the seven aerobic gram-negative rods | `aerobic-gram-neg-rod-narrows-to-aerobic-gram-neg-rods` |
| 0.40 | the six opportunist rods, **graded** | `burn-blood-aerobic-gram-neg-rod-narrows-to-opportunist-rods` |
| 0.60 | the six opportunist rods, **graded** | `compromised-aerobic-gram-neg-rod-narrows-to-opportunist-rods` |

The last two are **graded answers** — they distribute their belief across the set
rather than spreading it evenly, and they lean in *opposite directions*:

| rule | grading |
|---|---|
| burn | 0.20 on {pseudomonas} · 0.08 on {e-coli, proteus, serratia} · 0.07 on {klebsiella} · 0.05 on {enterobacter} |
| compromised host | 0.28 on {e-coli} · 0.16 on {klebsiella} · 0.08 on {pseudomonas} · 0.08 on {enterobacter, proteus, serratia} |

**The differential** — `K = 0.180`, ignorance 0.018, margin 0.234:

| organism | bel | pl |
|---|---|---|
| **e-coli** | 0.232 | 0.564 |
| **pseudomonas** | 0.176 | 0.468 |
| **klebsiella** | 0.165 | 0.458 |
| enterobacter | 0.029 | 0.381 |
| proteus, serratia | 0.000 | 0.398 |
| salmonella | 0.000 | 0.293 |
| bacteroides | 0.000 | 0.059 |

Set-valued: **0.234** on the seven aerobic gram-negative rods, 0.059 on
{enterobacter, proteus, serratia}, 0.041 on all eight.

Four things worth narrating. **Nothing has been excluded** — every rod retains
plausibility, because the only evidence is a stain and two facts about the patient.
**The two context rules lean opposite ways**, which is what `K = 0.180` measures: a
burn raises Pseudomonas, an immunocompromised host raises E. coli, and they genuinely
disagree without either being wrong. **The biggest single figure is the set-valued
0.234**, not any organism — the honest headline is that the culture has not been
discriminated yet, and a lactose or indole result is what would do it. And **E. coli
leads**, which surprises people who know the PAIP case: see the note below.

> **Why not Pseudomonas?** Before v0.13 this scenario returned pseudomonas at 0.613 and
> looked decisive. It reached that number by asserting that a burn made Klebsiella,
> E. coli, Enterobacter, Serratia and Proteus *impossible* — which burn-unit
> surveillance does not support. With the exclusion gone, the ranking is decided by the
> two rules' relative commitments (0.4 for burn against 0.6 for compromised host), and
> those are `:illustrative` figures that were never tied to evidence. The smaller,
> flatter numbers are the honest ones. See `docs/category-b-resolution-survey.md` §5C.

The anchor case in the README, and the one the smoke tests pin.

---

## Scenario 2 — Hospital-acquired immunocompromised gram-negative

> "62-year-old male, been inpatient for two weeks with a central line.
> Immunocompromised — chemo. New fevers. Blood culture: gram-negative rods, aerobic."

**Facts to extract**:
`compromised-host=t`, `hospital-acquired=t`, `culture-site=blood`, `gram=neg`,
`morphology=rod`, `aerobicity=aerobic`.

**The answers given**: the same two coarse answers as Scenario 1 (0.70 on the eight,
0.80 on the seven), plus **one graded answer at 0.60** from
`hospital-acquired-compromised-aerobic-gram-neg-rod-narrows-to-opportunist-rods`:

| grading |
|---|
| 0.28 on {e-coli} · 0.21 on {klebsiella} · 0.12 on {pseudomonas} · 0.09 on {enterobacter, proteus, serratia} |

**One graded answer, not three — this is the subsumption case.** Three context rules
fire here: compromised-host (0.60), hospital-acquired (0.70), and the
hospital-acquired-AND-compromised rule (0.60) whose premises are a strict superset of
both. It conditions on everything they do and more, so both are dropped and only its
distribution counts. That is production-rule specificity applied to belief.

The dropped rules are **absent from the explanation too**, not merely from the
arithmetic — an answer carrying a belief that no surviving rule stands behind would be
an attribution-free number in a clinical explanation.

**The differential** — `K = 0.000`, ignorance 0.018, margin 0.070:

| organism | bel | pl |
|---|---|---|
| **e-coli** | 0.280 | 0.580 |
| **klebsiella** | 0.210 | 0.510 |
| **pseudomonas** | 0.120 | 0.420 |
| enterobacter, proteus, serratia | 0.000 | 0.390 |
| salmonella | 0.000 | 0.300 |
| bacteroides | 0.000 | 0.060 |

Set-valued: 0.240 on the seven, 0.090 on {enterobacter, proteus, serratia}, 0.042 on
all eight.

**`K` is exactly zero**, and that is the instructive part. One graded answer nested
inside two coarser ones cannot contradict anything — there is only one epidemiological
opinion in the room, because the specific rule displaced the two general ones. Contrast
Scenario 1, where a burn and a compromised host disagreed and K was 0.180. Zero conflict
does not mean high confidence: E. coli leads at 0.280 with plausibility 0.580, so the
case is *unconflicted and unresolved*, which is a different thing from settled.

**The margin is 0.070, and it is now measuring the right thing.** It used to read 0.320,
because the largest focal mass in the case was the uninformative seven-member set and
the leader was being compared against nothing in particular. Raising this rule's
commitment at v0.14 (see below) made `{e-coli}` the largest focal mass instead, so the
margin now reports what a clinician actually wants: E. coli is 0.070 clear of
Klebsiella. A smaller number carrying far more information.

> **These figures moved at v0.14**, and the reason is a coherence fix rather than a
> recalibration. This rule committed **0.60** while the hospital-acquired rule it
> *subsumes* committed 0.70 — and because the specificity policy DROPS the subsumed
> rule, the corpus was committing 0.60 where it would have committed 0.70 on strictly
> less information. Learning that a hospital-acquired patient was *also* immunocompromised
> made it less sure. Raised to 0.70 with the focal masses rescaled in the same
> proportions, so the distribution's shape — which the literature decides — is
> untouched. Invariant 16 now forbids the inversion.

All three named organisms clear the therapy coverage gate (0.1) — see Scenario 8.

---

## Scenario 3 — Respiratory strep in an immunocompromised patient

> "45-year-old woman, HIV-positive with a low CD4 count, presenting with pneumonia.
> Sputum and blood cultures both showing gram-positive cocci in chains."

**Facts to extract**:
`compromised-host=t`, `culture-site=blood`, `infection-site=respiratory` (patient-1),
`gram=pos`, `morphology=coccus`, `growth-conformation=chains`.

**The answers given**:

| belief | narrows to |
|---|---|
| 0.70 | the nine gram-positives |
| 0.70 | the six chain-formers — **four streptococci and both enterococci** |
| 0.70 | {enterococcus-faecalis, enterococcus-faecium} |
| 0.75 | {pneumoniae, viridans, pyogenes}, **graded** — 0.45 on {pneumoniae} · 0.20 on {viridans} · 0.10 on {pyogenes} |

**The differential** — `K = 0.525`, ignorance 0.014, margin 0.084:

| organism | bel | pl |
|---|---|---|
| **streptococcus-pneumoniae** | 0.284 | 0.442 |
| **streptococcus-viridans** | 0.126 | 0.284 |
| **streptococcus-pyogenes** | 0.063 | 0.221 |
| enterococcus-faecalis, enterococcus-faecium | 0.000 | **0.526** |
| streptococcus-agalactiae | 0.000 | 0.158 |
| the three staphylococci | 0.000 | 0.047 |

Set-valued: **0.368 on {faecalis, faecium}**, 0.111 on the six chain-formers, 0.033 on
all nine.

**This is the scenario where the set-valued figure is the headline.** The leading named
organism is pneumococcus at 0.284 — but 0.368 of the belief sits on "one of the two
enterococci, the evidence does not say which", and each enterococcus individually has a
plausibility ceiling (0.526) far above pneumococcus's belief. Narrating this as
"pneumococcus" and stopping would be technically true and clinically misleading.

Note that **viridans now carries belief** (0.126) where it used to carry none. The
respiratory rule used to answer {pneumoniae} alone, which claimed a respiratory
specimen growing chains could not be viridans — and viridans streptococci both dominate
oropharyngeal flora and cause community-acquired pneumonia in their own right. That was
the most clinically misleading exclusion in the gram-positive half of the corpus. The
margin of 0.084 is the honest reading of how little separates the leaders.

It is also the best case for goal-directed questioning. Morphology cannot separate
streptococci from enterococci — the chain-former answer names all six — so the useful
question is obvious: **hemolysis** splits the streptococci three ways, and
**bile-esculin plus salt tolerance** confirms the enterococci. Ask for whichever is
available.

---

## Scenario 4 — Tropical traveler with gram-negative rod

> "Patient just back from two weeks in Southeast Asia. Bloody diarrhea, now febrile.
> Blood culture: gram-negative rods, aerobic."

**Facts to extract**:
`recent-travel=tropical` (patient-1), `culture-site=blood`, `gram=neg`,
`morphology=rod`, `aerobicity=aerobic`.

**The answers given**: 0.70 on the eight gram-negatives, 0.80 on the seven aerobic
rods, and **0.65 on the enteric rods, graded** — 0.42 on {salmonella} · 0.15 on
{e-coli} · 0.08 on {klebsiella} — from
`tropical-travel-aerobic-gram-neg-rod-narrows-to-enteric-rods`.

This is the context rule that kept the most content through Category B, because it is
the only one that points *away* from the opportunist set rather than around inside it:
travel to an endemic region genuinely raises the enteric organisms. What it can no
longer claim is that E. coli bacteraemia stops happening because the patient
travelled.

**The differential** — `K = 0.000`, ignorance 0.021, margin 0.270:

| organism | bel | pl |
|---|---|---|
| **salmonella** | 0.420 | 0.770 |
| **e-coli** | 0.150 | 0.500 |
| **klebsiella** | 0.080 | 0.430 |
| enterobacter, proteus, pseudomonas, serratia | 0.000 | 0.350 |
| bacteroides | 0.000 | 0.070 |

Set-valued: 0.280 on the seven, 0.049 on the eight.

**Conflict is zero** — every answer given is consistent with Salmonella, and the graded
answer sits *inside* both coarse ones, so all three agree and nothing competes.
Contrast Scenario 1, where two graded answers leaned different ways and K was 0.180.

Salmonella leads clearly (0.420 against E. coli's 0.150) but its plausibility is 0.770
rather than the 1.000 it used to show, because the rule now commits part of its 0.65 to
the two enteric rivals instead of all of it to Salmonella. The 0.350 shared by the four
rods the rule does not name is the honest statement that the evidence has not touched
them individually.

---

## Scenario 5 — Sepsis with low WBC

> "Elderly patient, septic, WBC is 2.1 — quite low. Blood culture: gram-negative rods."

**Facts to extract**:
`white-blood-count=low` (patient-1), `culture-site=blood`, `gram=neg`,
`morphology=rod`. (Aerobicity not yet available — this is an early-in-the-case
scenario.)

**The answers given**: one only — **0.70 on the eight gram-negatives**.

**The differential** — `K = 0.000`, ignorance **0.300**:

Every organism has `bel 0.000, pl 1.000`. The whole 0.70 sits as **set-valued mass on
the eight gram-negatives**, and the remaining 0.30 is ignorance.

**Read that carefully, because it is the case most easily narrated wrongly.** Nothing
has been concluded about any *individual* organism, but something substantial has been
concluded: it is one of eight, at 0.70. Under the old representation this scenario
reported nothing at all and the doc described it as "the family stays out of reach". It
was never out of reach — the coarse answer was always the finding, and the
representation could not say so.

`pl 1.000` on all eight is correct and means what it says: no evidence has spoken
against any of them.

### The low white count changes nothing, and that is now the point

**This scenario was rewritten at v0.13.** It used to continue: add
`aerobicity=aerobic`, the rule `blood-low-wbc-aerobic-gram-neg-rod-narrows-to-salmonella`
fires, and Salmonella lands at 0.55 — "one fact moved the case from *one of eight* to a
named organism."

**That rule has been retired**, so adding `aerobicity=aerobic` now gives only the 0.80
aerobic-rod answer: still `bel 0.000` on every organism, `pl 0.200` on bacteroides and
`1.000` on the seven, ignorance 0.060. **The white blood count is doing no work at
all.**

It was retired because it was the wrong conditional. The rule fired **on** a low white
count, so it owed P(Salmonella | low WBC); the 15–25% figure it cited is
P(low WBC | typhoid) — a *sensitivity*, and a weak one, since a normal or raised count
is commoner in typhoid and does not exclude it. Correcting the conditional does not
rescue the rule either: leukopenia in gram-negative bacteraemia marks **severity, not
species**, occurring across E. coli, Klebsiella and Pseudomonas sepsis alike. The
honest answer is the whole aerobic set, which adds nothing the Gram stain already said.

**So this scenario now demonstrates INERT VOCABULARY**, which is the more useful lesson.
`white-blood-count=low` is still assertable — a clinician reporting it should have it
recorded — but no rule reads it, the assertion succeeds, and nothing moves. That silence
is invisible unless the corpus declares it, which is why `describe_rules` reports
`summary.parameters` and why the fact tables mark inert values with a dagger (†).

**What Claude must do here**: assert the count for the record, and then *not* narrate it
as having contributed. Asking for a low white count as a discriminating test would be
worse still. The discriminating questions in this case are the biochemical ones —
lactose, indole, motility, urease, pigment — exactly as in Scenario 10.

---

## Scenario 6 — Abdominal anaerobe

> "Post-op appendectomy patient with an abdominal source. Culture from the collection
> shows gram-negative rods, anaerobic."

**Facts to extract**:
`infection-site=abdominal` (patient-1), `gram=neg`, `morphology=rod`,
`aerobicity=anaerobic`. (`culture-site=blood` is **not** asserted — the culture is from
the abdominal collection.)

**The answers given**: 0.70 on the eight gram-negatives, and **0.80 on {bacteroides}**.

**The differential** — `K = 0.000`, ignorance 0.060: **bacteroides `bel 0.800,
pl 1.000`**; the other seven at `bel 0.000, pl 0.200`.

**If the clinician also reports a positive blood culture** (`culture-site=blood`), the
classic PAIP rule fires alongside and the two reinforce to **0.98**:

bacteroides `bel 0.980, pl 1.000`, everything else `pl 0.020`, ignorance 0.006.

That is the tightest conclusion the gram-negative base can produce, and it is tight for
the right reason: two independent lines of evidence gave the *same* answer, so they
reinforce and nothing competes. Note that the aerobic-rod answer (which excludes
Bacteroides) never fires here — the organism is anaerobic, so that rule's premises are
not met. Nothing had to argue the anaerobe back in.

---

## Scenario 7 — Ambiguous gram stain (conflict from the bench)

> "Same 27-year-old burn patient as before, but the microbiologist is hedging:
> **probably gram-negative** rods on the slide, but they say **possibly gram-positive**
> — the stain wasn't great. Blood culture, anaerobic organism."

**Facts to extract** (note the confidence values driven by the hedging):
`burn=serious`, `compromised-host=t`, `culture-site=blood`,
`gram=neg` with `confidence=0.8` ("probably"), `gram=pos` with `confidence=0.6`
("possibly"), both on organism-1; `morphology=rod`, `aerobicity=anaerobic`.

**The answers given**:

| belief | narrows to |
|---|---|
| 0.70 | the eight **gram-negatives** |
| 0.70 | the nine **gram-positives** |
| 0.90 | {bacteroides} |

**The differential** — `K = 0.368`, m(Θ) 0.113, margin 0.579:

| organism | bel | pl |
|---|---|---|
| **bacteroides** | 0.661 | 0.918 |
| the seven other **gram-negatives** | 0.000 | 0.257 |
| the nine **gram-positives** | 0.000 | 0.195 |

**This scenario demonstrates conflict from the bench, and it now demonstrates only
that.** A gram stain cannot be both — the two answers share no member, so intersecting
them puts mass on the empty set. **K = 0.368**, and every bit of it comes from the
contradictory stain.

Note that the gram-positives and the gram-negatives no longer sit at the *same*
plausibility. The clinician called the stain **probably** negative and only **possibly**
positive, so the gram-negative reading is the stronger one and the organisms it admits
keep more room (0.257 against 0.195). That difference is the hedge, showing up in the
answer.

> **These figures moved at v0.16, and the reason is worth stating plainly.** This
> scenario used to report `K = 0.679` with bacteroides at `bel 0.841` — and it reported
> exactly those numbers *whatever confidences you asserted*. Evidence belief reached the
> `candidates` facts and went no further: every rule's answer entered combination at the
> rule's own declared `:belief`, so 0.8/0.6 here and 0.8/0.2 in the `culture-2` driver
> produced identical differentials, which is why this document could quote the driver's
> goldens against its own hedge for four releases without anything noticing. Answers are
> now discounted by the strength of the premises that fired them, and the numbers above
> are specific to the 0.8/0.6 hedge described. See `neomycin:answer-mass-of`.

> **An earlier correction, kept because it is a different lesson.** Before v0.13 this
> case read `K = 0.900` with pseudomonas at 0.228, on an organism the corpus knows is an
> **anaerobe**. Two Pseudomonas context rules had never gated on aerobicity, so they
> fired here and asserted an obligate aerobe against {bacteroides}. Part of the conflict
> this scenario attributed to the stain was the corpus contradicting itself. With the
> gates added, Pseudomonas holds no belief at all. Guarded now by invariant 15.

Nothing argues against anything: the gram-positive reading simply names nine organisms,
none of which is Bacteroides, and the arithmetic does the rest.

**What to narrate.** Not the point estimate alone. `bel 0.661` for Bacteroides is a
lead, not an identification, and with K at 0.368 better than a third of the belief in
this run went to combinations that cannot both hold. Read the **margin** with it: 0.579
says the leader is clear of the nearest answer that contradicts it, so unlike the
respiratory-strep case in Scenario 3 (margin 0.084) this is not a tie. The honest report
is: *"Bacteroides is the only answer consistent with an anaerobic gram-negative rod, but
the stain is contradicting itself — repeat it before relying on any of this."* This is
the case that argues most strongly for reading K and margin before reading anything
else.

---

## Scenario 8 — When the local antibiogram changes the answer (therapy overlay)

*Unlike Scenarios 1–7 (identification), this one showcases the **antibiogram overlay**
on the therapy side: the same case, same allergy, yields a **different regimen** once
this ward's local susceptibility counts are folded in.*

**Setup — load the local antibiogram (opt-in).** The schematic site-local counts in
`neomycin/therapy/antibiogram-data.lisp` are **not** loaded by default — the canonical
KB stays the pure reference. To overlay them, add one `load` to the bridge startup:

```bash
sbcl --load lisa.asd \
     --eval '(asdf:load-system :neomycin)' \
     --eval '(load (asdf:system-relative-pathname "neomycin" "neomycin/therapy/antibiogram-data.lisp"))' \
     --eval '(lisa-bridge:start)'
```

Run the case once **without** that `load` line (reference only) and once **with** it.

> "68-year-old man, two weeks inpatient on chemo — immunocompromised, central line.
> New fevers. Blood culture: gram-negative rods, aerobic. He's allergic to carbapenems."

**Facts to extract**: as Scenario 2, plus patient state `allergy-carbapenem` for therapy.

**Identification**: the Scenario 2 differential — e-coli `bel 0.280`, klebsiella
`bel 0.210`, pseudomonas `bel 0.120`, plus **0.240 of set-valued mass on the seven
aerobic gram-negative rods**.

**What the solver is asked to treat**: **all three named organisms**, since all clear
`*coverage-threshold*` (0.1) — plus the seven-member set as a coverage obligation in
its own right, discharged member by member.

> **Pseudomonas sat EXACTLY on the gate here at v0.13**, at 0.100, and that turned out
> to be a live bug rather than a curiosity. Beliefs are double-floats; the dial is a
> decimal literal and reads as a single-float, which promotes to 0.10000000149…, so
> `(>= 0.1d0 0.1)` was NIL and Pseudomonas was silently dropped from empiric cover in
> the one case where antipseudomonal cover is the entire clinical question. Fixed at
> v0.13 — the gate now compares in double precision, see `clears-gate-p` — and the
> v0.14 coherence fix moved Pseudomonas to 0.120, off the boundary entirely. **Both
> halves mattered**: the arithmetic was wrong, *and* the corpus should not have had a
> figure sitting on the dial in the first place.

> **On that threshold.** It was 0.2 through v0.10, chosen for a scale on which organism
> beliefs did not compete. Under candidate sets they share one unit of mass, so the same
> evidence yields systematically lower figures and 0.2 became stricter than anyone had
> decided. Recalibrated to 0.1 for v0.11 on a measured plateau. **That plateau
> measurement predates Category B and has not been redone**: graded answers moved every
> runner-up figure and put one of them exactly on the gate, so the dial's justification
> is now weaker than its docstring claims. Re-measuring it is open work, and moving a
> clinical dial as a side effect of a representation change is exactly what the
> docstring says not to do — so it has not been moved.

**Therapy — reference KB** (`recommend_therapy`, `patient=["allergy-carbapenem"]`):

| | drug | dose | covers | `bel` | `pl` | source |
|---|---|---|---|---|---|---|
| regimen | **piperacillin-tazobactam** | 4.5 g IV q6h | e-coli | 0.70 | 0.92 | reference |
| | | | klebsiella | 0.68 | 0.92 | reference |
| | | | pseudomonas | 0.64 | 0.90 | reference |
| | | | + serratia, salmonella, proteus, enterobacter | 0.70 | 0.92 | reference |

One drug covers everything, including all seven members of the set obligation. Meropenem
is **excluded by the allergy** and says so in `excluded`. `alternative_agents`:
ceftazidime, ceftriaxone, ciprofloxacin, gentamicin.

**Note the regimen changed at v0.13, and for a reason worth reading.** It used to be
ceftazidime. Ceftazidime does not cover Salmonella — and Salmonella is a member of the
seven-organism set obligation, which must be discharged *member by member*. With the
differential widened, the obligation is now large enough to matter and ceftazidime can
no longer discharge it, so the solver reaches for the agent that can. This is the
set-obligation machinery from v0.12 doing visible work.

**Therapy — with the local antibiogram loaded**: this ward records **41/48 (85%)
gentamicin-susceptible Pseudomonas**, which promotes gentamicin's anti-pseudomonal
coverage from a reference `[0.48, 0.88]` — below the gate — to `bel 0.82`, and lifts it
above ceftazidime. Its pseudomonas entry reads `source: local-antibiogram,
n_tested: 48`. The reference run *could not* use gentamicin; the local data earned it.

**What Claude should narrate** — cite the sample size, distinguish local from reference:

> *"With this ward's antibiogram, gentamicin covers Pseudomonas at belief 0.82 across
> **48 local isolates** (85% susceptible here) — a data-grounded figure. Klebsiella
> coverage is **reference-only**, so treat that half as provisional pending local
> sensitivities."*

**The other direction — resistance the reference would miss.** This ward's
**ceftazidime-susceptible Klebsiella is 18/40 (45%)** — a local ESBL signal — so that
pair drops from a covering `[0.64, 0.88]` to `[0.48, 0.52]`, below the gate. Where the
reference KB would offer ceftazidime for Klebsiella, the overlay makes the solver reach
elsewhere or report it honestly uncovered. **"Our ward is running 45% this quarter"
beats "the textbook says ~70%."**

> **⚠️ NOT FOR CLINICAL USE.** These counts are schematic, invented to exercise the
> machinery — not real surveillance, never a basis for prescribing.

---

## Scenario 9 — Resolving the Enterobacteriaceae species (biochemistry)

> "Aerobic gram-negative rods from a urine culture. The lab ran biochemicals:
> lactose fermenter, indole positive."

**Facts to extract**:
`gram=neg`, `morphology=rod`, `aerobicity=aerobic`, `lactose=fermenter`,
`indole=positive` (all organism-1).

**The answers given — five, at four different resolutions**:

| belief | narrows to |
|---|---|
| 0.70 | the eight gram-negatives |
| 0.80 | the seven aerobic gram-negative rods |
| 0.70 | {e-coli, enterobacter, klebsiella, serratia} — the lactose fermenters |
| 0.60 | {e-coli, proteus, bacteroides} — the indole producers |
| 0.80 | {e-coli} — the classic IMViC combination |

**The differential** — `K = 0.000`, ignorance 0.001:

| organism | bel | pl |
|---|---|---|
| **e-coli** | **0.884** | **1.000** |
| enterobacter, klebsiella, serratia | 0.000 | 0.080 |
| proteus | 0.000 | 0.060 |
| pseudomonas, salmonella | 0.000 | 0.024 |
| bacteroides | 0.000 | 0.012 |

**This is the corpus's best case, and the one to run first.** Five answers at four
resolutions, every one of them a different piece of evidence, and **conflict is exactly
zero** — because each set contains E. coli, so they are nested rather than competing.
Belief climbs to 0.884, higher than any single rule's figure, purely from agreement.

Note what the narrower answers did to the *others*. Klebsiella's ceiling fell to 0.080
not because anything mentioned Klebsiella, but because it is absent from the indole
answer and from {e-coli}. Nothing was authored to exclude it.

Note also what the indole answer does NOT do. It names Bacteroides, because indole
splits the *B. fragilis* group down the middle and cannot exclude it. That costs this
case nothing — the aerobic-rod answer already excludes the anaerobe, and doing that job
is *its* business, not the indole rule's. Each rule states only what its own evidence
establishes; intersection does the rest. See the authoring policy at the head of
`neomycin/rules/candidates-gram-neg.lisp`.

**The sibling variations** — swap the biochemistry:

| Discriminators | Result |
|---|---|
| red pigment | serratia `bel 0.800, pl 1.000`, K = 0.000 |
| urease+ / swarming | proteus `bel 0.800, pl 1.000`, K = 0.000; a set-valued 0.14 sits on the four urease producers |
| lactose+ / indole− / motile | **nothing named** — see below |

**The motile variation is the interesting one.** Lactose+, indole−, motile gives:

| organism | bel | pl |
|---|---|---|
| enterobacter | 0.000 | **1.000** |
| serratia | 0.000 | **1.000** |
| e-coli, klebsiella | 0.000 | 0.400 |

with **0.600 of set-valued mass on {enterobacter, serratia}** and K = 0.000. The corpus
declines to choose. Motility separates Enterobacter from non-motile Klebsiella but not
from Serratia, and rather than inventing a preference the rule answers "one of these
two" and stops. Narrating this as "Enterobacter" would be wrong; the answer is
*"a motile lactose-fermenting Enterobacteriaceae — Enterobacter or Serratia — and the
pigment test would settle it."*

**Contradictory biochemistry** — add a red pigment reading to the lactose+/indole+ case:

> "…lactose fermenter, indole positive, **and a red pigment on the plate**."

Now {e-coli} at 0.80 and {serratia} at 0.80 are both asserted, and they cannot both
hold:

| organism | bel | pl |
|---|---|---|
| **e-coli** | 0.670 | 0.758 |
| **serratia** | 0.242 | 0.303 |

**K = 0.736.** E. coli stays ahead because three answers admit it and only one admits
Serratia — but three quarters of the belief went to an impossibility, and the honest
narration says the bench results contradict each other and asks for a repeat, rather
than reporting E. coli at 67%.

---

## Scenario 10 — Family backstop when the species won't resolve (therapy)

> "Aerobic gram-negative rods in the blood. No host risk factors noted, and we don't
> have biochemicals back yet. What can we start empirically?"

**Facts to extract**:
`culture-site=blood`, `gram=neg`, `morphology=rod`, `aerobicity=aerobic` (organism-1).

**Identification**: two coarse answers only — 0.70 on the eight gram-negatives, 0.80 on
the seven aerobic rods. **No organism has any belief of its own**; 0.80 of set-valued
mass sits on the seven.

**Therapy — set obligations, discharged member by member**: with no species named,
what the solver must cover is the **sets themselves**. Two of them clear the gate:

| obligation | mass | members |
|---|---|---|
| the aerobic rods | 0.800 | e-coli, enterobacter, klebsiella, proteus, pseudomonas, salmonella, serratia |
| all gram-negatives | 0.140 | the seven above **+ bacteroides** |

| | drug | dose | covers | `bel` | `pl` |
|---|---|---|---|---|---|
| regimen | **meropenem** | 1 g IV q8h | e-coli, enterobacter, proteus, serratia | 0.90 | 0.99 |
| | | | klebsiella | 0.88 | 0.99 |
| | | | salmonella | 0.82 | 0.97 |
| | | | bacteroides | 0.80 | 0.96 |
| | | | pseudomonas | 0.72 | 0.92 |

Nothing uncovered, and both obligations report `uncovered: []`. `alternative_agents`:
ceftazidime, ceftriaxone, ciprofloxacin, gentamicin, metronidazole,
piperacillin-tazobactam. `alternative_regimens`: piperacillin-tazobactam alone.

**A set obligation is discharged MEMBER BY MEMBER, never through a therapy family.**
This section used to describe a "family backstop" that collapsed the coarse answer onto
`:enterobacteriaceae` and treated that as one item. Both halves of that were unsound and
v0.12 removed them: a KB family can read *covered* at 0.66 while a member sits at 0.46
below the susceptibility threshold, and mass committed to "one of these seven" is
committed to no member in particular, so a member clearing the coverage gate does not
discharge it. Measured at the time: four of sixty scenario × patient × objective
configurations were silently under-covering.

**Note the second obligation is why Bacteroides is in the regimen's coverage list.**
The 0.140 sitting on all eight gram-negatives includes an anaerobe, so the chosen agent
has to cover one — and meropenem does. `ceftazidime` no longer appears among the
alternative *regimens* for the same reason it lost Scenario 8: it cannot discharge a
set containing Salmonella.

Claude should offer the discriminating tests (lactose, indole, motility, urease,
pigment) that Scenario 9 shows resolving the species, and note that a named species
narrows the recommendation from family-level to species-level.

---

## Scenario 11 — "Why, and how confident?" (WHY/HOW explanation)

*Not a new case: a follow-up any clinician asks. It exercises the WHY/HOW facility —
the LLM answers from the engine's authoritative record via `explain_conclusion` →
`/why`, never from its own recollection of the arithmetic or the literature.*

Run Scenario 1 to conclusion, then ask:

> "Why Klebsiella, and how confident should I be? What's that based on?"

`explain_conclusion` with `{"organism": "klebsiella"}` returns the **argument** —
`bel 0.165`, `pl 0.458`, `K 0.180`, and four answers, **every one of which admits it**:

| admits? | belief | narrows to | grading (mass on klebsiella) | rule |
|---|---|---|---|---|
| ✔ | 0.70 | the eight gram-negatives | — flat | `gram-negative-narrows-to-gram-negatives` (`paip-subset`) |
| ✔ | 0.80 | the seven aerobic rods | — flat | `aerobic-gram-neg-rod-narrows-to-aerobic-gram-neg-rods` (`neomycin-extrapolation`) |
| ✔ | 0.40 | the six opportunist rods | leans pseudomonas 0.20; **0.07 on klebsiella** | `burn-blood-aerobic-gram-neg-rod-narrows-to-opportunist-rods` (`paip-subset`) |
| ✔ | 0.60 | the six opportunist rods | leans e-coli 0.28; **0.16 on klebsiella** | `compromised-aerobic-gram-neg-rod-narrows-to-opportunist-rods` (`paip-subset`) |

`intersection`: the six opportunist rods — **not** `["klebsiella"]`.

**This scenario changed shape at v0.13, and what it now teaches is more useful.** It
used to show an answer with `admits: false` — a flat `{pseudomonas}` answer that
excluded Klebsiella — and the lesson was that such answers are returned deliberately,
because nothing argues against anything and a hypothesis loses ground only when other
evidence names something else. **That lesson is unchanged and still load-bearing**, but
it no longer has an example here: the context rules grade instead of excluding, so
every answer in this case admits Klebsiella. For a case that still shows an
`admits: false` row, see **Scenario 12**, where a bench finding does the excluding —
which is where exclusion belongs.

**What this case teaches instead is how to read a graded argument.** Klebsiella is held
at 0.165 not by any objection but by *where the two context rules put their mass*: the
burn rule gives it 0.07 of its 0.40 while giving Pseudomonas 0.20, and the
compromised-host rule gives it 0.16 of its 0.60 while giving E. coli 0.28. Read only
`narrows_to`, and all four answers look like unanimous support. Read `grading`, and you
can see Klebsiella coming third in both. **`mass_for_organism` is the field that makes
this narratable**, and an explanation that omits it will overstate the case.

**The wide `intersection` is a finding, not a gap.** When every answer is
epidemiological, the intersection stays wide, and that is the honest signal that the
culture has not been discriminated. A narrator should say so and name the bench test
that would settle it.

**There is no arithmetic to quote.** Nothing composes one belief through another, so
`/why` has no multiplication to report — a change from the pre-v0.11 payload, which
narrated a composition string.

**The provenance, quoted and verified.** Each rule carries `origin`, literature
`evidence` (NCBI Bookshelf NBK8035 / NBK519004 among others for the compromised-host
rule) and `belief_basis: illustrative`. **Claude must say the 0.165 is a schematic
figure, not a measured probability** — the citations verify the *association*, never
the number. That applies to the **grading** as well: the focal masses follow published
proportions, but the total each rule commits is the same illustrative figure it always
carried, so no part of a graded answer is a measured quantity.

The payload also carries a `narrative` field, a plain-language rendering of the whole
argument that can be quoted verbatim.

---

## Scenario 12 — Hemolysis contradicts the site (gram-positive conflict)

> "Sputum culture from a chest infection — gram-positive cocci in chains. The bench has
> just phoned through beta hemolysis, bacitracin sensitive."

**Facts to extract**:
`infection-site=respiratory` (patient-1), `culture-site=blood`, `gram=pos`,
`morphology=coccus`, `growth-conformation=chains`, `hemolysis=beta`,
`bacitracin=sensitive`.

**The answers given**:

| belief | narrows to |
|---|---|
| 0.70 | the nine gram-positives |
| 0.70 | the six chain-formers |
| 0.75 | {streptococcus-agalactiae, streptococcus-pyogenes} — beta-hemolytic |
| 0.85 | {streptococcus-pyogenes} — bacitracin-sensitive |
| 0.75 | {pneumoniae, viridans, pyogenes}, **graded** — 0.45 · 0.20 · 0.10 — the respiratory site |

**The differential** — `K = 0.626`, ignorance 0.002, margin 0.790:

| organism | bel | pl |
|---|---|---|
| **streptococcus-pyogenes** | 0.835 | 0.935 |
| streptococcus-pneumoniae | 0.045 | 0.070 |
| streptococcus-viridans | 0.020 | 0.045 |
| streptococcus-agalactiae | 0.000 | 0.100 |
| the enterococci | 0.000 | 0.025 |
| the staphylococci | 0.000 | 0.008 |

Set-valued: 0.075 on {agalactiae, pyogenes}.

**The clinical picture and the bench result disagree, and the corpus says so without
any rule mentioning the disagreement.** The site answer leans pneumococcus; the
hemolysis answers "group A or B". **K = 0.626** is the size of that contradiction, and
pneumococcus falling to `bel 0.045` is the consequence — not a rejection.

**The bench result won more decisively than it used to, and that is the improvement.**
Before Category B the site rule answered {pneumoniae} flat, so it contradicted
{pyogenes, agalactiae} outright: K was 0.722 and pyogenes reached only 0.764. The
graded rule now *admits* pyogenes at 0.10, so part of what used to be conflict is
agreement, and the bacitracin result is left further ahead (0.835). An epidemiological
prior should yield to a bench finding rather than fight it to a standstill, and here it
visibly does.

**Good narration**: *"the beta hemolysis points to a group A or B strep and the
bacitracin result names group A — that's a bench call at 0.835. The respiratory site
did favour pneumococcus, but it's a weaker kind of evidence and it doesn't exclude
anything; pneumococcus is still on the table at plausibility 0.07. The two findings do
genuinely disagree (K = 0.63), and the margin of 0.79 says the bench answer is a long
way clear."*

**Bad narration**: "pneumococcus is ruled out" (it isn't — it retains belief), or
"a rule argued against pneumococcus" (none did, and none can).

**Variation — when the two agree.** Swap `hemolysis=alpha` and `optochin=sensitive`:

| organism | bel | pl |
|---|---|---|
| **streptococcus-pneumoniae** | **0.903** | **0.954** |
| streptococcus-viridans | 0.041 | 0.092 |
| streptococcus-pyogenes | 0.005 | 0.018 |

**K = 0.266**, against 0.626 when the findings disagreed. Same cluster, same two
evidence streams, opposite outcome — and the clearest signal remains K, now read
alongside a margin of 0.862.

> K is no longer *zero* here, and the residue is honest rather than a defect. The site
> answer is graded and puts 0.10 on pyogenes, while the alpha-hemolysis answer
> {pneumoniae, viridans} excludes pyogenes — so a small slice of the site rule's mass
> genuinely conflicts with the bench result. Before Category B the site rule answered
> {pneumoniae} flat, sat nested inside everything, and produced a tidy K = 0.000. The
> tidiness came from a claim the rule could not support.

---

## Scenario 13 — A host factor reinforcing a bench result

> "Neonate, five days old, blood culture positive. Gram-positive cocci in chains,
> beta-hemolytic, bacitracin resistant."

**Facts to extract**:
`age-group=neonate` (patient-1), `culture-site=blood`, `gram=pos`, `morphology=coccus`,
`growth-conformation=chains`, `hemolysis=beta`, `bacitracin=resistant`.

**The answers given**: 0.70 on the nine gram-positives, 0.70 on the six chain-formers,
0.75 on {agalactiae, pyogenes}, and **0.91 on {streptococcus-agalactiae}** — two rules
reinforcing, the bacitracin-resistant one (0.70) and the neonatal host factor (0.70).

**The differential** — `K = 0.000`, ignorance 0.002:

| organism | bel | pl |
|---|---|---|
| **streptococcus-agalactiae** | **0.910** | **1.000** |
| streptococcus-pyogenes | 0.000 | 0.090 |
| everything else | 0.000 | ≤ 0.023 |

**The deliberate counterpart to Scenario 12.** There, two evidence streams reached
mutually exclusive answers and three quarters of the belief went to conflict. Here they
reach the *same* answer, reinforce to 0.91, and K is zero. That contrast is the whole
demonstration: conflict is reported when it exists and stays silent when it doesn't.

It also makes the case for host factors concrete. `age-group=neonate` costs nothing and
has no lab turnaround, and it lifted the call from 0.70 to 0.91. **Ask for host factors
early.**

**Honest caveat to state when narrating**: the rule keys on the neonatal age band, and
group B strep leads early-onset neonatal sepsis in *term* infants — in preterm infants
E. coli is commoner. That scoping is in the rule's provenance and
`explain_conclusion` returns it.

---

## Scenario 14 — Interrogating the rulebase itself (the catalogue)

*Not a case: a question **about the corpus**. It exercises the rule catalogue — the LLM
answers from the compiled rulebase via `describe_rules` → `/rules`, because the system
prompt deliberately does not carry a copy of it.*

Ask cold, before asserting anything:

> "Which single test best discriminates within the streptococci, and how heavily does
> the system weight it?"

Claude should call `describe_rules` with `names=streptococcus-pneumoniae` (or any
species in the group). **`?names=` returns every rule whose answer still admits that
organism** — seven for pneumococcus, from the 9-member gram-positive answer down to the
1-member optochin answer:

| rule | belief | resolution | narrows to |
|---|---|---|---|
| `gram-positive-narrows-to-gram-positives` | 0.70 | 9 | all gram-positives |
| `chains-narrows-to-chain-formers` | 0.70 | 6 | streptococci + enterococci |
| `catalase-negative-narrows-to-chain-formers` | 0.70 | 6 | same, different evidence |
| `bile-esculin-negative-narrows-to-streptococci` | 0.60 | 4 | the four streptococci |
| `respiratory-chains-narrows-to-pneumoniae` | 0.75 | 3 | {pneumoniae, viridans, pyogenes}, **graded** |
| `alpha-hemolysis-narrows-to-alpha-hemolytic-strep` | 0.75 | 2 | {pneumoniae, viridans} |
| `optochin-sensitive-narrows-to-pneumoniae` | 0.85 | 1 | {pneumoniae} |

**The resolution column is the answer to the question.** Hemolysis is the branch point
because it takes the answer from 6 organisms to 2 in one test, and the disc tests then
take it from 2 to 1. A good reply names that progression and quotes the beliefs
exactly, not approximately.

**Note the respiratory rule sits at resolution 3, not 1, and carries a `grading`.** It
is the only epidemiological rule in this list, and it is the one a clinician is most
likely to over-read: it *leans* pneumococcus (0.45 of its 0.75) but admits viridans
(0.20) and pyogenes (0.10). A reply that reported it as a 1-organism rule — as this
table used to — would be describing a test that discriminates, when what it describes
is a prior that ranks. **The lesson for narration: read `resolution` and `grading`
together.** A low resolution means the evidence genuinely narrows; a grading means it
merely leans.

`?premises=beta` asks it from the other side — which rules read a beta-hemolysis
result — and returns four: `beta-hemolysis-narrows-to-beta-hemolytic-strep`, the two
bacitracin discriminators, and the neonatal host-factor rule.

**What a good answer contains**: the rationale from each rule's provenance `note` —
e.g. bacitracin-resistant → agalactiae is only 0.70 *"because groups C and G are also
bacitracin-resistant"*. **What it must not contain**: any belief, premise or citation
stated without a `describe_rules` call behind it.

The corpus `summary` in every response gives the shape: **46 rules, 17 organisms**, and
the resolution distribution — 17 rules naming a single organism, 9 narrowing to a pair,
and 20 answering coarser, up to a 9-member set:

| resolution | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|
| rules | 17 | 9 | 5 | 3 | 1 | 7 | 2 | 1 | 1 |

**That distribution shifted at v0.13 and the shift is the story of this release.**
Single-organism rules used to be the largest block by a wide margin; Category B moved
nine epidemiological rules off resolution 1, because a burn or a compromised host does
not name an organism. What is left at resolution 1 is almost entirely BENCH findings,
which is where a one-organism answer belongs.

An organism absent from `summary.organisms` is one the corpus cannot name at all, and
Claude should say so plainly rather than reasoning about it. Likewise a parameter or
value absent from `summary.parameters` is **inert** — assertable, accepted, and read by
no rule. `white-blood-count` is the current example (see Scenario 5).

Endpoint smoke test: `./bin/test-rules.sh`.

---

## Scenario 15 — The same case under two stewardship objectives

*The therapy solver's **objective** is a policy dial, like the coverage gate. This
scenario turns it and watches one case give two defensible answers. It is also the case
from `exact-solver-design.md` §1.1 — where a clinician asked for a narrower agent and
was told, falsely, that none existed.*

> "Aerobic gram-negative rods in the blood. Biochemicals are back — lactose fermenter,
> indole positive. No host risk factors, no allergies."

**Facts to extract**: `culture-site=blood`, `gram=neg`, `morphology=rod`,
`aerobicity=aerobic`, `lactose=fermenter`, `indole=positive`.

**Identification**: the Scenario 9 result — **E. coli `bel 0.884, pl 1.000`**, K = 0.000.

**Therapy, default objective** (`lexicographic` — drug count, then susceptibility × belief):

| | drug | dose | `bel` | `pl` | ignorance |
|---|---|---|---|---|---|
| regimen | **meropenem** | 1 g IV q8h | 0.90 | 0.99 | 0.09 |

`alternative_regimens`, strongest coverage first: ceftriaxone → piperacillin-tazobactam
→ ceftazidime → gentamicin → ciprofloxacin.

**Therapy, spectrum-sparing** (`objective: "spectrum-sparing"`):

| | drug | dose | `bel` | `pl` | ignorance |
|---|---|---|---|---|---|
| regimen | **gentamicin** | 5–7 mg/kg IV q24h | 0.64 | 0.90 | 0.26 |

`alternative_regimens`, narrowest first: ciprofloxacin → ceftriaxone → ceftazidime →
**meropenem** → piperacillin-tazobactam.

**What the contrast teaches**, in rising order of interest:

1. **The trade is quantified, not asserted.** Narrowing costs coverage floor — 0.90 →
   0.64 — *and* certainty: ignorance widens 0.09 → 0.26. The narrower agent is not
   merely less covering, it is less *known*. Both numbers are in the payload.

2. **The alternatives list is symmetric.** Whichever objective runs, the other's answer
   appears in `alternative_agents`. Neither regimen can imply it was the only option —
   exactly the failure §1.1 records.

3. **The ordering of `alternative_regimens` *is* the objective.** Same five drugs, two
   orders, reversed at the ends. Ask Claude *"why is meropenem last now?"* — the answer
   is the dial, visible in the data rather than asserted in prose.

**What Claude must not do**: present the spectrum-sparing regimen as simply better. It
is narrower *and* less certain.

**The dial's known failure, worth demonstrating deliberately.** Spectrum breadth is
blind to the WHO AWaRe Access/Watch/Reserve axis, which the KB annotates but does not
encode. On an enterococcus case the objective moves from **ampicillin** (AWaRe
*Access*) to **linezolid** (AWaRe *Reserve*) — genuinely narrower, and backwards as
stewardship. Shipped as measured rather than patched, because a dial that visibly does
the wrong thing for a stateable reason teaches more than one quietly constrained until
it looks sensible. Full table: `docs/exact-solver-design.md` §3.6.

> **⚠️ NOT FOR CLINICAL USE.** Gentamicin monotherapy for gram-negative bacteraemia is a
> schematic solver's output, not a therapeutic proposal. The objective optimises a
> declared breadth tier over an illustrative KB; it does not know what this drug does to
> a kidney, or that aminoglycoside monotherapy is not how this is treated.

---

## Rule Coverage Matrix

*Which scenarios make each rule fire, captured by running every scenario and reading
the rules behind each answer. Scenario 14 is deliberately absent: it queries the
catalogue rather than exercising the engine.*

*Re-captured at v0.13 by running every scenario and reading the derivation record.*

| Rule | Scenarios |
|---|---|
| gram-negative-narrows-to-gram-negatives | 1, 2, 4, 5, 6, 7, 9, 10 |
| gram-positive-narrows-to-gram-positives | 3, 7, 12, 13 |
| aerobic-gram-neg-rod-narrows-to-aerobic-gram-neg-rods | 1, 2, 4, 5†, 9, 10 |
| burn-blood-aerobic-gram-neg-rod-narrows-to-opportunist-rods | 1 |
| compromised-aerobic-gram-neg-rod-narrows-to-opportunist-rods | 1, 2§ |
| hospital-acquired-aerobic-gram-neg-rod-narrows-to-opportunist-rods | 2§ |
| hospital-acquired-compromised-aerobic-gram-neg-rod-narrows-to-opportunist-rods | 2 |
| tropical-travel-aerobic-gram-neg-rod-narrows-to-enteric-rods | 4 |
| anaerobic-gram-neg-rod-in-abdomen-narrows-to-bacteroides | 6 |
| anaerobic-gram-neg-rod-in-blood-narrows-to-bacteroides | 6‡, 7 |
| lactose-fermenter-narrows-to-fermenters | 9, 9-motile, 9-conflict |
| indole-positive-narrows-to-indole-producers | 9, 9-conflict |
| lactose-pos-indole-pos-narrows-to-e-coli | 9, 9-conflict |
| motile-lactose-pos-indole-neg-narrows-to-motile-fermenters | 9-motile |
| red-pigment-narrows-to-serratia | 9-pigment, 9-conflict |
| urease-positive-narrows-to-urease-producers | 9-urease |
| urease-pos-swarming-narrows-to-proteus | 9-urease |
| chains-narrows-to-chain-formers | 3, 12, 12-variation, 13 |
| blood-compromised-chains-narrows-to-enterococci | 3 |
| respiratory-chains-narrows-to-pneumoniae | 3, 12, 12-variation |
| beta-hemolysis-narrows-to-beta-hemolytic-strep | 12, 13 |
| bacitracin-sensitive-narrows-to-pyogenes | 12 |
| bacitracin-resistant-narrows-to-agalactiae | 13 |
| neonate-beta-hemolytic-narrows-to-agalactiae | 13 |
| alpha-hemolysis-narrows-to-alpha-hemolytic-strep | 12-variation |
| optochin-sensitive-narrows-to-pneumoniae | 12-variation |

† with `aerobicity=aerobic` added.  ‡ with `culture-site=blood` added.
**§ fires but is SUBSUMED** by the hospital-acquired-and-compromised rule, so it
contributes no mass and is not cited in the explanation. It is listed because it *fired*
— this matrix records rule reachability, not influence.

**Two rows disappeared at v0.13.** `blood-low-wbc-aerobic-gram-neg-rod-narrows-to-salmonella`
was **retired** (Scenario 5), and the burn and compromised-host rules no longer fire in
Scenario 7: that culture is anaerobic, and both are now gated on aerobic growth, which
is the corpus defect Scenario 7 was hiding.

**Fifteen rules fire in no scenario here** — the whole staphylococcus cluster
(`clumps-narrows-to-staphylococci`, `catalase-positive-narrows-to-staphylococci`, the
coagulase pair, the two host-factor aureus rules,
`novobiocin-resistant-narrows-to-saprophyticus`,
`prosthetic-material-coag-neg-narrows-to-epidermidis`,
`urinary-coag-neg-narrows-to-saprophyticus`), enterococcal speciation
(`bile-esculin-salt-tolerant-narrows-to-enterococci`, the sorbitol/arabinose pair),
`catalase-negative-narrows-to-chain-formers`, `bile-esculin-negative-narrows-to-streptococci`,
`optochin-resistant-narrows-to-viridans`, `lactose-non-fermenter-narrows-to-non-fermenters`,
and `neutropenia-aerobic-gram-neg-rod-narrows-to-opportunist-rods`.

This is a **gap in the scenario collection, not in the corpus** — the rules are tested
by the suite and reachable through the catalogue. It is recorded here rather than
papered over, because a coverage matrix that quietly omitted them would read as
coverage.

---

## Notes for Investigators

- **Read K WITH the margin — neither is interpretable alone.** High conflict (9 at
  0.736, 12 at 0.626) means the point estimates survived heavy renormalization. But K
  rises as a winner *strengthens* against rivals, so it is not a reliability score, and
  the cleanest demonstration is that the ORDER can invert: Scenario 7 has the LOWER
  conflict (K = 0.368) and a margin of 0.579, while Scenario 3 has the HIGHER conflict
  (K = 0.525) and a margin of 0.084 — a near-tie. More conflict, less decided. Quote
  them as a pair, always.
- **The best scenarios for reinforcement** are 13 (agalactiae 0.91, K = 0) and
  12-variation (pneumoniae 0.903) — independent evidence reaching the same answer.
- **The best scenarios for honest indecision** are 5 (nothing named at all, 0.70 on the
  eight), 1 (a three-way split with 0.234 sitting on the seven-member set) and 3 (0.368
  on the enterococcal pair). Each has its headline on a *set*, and each is a case where
  naming a single organism would be the wrong answer.
- **Epidemiology ranks; it does not identify.** Scenarios 1, 2 and 4 are built entirely
  from stain plus host context, and none of them names an organism. Their graded
  answers lean — sometimes strongly — but the intersection stays wide and the right
  narration is which bench test would close it. If a scenario built only from context
  rules ever reports a confident single organism again, something has gone wrong.
- **`pl` for an organism no rule mentioned** is answerable and meaningful — it is the
  residual ignorance, and it is the corpus's answer to "could this be something you
  don't model?" In Scenario 1 that is 0.018; in Scenario 5 it is 0.300.
- Every figure here was **re-captured from the engine on the v0.13 corpus** after
  Category B. When beliefs change intentionally, re-capture rather than re-deriving by
  hand — three defects in this pass were found precisely because re-measuring disagreed
  with the prose.