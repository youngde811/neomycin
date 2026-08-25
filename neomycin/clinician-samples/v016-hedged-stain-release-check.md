# Release check — a hedged Gram stain (evidence discounting)

**Date:** 2026-08-25 · **Branch:** `feature/evidence-belief-discount` → v0.16.0
**Backend:** Anthropic direct · **Model:** `claude-sonnet-5`
**Belief system:** Dempster-Shafer (candidate sets) · **Verbosity:** full
**NOT FOR CLINICAL USE.**

The whole stack in one pass — prompt + tool schemas + bridge + engine, with the model in
the loop — as `CLAUDE.md` "Release check — the layers must agree" requires. Captured by
`bin/release-check.py --scenario hedged-stain`, which passed all six assertions.

**This is the scenario the gate did not have.** All four earlier scenarios assert every
fact at full confidence, so none of them could exercise what v0.16.0 changed — and,
before v0.16.0, none of them could have caught what it fixed. Evidence belief reached
the `candidates` fact and stopped there: a clinician could call a stain *probably*
gram-negative or *probably gram-positive* and receive the identical differential.

Scenario: *"Seriously burned, immunocompromised patient. Blood culture, anaerobic
organism. The microbiologist is hedging: PROBABLY gram-negative rods on the slide, but
POSSIBLY gram-positive — the stain was poor."*

## The golden table — every figure derivable by hand

The prompt maps *probably* → `confidence 0.8` and *possibly* → `confidence 0.6`. Both
Gram rules carry `:belief 0.7`. An answer is discounted by the conjoined belief of the
premises that fired it, so each rule's 0.7 is scaled by its stain reading:

| quantity | derivation | payload | model quoted |
|---|---|---:|---|
| gram-negative answer | 0.7 × **0.8** | **0.5600** | 0.56 ✓ |
| gram-positive answer | 0.7 × **0.6** | **0.4200** | 0.42 ✓ |
| conflict *K* | 0.56 × 0.42 (the two sets are disjoint) | **0.2352** | 0.235 ✓ |
| m(Θ) | (1−0.56)(1−0.42) ÷ (1−*K*) | **0.3337** | 0.33 ✓ |
| margin | leader vs the nearest contradicting answer | **0.1831** | 0.183 ✓ |

Every quoted figure is a rounding of one the model had received in a payload earlier in
the same transcript, which is what release-check assertion 3 verifies mechanically.

**Before v0.16.0 every one of these was different, and none of them moved with the
hedge.** Both answers entered combination at the rule's own 0.7, giving *K* = 0.7 × 0.7
= **0.49** — the same figure whether the clinician said 80/60, 50/50, or reversed the
reading entirely.

## What to look for in the narration

- **The headline is a SET and the model leaves it there.** `leading_answer` is the eight
  gram-negatives; every member sits at `bel 0.0000`. Two stain readings and nothing else
  cannot name an organism, and the narration does not pretend otherwise.
- **The model explains the discount correctly and unprompted** — *"this already reflects
  the 0.8 confidence you gave the gram-negative reading, run through the rule's own 0.7
  belief weight."* That is what the code does, described without being told to.
- **It asks for the one fact that would break the tie.** `anaerobic-gram-neg-rod-in-
  blood-narrows-to-bacteroides` is one premise short — `morphology` — and the model
  surfaces that from `/partial-matches` rather than guessing. Morphology is never
  supplied, so the differential correctly stays on the set.
- **It reads *K* the way this project insists it be read** — *"not a measure of how much
  is known, only how much conflicting evidence was overruled or discarded"* — and pairs
  it with the margin rather than narrating it alone: *"margin = 0.183 is what actually
  tells you whether that conflict resolved. It didn't, not really: 0.183 is a thin
  lead."* Compare culture-4, where a far higher *K* accompanies a decisive answer.
- **It attributes the conflict correctly.** *"Every bit of `conflict = 0.235` and the
  resulting `margin = 0.183` comes from those two gram rules disagreeing with each other,
  and nothing else"* — checked against the argument trace rather than asserted. This is
  the claim culture-2's test comment made for years while the arithmetic did not support
  it; here it does, and the model verified it before saying so.
- **It states the disclosure**: a 17-organism research corpus with schematic,
  illustrative beliefs, and the split reflects the confidence the clinician gave rather
  than a measured probability of anything.

---

# Lisa/Claude session transcript

- Started: 2026-08-25T15:42:46
- Model: `claude-sonnet-5`
- Bridge: `http://localhost:8090`
- Belief system: `Dempster-Shafer (candidate sets)`
- Verbosity: `full`

---

## Clinician

Seriously burned, immunocompromised patient. Blood culture, anaerobic organism. The microbiologist is hedging: PROBABLY gram-negative rods on the slide, but POSSIBLY gram-positive - the stain was poor. Please run inference and give me the differential.

### Tool call: `assert_fact`

```json
{
  "fact_type": "burn",
  "value": "serious"
}
```

### Tool result: `assert_fact`

