# Clinician Scenarios for the MYCIN Rulebase

A curated set of vignettes for driving the expanded 18-rule MYCIN rulebase
(`examples/mycin.lisp`) through the Claude driver
(`src/llm/claude/driver.py`) and the HTTP bridge. Each scenario is written
the way a clinician might present a case at the bedside, and each is
annotated with:

- **Facts to be extracted** — what Claude should turn the vignette into
- **Rules expected to fire** — the descriptive rule names from the rulebase
- **Expected differential** — the organism hypotheses and belief behavior,
  contrasted between certainty factors (CF) and Dempster-Shafer (DS)

Together Scenarios 1–7 exercise most of the base directly, and Scenario 7
reaches the disconfirming rules. Two `clumps`-based gram-positive rules
(staphylococcus, staph-aureus) and two of the three disconfirming rules are
reachable only by the noted variations (see the coverage matrix). Critically,
several cases produce situations where *multiple rules conclude the same
organism* — which is where belief combination becomes visible — and Scenario 7
produces *conflicting* evidence, which is where CF and DS diverge.

**Scenario 8** steps past identification to the **therapy** side: it shows the
**antibiogram overlay** changing the recommended regimen once a site-local
susceptibility count is folded into the curated figures — local data promoting a
provisional agent and, in the other direction, exposing local resistance the
reference would miss.

## How to Run

Start the bridge under the belief system you want to see:

```bash
# Dempster-Shafer (default)
sbcl --load lisa.asd \
     --eval '(asdf:load-system :lisa)' \
     --eval '(in-package :lisa-user)' \
     --eval '(load "examples/mycin.lisp")' \
     --eval '(asdf:load-system :lisa-bridge)' \
     --eval '(lisa-bridge:start)'

# Certainty factors (override with the env var)
LISA_BELIEF_SYSTEM=cf sbcl --load lisa.asd ...  (same, just the env var)
```

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
- `aerobic-gram-neg-rod-suggests-enterobacteriaceae` (0.8) — family-level identity
- `aerobic-gram-neg-rod-suggests-enterobacteriaceae-class` (0.8) — derives the family class (tier 1)
- `enterobacteriaceae-in-compromised-host-suggests-klebsiella` (0.5, tier-2) — composes to 0.8×0.5 = 0.40

**Expected differential**:
- **Enterobacteriaceae** — single rule, strongest single hypothesis.
  - CF: `0.8`, DS: `bel 0.8, pl 1.0, ignorance 0.2`
- **Pseudomonas** — two rules conclude it, so belief combines.
  - CF: `~0.76` (0.4 ⊕ 0.6 = 0.4 + 0.6 − 0.24)
  - DS: `bel ~0.76`, `pl 1.0`, `ignorance ~0.24`
- **Klebsiella** — a *chained* (tier-2) refinement of the enterobacteriaceae
  family: its belief composes through the class (0.8 × 0.5), landing lower.
  - CF: `0.40`, DS: `bel 0.40, pl 1.0, ignorance 0.60`

This is the canonical case for showing "multiple rules → belief
combination" (on pseudomonas), and simultaneously for showing how a
single-rule hypothesis with a moderate belief factor produces a wide
ignorance interval under DS — a nuance CF collapses to a single number.
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
- `aerobic-gram-neg-rod-suggests-enterobacteriaceae` (0.8) — family-level identity
- `aerobic-gram-neg-rod-suggests-enterobacteriaceae-class` (0.8) — derives the family class (tier 1)
- `hospital-acquired-enterobacteriaceae-in-compromised-host-suggests-klebsiella` (0.6, tier-2)
- `hospital-acquired-aerobic-gram-neg-rod-suggests-pseudomonas` (0.7)
- `enterobacteriaceae-in-compromised-host-suggests-klebsiella` (0.5, tier-2)

**Expected differential**:
- **Pseudomonas** — two rules → combined belief. CF ~0.88; DS bel ~0.88, low
  ignorance.
- **Klebsiella** — two *chained* (tier-2) rules → combined belief, each composing
  through the family (0.8×0.6 and 0.8×0.5). CF ~0.688; DS bel ~0.688.
- **Enterobacteriaceae** — single rule. CF 0.8; DS bel 0.8, ignorance 0.2.

Good three-way differential. Exercises the hospital-acquired branch of the
new rules and produces two organisms with multi-rule support.

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
- `gram-pos-cocci-in-chains-suggests-streptococcus` (0.7)
- `respiratory-gram-pos-cocci-in-chains-suggests-strep-pneumoniae` (0.75)
- `gram-pos-cocci-in-chains-in-blood-compromised-suggests-enterococcus` (0.7)

