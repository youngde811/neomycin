# Release check — burn ICU, v0.11 candidate sets (2026-08-22)

A verbatim driver session run as the **release check** described in `CLAUDE.md`
("the layers must agree"): prompt + tool schemas + bridge + engine in one loop, with
every narrated figure checked against the engine afterwards. The first sample
captured under the v0.11 candidate-set representation.

**Goldens this reproduces** (`culture-1b`, computed independently and matched exactly):

| quantity | golden | narrated |
|---|---|---|
| `bel(pseudomonas)` | 0.8375 | 0.84 ✓ |
| `bel(klebsiella)` | 0.0975 | 0.0975 ✓ |
| `pl(klebsiella)` | 0.1625 | 0.16 ✓ |
| conflict `K` | 0.5568 | 0.557 ✓ |
| `margin` | 0.7401 | 0.74 ✓ |
| `pl(proteus)` before → after urease | 0.0650 → 0.0260 | 0.065 → 0.026 ✓ |
| coverage threshold | 0.1 | 0.1 ✓ (read from the echoed field, not recalled) |
| regimen | meropenem | meropenem ✓ |

**What it exercises, and why it was run.** Each of these was a defect found by
auditing the 2026-08-18 consultation:

- **conflict read with `margin`** — "K=0.557/margin=0.74 said this was a real
  overrule, not an unstable tie". The August session called the same numbers
  "the evidence fighting itself", three times, while the identification sharpened.
- **`below_threshold` / `covered_by`** — Klebsiella misses the gate by 0.0025 and the
  narration says meropenem covers it anyway at 0.88. Previously reported as untreated.
- **the urease-negative reciprocal** — a reading that fired nothing before v0.11.x.

**It also found a live defect, on the first run.** `/rules?premises=` matched premise
VALUES only, so `?premises=urease` returned zero rules and the model told the
clinician there was no rule reading a negative urease and that Proteus could not be
excluded — both false. The filter now matches parameter names too. This transcript is
the **second** run, after that fix; the first is not kept, but the failure is recorded
here because it is the reason the release check exists.

---

# Lisa/Claude session transcript

- Started: 2026-08-22T18:59:02
- Model: `claude-sonnet-5`
- Bridge: `http://localhost:8090`
- Belief system: `Dempster-Shafer (candidate sets)`
- Verbosity: `normal`

---

## Clinician

27-year-old with serious burns, so immunocompromised. Blood culture: gram-negative rods, aerobic. Hospital-acquired.

### Tool call: `assert_fact`

```json
{
  "fact_type": "burn",
  "value": "serious"
}
```

### Tool call: `assert_fact`

```json
{
  "fact_type": "compromised-host",
  "value": "t"
}
```

### Tool call: `assert_fact`

```json
{
  "fact_type": "hospital-acquired",
  "value": "t"
}
```

### Tool call: `assert_fact`

```json
{
  "fact_type": "culture-site",
  "value": "blood"
}
```

### Tool call: `assert_fact`

```json
{
  "fact_type": "gram",
  "value": "neg"
}
```

### Tool call: `assert_fact`

```json
{
  "fact_type": "morphology",
  "value": "rod"
}
```

### Tool call: `assert_fact`

```json
{
  "fact_type": "aerobicity",
  "value": "aerobic"
}
```

### Tool call: `run_inference`

_(no arguments)_

### Tool call: `get_conclusions`

_(no arguments)_

### Tool result: `get_conclusions`