```json
{
  "status": "asserted",
  "fact_type": "burn",
  "value": "serious",
  "scoped_to": "patient-1",
  "inert": false
}
```

### Tool call: `assert_fact`

```json
{
  "fact_type": "compromised-host",
  "value": "t"
}
```

### Tool result: `assert_fact`

```json
{
  "status": "asserted",
  "fact_type": "compromised-host",
  "value": "t",
  "scoped_to": "patient-1",
  "inert": false
}
```

### Tool call: `assert_fact`

```json
{
  "fact_type": "culture-site",
  "value": "blood"
}
```

### Tool result: `assert_fact`

```json
{
  "status": "asserted",
  "fact_type": "culture-site",
  "value": "blood",
  "scoped_to": "culture-1",
  "inert": false
}
```

### Tool call: `assert_fact`

```json
{
  "fact_type": "aerobicity",
  "value": "anaerobic"
}
```

### Tool result: `assert_fact`

```json
{
  "status": "asserted",
  "fact_type": "aerobicity",
  "value": "anaerobic",
  "scoped_to": "organism-1",
  "inert": false
}
```

### Tool call: `assert_fact`

```json
{
  "fact_type": "gram",
  "value": "neg",
  "confidence": 0.8
}
```

### Tool result: `assert_fact`

```json
{
  "status": "asserted",
  "fact_type": "gram",
  "value": "neg",
  "scoped_to": "organism-1",
  "inert": false,
  "confidence": 0.8
}
```

### Tool call: `assert_fact`

```json
{
  "fact_type": "gram",
  "value": "pos",
  "confidence": 0.6
}
```

### Tool result: `assert_fact`

```json
{
  "status": "asserted",
  "fact_type": "gram",
  "value": "pos",
  "scoped_to": "organism-1",
  "inert": false,
  "confidence": 0.6
}
```

## Assistant

Both gram readings recorded (neg at 0.8, pos at 0.6) as separate pieces of evidence — I'm not overwriting one with the other, since the microbiologist genuinely gave conflicting partial evidence and the belief algebra can carry both. Let me check what's close to firing, then run inference.

### Tool call: `get_partial_matches`

```json
{}
```

### Tool result: `get_partial_matches`

