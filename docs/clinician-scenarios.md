# Clinician Scenarios for the MYCIN Rulebase

A curated set of vignettes for driving the 50-rule neomycin MYCIN rulebase
(`neomycin/rules/` — **not** Lisa's `examples/mycin.lisp`) through the
Claude driver (`src/llm/claude/driver.py`) and the HTTP bridge. Each scenario is
written the way a clinician might present a case at the bedside, and each is
annotated with:

- **Facts to be extracted** — what Claude should turn the vignette into
- **Rules expected to fire** — the descriptive rule names from the rulebase
- **Expected differential** — the organism hypotheses and belief behavior,
  contrasted between certainty factors (CF) and Dempster-Shafer (DS)

Together Scenarios 1–7 exercise the gram-negative base directly; Scenarios 9–10 cover
the biochemical enterobacteriaceae species (E. coli, Enterobacter, Serratia,
Proteus) and the therapy family-backstop; Scenario 11 exercises the WHY/HOW
explanation facility; Scenarios 12–13 cover the **gram-positive cocci** — the
staphylococcus, streptococcus and enterococcus clusters, their cross-disconfirming
rules, and the host-factor modifiers. Scenarios 7 and 12 reach the disconfirming
rules. Critically, several cases produce situations where *multiple rules conclude
the same organism* — which is where belief combination becomes visible — and
Scenarios 7 and 12 produce *conflicting* evidence, which is where CF and DS diverge.

**If you only run two:** Scenario 12 is the sharpest CF-vs-DS contrast in the corpus
(a single number going negative versus a bounded interval), and Scenario 13 is its
counterpart where the two algebras agree exactly. Run them back to back.

**A note on organism-classes.** Four keywords are **organism-classes**, not leaf
identities: `enterobacteriaceae` (a family) and `staphylococcus`, `streptococcus`,
`enterococcus` (genera). Evidence derives the *class* first, and specific species are
refined *from* it — so a species' belief is the product of the two, and only species
appear in `/conclusions`. None of the four ever appears as an identity. On the therapy
side the solver still covers a class empirically as a **backstop** when no member
species was pinned down (Scenario 10).

**Scenario 8** steps past identification to the **therapy** side: it shows the
**antibiogram overlay** changing the recommended regimen once a site-local
susceptibility count is folded into the curated figures — local data promoting a
provisional agent and, in the other direction, exposing local resistance the
reference would miss.

## How to Run

Start the bridge under the belief system you want to see:

```bash
# Dempster-Shafer (default). Loads neomycin's canonical rulebase — NOT
# examples/mycin.lisp, which is Lisa-proper and lacks the chained cluster.
sbcl --load lisa.asd \
     --eval '(load "lisa-bridge.asd")' \
     --eval '(load "neomycin.asd")' \
     --eval '(asdf:load-system :neomycin)' \
     --eval '(lisa-bridge:start)'

# Certainty factors (override with the env var)
LISA_BELIEF_SYSTEM=cf sbcl --load lisa.asd ...  (same, just the env var)
```

(Or simply `(load "neomycin.lisp")`, the convenience loader that does the above
and starts the bridge on 8090.)

Then start the driver in another shell:

```bash
export ANTHROPIC_API_KEY=sk-...
python src/llm/claude/driver.py
# transcripts land in ./sessions/session-YYYYmmdd-HHMMSS.md by default
```

You can switch belief systems per session at the `Clinician:` prompt by
asking Claude to reset with a specific system (Claude will pass
`{"belief_system": "ds"}` to `reset_session`), or from the shell:

```bash
curl -sX POST http://localhost:8090/reset \
     -H 'content-type: application/json' \
     -d '{"belief_system":"ds"}'
```

Transcript flags: `--no-transcript`, `--transcript-verbosity {minimal,normal,full}`,
`--transcript-dir PATH`. See `driver.py --help`.

---

## Scenario 1 — PAIP culture-1 baseline

> "I have a 27-year-old female burn patient. She's obviously
> immunocompromised. Blood culture: gram-negative rods, aerobic, three days
> old."

**Facts to extract**:
`burn=serious` (patient-1), `compromised-host=t` (patient-1),
`culture-site=blood`, `culture-age=3`, `gram=neg` (organism-1),
`morphology=rod`, `aerobicity=aerobic`.

**Rules that fire**:
- `gram-neg-rod-in-burn-patient-suggests-pseudomonas` (0.4)
- `gram-neg-rod-in-compromised-host-suggests-pseudomonas` (0.6)
- `aerobic-gram-neg-rod-suggests-enterobacteriaceae-class` (0.8) — derives the family class (tier 1)
- `enterobacteriaceae-in-compromised-host-suggests-klebsiella` (0.5, tier-2) — commits 0.5 to {klebsiella}; under the shared frame the class evidence corroborates rather than discounts, and klebsiella lands at [0.286, 0.571] after conflict (under `ds` it composes multiplicatively to 0.8×0.5 = 0.40)

**Expected differential** (identities in `/conclusions`):
- **Pseudomonas** — two rules conclude it, so belief combines.
  - CF: `~0.76` (0.4 ⊕ 0.6 = 0.4 + 0.6 − 0.24)
  - DS: `bel ~0.76`, `pl 1.0`, `ignorance ~0.24`
- **Klebsiella** — a *chained* (tier-2) refinement of the enterobacteriaceae
  family: its belief composes through the class (0.8 × 0.5), landing lower.
  - CF: `0.40`, DS: `bel 0.40, pl 1.0, ignorance 0.60`
- **Enterobacteriaceae (class, not an identity)** — the derived organism-*class*
  at `0.8` sits behind Klebsiella but does **not** appear in `/conclusions`. Ask
  for lactose/indole/motility/urease/pigment to resolve the species further.

This is the canonical case for showing "multiple rules → belief
combination" (on pseudomonas), and simultaneously for showing how a
single-rule *chained* hypothesis (Klebsiella) produces a wide ignorance
interval under DS — a nuance CF collapses to a single number.
It's also the anchor case in the README.

---

## Scenario 2 — Hospital-acquired immunocompromised gram-negative

> "62-year-old male, been inpatient for two weeks with a central line.
> Immunocompromised — chemo. New fevers. Blood culture: gram-negative rods,
> aerobic."

**Facts to extract**:
`compromised-host=t`, `hospital-acquired=t`, `culture-site=blood`,
`gram=neg`, `morphology=rod`, `aerobicity=aerobic`.

**Rules that fire**:
- `gram-neg-rod-in-compromised-host-suggests-pseudomonas` (0.6)
- `aerobic-gram-neg-rod-suggests-enterobacteriaceae-class` (0.8) — derives the family class (tier 1)
- `hospital-acquired-enterobacteriaceae-in-compromised-host-suggests-klebsiella` (0.6, tier-2)
- `hospital-acquired-aerobic-gram-neg-rod-suggests-pseudomonas` (0.7)
- `enterobacteriaceae-in-compromised-host-suggests-klebsiella` (0.5, tier-2)

**Expected differential** (identities in `/conclusions`):
- **Pseudomonas** — two rules → combined belief. CF ~0.88; DS bel ~0.88, low
  ignorance.
- **Klebsiella** — two *chained* (tier-2) rules → combined belief, each composing
  through the family (0.8×0.6 and 0.8×0.5). CF ~0.688; DS bel ~0.688.
- **Enterobacteriaceae (class, not an identity)** — derived at 0.8, sits behind
  Klebsiella but is not itself in `/conclusions`.

Good two-way species differential (Pseudomonas + Klebsiella), both with multi-rule
support. Exercises the hospital-acquired branch of the chained rules.

---

## Scenario 3 — Respiratory strep in an immunocompromised patient

> "45-year-old woman, HIV-positive with a low CD4 count, presenting with
> pneumonia. Sputum and blood cultures both showing gram-positive cocci in
> chains."

**Facts to extract**:
`compromised-host=t`, `culture-site=blood`,
`infection-site=respiratory` (patient-1), `gram=pos`, `morphology=coccus`,
`growth-conformation=chains`.

**Rules that fire**:
- `gram-pos-cocci-in-chains-suggests-streptococcus-class` (0.7) → organism-class
- `gram-pos-cocci-in-chains-in-blood-compromised-suggests-enterococcus` (0.7) → organism-class
- `respiratory-gram-pos-cocci-in-chains-suggests-strep-pneumoniae` (0.75, tier-2)

**Expected differential**:
Two genus *classes* are derived — streptococcus and enterococcus, both at 0.7 —
but only one leaf **species** is reachable without a bench test:

- **Streptococcus pneumoniae** — CF 0.525, DS bel 0.525 / ignorance 0.475
  (chained: 0.7 class × 0.75 rule)

Neither `streptococcus` nor `enterococcus` appears in `/conclusions`, because both
are organism-*classes* now, not leaf identities. **This is the scenario that best
shows why goal-directed questioning matters**: morphology alone gets you a genus and
one weakly-supported species, and the discriminating question is obvious from the
cluster — *"is there a hemolysis reading?"* Alpha plus optochin-sensitive would push
pneumococcus to 0.595 and combine with the site rule; beta would fire the
cross-disconfirming rule and pull it *down* instead (Scenario 12). A bile-esculin
plus salt-tolerance result would split the enterococcus class into species.

Under the older flat rulebase this scenario reported three co-equal hypotheses at
0.7/0.75/0.7 with nothing to choose between them — a differential that looked
richer than it was, because two of the three were genera masquerading as species.

---

## Scenario 4 — Tropical traveler with gram-negative rod

> "Patient just back from two weeks in Southeast Asia. Bloody diarrhea, now
> febrile. Blood culture: gram-negative rods, aerobic."

**Facts to extract**:
`recent-travel=tropical` (patient-1), `culture-site=blood`, `gram=neg`,
`morphology=rod`, `aerobicity=aerobic`.

**Rules that fire**:
- `aerobic-gram-neg-rod-suggests-enterobacteriaceae-class` (0.8) — derives the family class (tier 1)
- `enterobacteriaceae-with-tropical-travel-suggests-salmonella` (0.65, tier-2)

**Expected differential** (identities in `/conclusions`):
- **Salmonella** — a *chained* (tier-2) refinement: belief composes 0.8 × 0.65.
  CF 0.52, DS bel 0.52 / ignorance 0.48
- **Enterobacteriaceae (class, not an identity)** — derived at 0.8; Salmonella is
  refined from it but the family itself is not in `/conclusions`.

The enterobacteriaceae *class* is the correct broader abstraction (Salmonella is
one of its species); worth having Claude explain the taxonomic relationship —
that Salmonella's belief is lower precisely because it composes *through* the
family — after narrating the beliefs.

---

## Scenario 5 — Sepsis with low WBC

> "Elderly patient, septic, WBC is 2.1 — quite low. Blood culture:
> gram-negative rods."

**Facts to extract**:
`white-blood-count=low` (patient-1), `culture-site=blood`, `gram=neg`,
`morphology=rod`. (Aerobicity not yet available — this is an early-in-the-case
scenario.)

**Rules that fire**:
- (none conclude yet) — the low-WBC salmonella rule is now a *tier-2* refinement
  (`enterobacteriaceae-in-blood-with-low-wbc-suggests-salmonella`, 0.55), so it needs
  the enterobacteriaceae **class** established first, and the class requires an
  aerobicity result. Without aerobicity, neither the family nor Salmonella fires.

**Expected partial matches**:
Because aerobicity isn't yet available, the enterobacteriaceae class hasn't been
derived, so Salmonella can't be refined from it. This makes the case an even sharper
demonstration of `get_partial_matches` and Claude asking "do you have aerobicity
results?" as *the* discriminating question — without it, the family (and every
species under it) stays out of reach.