```json
{
  "organisms": [
    {
      "organism": "organism-1",
      "conflict": 0.5568000376060609,
      "margin": 0.7400724063808124,
      "leading_answer": [
        "pseudomonas"
      ],
      "margin_against": [
        "klebsiella"
      ],
      "ignorance": 0.0038989139042878177,
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
          "belief": 0.7
        },
        {
          "narrows_to": [
            "pseudomonas"
          ],
          "belief": 0.92800003
        },
        {
          "narrows_to": [
            "e-coli",
            "enterobacter",
            "klebsiella",
            "proteus",
            "pseudomonas",
            "salmonella",
            "serratia"
          ],
          "belief": 0.8
        },
        {
          "narrows_to": [
            "klebsiella"
          ],
          "belief": 0.6
        }
      ],
      "hypotheses": [
        {
          "value": "pseudomonas",
          "bel": 0.8375452539880078,
          "pl": 0.9025271523928048,
          "ignorance": 0.06498189840479696
        },
        {
          "value": "klebsiella",
          "bel": 0.09747284760719542,
          "pl": 0.16245474601199236,
          "ignorance": 0.06498189840479694
        },
        {
          "value": "bacteroides",
          "bel": 0.0,
          "pl": 0.012996379680959388,
          "ignorance": 0.012996379680959388
        },
        {
          "value": "e-coli",
          "bel": 0.0,
          "pl": 0.06498189840479694,
          "ignorance": 0.06498189840479694
        },
        {
          "value": "enterobacter",
          "bel": 0.0,
          "pl": 0.06498189840479694,
          "ignorance": 0.06498189840479694
        },
        {
          "value": "proteus",
          "bel": 0.0,
          "pl": 0.06498189840479694,
          "ignorance": 0.06498189840479694
        },
        {
          "value": "salmonella",
          "bel": 0.0,
          "pl": 0.06498189840479694,
          "ignorance": 0.06498189840479694
        },
        {
          "value": "serratia",
          "bel": 0.0,
          "pl": 0.06498189840479694,
          "ignorance": 0.06498189840479694
        }
      ],
      "set_valued": [
        {
          "members": [
            "e-coli",
            "enterobacter",
            "klebsiella",
            "proteus",
            "pseudomonas",
            "salmonella",
            "serratia"
          ],
          "mass": 0.05198551872383756
        },
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
          "mass": 0.009097465776671572
        }
      ]
    }
  ],
  "belief_system": "Dempster-Shafer (candidate sets)",
  "conclusions": [
    {
      "value": "pseudomonas",
      "belief": 0.8375452539880078
    },
    {
      "value": "klebsiella",
      "belief": 0.09747284760719542
    }
  ]
}
```

## Assistant

Here's the picture with the facts you've given (serious burn → immunocompromised, hospital-acquired, blood culture with aerobic gram-negative rods):

**Pseudomonas aeruginosa** is the leading identification: **belief 0.84, plausibility 0.90** — a narrow band of residual uncertainty (~0.06), so this is a fairly settled call.

**Klebsiella** is also still on the table, but at much lower share: **belief 0.10, plausibility 0.16**.

A few other Enterobacteriaceae (E. coli, Enterobacter, Proteus, Salmonella, Serratia, Bacteroides) sit at belief 0 / plausibility ~0.06 — not excluded, just names nothing has specifically spoken to yet; that plausibility ceiling is the residual ignorance in the case, not evidence against them.

**How this was built** (four answers fired):
1. Gram-negative stain alone → "one of {bacteroides, e-coli, enterobacter, klebsiella, proteus, pseudomonas, salmonella, serratia}" at 0.70
2. Burn + aerobic gram-neg rod + blood culture → **Pseudomonas specifically**, at 0.928
3. Aerobic gram-neg rod → "one of the seven Enterobacteriaceae/Pseudomonas" at 0.80
4. Compromised-host → **Klebsiella specifically**, at 0.60

The **conflict** here is K = 0.557, with a **margin of 0.74** between Pseudomonas and Klebsiella (the nearest rival answer). That's a case of high K with a *wide* margin — meaning the Klebsiella-favoring evidence (the compromised-host rule) was real and did fire, but the burn+blood-culture Pseudomonas evidence was stronger and overruled it, rather than the picture being genuinely torn. This is essentially the classic burn-ICU pattern this corpus was built to illustrate.

Would you like me to pull the full `explain_conclusion` breakdown (with citations) for Pseudomonas or Klebsiella, or shall I check antimicrobial therapy coverage for this differential? If therapy, I'll need to know about any drug allergies or contraindications first.

## Clinician

Urease came back negative.

### Tool call: `assert_fact`

```json
{
  "fact_type": "urease",
  "value": "negative"
}
```

### Tool call: `describe_rules`

_premises='urease'_

## Assistant

Urease-negative is meaningful here — let me run it through.

### Tool call: `run_inference`

_(no arguments)_

### Tool call: `get_conclusions`

_(no arguments)_

### Tool result: `get_conclusions`