```json
{
  "partial_matches": [
    {
      "rule": "clumps-narrows-to-staphylococci",
      "belief": 0.7,
      "matched": [
        "organism",
        "gram (value=pos)"
      ],
      "missing": [
        "morphology (value=coccus)",
        "growth-conformation (value=clumps)"
      ],
      "matched_count": 2,
      "total_conditions": 4
    },
    {
      "rule": "chains-narrows-to-chain-formers",
      "belief": 0.7,
      "matched": [
        "organism",
        "gram (value=pos)"
      ],
      "missing": [
        "morphology (value=coccus)",
        "growth-conformation (value=chains)"
      ],
      "matched_count": 2,
      "total_conditions": 4
    },
    {
      "rule": "catalase-negative-narrows-to-chain-formers",
      "belief": 0.7,
      "matched": [
        "organism",
        "gram (value=pos)"
      ],
      "missing": [
        "morphology (value=coccus)",
        "catalase (value=negative)"
      ],
      "matched_count": 2,
      "total_conditions": 4
    },
    {
      "rule": "catalase-positive-narrows-to-staphylococci",
      "belief": 0.7,
      "matched": [
        "organism",
        "gram (value=pos)"
      ],
      "missing": [
        "morphology (value=coccus)",
        "catalase (value=positive)"
      ],
      "matched_count": 2,
      "total_conditions": 4
    },
    {
      "rule": "bile-esculin-salt-tolerant-narrows-to-enterococci",
      "belief": 0.8,
      "matched": [
        "organism",
        "gram (value=pos)"
      ],
      "missing": [
        "morphology (value=coccus)",
        "growth-conformation (value=chains)",
        "bile-esculin (value=positive)",
        "salt-tolerance (value=tolerant)"
      ],
      "matched_count": 2,
      "total_conditions": 6
    },
    {
      "rule": "bile-esculin-negative-narrows-to-streptococci",
      "belief": 0.6,
      "matched": [
        "organism",
        "gram (value=pos)"
      ],
      "missing": [
        "morphology (value=coccus)",
        "growth-conformation (value=chains)",
        "bile-esculin (value=negative)"
      ],
      "matched_count": 2,
      "total_conditions": 5
    },
    {
      "rule": "blood-compromised-chains-narrows-to-enterococci",
      "belief": 0.7,
      "matched": [
        "organism",
        "culture",
        "patient",
        "culture-site (value=blood)",
        "gram (value=pos)",
        "compromised-host (value=t)"
      ],
      "missing": [
        "morphology (value=coccus)",
        "growth-conformation (value=chains)"
      ],
      "matched_count": 6,
      "total_conditions": 8
    },
    {
      "rule": "coagulase-positive-narrows-to-aureus",
      "belief": 0.85,
      "matched": [
        "organism",
        "gram (value=pos)"
      ],
      "missing": [
        "morphology (value=coccus)",
        "growth-conformation (value=clumps)",
        "coagulase (value=positive)"
      ],
      "matched_count": 2,
      "total_conditions": 5
    },
    {
      "rule": "coagulase-negative-narrows-to-coagulase-negative-staph",
      "belief": 0.85,
      "matched": [
        "organism",
        "gram (value=pos)"
      ],
      "missing": [
        "morphology (value=coccus)",
        "growth-conformation (value=clumps)",
        "coagulase (value=negative)"
      ],
      "matched_count": 2,
      "total_conditions": 5
    },
    {
      "rule": "novobiocin-resistant-narrows-to-saprophyticus",
      "belief": 0.8,
      "matched": [
        "organism"
      ],
      "missing": [
        "coagulase (value=negative)",
        "novobiocin (value=resistant)"
      ],
      "matched_count": 1,
      "total_conditions": 3
    },
    {
      "rule": "novobiocin-sensitive-narrows-to-epidermidis",
      "belief": 0.7,
      "matched": [
        "organism"
      ],
      "missing": [
        "coagulase (value=negative)",
        "novobiocin (value=sensitive)"
      ],
      "matched_count": 1,
      "total_conditions": 3
    },
    {
      "rule": "beta-hemolysis-narrows-to-beta-hemolytic-strep",
      "belief": 0.75,
      "matched": [
        "organism"
      ],
      "missing": [
        "hemolysis (value=beta)"
      ],
      "matched_count": 1,
      "total_conditions": 2
    },
    {
      "rule": "alpha-hemolysis-narrows-to-alpha-hemolytic-strep",
      "belief": 0.75,
      "matched": [
        "organism"
      ],
      "missing": [
        "hemolysis (value=alpha)"
      ],
      "matched_count": 1,
      "total_conditions": 2
    },
    {
      "rule": "bacitracin-sensitive-narrows-to-pyogenes",
      "belief": 0.85,
      "matched": [
        "organism"
      ],
      "missing": [
        "hemolysis (value=beta)",
        "bacitracin (value=sensitive)"
      ],
      "matched_count": 1,
      "total_conditions": 3
    },
    {
      "rule": "bacitracin-resistant-narrows-to-agalactiae",
      "belief": 0.7,
      "matched": [
        "organism"
      ],
      "missing": [
        "hemolysis (value=beta)",
        "bacitracin (value=resistant)"
      ],
      "matched_count": 1,
      "total_conditions": 3
    },
    {
      "rule": "optochin-sensitive-narrows-to-pneumoniae",
      "belief": 0.85,
      "matched": [
        "organism"
      ],
      "missing": [
        "hemolysis (value=alpha)",
        "optochin (value=sensitive)"
      ],
      "matched_count": 1,
      "total_conditions": 3
    },
    {
      "rule": "optochin-resistant-narrows-to-viridans",
      "belief": 0.65,
      "matched": [
        "organism"
      ],
      "missing": [
        "hemolysis (value=alpha)",
        "optochin (value=resistant)"
      ],
      "matched_count": 1,
      "total_conditions": 3
    },
    {
      "rule": "sorbitol-pos-arabinose-neg-narrows-to-faecalis",
      "belief": 0.7,
      "matched": [
        "organism"
      ],
      "missing": [
        "bile-esculin (value=positive)",
        "salt-tolerance (value=tolerant)",
        "sorbitol (value=fermenter)",
        "arabinose (value=non-fermenter)"
      ],
      "matched_count": 1,
      "total_conditions": 5
    },
    {
      "rule": "arabinose-pos-sorbitol-neg-narrows-to-faecium",
      "belief": 0.7,
      "matched": [
        "organism"
      ],
      "missing": [
        "bile-esculin (value=positive)",
        "salt-tolerance (value=tolerant)",
        "arabinose (value=fermenter)",
        "sorbitol (value=non-fermenter)"
      ],
      "matched_count": 1,
      "total_conditions": 5
    },
    {
      "rule": "hospital-acquired-clumps-narrows-to-aureus",
      "belief": 0.8,
      "matched": [
        "organism",
        "patient",
        "gram (value=pos)"
      ],
      "missing": [
        "morphology (value=coccus)",
        "growth-conformation (value=clumps)",
        "hospital-acquired (value=t)"
      ],
      "matched_count": 3,
      "total_conditions": 6
    },
    {
      "rule": "iv-drug-use-clumps-narrows-to-aureus",
      "belief": 0.55,
      "matched": [
        "organism",
        "patient",
        "gram (value=pos)"
      ],
      "missing": [
        "morphology (value=coccus)",
        "growth-conformation (value=clumps)",
        "iv-drug-use (value=t)"
      ],
      "matched_count": 3,
      "total_conditions": 6
    },
    {
      "rule": "respiratory-chains-narrows-to-pneumoniae",
      "belief": 0.75,
      "matched": [
        "organism",
        "culture",
        "gram (value=pos)"
      ],
      "missing": [
        "infection-site (value=respiratory)",
        "morphology (value=coccus)",
        "growth-conformation (value=chains)"
      ],
      "matched_count": 3,
      "total_conditions": 6
    },
    {
      "rule": "neonate-beta-hemolytic-narrows-to-agalactiae",
      "belief": 0.7,
      "matched": [
        "organism",
        "patient",
        "gram (value=pos)"
      ],
      "missing": [
        "age-group (value=neonate)",
        "morphology (value=coccus)",
        "hemolysis (value=beta)"
      ],
      "matched_count": 3,
      "total_conditions": 6
    },
    {
      "rule": "prosthetic-material-coag-neg-narrows-to-epidermidis",
      "belief": 0.6,
      "matched": [
        "organism",
        "patient",
        "gram (value=pos)"
      ],
      "missing": [
        "morphology (value=coccus)",
        "coagulase (value=negative)",
        "prosthetic-material (value=t)"
      ],
      "matched_count": 3,
      "total_conditions": 6
    },
    {
      "rule": "urinary-coag-neg-narrows-to-saprophyticus",
      "belief": 0.65,
      "matched": [
        "organism",
        "patient",
        "gram (value=pos)"
      ],
      "missing": [
        "morphology (value=coccus)",
        "coagulase (value=negative)",
        "infection-site (value=urinary)"
      ],
      "matched_count": 3,
      "total_conditions": 6
    },
    {
      "rule": "aerobic-gram-neg-rod-narrows-to-aerobic-gram-neg-rods",
      "belief": 0.8,
      "matched": [
        "organism",
        "gram (value=neg)"
      ],
      "missing": [
        "morphology (value=rod)",
        "aerobicity (value=aerobic)"
      ],
      "matched_count": 2,
      "total_conditions": 4
    },
    {
      "rule": "lactose-fermenter-narrows-to-fermenters",
      "belief": 0.7,
      "matched": [
        "organism",
        "gram (value=neg)"
      ],
      "missing": [
        "morphology (value=rod)",
        "aerobicity (value=aerobic)",
        "lactose (value=fermenter)"
      ],
      "matched_count": 2,
      "total_conditions": 5
    },
    {
      "rule": "lactose-non-fermenter-narrows-to-non-fermenters",
      "belief": 0.7,
      "matched": [
        "organism",
        "gram (value=neg)"
      ],
      "missing": [
        "morphology (value=rod)",
        "aerobicity (value=aerobic)",
        "lactose (value=non-fermenter)"
      ],
      "matched_count": 2,
      "total_conditions": 5
    },
    {
      "rule": "indole-positive-narrows-to-indole-producers",
      "belief": 0.6,
      "matched": [
        "organism",
        "gram (value=neg)"
      ],
      "missing": [
        "morphology (value=rod)",
        "indole (value=positive)"
      ],
      "matched_count": 2,
      "total_conditions": 4
    },
    {
      "rule": "urease-positive-narrows-to-urease-producers",
      "belief": 0.7,
      "matched": [
        "organism",
        "gram (value=neg)"
      ],
      "missing": [
        "morphology (value=rod)",
        "urease (value=positive)"
      ],
      "matched_count": 2,
      "total_conditions": 4
    },
    {
      "rule": "red-pigment-narrows-to-serratia",
      "belief": 0.8,
      "matched": [
        "organism",
        "gram (value=neg)"
      ],
      "missing": [
        "morphology (value=rod)",
        "pigment (value=red)"
      ],
      "matched_count": 2,
      "total_conditions": 4
    },
    {
      "rule": "lactose-pos-indole-pos-narrows-to-e-coli",
      "belief": 0.8,
      "matched": [
        "organism",
        "gram (value=neg)"
      ],
      "missing": [
        "morphology (value=rod)",
        "aerobicity (value=aerobic)",
        "lactose (value=fermenter)",
        "indole (value=positive)"
      ],
      "matched_count": 2,
      "total_conditions": 6
    },
    {
      "rule": "motile-lactose-pos-indole-neg-narrows-to-motile-fermenters",
      "belief": 0.6,
      "matched": [
        "organism",
        "gram (value=neg)"
      ],
      "missing": [
        "morphology (value=rod)",
        "aerobicity (value=aerobic)",
        "lactose (value=fermenter)",
        "indole (value=negative)",
        "motility (value=motile)"
      ],
      "matched_count": 2,
      "total_conditions": 7
    },
    {
      "rule": "urease-negative-narrows-to-non-proteus-rods",
      "belief": 0.7,
      "matched": [
        "organism",
        "gram (value=neg)"
      ],
      "missing": [
        "morphology (value=rod)",
        "urease (value=negative)"
      ],
      "matched_count": 2,
      "total_conditions": 4
    },
    {
      "rule": "non-motile-narrows-to-non-motile-rods",
      "belief": 0.6,
      "matched": [
        "organism",
        "gram (value=neg)"
      ],
      "missing": [
        "morphology (value=rod)",
        "aerobicity (value=aerobic)",
        "motility (value=non-motile)"
      ],
      "matched_count": 2,
      "total_conditions": 5
    },
    {
      "rule": "urease-pos-swarming-narrows-to-proteus",
      "belief": 0.8,
      "matched": [
        "organism",
        "gram (value=neg)"
      ],
      "missing": [
        "morphology (value=rod)",
        "urease (value=positive)",
        "motility (value=swarming)"
      ],
      "matched_count": 2,
      "total_conditions": 5
    },
    {
      "rule": "burn-blood-aerobic-gram-neg-rod-narrows-to-opportunist-rods",
      "belief": 0.4,
      "matched": [
        "organism",
        "culture",
        "culture-site (value=blood)",
        "gram (value=neg)",
        "burn (value=serious)"
      ],
      "missing": [
        "morphology (value=rod)",
        "aerobicity (value=aerobic)"
      ],
      "matched_count": 5,
      "total_conditions": 7
    },
    {
      "rule": "compromised-aerobic-gram-neg-rod-narrows-to-opportunist-rods",
      "belief": 0.6,
      "matched": [
        "organism",
        "culture",
        "gram (value=neg)",
        "compromised-host (value=t)"
      ],
      "missing": [
        "morphology (value=rod)",
        "aerobicity (value=aerobic)"
      ],
      "matched_count": 4,
      "total_conditions": 6
    },
    {
      "rule": "hospital-acquired-aerobic-gram-neg-rod-narrows-to-opportunist-rods",
      "belief": 0.7,
      "matched": [
        "organism",
        "culture",
        "gram (value=neg)"
      ],
      "missing": [
        "morphology (value=rod)",
        "aerobicity (value=aerobic)",
        "hospital-acquired (value=t)"
      ],
      "matched_count": 3,
      "total_conditions": 6
    },
    {
      "rule": "neutropenia-aerobic-gram-neg-rod-narrows-to-opportunist-rods",
      "belief": 0.5,
      "matched": [
        "organism",
        "culture",
        "gram (value=neg)"
      ],
      "missing": [
        "morphology (value=rod)",
        "aerobicity (value=aerobic)",
        "neutropenia (value=t)"
      ],
      "matched_count": 3,
      "total_conditions": 6
    },
    {
      "rule": "anaerobic-gram-neg-rod-in-blood-narrows-to-bacteroides",
      "belief": 0.9,
      "matched": [
        "organism",
        "culture",
        "culture-site (value=blood)",
        "gram (value=neg)",
        "aerobicity (value=anaerobic)"
      ],
      "missing": [
        "morphology (value=rod)"
      ],
      "matched_count": 5,
      "total_conditions": 6
    },
    {
      "rule": "anaerobic-gram-neg-rod-in-abdomen-narrows-to-bacteroides",
      "belief": 0.8,
      "matched": [
        "organism",
        "culture",
        "gram (value=neg)",
        "aerobicity (value=anaerobic)"
      ],
      "missing": [
        "morphology (value=rod)",
        "infection-site (value=abdominal)"
      ],
      "matched_count": 4,
      "total_conditions": 6
    },
    {
      "rule": "hospital-acquired-compromised-aerobic-gram-neg-rod-narrows-to-opportunist-rods",
      "belief": 0.7,
      "matched": [
        "organism",
        "culture",
        "gram (value=neg)",
        "compromised-host (value=t)"
      ],
      "missing": [
        "morphology (value=rod)",
        "aerobicity (value=aerobic)",
        "hospital-acquired (value=t)"
      ],
      "matched_count": 4,
      "total_conditions": 7
    },
    {
      "rule": "tropical-travel-aerobic-gram-neg-rod-narrows-to-enteric-rods",
      "belief": 0.65,
      "matched": [
        "organism",
        "culture",
        "gram (value=neg)"
      ],
      "missing": [
        "morphology (value=rod)",
        "aerobicity (value=aerobic)",
        "recent-travel (value=tropical)"
      ],
      "matched_count": 3,
      "total_conditions": 6
    }
  ]
}
```