**Expected differential (with only the facts above)**:
- (nothing concluded yet — aerobicity is the gating fact for the whole family)

If aerobicity=aerobic is added, `aerobic-gram-neg-rod-suggests-enterobacteriaceae-class`
fires and derives the family class; the class then lets the tier-2 rule refine
Salmonella, composing to 0.8 × 0.55 = 0.44. The differential broadens from nothing to
Salmonella (with the enterobacteriaceae *class* standing behind it, though the class
itself is not a `/conclusions` identity).

---

## Scenario 6 — Abdominal anaerobe

> "Post-op appendectomy patient with an abdominal source. Culture from the
> collection shows gram-negative rods, anaerobic."

**Facts to extract**:
`infection-site=abdominal` (patient-1), `gram=neg`, `morphology=rod`,
`aerobicity=anaerobic`. (Note: `culture-site=blood` is NOT asserted here —
the culture is from the abdominal collection, not blood.)

**Rules that fire**:
- `anaerobic-gram-neg-rod-in-abdomen-suggests-bacteroides` (0.8)

If the clinician also mentions a positive blood culture (adding
`culture-site=blood`), the classic PAIP rule fires too:
- `anaerobic-gram-neg-rod-in-blood-suggests-bacteroides` (0.9)

**Expected differential (both rules firing)**:
- **Bacteroides** — two rules → combined belief.
  - CF: `0.9 ⊕ 0.8 = 0.98`
  - DS: `bel 0.98, pl 1.0, ignorance 0.02` — tight interval, sharp
    conclusion.