**Expected differential**:
Three competing gram-positive hypotheses, each from a single rule — so no
belief combination on any one organism, but a great case for showing
partial-matches driving discriminating questions ("do we have a respiratory
source?" completes the *strep-pneumoniae* rule).

- **Streptococcus** — CF 0.7, DS bel 0.7 / ignorance 0.3
- **Streptococcus pneumoniae** — CF 0.75, DS bel 0.75 / ignorance 0.25
- **Enterococcus** — CF 0.7, DS bel 0.7 / ignorance 0.3

---

## Scenario 4 — Tropical traveler with gram-negative rod

> "Patient just back from two weeks in Southeast Asia. Bloody diarrhea, now
> febrile. Blood culture: gram-negative rods, aerobic."

**Facts to extract**:
`recent-travel=tropical` (patient-1), `culture-site=blood`, `gram=neg`,
`morphology=rod`, `aerobicity=aerobic`.

**Rules that fire**:
- `aerobic-gram-neg-rod-suggests-enterobacteriaceae` (0.8) — family-level identity
- `aerobic-gram-neg-rod-suggests-enterobacteriaceae-class` (0.8) — derives the family class (tier 1)
- `enterobacteriaceae-with-tropical-travel-suggests-salmonella` (0.65, tier-2)

**Expected differential**:
- **Enterobacteriaceae** — CF 0.8, DS bel 0.8 / ignorance 0.2
- **Salmonella** — a *chained* (tier-2) refinement: belief composes 0.8 × 0.65.
  CF 0.52, DS bel 0.52 / ignorance 0.48

Enterobacteriaceae is the correct broader hypothesis (Salmonella is one of
them); worth having Claude explain the taxonomic relationship after
narrating the beliefs.

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

If aerobicity=aerobic is added, `aerobic-gram-neg-rod-suggests-enterobacteriaceae`
(the family identity) and `aerobic-gram-neg-rod-suggests-enterobacteriaceae-class`
(the family class) both fire; the class then lets the tier-2 rule refine Salmonella,
composing to 0.8 × 0.55 = 0.44. The differential broadens from nothing to the family
plus Salmonella.

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

**Identification differential** (DS — the Scenario 2 shape):
- **Pseudomonas** — `bel 0.88` (two rules combine)
- **Klebsiella** — `bel 0.80` (two rules combine)
- **Enterobacteriaceae** — `bel 0.80` (single rule)

**Therapy — reference only** (`recommend_therapy`, `patient=["allergy-carbapenem"]`):
- Regimen: **piperacillin-tazobactam** alone — covers all three (pseudomonas `0.64`,
  klebsiella `0.68`, enterobacteriaceae `0.70`), every entry `source: reference`.
- (Meropenem, the usual broad choice, is excluded by the allergy.)

**Therapy — with the local antibiogram loaded** (identical request):
- Regimen: **gentamicin** alone. Why the switch? This ward's antibiogram records
  **41/48 (85%) gentamicin-susceptible Pseudomonas** — so gentamicin's anti-pseudomonal
  coverage, only `[0.48, 0.88]` (bel `0.48`, *below* the 0.5 gate) in the reference,
  is **promoted to bel `0.82`** and now covers. Its entry reads
  `source: local-antibiogram, n_tested: 48`; klebsiella and enterobacteriaceae remain
  `source: reference`. The reference run *couldn't* use gentamicin — its pseudomonas
  figure was too uncertain to count. **The local data earned it.**

**What Claude should narrate** (per the provenance guidance in `system-prompt.md`) —
cite the sample size, distinguish local from reference:

> *"With this ward's antibiogram, gentamicin alone covers the differential:
> Pseudomonas at belief 0.82 across **48 local isolates** (85% susceptible here) — a
> data-grounded, reasonably solid figure. Klebsiella and Enterobacteriaceae coverage
> is **reference-only**, so treat those as provisional pending local sensitivities."*

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

## Rule Coverage Matrix

| Rule | Scenarios that exercise it |
|---|---|
| gram-neg-rod-in-burn-patient-suggests-pseudomonas | 1, 7 |
| gram-pos-cocci-in-clumps-suggests-staphylococcus | (add clumps to 7) |
| anaerobic-gram-neg-rod-in-blood-suggests-bacteroides | 6*, 7 |
| gram-neg-rod-in-compromised-host-suggests-pseudomonas | 1, 2, 7 |
| aerobic-gram-neg-rod-suggests-enterobacteriaceae | 1, 2, 4 |
| gram-pos-cocci-in-chains-suggests-streptococcus | 3 |
| hospital-acquired-gram-pos-cocci-in-clumps-suggests-staph-aureus | (variant of 2) |
| hospital-acquired-enterobacteriaceae-in-compromised-host-suggests-klebsiella (tier-2) | 2 |
| hospital-acquired-aerobic-gram-neg-rod-suggests-pseudomonas | 2 |
| enterobacteriaceae-in-compromised-host-suggests-klebsiella (tier-2) | 1, 2 |
| respiratory-gram-pos-cocci-in-chains-suggests-strep-pneumoniae | 3 |
| enterobacteriaceae-with-tropical-travel-suggests-salmonella (tier-2) | 4 |
| gram-pos-cocci-in-chains-in-blood-compromised-suggests-enterococcus | 3 |
| enterobacteriaceae-in-blood-with-low-wbc-suggests-salmonella (tier-2) | 5 |
| aerobic-gram-neg-rod-suggests-enterobacteriaceae-class (tier-1) | 1, 2, 4 |
| anaerobic-gram-neg-rod-in-abdomen-suggests-bacteroides | 6 |
| gram-pos-stain-argues-against-gram-neg-organism | 7 |
| gram-neg-stain-argues-against-gram-pos-organism | (needs a gram-neg reading alongside a live gram-positive hypothesis) |
| aerobic-growth-argues-against-anaerobe | (needs an aerobic result contradicting a prior bacteroides hypothesis) |

*Scenario 6 fires this rule only if a blood culture is also asserted.

The three disconfirming rules carry negative beliefs and fire only when a
contradictory finding meets a live hypothesis. Scenario 7 exercises the first
directly; the other two need a scenario where the oxygen requirement or stain
flips against an already-supported organism.

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