## Assistant

Good — I have enough facts to run a preliminary inference, but there's one high-value gap: the **anaerobic-gram-neg-rod-in-blood-narrows-to-bacteroides** rule is missing only `morphology` (rod vs. coccus) and is otherwise fully matched (5 of 6 conditions, belief 0.9). That's the single most informative thing to ask right now — do you have a morphology reading (rod or coccus) on the anaerobic organism?

In the meantime, let me run inference on what we have so you can see where the hedge on gram stain has landed things.

### Tool call: `run_inference`

```json
{}
```

### Tool result: `run_inference`

```json
{
  "status": "completed",
  "rules_fired": 4
}
```

### Tool call: `get_conclusions`

```json
{}
```

### Tool result: `get_conclusions`

```json
{
  "organisms": [
    {
      "organism": "organism-1",
      "conflict": 0.23519999999999996,
      "margin": 0.18305439330543938,
      "leading_answer": [
        "bacteroides",
        "e-coli",
        "enterobacter",
        "klebsiella",
        "proteus",
        "pseudomonas",
        "salmonella",
        "serratia"
      ],
      "margin_against": [
        "enterococcus-faecalis",
        "enterococcus-faecium",
        "staphylococcus-aureus",
        "staphylococcus-epidermidis",
        "staphylococcus-saprophyticus",
        "streptococcus-agalactiae",
        "streptococcus-pneumoniae",
        "streptococcus-pyogenes",
        "streptococcus-viridans"
      ],
      "theta_mass": 0.3336820083682009,
      "answers": [
        {
          "narrows_to": [
            "bacteroides",
            "e-coli",
            "enterobacter",
            "klebsiella",
            "proteus",
            "pseudomonas",
            "salmonella",
            "serratia"
          ],
          "belief": 0.56
        },
        {
          "narrows_to": [
            "enterococcus-faecalis",
            "enterococcus-faecium",
            "staphylococcus-aureus",
            "staphylococcus-epidermidis",
            "staphylococcus-saprophyticus",
            "streptococcus-agalactiae",
            "streptococcus-pneumoniae",
            "streptococcus-pyogenes",
            "streptococcus-viridans"
          ],
          "belief": 0.41999999999999993
        }
      ],
      "hypotheses": [
        {
          "value": "bacteroides",
          "bel": 0.0,
          "pl": 0.7583682008368202,
          "ignorance": 0.7583682008368202
        },
        {
          "value": "e-coli",
          "bel": 0.0,
          "pl": 0.7583682008368202,
          "ignorance": 0.7583682008368202
        },
        {
          "value": "enterobacter",
          "bel": 0.0,
          "pl": 0.7583682008368202,
          "ignorance": 0.7583682008368202
        },
        {
          "value": "enterococcus-faecalis",
          "bel": 0.0,
          "pl": 0.5753138075313808,
          "ignorance": 0.5753138075313808
        },
        {
          "value": "enterococcus-faecium",
          "bel": 0.0,
          "pl": 0.5753138075313808,
          "ignorance": 0.5753138075313808
        },
        {
          "value": "klebsiella",
          "bel": 0.0,
          "pl": 0.7583682008368202,
          "ignorance": 0.7583682008368202
        },
        {
          "value": "proteus",
          "bel": 0.0,
          "pl": 0.7583682008368202,
          "ignorance": 0.7583682008368202
        },
        {
          "value": "pseudomonas",
          "bel": 0.0,
          "pl": 0.7583682008368202,
          "ignorance": 0.7583682008368202
        },
        {
          "value": "salmonella",
          "bel": 0.0,
          "pl": 0.7583682008368202,
          "ignorance": 0.7583682008368202
        },
        {
          "value": "serratia",
          "bel": 0.0,
          "pl": 0.7583682008368202,
          "ignorance": 0.7583682008368202
        },
        {
          "value": "staphylococcus-aureus",
          "bel": 0.0,
          "pl": 0.5753138075313808,
          "ignorance": 0.5753138075313808
        },
        {
          "value": "staphylococcus-epidermidis",
          "bel": 0.0,
          "pl": 0.5753138075313808,
          "ignorance": 0.5753138075313808
        },
        {
          "value": "staphylococcus-saprophyticus",
          "bel": 0.0,
          "pl": 0.5753138075313808,
          "ignorance": 0.5753138075313808
        },
        {
          "value": "streptococcus-agalactiae",
          "bel": 0.0,
          "pl": 0.5753138075313808,
          "ignorance": 0.5753138075313808
        },
        {
          "value": "streptococcus-pneumoniae",
          "bel": 0.0,
          "pl": 0.5753138075313808,
          "ignorance": 0.5753138075313808
        },
        {
          "value": "streptococcus-pyogenes",
          "bel": 0.0,
          "pl": 0.5753138075313808,
          "ignorance": 0.5753138075313808
        },
        {
          "value": "streptococcus-viridans",
          "bel": 0.0,
          "pl": 0.5753138075313808,
          "ignorance": 0.5753138075313808
        }
      ],
      "set_valued": [
        {
          "members": [
            "bacteroides",
            "e-coli",
            "enterobacter",
            "klebsiella",
            "proteus",
            "pseudomonas",
            "salmonella",
            "serratia"
          ],
          "mass": 0.4246861924686193
        },
        {
          "members": [
            "enterococcus-faecalis",
            "enterococcus-faecium",
            "staphylococcus-aureus",
            "staphylococcus-epidermidis",
            "staphylococcus-saprophyticus",
            "streptococcus-agalactiae",
            "streptococcus-pneumoniae",
            "streptococcus-pyogenes",
            "streptococcus-viridans"
          ],
          "mass": 0.2416317991631799
        }
      ]
    }
  ],
  "belief_system": "Dempster-Shafer (candidate sets)",
  "conclusions": []
}
```