Excellent case for showing DS combination *narrowing* the ignorance interval
as independent evidence accumulates.

---

## Scenario 7 — Ambiguous gram stain

> "Same 27-year-old burn patient as before, but the microbiologist is
> hedging: **probably gram-negative** rods on the slide, but they say
> **possibly gram-positive** — the stain wasn't great. Blood culture,
> anaerobic organism."

**Facts to extract** (note the confidence values driven by clinician hedging):
`burn=serious`, `compromised-host=t`, `culture-site=blood`,
`gram=neg` with `confidence=0.8` ("probably"),
`gram=pos` with `confidence=0.6` ("possibly"), (both on organism-1),
`morphology=rod`, `aerobicity=anaerobic`.

**Rules that fire**:
- `anaerobic-gram-neg-rod-in-blood-suggests-bacteroides` (0.9)
- `gram-neg-rod-in-burn-patient-suggests-pseudomonas` (0.4)
- `gram-neg-rod-in-compromised-host-suggests-pseudomonas` (0.6)
- `gram-pos-stain-argues-against-gram-neg-organism` (−0.7) — the disconfirming
  rule: the possible gram-*positive* reading argues *against* both
  gram-negative hypotheses (bacteroides and pseudomonas)

**Expected differential**:
This is the case that pulls CF and DS apart. Both fold in the disconfirming
gram-positive evidence, but they encode the result differently:

| Organism | CF | DS |
|---|---|---|
| **Bacteroides** | `0.52` | `bel 0.60, pl 0.83, ignorance 0.23` |
| **Pseudomonas** | `0.39` | `bel 0.51, pl 0.80, ignorance 0.29` |

- **CF** combines the negative evidence as a negative certainty factor and
  reports a single lowered number — you can't distinguish "conflicted" from
  "weakly supported."
- **DS** combines via Dempster's rule of combination with conflict
  renormalization: the gram-positive reading puts mass on *not-H*, so
  **plausibility drops below 1.0**. That `pl` ceiling (0.83, 0.80) is the
  visible fingerprint of the conflict. Note DS's `bel` sits *above* CF's
  number — Dempster redistributes the conflict mass rather than subtracting it,
  so `bel` and `pl` carry different parts of the story.

This is the interesting DS case: **DS makes evidential conflict visible as a
plausibility ceiling below 1.0, where CF collapses it to a single number**.
Run it under both systems and compare the transcripts.

---

## Scenario 8 — When the local antibiogram changes the answer (therapy overlay)

*Unlike Scenarios 1–7 (identification), this one showcases the **antibiogram
overlay** on the therapy side: the same case, same allergy, yields a **different
regimen** once **this ward's** local susceptibility counts are folded in. It
exercises `recommend_therapy` and the provenance narration.*

**Setup — load the local antibiogram (opt-in).** The schematic site-local counts in
`neomycin/therapy/antibiogram-data.lisp` are **not** loaded by default — the canonical
KB stays the pure reference. To overlay them, add one `load` to the bridge startup:

```bash
sbcl --load lisa.asd \
     --eval '(asdf:load-system :neomycin)' \
     --eval '(load (asdf:system-relative-pathname "neomycin" "neomycin/therapy/antibiogram-data.lisp"))' \
     --eval '(lisa-bridge:start)'
```