```json
{
  "organisms": [
    {
      "organism": "organism-1",
      "conflict": 0.5568000376060609,
      "margin": 0.7400724063808124,
      "leading_answer": [
        "pseudomonas"
      ],
      "margin_against": [
        "klebsiella"
      ],
      "ignorance": 0.001559565561715127,
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
          "belief": 0.7
        },
        {
          "narrows_to": [
            "pseudomonas"
          ],
          "belief": 0.92800003
        },
        {
          "narrows_to": [
            "e-coli",
            "enterobacter",
            "klebsiella",
            "proteus",
            "pseudomonas",
            "salmonella",
            "serratia"
          ],
          "belief": 0.8
        },
        {
          "narrows_to": [
            "klebsiella"
          ],
          "belief": 0.6
        },
        {
          "narrows_to": [
            "bacteroides",
            "e-coli",
            "enterobacter",
            "klebsiella",
            "pseudomonas",
            "salmonella",
            "serratia"
          ],
          "belief": 0.6
        }
      ],
      "hypotheses": [
        {
          "value": "pseudomonas",
          "bel": 0.8375452539880078,
          "pl": 0.9025271523928047,
          "ignorance": 0.06498189840479685
        },
        {
          "value": "klebsiella",
          "bel": 0.09747284760719542,
          "pl": 0.1624547460119924,
          "ignorance": 0.06498189840479697
        },
        {
          "value": "bacteroides",
          "bel": 0.0,
          "pl": 0.012996379680959388,
          "ignorance": 0.012996379680959388
        },
        {
          "value": "e-coli",
          "bel": 0.0,
          "pl": 0.06498189840479696,
          "ignorance": 0.06498189840479696
        },
        {
          "value": "enterobacter",
          "bel": 0.0,
          "pl": 0.06498189840479696,
          "ignorance": 0.06498189840479696
        },
        {
          "value": "proteus",
          "bel": 0.0,
          "pl": 0.025992759361918784,
          "ignorance": 0.025992759361918784
        },
        {
          "value": "salmonella",
          "bel": 0.0,
          "pl": 0.06498189840479696,
          "ignorance": 0.06498189840479696
        },
        {
          "value": "serratia",
          "bel": 0.0,
          "pl": 0.06498189840479696,
          "ignorance": 0.06498189840479696
        }
      ],
      "set_valued": [
        {
          "members": [
            "e-coli",
            "enterobacter",
            "klebsiella",
            "pseudomonas",
            "salmonella",
            "serratia"
          ],
          "mass": 0.03119131123430254
        },
        {
          "members": [
            "e-coli",
            "enterobacter",
            "klebsiella",
            "proteus",
            "pseudomonas",
            "salmonella",
            "serratia"
          ],
          "mass": 0.020794207489535026
        },
        {
          "members": [
            "bacteroides",
            "e-coli",
            "enterobacter",
            "klebsiella",
            "pseudomonas",
            "salmonella",
            "serratia"
          ],
          "mass": 0.007797827808575633
        },
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
          "mass": 0.003638986310668629
        }
      ]
    }
  ],
  "belief_system": "Dempster-Shafer (candidate sets)",
  "conclusions": [
    {
      "value": "pseudomonas",
      "belief": 0.8375452539880078
    },
    {
      "value": "klebsiella",
      "belief": 0.09747284760719542
    }
  ]
}
```

## Assistant

The urease-negative result did register a new answer — **"urease-negative-narrows-to-non-proteus-rods"** at belief 0.6, which narrows the field to seven organisms by excluding Proteus (Proteus is characteristically strongly urease-positive, so a negative result rules it out).

**Effect on the numbers:** Pseudomonas and Klebsiella's belief figures are essentially unchanged (0.8375 and 0.0975, same as before to four decimal places) — those two were already sitting on their own answers (the burn/blood-culture Pseudomonas rule at 0.928, the compromised-host Klebsiella rule at 0.60), and the new urease answer doesn't add resolution *for* either of them since both were already inside all the coarser sets. What it did move is **Proteus**: its plausibility dropped from 0.065 to 0.026, since it's now been excluded by name from this newest answer.

So — urease-negative was genuinely informative, just not for the two organisms currently leading. It closes off Proteus as a live possibility rather than sharpening the Pseudomonas-vs-Klebsiella picture.

**Overall standing is unchanged:**
- **Pseudomonas**: belief 0.84, plausibility 0.90
- **Klebsiella**: belief 0.10, plausibility 0.16
- Conflict K = 0.557, margin = 0.74 (Pseudomonas comfortably ahead — the same wide-margin overrule of the Klebsiella-favoring evidence as before)

If you want to narrow the Enterobacteriaceae/Pseudomonas set further, lactose, indole, motility, or pigment are the remaining discriminators this corpus can act on. Otherwise, would you like me to check therapy coverage now? If so, let me know about any drug allergies or contraindications.

## Clinician

No known drug allergies. What therapy do you recommend?

### Tool call: `recommend_therapy`

```json
{
  "patient": []
}
```

### Tool result: `recommend_therapy`