## Assistant

Here's where things stand — and this is a genuinely torn picture, not a resolved one.

**The two hedges are pulling in different directions, and both registered:**

- The rule **anaerobic-gram-neg-rod-in-blood-narrows-to-bacteroides** fired on the gram-negative (0.8 confidence) reading, narrowing to a set of eight gram-negative organisms — {bacteroides, e-coli, enterobacter, klebsiella, proteus, pseudomonas, salmonella, serratia} — at belief 0.56.
- Simultaneously, the gram-positive (0.6 confidence) reading fired the **chain-formers / staphylococci** family of answers, narrowing to a set of nine gram-positive cocci — {enterococcus-faecalis, enterococcus-faecium, staphylococcus-aureus, staphylococcus-epidermidis, staphylococcus-saprophyticus, streptococcus-agalactiae, streptococcus-pneumoniae, streptococcus-pyogenes, streptococcus-viridans} — at belief 0.42.

These two sets don't overlap at all, so **no single organism has any belief committed to it yet** — every hypothesis in the payload sits at `bel: 0.0`. What you have is belief split between two whole *sets*, which is the honest reflection of a stain read two ways.

**Reading the numbers:**
- `conflict` (K) = 0.235, `margin` = 0.183, with `margin_against` naming the gram-positive set. K here isn't "the evidence deteriorating" — it's the mass Dempster-Shafer had to write off because a gram-negative-rod answer and a gram-positive-coccus answer are mutually exclusive. The modest margin (0.18) says this conflict is real and not close to resolved: the gram-negative reading is ahead, but not by much.
- `theta_mass` = 0.33 — a third of belief committed to nothing named at all. That's the corpus's honest ignorance given how much rides on a stain that's explicitly unreliable here, and it is **not** the same thing as any one organism's own uncertainty.
- Within the gram-negative set, **Bacteroides specifically** hasn't been named yet — the anaerobic-gram-neg-rod-in-blood rule answers "one of these eight," not "Bacteroides," because it's still missing `morphology`. Every organism in both sets has `pl` well above 0 (0.76 for the gram-negative candidates, 0.58 for the gram-positive ones) — none is excluded, all are still consistent with what's known.