Run the case once **without** that `load` line (reference only) and once **with** it
(local overlay) to see the contrast. A real deployment would swap in *its own* counts
file the same way.

> "68-year-old man, two weeks inpatient on chemo — immunocompromised, central line.
> New fevers. Blood culture: gram-negative rods, aerobic. He's allergic to
> carbapenems."

**Facts to extract**:
`compromised-host=t`, `hospital-acquired=t`, `culture-site=blood`, `gram=neg`,
`morphology=rod`, `aerobicity=aerobic`; patient state `allergy-carbapenem` for therapy.

**Identification differential** (DS — the Scenario 2 shape). Both `/conclusions`
identities are enterobacteriaceae-family species or pseudomonas; the family itself is
a *class*, not an identity:
- **Pseudomonas** — `bel 0.88` (two rules combine)
- **Klebsiella** — `bel 0.688` (two *chained* tier-2 rules combine, each composing
  through the enterobacteriaceae class: 0.8×0.6 ⊕ 0.8×0.5)
- **Enterobacteriaceae** — the derived *class* (0.8), not a `/conclusions` identity.
  Because Klebsiella (a member species) clears the coverage gate, the therapy solver
  treats Klebsiella and does **not** add the family as a backstop (contrast Scenario 10).

**Therapy — reference only** (`recommend_therapy`, `patient=["allergy-carbapenem"]`):
- Regimen: **ceftazidime** alone — covers both (pseudomonas `0.70`, klebsiella `0.64`),
  every entry `source: reference`.
- (Meropenem, the usual broad choice, is excluded by the allergy.)

**Therapy — with the local antibiogram loaded** (identical request):
- Regimen: **gentamicin** alone. Why the switch? This ward's antibiogram records
  **41/48 (85%) gentamicin-susceptible Pseudomonas** — so gentamicin's anti-pseudomonal
  coverage, only `[0.48, 0.88]` (bel `0.48`, *below* the 0.5 gate) in the reference,
  is **promoted to bel `0.82`** and now covers. That promotion also lifts gentamicin's
  weighted score above ceftazidime's, so the solver prefers it. Its pseudomonas entry
  reads `source: local-antibiogram, n_tested: 48`; klebsiella stays `source: reference`.
  The reference run *couldn't* use gentamicin — its pseudomonas figure was too uncertain
  to count. **The local data earned it.**

**What Claude should narrate** (per the provenance guidance in `system-prompt.md`) —
cite the sample size, distinguish local from reference:

> *"With this ward's antibiogram, gentamicin alone covers the differential:
> Pseudomonas at belief 0.82 across **48 local isolates** (85% susceptible here) — a
> data-grounded, reasonably solid figure. Klebsiella coverage is **reference-only**,
> so treat it as provisional pending local sensitivities."*

**The other direction — resistance the reference would miss.** The overlay pulls
figures *down* where the ward is more resistant than the textbook, too. This ward's
**ceftazidime-susceptible Klebsiella is 18/40 (45%)** — a local ESBL signal — so
`kb-susceptibility` for klebsiella/ceftazidime drops from the reference `[0.64, 0.88]`
(covers) to `[0.48, 0.52]` (**below the gate**). Ceftazidime can then no longer count
as covering Klebsiella: where the reference KB would offer it, the overlay makes the
solver reach for another agent or surface Klebsiella as honestly uncovered. This is
the overlay's whole point — **"our ward is running 45% this quarter" beats "the
textbook says ~70%."**

> **⚠️ NOT FOR CLINICAL USE.** These counts are schematic, invented to exercise the
> machinery — not real surveillance, never a basis for prescribing.

---

## Scenario 9 — Resolving the enterobacteriaceae species (biochemistry)

> "Aerobic gram-negative rods from a urine culture. The lab ran biochemicals:
> lactose fermenter, indole positive."

**Facts to extract**:
`gram=neg`, `morphology=rod`, `aerobicity=aerobic`, `lactose=fermenter`,
`indole=positive` (all organism-1).

**Rules that fire**:
- `aerobic-gram-neg-rod-suggests-enterobacteriaceae-class` (0.8) — derives the family class (tier 1)
- `enterobacteriaceae-lactose-pos-indole-pos-suggests-e-coli` (0.8, tier-2) — composes to 0.8×0.8

**Expected differential**:
- **E. coli** — the classic lactose+/indole+ pair. Its belief composes *through*
  the family class: `0.8 × 0.8 = 0.64`.
  - CF `0.64`, DS `bel 0.64, pl 1.0, ignorance 0.36`
- Enterobacteriaceae itself is the derived *class* (0.8) behind E. coli, not a
  `/conclusions` identity.

**Therapy**: E. coli carries no KB sensitivities of its own — via the family
roll-up it inherits enterobacteriaceae's, so **meropenem** (family `bel 0.90`)
covers it, nothing uncovered.

**The sibling variations** (swap the biochemistry to land on a different species —
each composes through the same 0.8 class):

| Discriminators | Rule | Species | Composed belief |
|---|---|---|---|
| lactose+ / indole− / motile | `…motile-lactose-pos-indole-neg-suggests-enterobacter` (0.6) | Enterobacter | 0.48 |
| red pigment | `…red-pigment-suggests-serratia` (0.75) | Serratia | 0.60 |
| urease+ / swarming | `…urease-pos-swarming-suggests-proteus` (0.8) | Proteus | 0.64 |