```json
{
  "regimen": [
    {
      "drug": "meropenem",
      "dose": "1 g IV q8h",
      "covers": [
        "pseudomonas"
      ],
      "susceptibility": [
        {
          "organism": "pseudomonas",
          "bel": 0.72,
          "pl": 0.92,
          "ignorance": 0.19999999,
          "source": "reference"
        }
      ]
    }
  ],
  "items_to_treat": [
    {
      "organism": "pseudomonas",
      "belief": 0.8375452539880078
    }
  ],
  "excluded": [],
  "uncovered": [],
  "below_threshold": [
    {
      "organism": "klebsiella",
      "belief": 0.09747284760719542,
      "covered_by": [
        {
          "drug": "meropenem",
          "susceptibility": {
            "organism": "klebsiella",
            "bel": 0.88,
            "pl": 0.99,
            "ignorance": 0.110000014,
            "source": "reference"
          }
        }
      ]
    }
  ],
  "set_obligations": [],
  "alternative_agents": [
    {
      "drug": "ceftazidime",
      "dose": "2 g IV q8h",
      "covers": [
        "pseudomonas"
      ],
      "susceptibility": [
        {
          "organism": "pseudomonas",
          "bel": 0.7,
          "pl": 0.9,
          "ignorance": 0.19999999,
          "source": "reference"
        }
      ]
    },
    {
      "drug": "piperacillin-tazobactam",
      "dose": "4.5 g IV q6h",
      "covers": [
        "pseudomonas"
      ],
      "susceptibility": [
        {
          "organism": "pseudomonas",
          "bel": 0.64,
          "pl": 0.9,
          "ignorance": 0.26,
          "source": "reference"
        }
      ]
    }
  ],
  "alternative_regimens": [
    {
      "drugs": [
        {
          "drug": "ceftazidime",
          "dose": "2 g IV q8h",
          "covers": [
            "pseudomonas"
          ],
          "susceptibility": [
            {
              "organism": "pseudomonas",
              "bel": 0.7,
              "pl": 0.9,
              "ignorance": 0.19999999,
              "source": "reference"
            }
          ]
        }
      ]
    },
    {
      "drugs": [
        {
          "drug": "piperacillin-tazobactam",
          "dose": "4.5 g IV q6h",
          "covers": [
            "pseudomonas"
          ],
          "susceptibility": [
            {
              "organism": "pseudomonas",
              "bel": 0.64,
              "pl": 0.9,
              "ignorance": 0.26,
              "source": "reference"
            }
          ]
        }
      ]
    }
  ],
  "belief_system": "Dempster-Shafer (candidate sets)",
  "solver": "exact",
  "gate": "belief",
  "objective": "lexicographic",
  "coverage_threshold": 0.1,
  "susceptibility_threshold": 0.5
}
```

## Assistant

Given no drug allergies, here's what the solver returned (exact solver, default `lexicographic` tiebreak, default `belief` coverage gate, coverage threshold 0.1, susceptibility threshold 0.5):

**Regimen: meropenem 1 g IV q8h**
- Targets: Pseudomonas (identification belief 0.84, which clears the 0.1 coverage threshold)
- Susceptibility against Pseudomonas: belief 0.72, plausibility 0.92 — a fairly wide interval (ignorance 0.20), and it's a **reference-only** figure with no local isolates folded in, so treat it as provisional pending your local antibiogram.

**Klebsiella — below threshold, but still covered.** Klebsiella's identification belief is 0.0975, just under the 0.1 coverage gate — a near miss by about 0.003, which is a threshold effect rather than the evidence being weak (recall K=0.557/margin=0.74 said this was a real overrule, not an unstable tie). The solver therefore didn't target Klebsiella specifically, **but meropenem covers it anyway**: susceptibility belief 0.88, plausibility 0.99 (again reference-only, ignorance 0.11) — so it's not actually an untreated gap.

**Nothing was excluded** (no contraindications given) and **nothing was left uncovered**.

**Alternatives the solver passed over** (same drug count — 1 — but scored lower on the tiebreak of susceptibility × belief):
- **Ceftazidime** 2 g IV q8h — Pseudomonas belief 0.70, plausibility 0.90 (reference, ignorance 0.20)
- **Piperacillin-tazobactam** 4.5 g IV q6h — Pseudomonas belief 0.64, plausibility 0.90 (reference, ignorance 0.26)

Both are legitimate single-agent options against Pseudomonas; meropenem simply carries the highest reference susceptibility figure, which is why the tiebreak favored it. If you wanted to explore narrowing (e.g., `spectrum-sparing` objective) I can rerun it, but I'd flag up front: with only one named organism to cover, narrowing here trades a somewhat lower coverage floor for a somewhat narrower drug — it isn't a straightforward improvement, and I'd want to show you the trade explicitly rather than just switching agents.

One important caveat to repeat: **this is a research/illustrative tool, not a basis for real prescribing** — the susceptibility figures are schematic reference data, not your lab's actual antibiogram.


---

*Ended 2026-08-22T19:00:06*