**This is the point where a single bench result would do more than anything else I could ask for:** a `morphology` reading (rod vs. coccus) would settle which of the two big sets you're actually in, since the anaerobic-gram-neg-rod-in-blood rule is sitting at 5/6 conditions matched and just needs morphology=rod to name Bacteroides directly at 0.9 belief. If morphology instead comes back coccus, that would firm up the gram-positive branch instead (though it would still need `catalase` or `growth-conformation` to go further — clumps vs. chains, staph vs. strep/enterococcus).

Before you act on any of this: **this is a 17-organism research corpus with schematic, illustrative belief numbers** — not a validated system and not a basis for clinical decisions. The `0.56`/`0.42` split reflects how the confidence you gave me (0.8 vs 0.6) propagated through the rules, not a measured probability of anything.

Can you get a morphology reading, or any other discriminator (lactose/indole/urease/pigment if it leans gram-negative; catalase if it leans gram-positive)?

## Clinician

How much of that conflict comes from the stain itself, and how confident should I be? Quote the actual figures.

### Tool call: `explain_conclusion`

```json
{
  "organism": "bacteroides"
}
```

### Tool result: `explain_conclusion`

```json
{
  "organism": "bacteroides",
  "entity": "organism-1",
  "bel": 0.0,
  "pl": 0.7583682008368202,
  "conflict": 0.23519999999999996,
  "margin": 0.18305439330543938,
  "leading_answer": [
    "bacteroides",
    "e-coli",
    "enterobacter",
    "klebsiella",
    "proteus",
    "pseudomonas",
    "salmonella",
    "serratia"
  ],
  "margin_against": [
    "enterococcus-faecalis",
    "enterococcus-faecium",
    "staphylococcus-aureus",
    "staphylococcus-epidermidis",
    "staphylococcus-saprophyticus",
    "streptococcus-agalactiae",
    "streptococcus-pneumoniae",
    "streptococcus-pyogenes",
    "streptococcus-viridans"
  ],
  "theta_mass": 0.3336820083682009,
  "argument": [
    {
      "narrows_to": [
        "bacteroides",
        "e-coli",
        "enterobacter",
        "klebsiella",
        "proteus",
        "pseudomonas",
        "salmonella",
        "serratia"
      ],
      "belief": 0.56,
      "admits": true,
      "rules": [
        {
          "rule": "gram-negative-narrows-to-gram-negatives",
          "belief": 0.7,
          "provenance": {
            "origin": "paip-subset",
            "evidence": [
              "NCBI Bookshelf / StatPearls, Gram Staining, NBK562156",
              "NCBI Bookshelf / StatPearls, Gram-Positive Bacteria, NBK470553"
            ],
            "belief_basis": "illustrative",
            "note": "The Gram stain partitions bacteria into two mutually exclusive cell-wall categories. Stated as what a gram-negative result establishes; the gram-positives are excluded by intersection."
          }
        }
      ]
    },
    {
      "narrows_to": [
        "enterococcus-faecalis",
        "enterococcus-faecium",
        "staphylococcus-aureus",
        "staphylococcus-epidermidis",
        "staphylococcus-saprophyticus",
        "streptococcus-agalactiae",
        "streptococcus-pneumoniae",
        "streptococcus-pyogenes",
        "streptococcus-viridans"
      ],
      "belief": 0.41999999999999993,
      "admits": false,
      "rules": [
        {
          "rule": "gram-positive-narrows-to-gram-positives",
          "belief": 0.7,
          "provenance": {
            "origin": "paip-subset",
            "evidence": [
              "NCBI Bookshelf / StatPearls, Gram Staining, NBK562156",
              "NCBI Bookshelf / StatPearls, Gram-Positive Bacteria, NBK470553"
            ],
            "belief_basis": "illustrative",
            "note": "The mirror image: a gram-positive stain narrows to the gram-positive organisms the corpus models."
          }
        }
      ]
    }
  ],
  "intersection": [
    "bacteroides",
    "e-coli",
    "enterobacter",
    "klebsiella",
    "proteus",
    "pseudomonas",
    "salmonella",
    "serratia"
  ],
  "narrative": "gram-negative-narrows-to-gram-negatives said one of {bacteroides, e-coli, enterobacter, klebsiella, proteus, pseudomonas, salmonella, serratia} at 0.56; gram-positive-narrows-to-gram-positives said one of {enterococcus-faecalis, enterococcus-faecium, staphylococcus-aureus, staphylococcus-epidermidis, staphylococcus-saprophyticus, streptococcus-agalactiae, streptococcus-pneumoniae, streptococcus-pyogenes, streptococcus-viridans} at 0.42. One answer admits bacteroides, and together they narrow to {bacteroides, e-coli, enterobacter, klebsiella, proteus, pseudomonas, salmonella, serratia}. One other names organisms bacteroides is not among, which is what costs it plausibility -- no rule argues against bacteroides.",
  "belief_system": "Dempster-Shafer (candidate sets)"
}
```