Motility is what separates Enterobacter from non-motile Klebsiella (both
lactose+/indole−). A **urease-positive** result additionally fires the disconfirming
`urease-pos-argues-against-urease-negative-organism` (−0.7) against E. coli and
Salmonella — so in a case with two near-tied siblings, a contradictory urease pulls the
urease-negative one's *plausibility below 1.0*: the DS-conflict fingerprint applied to
biochemistry.

**Cross-disconfirmation variation — contradictory biochemistry pulls both siblings
down.** Add a **red pigment** reading to the lactose+/indole+ case above:

> "Aerobic gram-negative rods, urine culture. Biochemicals: lactose fermenter,
> indole positive, **and a red pigment on the plate**."

Now two siblings are confirmed — E. coli (lactose+/indole+, 0.64) and Serratia (red
pigment, 0.60) — but one organism cannot be both, and the biochemistry says so:

- **`red-pigment-argues-against-non-serratia`** (−0.8) fires against E. coli
  (prodigiosin is essentially Serratia-specific).
- **`indole-pos-argues-against-indole-negative-species`** (−0.6) fires against
  Serratia (which is characteristically indole-negative).

Each sibling is disconfirmed by exactly the marker that confirmed the *other*, so
**both plausibilities fall below 1.0** — the honest "the biochemistry doesn't cleanly
fit either" that a flat `pl 1.0` on both could not express:

| Species | confirmed | disconfirmed by | CF | DS `bel` | DS `pl` |
|---|---|---|---|---|---|
| E. coli | 0.64 (lactose+/indole+) | red pigment (−0.8) | −0.44 | 0.26 | 0.41 |
| Serratia | 0.60 (red pigment) | indole+ (−0.6) | 0.00 | 0.375 | 0.625 |

The conflict is **asymmetric**: the more-specific pigment (−0.8) bites harder than the
indole (−0.6), so E. coli ends up *below* Serratia. Ask `/why` on either and the engine
shows which finding pulled it down, with citations. This is the reconstruction of a live
clinician session where both siblings sat at `pl 1.0` and the engine could not voice the
contradiction. (Symmetrically, `lactose-fermenter-argues-against-non-fermenters` (−0.7)
and its non-fermenter complement (−0.6) do the same for the Salmonella/Proteus axis — a
context-suggested Salmonella meeting a lactose+ reading is pulled below 1.0 while a
biochemically-confirmed E. coli stays clean.)

---

## Scenario 10 — Family backstop when the species won't resolve (therapy)

> "Aerobic gram-negative rods in the blood. No host risk factors noted, and we
> don't have biochemicals back yet. What can we start empirically?"

**Facts to extract**:
`culture-site=blood`, `gram=neg`, `morphology=rod`, `aerobicity=aerobic` (organism-1).

**Rules that fire**:
- `aerobic-gram-neg-rod-suggests-enterobacteriaceae-class` (0.8) — the class, and *only* the class

**Expected differential**:
- `/conclusions` is **empty of leaf identities** — no host context or biochemistry
  fired any species rule. Only the enterobacteriaceae *class* (0.8) was derived.

**Therapy — the family backstop** (`recommend_therapy`):
- Because no member species cleared the coverage gate, the solver carries the
  **enterobacteriaceae family** itself in as a backstop item and treats it empirically:
  **meropenem** alone (family `bel 0.90`), nothing uncovered.
- This is the mirror image of Scenario 8: there, Klebsiella *did* clear the gate, so
  the family was suppressed and the member was treated. Here nothing did, so the family
  is the honest empiric target — "an enterobacteriaceae, species not yet resolved; cover
  the family until the biochemicals narrow it."

Claude should offer the discriminating tests (lactose, indole, motility, urease,
pigment) that would let Scenario 9 refine the species — and note that once a species
clears the gate, the recommendation narrows from family-level to species-level.

---

## Scenario 11 — "Why, and how confident?" (WHY/HOW explanation)

*Not a new case: a follow-up any clinician asks. It exercises the **WHY/HOW facility**
— the LLM answers from the engine's authoritative derivation (via `explain_conclusion`
→ `/why`), not from its own recollection of the arithmetic or the literature.*

Run Scenario 1 (the burn patient) to conclusion, then ask:

> "Why Klebsiella, and how confident should I be? What's that based on?"

Claude calls `explain_conclusion` with `{"organism": "klebsiella"}` and narrates the
returned record — it must **not** recompute the number or recall a citation from memory:

- **The arithmetic (quoted, engine-computed).** Klebsiella was refined from the derived
  **enterobacteriaceae class**: `"0.800 (organism-class enterobacteriaceae) composed with
  the 0.500 rule = 0.400"`. The class premise carries its **own** derivation — the
  aerobic gram-negative rod evidence concluding the family at 0.8 — so Claude can explain
  *why* Klebsiella runs lower than a raw rule: it composes **through** the family.
- **The provenance (quoted, verified).** The Klebsiella rule's `evidence` cites NCBI
  Bookshelf **NBK8035 / NBK519004** (`origin: paip-subset`); the class rule cites
  **NBK8035 / NBK559296** (`origin: neomycin-extrapolation`). Claude cites these, and can
  distinguish inherited MYCIN/PAIP heritage from this fork's own additions if asked.
- **The honesty line.** Every rule carries `belief_basis: illustrative`. Claude must say
  the **0.40 itself is a schematic teaching figure, not a measured probability** — the
  citations verify the *association* (Klebsiella as an opportunistic Enterobacteriaceae),
  never the number. This is the whole point of the facility: the explanation is queryable
  ground truth, and its limits are stated, not blurred.

Contrast with **Pseudomonas** in the same case: `explain_conclusion` returns **two**
firings — `"rule belief 0.400 = 0.400"` then `"prior 0.400 combined with the 0.600 rule =
0.760"` — so Claude explains belief **combination** from the engine's own before/after
record. Try it under both belief systems: under DS each `belief_before`/`belief_after`
is an interval, so the explanation shows ignorance narrowing/shifting per firing.

---

## Rule Coverage Matrix

*Which scenarios make each rule **fire**. Scenario 14 is deliberately absent: it
queries the catalogue rather than exercising the engine, so it covers every rule by
description and none by firing.*

| Rule | Scenarios that exercise it |
|---|---|
| gram-neg-rod-in-burn-patient-suggests-pseudomonas | 1, 7 |
| gram-pos-cocci-in-clumps-suggests-staphylococcus | (add clumps to 7) |
| anaerobic-gram-neg-rod-in-blood-suggests-bacteroides | 6*, 7 |
| gram-neg-rod-in-compromised-host-suggests-pseudomonas | 1, 2, 7 |
| gram-pos-cocci-in-chains-suggests-streptococcus | 3 |
| hospital-acquired-gram-pos-cocci-in-clumps-suggests-staph-aureus | (variant of 2) |
| hospital-acquired-enterobacteriaceae-in-compromised-host-suggests-klebsiella (tier-2) | 2, 8 |
| hospital-acquired-aerobic-gram-neg-rod-suggests-pseudomonas | 2, 8 |
| enterobacteriaceae-in-compromised-host-suggests-klebsiella (tier-2) | 1, 2, 8 |
| respiratory-gram-pos-cocci-in-chains-suggests-strep-pneumoniae | 3 |
| enterobacteriaceae-with-tropical-travel-suggests-salmonella (tier-2) | 4 |
| gram-pos-cocci-in-chains-in-blood-compromised-suggests-enterococcus | 3 |
| enterobacteriaceae-in-blood-with-low-wbc-suggests-salmonella (tier-2) | 5 |
| enterobacteriaceae-lactose-pos-indole-pos-suggests-e-coli (tier-2) | 9 |
| enterobacteriaceae-motile-lactose-pos-indole-neg-suggests-enterobacter (tier-2) | 9 (variation) |
| enterobacteriaceae-red-pigment-suggests-serratia (tier-2) | 9 (variation) |
| enterobacteriaceae-urease-pos-swarming-suggests-proteus (tier-2) | 9 (variation) |
| aerobic-gram-neg-rod-suggests-enterobacteriaceae-class (tier-1) | 1, 2, 4, 5, 8, 9, 10 |
| anaerobic-gram-neg-rod-in-abdomen-suggests-bacteroides | 6 |
| gram-pos-stain-argues-against-gram-neg-organism | 7 |
| gram-neg-stain-argues-against-gram-pos-organism | (needs a gram-neg reading alongside a live gram-positive hypothesis) |
| aerobic-growth-argues-against-anaerobe | (needs an aerobic result contradicting a prior bacteroides hypothesis) |
| urease-pos-argues-against-urease-negative-organism | 9 (with two siblings and a urease+ reading) |
| red-pigment-argues-against-non-serratia | 9 (cross-disconfirmation variation) |
| indole-pos-argues-against-indole-negative-species | 9 (cross-disconfirmation variation) |
| lactose-fermenter-argues-against-non-fermenters | 9 (context Salmonella meeting a lactose+ reading) |
| lactose-non-fermenter-argues-against-fermenters | (needs a non-fermenter reading against a live fermenter hypothesis) |

*Scenario 6 fires this rule only if a blood culture is also asserted.

The retired one-hop `aerobic-gram-neg-rod-suggests-enterobacteriaceae` **identity**
rule is gone (C2) — the tier-1 **class** rule now covers that evidence path, and the
family reaches therapy only as a species (Scenarios 1/2/4/5/8/9) or as a backstop
(Scenario 10).

The sixteen disconfirming rules carry negative beliefs and fire only when a
contradictory finding meets a live hypothesis. Scenario 7 exercises the gram-stain
one directly; the five enterobacteriaceae **biochemical** ones (urease, red pigment,
indole, and the two lactose rules) are reachable in Scenario 9's two-sibling and
cross-disconfirmation variations; the eight **gram-positive** ones are driven by
Scenario 12; the aerobic-vs-anaerobe one needs a scenario where the oxygen requirement
flips against an already-supported organism.

---

## Scenario 12 — Hemolysis contradicts the site (gram-positive cross-disconfirmation)

> "Sputum culture from a chest infection — gram-positive cocci in chains. The
> bench has just phoned through beta hemolysis, bacitracin sensitive."

**Facts to extract**:
`infection-site=respiratory` (patient-1), `culture-site=blood`, `gram=pos`,
`morphology=coccus`, `growth-conformation=chains`, `hemolysis=beta`,
`bacitracin=sensitive`.

Driver: `(culture-4)`.

**Rules that fire**:
- `gram-pos-cocci-in-chains-suggests-streptococcus-class` (0.7) → organism-class
- `strep-beta-hemolytic-bacitracin-sensitive-suggests-strep-pyogenes` (0.85, tier-2)
- `respiratory-gram-pos-cocci-in-chains-suggests-strep-pneumoniae` (0.75, tier-2)
- `beta-hemolysis-argues-against-non-beta-streptococci` (**−0.75**)

**Expected differential**:

| Organism | CF | DS |
|---|---|---|
| Streptococcus pyogenes | 0.595 | [0.595, 1.0] |
| Streptococcus pneumoniae | **−0.474** | **[0.216, 0.412]** |