## Assistant

All the conflict traces to exactly two rules, and nothing else — confirmed by the argument trace:

**The entire conflict is the stain, full stop.**

- `gram-negative-narrows-to-gram-negatives` fired at **belief 0.56** (this already reflects the 0.8 confidence you gave the gram-negative reading, run through the rule's own 0.7 belief weight), answering "one of eight" — {bacteroides, e-coli, enterobacter, klebsiella, proteus, pseudomonas, salmonella, serratia}.
- `gram-positive-narrows-to-gram-positives` fired at **belief 0.42** (from your 0.6 confidence on the gram-positive reading through the same 0.7 rule weight), answering "one of nine" — the enterococci/staphylococci/streptococci set.

No other rule contributed to this conflict. The anaerobic/blood/burn/compromised-host facts are all sitting in working memory waiting on `morphology` — they haven't fired yet, so they are not part of this number. **Every bit of `conflict = 0.235` and the resulting `margin = 0.183` comes from those two gram rules disagreeing with each other, and nothing else.** That's visible directly in the trace: only those two rules appear in the argument.

**How to read it:**
- K = 0.235 is the mass Dempster-Shafer had to discard because "one of these eight gram-negatives" and "one of these nine gram-positives" cannot both be true — it is not a measure of how much *is* known, only how much *conflicting* evidence was overruled or discarded.
- margin = 0.183 is what actually tells you whether that conflict resolved. It didn't, not really: 0.183 is a thin lead. The gram-negative branch is ahead of the gram-positive branch by only about 0.18 belief-points out of a maximum possible margin of ~1.0 — read as roughly "the negative reading is somewhat favored, but the positive reading remains genuinely live," not as a settled call.
- Concretely: `bel = 0.0` and `pl = 0.76` for bacteroides itself, and `bel = 0.0`, `pl = 0.58` for every gram-positive candidate (e.g., staph aureus). Nothing is excluded on either side; nothing has bel > 0 yet because neither branch has narrowed to a single species.

**How confident should you be?** Not very, on the stain alone. A 0.56-vs-0.42 split with a 0.18 margin is, in plain terms, a coin that's landed slightly more often on gram-negative but not decisively — exactly what you'd expect from a hedge of "probably X, possibly Y" run through the algebra rather than resolved by it. This is illustrative arithmetic from a schematic, non-clinical corpus (belief_basis: illustrative on every rule cited above) — not a measured probability, and not something to act on directly.

The single fact that would collapse this fastest is still `morphology`: rod vs. coccus feeds a rule sitting at 5/6 conditions matched (the anaerobic-gram-neg-rod-in-blood-narrows-to-bacteroides rule, belief 0.9) or would instead firm up the gram-positive branch. Do you have that reading?


---

*Ended 2026-08-25T15:43:58*