**Why this is the best CF-vs-DS scenario in the corpus.** Two rules refine the same
genus class along different axes — biochemical (beta + bacitracin-sensitive → group A)
and clinical (respiratory site → pneumococcus). But a beta-hemolytic organism *cannot*
be the alpha-hemolytic pneumococcus, so the two calls are mutually exclusive, and the
hemolysis rule says so.

Watch what each algebra does with that:

- **CF** collapses the pneumococcus to a single negative number, −0.474. It reads as
  "disbelieved" and stops there. The number cannot tell you whether the case against it
  is overwhelming or merely adequate, and it has silently discarded the fact that a
  respiratory source genuinely *did* support it.
- **DS** returns `[0.216, 0.412]`. Belief fell but did not vanish — the site evidence
  is still in there — and the *ceiling* dropped to 0.41, which is the new information:
  hemolysis caps how plausible pneumococcus can now be. Two numbers, two distinct
  facts.

Conflict also stays **localized**. Nothing argues against S. pyogenes, so it holds
clean at `[0.595, 1.0]` instead of being dragged down alongside its sibling — the
property that lets a clinician read the interval as being about *that* organism.

Good narration names the marker and both bounds: *"the beta hemolysis argues against
pneumococcus — belief down to 0.22 with plausibility capped at 0.41 — so it's still on
the table but no longer the leading call."* Bad narration says "pneumococcus is ruled
out." It isn't.

**Variation** — swap `hemolysis=alpha` and `optochin=sensitive` for the beta/bacitracin
pair. Now the biochemistry and the site *agree*: pneumococcus is confirmed twice
(0.595 from optochin, 0.525 from the site) and combines upward, while
`alpha-hemolysis-argues-against-beta-hemolytic-streptococci` keeps S. pyogenes out.
Same cluster, opposite dynamic.

---

## Scenario 13 — A host factor reinforcing a bench result (belief combination)

> "Neonate, five days old, blood culture positive. Gram-positive cocci in chains,
> beta-hemolytic, bacitracin resistant."

**Facts to extract**:
`age-group=neonate` (patient-1), `culture-site=blood`, `gram=pos`,
`morphology=coccus`, `growth-conformation=chains`, `hemolysis=beta`,
`bacitracin=resistant`.

Driver: `(culture-5)`.

**Rules that fire**:
- `gram-pos-cocci-in-chains-suggests-streptococcus-class` (0.7) → organism-class
- `strep-beta-hemolytic-bacitracin-resistant-suggests-strep-agalactiae` (0.7, tier-2)
- `neonate-with-beta-hemolytic-strep-suggests-strep-agalactiae` (0.7, host factor)

**Expected differential**:

- **Streptococcus agalactiae (group B)** — CF 0.7399, DS bel 0.7399 / **ignorance
  0.2601, plausibility 1.0**

Two independent paths reach the same species — the bench result (beta,
bacitracin-resistant → 0.49) and the host factor (neonate + beta-hemolytic → 0.49) —
and their masses **combine**: `0.49 + 0.49 − 0.49×0.49 = 0.7399`.

This is the deliberate counterpart to Scenario 12. There, two paths reached mutually
exclusive species and the algebras diverged sharply. Here they reach the *same* species
and there is no conflict at all — so plausibility stays pinned at 1.0 and **CF and DS
agree exactly**. That agreement is worth demonstrating: it shows DS is not a
pessimism knob that always widens intervals, it is a representation that reports
conflict when conflict exists and stays quiet when it doesn't.

It also makes the point of host factors concrete. `age-group=neonate` costs nothing and
has no lab turnaround, yet it lifted the call from 0.49 to 0.74. Ask for host factors
early.

**Honest caveat to state when narrating**: the rule keys on the neonatal age band, and
group B strep leads early-onset neonatal sepsis in *term* infants — in preterm infants
E. coli is the commoner cause. That scoping is recorded in the rule's provenance and
`explain_conclusion` will return it.

---

## Scenario 14 — Interrogating the rulebase itself (the catalogue)

*Not a case: a question **about the corpus** rather than about a patient. It exercises
the **rule catalogue** — the LLM answers from the compiled rulebase via
`describe_rules` → `/rules`, because the system prompt deliberately no longer carries a
copy of it.*

Ask cold, before asserting anything, or as a follow-up to any case:

> "Which single test best discriminates within the streptococci, and how heavily does
> the system weight it?"

Claude calls `describe_rules` with `cluster=streptococcus`. A cluster query returns
three things a client cannot get from any one of them alone:

- the rule **deriving the class** (`gram-pos-cocci-in-chains-suggests-streptococcus-class`, 0.7);
- every rule **refining a species off it** — the hemolysis/disc rules at 0.85, 0.85,
  0.7 and 0.65, each with the premises it requires;
- every rule **arguing against** one of those species — `beta-hemolysis-argues-against-
  non-beta-streptococci` and `alpha-hemolysis-argues-against-beta-hemolytic-streptococci`
  (both −0.75), `optochin-sensitive-argues-against-viridans` (−0.70).

That third arm is the point. Ruling-out rules key off the *identity* and never mention
the organism-class, so a naive cluster query answers only "what argues **for** each
species" — precisely half of what "what discriminates?" means.

**What a good answer contains**: hemolysis named as the branch point *because* it both
gates the species rules and fires a disconfirming rule against the other branch; exact
beliefs quoted, not approximated; and the *rationale* from each rule's provenance `note`
— e.g. bacitracin-resistant → agalactiae is only 0.70 "because groups C and G are also
bacitracin-resistant, so it narrows rather than names."

**What a good answer does not contain**: any belief, premise, or citation stated without
a `describe_rules` call behind it. The prompt states the corpus counts and quotes rule
names in its examples; everything else it must ask for. Two suite guards
(`prompt-tests.lisp`) hold that line from the other side — every rule name the prompt
quotes must exist, and the counts it states must be the real ones.

**Other useful shapes of the same question**:

| Ask | Query it should produce |
|---|---|
| "What would have to be true for Serratia?" | `concludes=serratia` |
| "What can we refine once it's in the enterobacteriaceae family?" | `premises=enterobacteriaceae` |
| "What can argue *against* a hypothesis here?" | `kind=disconfirming` |
| "Tell me about that rule" (named by a trace or partial match) | `name=<rule>` |

Sample transcript: `neomycin/clinician-samples/strep-hemolysis-conflict-rule-catalogue.md`
(Scenario 12 followed by this question). Endpoint smoke test: `./bin/test-rules.sh`.

---

## Scenario 15 — The same case under two stewardship objectives

*The therapy solver's **objective** is a policy dial, like the belief system and the
coverage gate. This scenario turns it and watches one case give two defensible
answers. It is also the case from `exact-solver-design.md` §1.1 — the one where a
clinician asked for a narrower agent and was told, falsely, that none existed. Worth
running for that reason alone: it is the bug, the fix, and the dial, on one culture.*

> "Aerobic gram-negative rods in the blood. Biochemicals are back — lactose
> fermenter, indole positive. No host risk factors, no allergies."

**Facts to extract**: `culture-site=blood`, `gram=neg`, `morphology=rod`,
`aerobicity=aerobic`, `lactose=fermenter`, `indole=positive`.

**Identification**: **E. coli, bel 0.64, pl 1.0, ignorance 0.36** — chained through
the derived enterobacteriaceae class (0.8 × the 0.8 species rule). One rule fires;
nothing argues against it, so plausibility stays at the ceiling.

**Therapy, default objective** (`recommend_therapy`, no `objective` passed):

| | drug | dose | `bel` | `pl` | ignorance |
|---|---|---|---|---|---|
| regimen | **meropenem** | 1 g IV q8h | 0.90 | 0.99 | 0.09 |

`alternative_agents`: ceftazidime (0.66), ceftriaxone (0.72), ciprofloxacin (0.62),
gentamicin (0.64), piperacillin-tazobactam (0.70).

**Therapy, spectrum-sparing** (`objective: "spectrum-sparing"`):

| | drug | dose | `bel` | `pl` | ignorance |
|---|---|---|---|---|---|
| regimen | **gentamicin** | 5-7 mg/kg IV q24h | 0.64 | 0.90 | 0.26 |

`alternative_agents` now lists **meropenem (0.90)** in gentamicin's place.

**What the contrast teaches.** Three things, in rising order of interest:

1. **The trade is quantified, not asserted.** Narrowing costs coverage floor —
   0.90 → 0.64 — *and* certainty: ignorance widens 0.09 → 0.26. The narrower agent is
   not merely less covering, it is less *known*. Both numbers are in the payload, so
   the clinician weighs the trade rather than taking the solver's word for it.

2. **The alternatives list is symmetric.** Whichever objective runs, the other
   objective's answer appears in `alternative_agents`. Neither regimen can imply it
   was the only option — which is exactly the failure §1.1 records.

3. **The ordering of `alternative_regimens` is itself the objective.** Under the
   default it runs ceftriaxone → pip-tazo → ceftazidime → gentamicin → ciprofloxacin,
   strongest coverage first. Under spectrum-sparing it runs ciprofloxacin →
   ceftriaxone → ceftazidime → meropenem → pip-tazo, narrowest first. Same five drugs,
   reordered by the policy in force. Ask Claude *"why is meropenem last now?"* — the
   answer is the dial, and it is visible in the data rather than in prose.

**What Claude must not do**: present the spectrum-sparing regimen as simply better.
It is narrower *and* less certain, and on other cases it is worse in a second way —
see the enterococcus note below. The prompt requires the trade stated in both
directions.

**The dial's known failure, worth demonstrating deliberately.** Spectrum breadth is
blind to the WHO AWaRe Access/Watch/Reserve axis, which the KB annotates but does not
encode. On an enterococcus case the objective moves from **ampicillin** (AWaRe
*Access*) to **linezolid** (AWaRe *Reserve*) — genuinely narrower, and backwards as
stewardship. That is shipped as measured rather than patched, because a dial that
visibly does the wrong thing for a stateable reason teaches more than one quietly
constrained until it looks sensible. Full table and reasoning:
`docs/exact-solver-design.md` §3.6.

> **⚠️ NOT FOR CLINICAL USE.** Gentamicin monotherapy for gram-negative bacteraemia
> is a schematic solver's output, not a therapeutic proposal. The objective optimises
> a declared breadth tier over an illustrative KB; it does not know what this drug
> does to a kidney, or that aminoglycoside monotherapy is not how this is treated.

---

## Notes for Investigators

- Scenarios that fire **only one rule per organism** don't exercise belief
  combination. If you want to see combination, either combine scenarios
  (e.g., add hospital-acquired to Scenario 1) or use Scenarios 1, 2, or 6.
- The abdominal-plus-blood variant of Scenario 6 is currently the tightest
  DS interval the base can produce (two high-belief rules on the same
  organism).
- Scenario 7 is the most instructive case for contrasting CF and DS — run
  it under both belief systems and compare the transcripts.
