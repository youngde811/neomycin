# Gram-positive cocci — two more chained clusters, plus host-factor modifiers

> **📦 ATTIC — historical record.** Design for the gram-positive expansion, written in terms of CHAINED CLUSTERS, ORGANISM-CLASSES and lettered slices. **None of those mechanisms survives** — the rules it produced were converted to narrows-to answers at v0.11 and live in `neomycin/rules/candidates-gram-pos.lisp`.

*Design & slice plan. Branch: `feature/gram-positive-cluster`. Implements
`docs/corpus-expansion-sketch.md` §5.5 (host factors) and two more instances of the
§3(B) chained-cluster pattern, taking the corpus from 27 → 50 rules.*

> **⚠️ NOT FOR CLINICAL USE.** Everything below is a research illustration of
> 1970s clinical logic. Provenance notes concern *fidelity to historical MYCIN*
> and the *existence* of a documented clinical association — **never** clinical
> validity, and never the belief numbers, which stay `:belief-basis :illustrative`.

---

## 1. Why — the gram-positive side has the defect enterobacteriaceae had

Slice C2 of the chained-cluster work retired the one-hop
`aerobic-gram-neg-rod-suggests-enterobacteriaceae` **leaf identity** rule on the
grounds that enterobacteriaceae is a *family*, not a species, and that carrying
it as a leaf double-counted the same evidence.

The gram-positive side still has exactly that defect, three times over:

- `gram-pos-cocci-in-clumps-suggests-staphylococcus` (0.7) concludes
  `organism-identity :staphylococcus` — a **genus**, not a species.
- `gram-pos-cocci-in-chains-suggests-streptococcus` (0.7) — likewise a genus.
- `gram-pos-cocci-in-chains-in-blood-compromised-suggests-enterococcus` (0.7) —
  likewise a genus.

Meanwhile two further rules jump *straight* from raw morphology to a species
(`…suggests-staph-aureus`, `…suggests-strep-pneumoniae`), skipping the genus
entirely. So the same evidence supports both a genus-as-leaf and a species, with
no relationship between them — the pre-C2 situation.

This is the cheapest high-value corpus increment available, because it is a
**principled repeat of a pattern with a worked template**, not a new invention.

### What it buys the DS algebra (sketch §6)

The gram-positive cocci have a genuinely better discriminator tree than the
enterobacteriaceae do — catalase, coagulase, hemolysis, and four
disc/biochemical tests partition the space into **mutually exclusive** siblings.
Mutual exclusivity is precisely what makes `pl` fall below 1.0. Where the
enterobacteriaceae discriminators are partly overlapping (hence the honest
exclusions in the v0.5.0 cross-disconfirming rules — Proteus dropped from the
indole rule, Serratia from the lactose rule), hemolysis is a clean three-way
partition and coagulase a clean two-way one. The negative beliefs here can
therefore be *stronger* and the resulting conflict sharper.

---

## 2. The discriminator tree

Standard clinical microbiology; **every claim below is verified against an
authoritative source before the corresponding rule is authored** (§7, slice 0)
and the citation lands in that rule's machine-readable `:provenance :evidence`,
per the WHY/HOW facility.

```
gram-positive coccus
├── in CLUMPS  (catalase +)              → organism-class :staphylococcus  [tier 1]
│   ├── coagulase +                                  → S. aureus
│   └── coagulase −  (CoNS)
│       ├── novobiocin resistant                     → S. saprophyticus
│       └── (default CoNS)                           → S. epidermidis
├── in CHAINS  (catalase −)              → organism-class :streptococcus   [tier 1]
│   ├── beta hemolysis
│   │   ├── bacitracin sensitive                     → S. pyogenes    (Group A)
│   │   └── bacitracin resistant                     → S. agalactiae  (Group B)
│   └── alpha hemolysis
│       ├── optochin sensitive                       → S. pneumoniae
│       └── optochin resistant                       → viridans group
└── in CHAINS, bile-esculin +, salt-tolerant
                                         → organism-class :enterococcus    [tier 1]
    ├── arabinose −, sorbitol +                      → E. faecalis
    └── arabinose +, sorbitol −                      → E. faecium
```

**Why the enterococcus split needs *both* sugars.** The common teaching is that
arabinose alone separates the two. Verification found that claim contested: the
Facklam-scheme literature reports *E. faecalis* fermenting sorbitol but not
arabinose and *E. faecium* the reverse (PMC5476817, exact quote in §9), while
the biochemical key in PMC91588 found arabinose insufficiently discriminating
between them. Requiring the **pair** is the honest reading of a genuinely
divided source base, and the disagreement itself is recorded in both species
rules' `:provenance :note`. Belief is held at 0.7 rather than the 0.8 a clean
single marker would earn.

**Enterococcus gets its own tier-1 class.** Bile-esculin positivity alone does
not separate enterococci from the non-enterococcal group D streptococci —
growth in 6.5% NaCl is what does, so the class rule requires both. Modern
taxonomy (the 1984 genus split, *after* MYCIN) backs treating it as a genus
peer of *Staphylococcus* and *Streptococcus* rather than a streptococcal
subtype. The E. faecalis / E. faecium split it enables is not decoration: it is
the single most therapy-consequential distinction on the gram-positive side,
since ampicillin and vancomycin behave very differently across the two.

**Tier-1 premises are carried over unchanged where a leaf is retired, as C2
did.** The staphylococcus and streptococcus class rules take the premises of the
leaf rules they replace (`gram pos` + `coccus` + `clumps`/`chains`) and the same
`0.7` belief. Catalase is *not* made a mandatory premise — that would break
every existing scenario that never asserts it. It enters instead as a
disconfirming rule (§3.4), which is where it does real DS work anyway.

---

## 3. Rule inventory

### 3.1 Tier-1 — genus as a belief-valued intermediate (3 new, 1 re-pointed, 2 retired)

| Rule | Belief | Notes |
|---|---|---|
| `gram-pos-cocci-in-clumps-suggests-staphylococcus-class` | 0.7 | carried from the retired leaf |
| `gram-pos-cocci-in-chains-suggests-streptococcus-class` | 0.7 | carried from the retired leaf |
| `bile-esculin-pos-salt-tolerant-chains-suggests-enterococcus-class` | 0.8 | new; the characteristic pair |
| `gram-pos-cocci-in-chains-in-blood-compromised-suggests-enterococcus` | 0.7 | **re-pointed** to conclude the class, not an identity |

Retired: `gram-pos-cocci-in-clumps-suggests-staphylococcus`,
`gram-pos-cocci-in-chains-suggests-streptococcus`.

Two evidence paths to the enterococcus class (biochemical and clinical) mirror
the two paths klebsiella and salmonella each already have — and keep the class
reachable in scenarios that never run a bile-esculin.

### 3.2 Tier-2 — species refinement (9 new, 2 re-parented)

Belief composes **through** the class: species belief = class belief × the
rule's belief.

**Staphylococcus** (class 0.7):

| Rule | Belief | Composes to |
|---|---|---|
| `staph-coagulase-pos-suggests-staph-aureus` | 0.85 | 0.595 |
| `staph-coagulase-neg-suggests-staph-epidermidis` | 0.55 | 0.385 |
| `staph-coagulase-neg-novobiocin-resistant-suggests-staph-saprophyticus` | 0.8 | 0.56 |
| `hospital-acquired-gram-pos-cocci-in-clumps-suggests-staph-aureus` *(re-parented, 0.8)* | 0.8 | 0.56 |

`0.55` for S. epidermidis is deliberately the weakest in the corpus: CoNS is a
*group*, and S. epidermidis is the default member rather than a positive
identification. That near-tie against S. saprophyticus is the point.

**Streptococcus** (class 0.7):

| Rule | Belief | Composes to |
|---|---|---|
| `strep-beta-hemolytic-bacitracin-sensitive-suggests-strep-pyogenes` | 0.85 | 0.595 |
| `strep-beta-hemolytic-bacitracin-resistant-suggests-strep-agalactiae` | 0.7 | 0.49 |
| `strep-alpha-hemolytic-optochin-sensitive-suggests-strep-pneumoniae` | 0.85 | 0.595 |
| `strep-alpha-hemolytic-optochin-resistant-suggests-viridans` | 0.65 | 0.455 |
| `respiratory-gram-pos-cocci-in-chains-suggests-strep-pneumoniae` *(re-parented, 0.75)* | 0.75 | 0.525 |

**Enterococcus** (class 0.8):

| Rule | Belief | Composes to |
|---|---|---|
| `enterococcus-sorbitol-pos-arabinose-neg-suggests-e-faecalis` | 0.7 | 0.56 |
| `enterococcus-arabinose-pos-sorbitol-neg-suggests-e-faecium` | 0.7 | 0.56 |

A deliberate exact tie — two siblings at 0.56 separated only by a reciprocal
pair of sugar reactions, which is the sharpest possible setup for the
cross-disconfirming rule in §3.4 to do visible work.

### 3.3 Host-factor modifiers (5 new) — sketch §5.5

Patient-level evidence that **shifts belief on hypotheses other rules raise**,
rather than naming an organism from morphology. Weak-to-moderate by design:
this is the CF-vs-DS material, where a single number hides what an interval shows.

| Rule | Belief | Association |
|---|---|---|
| `neutropenia-with-aerobic-gram-neg-rod-suggests-pseudomonas` | 0.5 | classic neutropenic-sepsis pathogen |
| `prosthetic-material-with-coagulase-neg-staph-suggests-staph-epidermidis` | 0.6 | device-associated biofilm infection |
| `iv-drug-use-with-staphylococcus-suggests-staph-aureus` | 0.55 | S. aureus predominance in injection-related bacteremia |
| `neonate-with-beta-hemolytic-strep-suggests-strep-agalactiae` | 0.7 | Group B strep, neonatal sepsis |
| `urinary-coagulase-neg-staph-suggests-staph-saprophyticus` | 0.65 | S. saprophyticus as a UTI agent |

*Deferred to keep the total at 50* (all defensible, none load-bearing):
neutropenia → viridans via chemotherapy mucositis; asplenia → S. pneumoniae;
indwelling catheter → Proteus.

### 3.4 Cross-disconfirmation (8 new)

The DS-conflict layer — without these the new siblings all sit at `pl 1.0`, the
exact gap observed live before v0.5.0.

| Rule | Belief | Argues against |
|---|---|---|
| `coagulase-neg-argues-against-staph-aureus` | −0.85 | S. aureus |
| `coagulase-pos-argues-against-coagulase-negative-staph` | −0.85 | S. epidermidis, S. saprophyticus |
| `beta-hemolysis-argues-against-non-beta-streptococci` | −0.75 | S. pneumoniae, viridans |
| `alpha-hemolysis-argues-against-beta-hemolytic-streptococci` | −0.75 | S. pyogenes, S. agalactiae |
| `optochin-sensitive-argues-against-viridans` | −0.7 | viridans group |
| `bile-esculin-neg-argues-against-enterococci` | −0.6 | E. faecalis, E. faecium |
| `catalase-neg-argues-against-staphylococci` | −0.7 | S. aureus, S. epidermidis, S. saprophyticus |
| `arabinose-pos-argues-against-e-faecalis` | −0.7 | E. faecalis |

Hemolysis is a clean partition, so the two hemolysis rules carry a stronger
−0.75 than the enterobacteriaceae biochemicals did; coagulase is cleaner still
(−0.85). `bile-esculin` gets the mildest −0.6: some non-enterococcal group D
streptococci are also bile-esculin positive, so a *negative* is informative but
not decisive.

### 3.5 Accounting

| Category | Now | After |
|---|---|---|
| One-hop leaf confirming | 10 | 5 |
| Tier-1 class rules | 1 | 5 |
| Tier-2 species (enterobacteriaceae) | 8 | 8 |
| Tier-2 species (staphylococcus) | — | 4 |
| Tier-2 species (streptococcus) | — | 5 |
| Tier-2 species (enterococcus) | — | 2 |
| Host-factor modifiers | — | 5 |
| Disconfirming | 8 | 16 |
| **Total** | **27** | **50** |

25 rules authored, 2 retired: **net +23**. Disconfirming rises slightly to 32%
of the corpus. Leaf identities go 13 → 17: `:staphylococcus`, `:streptococcus`
and `:enterococcus` leave the identity space to become classes; seven species
enter (`:staphylococcus-epidermidis`, `:staphylococcus-saprophyticus`,
`:streptococcus-pyogenes`, `:streptococcus-agalactiae`,
`:streptococcus-viridans`, `:enterococcus-faecalis`, `:enterococcus-faecium`).

Three chained clusters after this, up from one.

---

## 4. New parameters

Organism-level (10): `catalase`, `coagulase`, `hemolysis`, `optochin`,
`bacitracin`, `novobiocin`, `bile-esculin`, `salt-tolerance`, `arabinose`,
`sorbitol`.

Patient-level (4): `neutropenia`, `prosthetic-material`, `iv-drug-use`,
`age-group` (neonate | infant | adult | elderly). The urinary host-factor rule
reuses the existing `infection-site`.

**14 new parameters in total.**

All are plain `param-mixin` subclasses — one `defclass` each, no schema change
(sketch §7).

---

## 5. Knock-on effects

- **`gram-neg-stain-argues-against-gram-pos-organism`** — its `member` test list
  names `:staphylococcus`, `:streptococcus` and `:enterococcus`, none of which
  will exist as identities. Replace with the seven new species plus the retained
  `:staphylococcus-aureus` / `:streptococcus-pneumoniae`. The C2 precedent is
  recorded in that rule's own comment, which already notes dropping
  `:enterobacteriaceae` for the same reason.
- **Therapy KB** — `:staphylococcus`, `:streptococcus` and `:enterococcus` are
  currently KB organisms with real susceptibility entries. They become **family
  keys** via the existing `deffamily` mechanism, so the new species inherit
  those susceptibilities with no new entries, exactly as `:e-coli` inherits from
  `:enterobacteriaceae` today. No solver change. The one place this deserves a
  second look is E. faecium, whose whole clinical interest is that it does *not*
  behave like the family average on ampicillin or vancomycin — a good candidate
  for species-specific overrides in a follow-up, not here.
- **Existing scenario goldens** — `culture-3` (chains → strep, strep-pneumoniae,
  enterococcus) and `culture-multi` (clumps → staph) both change shape: the
  genus stops appearing in `/conclusions` and species compose through it. Same
  re-capture C2 required.
- **Two new drivers** — `culture-4` (gram-positive differential: hemolysis +
  optochin driving competing strep species) and `culture-5` (host factors
  shifting a differential).
- **LLM surfaces** — `system-prompt.md` ontology and `tools.json` fact-type
  enums need the 14 new parameters and the revised identity list.

---

## 6. The testing problem this increment triggers (sketch §8)

At 50 rules the golden-per-rule model is at the limit the sketch predicted. The
plan is **complementary, not a replacement**:

- Keep hand-verified goldens for every rule fired in isolation — 50 is still
  tractable, and the tier-2 composition goldens are exactly the ones worth
  hand-checking.
- Add **property tests** that hold mechanically across the whole corpus: a
  confirming rule fired alone contributes exactly its `:belief`; a disconfirming
  rule drops `pl` below 1.0; CF and DS agree absent conflict and diverge under
  it. These exist as one-off behavioural tests today; generalize them to iterate
  over the rulebase.
- Split `neomycin/rulebase.lisp` (747 lines) into `neomycin/rules/` by cluster —
  `context.lisp`, `identity-gram-neg.lisp`, `chain-enterobacteriaceae.lisp`,
  `chain-gram-pos.lisp`, `host-factors.lisp`, `disconfirming.lisp`,
  `drivers.lisp`. Diff-reviewability is the reason to do it *with* this
  increment rather than after.

---

## 7. Slice plan

Each slice is green and committed separately. **All slices delivered** — the corpus
landed at exactly 50 rules, 858 assertions / 152 tests, 0 failures.

- ✅ **Slice 0 — citations.** Verify every clinical claim in §2/§3 against NCBI
  Bookshelf / StatPearls / CDC / IDSA. No rule is authored before its citation
  exists.
- ✅ **Slice A — params + tier-1.** 14 new `param-mixin` classes; three class rules
  + one re-pointed; retire the two genus leaves; fix the gram-neg-stain member
  list; re-capture `culture-3` / `culture-multi` goldens.
- ✅ **Slice B — tier-2 species.** 9 new species rules + 2 re-parented; DS
  composition goldens.
- ✅ **Slice C — cross-disconfirmation.** 8 rules; conflict goldens showing `pl`
  falling below 1.0 for the losing sibling.
- ✅ **Slice D — host factors.** 5 modifier rules; `culture-5`.
- ✅ **Slice E — split + property tests.** `neomycin/rules/`; corpus-wide
  invariants.
- ✅ **Slice F — sync.** Therapy `deffamily`; CLAUDE.md counts; README; clinician
  scenarios; corpus sketch §5 status; system prompt; tools.json.

---

## 8. Open questions (for review)

1. **S. epidermidis as the CoNS default** *(decided: keep, 0.55)*. Modeling
   "coagulase-negative, nothing else distinctive" as *S. epidermidis at 0.55* is
   a simplification; the honest alternative is a
   `:coagulase-negative-staphylococcus` group identity. Sketch §5.2
   (significance/contaminant) will want the group form, since
   CoNS-from-a-single-blood-draw is that increment's motivating example. The
   choice here constrains that later increment — revisit when §5.2 is scheduled.
2. **Do the host-factor rules belong on the identity axis at all?** They assert
   `organism-identity` like everything else, so "modifier" describes intent, not
   mechanism. A true modifier would scale an existing belief rather than
   contribute a new one — which the engine does not currently express. Engine-axis
   work, noted not done.
3. **E. faecium's therapy inheritance** (§5). Inheriting the `:enterococcus`
   family susceptibilities understates exactly the resistance that makes the
   species split worth modeling. Correct fix is species-level KB entries;
   deferred so this increment stays corpus-only.

---

## 9. Verified citations (slice 0 output)

Every clinical claim behind a rule in §3, checked against a primary source
before authoring. These strings become the rules' `:provenance :evidence`.
**They verify that the clinical association is documented — never the belief
value, which stays `:belief-basis :illustrative`.**

| Claim | Source | Verified detail |
|---|---|---|
| Catalase separates *Staphylococcus* (+) from *Streptococcus*/*Enterococcus* (−) | StatPearls, Gram-Positive Bacteria, NBK470553; Medical Microbiology 4th ed. ch.12, NBK8448 | "Gram-positive cocci include Staphylococcus (catalase-positive), which forms clusters" |
| Coagulase separates *S. aureus* (+) from CoNS (−) | NBK8448; StatPearls, S. aureus Infection, NBK441868 | "tests made for catalase and coagulase production, allowing the coagulase-positive S aureus to be identified quickly" |
| *S. epidermidis* is coagulase-negative, catalase-positive, clustered | StatPearls, S. epidermidis Infection, NBK563240 | confirmed verbatim |
| Novobiocin resistance identifies *S. saprophyticus* among CoNS | StatPearls, S. saprophyticus Infection, NBK482367 | "93% positive predictive accuracy as a presumptive test" — supports 0.8, not higher |
| Streptococci partition into beta / alpha / gamma hemolysis | Medical Microbiology 4th ed. ch.13 (Streptococcus), NBK7611 | three-way split on blood agar |
| Bacitracin sensitivity presumptively identifies group A (*S. pyogenes*) vs B/C/G | NBK7611 | up to 10% of *S. pyogenes* are bacitracin-**resistant**, and 3–5% of group C/G susceptible — the reason for 0.85, not 0.95 |
| Optochin (and bile) sensitivity separates *S. pneumoniae* from other alpha-hemolytic streptococci | NBK7611 | "S pneumoniae can be separated from other α-hemolytic streptococci on the basis of sensitivity to surfactants, such as bile or optochin" |
| Bile-esculin hydrolysis presumptively identifies group D | J Clin Microbiol, bile-esculin test, PMC376909; PMC379740 | 100:2 group-D to non-group-D positive ratio |
| 6.5% NaCl tolerance separates enterococci from non-enterococcal group D | PMC379740; Enterococci (NCBI Bookshelf), NBK190427 | "Enterococcal group D streptococci were differentiated from non-enterococcal group D streptococci by 6.5% NaCl tolerance" |
| *E. faecalis* sorbitol+/arabinose−; *E. faecium* arabinose+/sorbitol− | PMC5476817 | "All the *Enterococcus faecalis* isolates fermented sorbitol, mannitol, glucose and lactose but not arabinose while *E. faecium* was able to ferment arabinose, mannitol, glucose and lactose but not sorbitol" |
| — **contested by** — | PMC91588 (Identification of *Enterococcus* spp. with a Biochemical Key) | its consensus matrix does **not** treat arabinose as discriminating between the two; hence the pair requirement and 0.7 |
| Prosthetic material / devices predispose to CoNS, esp. *S. epidermidis*, via biofilm | NBK563240 | "Patients with prosthetic valves, cardiac devices, central lines, catheters… are at most risk"; up to 40% of prosthetic valve endocarditis is CoNS |
| Injection drug use → *S. aureus* predominance | PMC6374230; StatPearls, Tricuspid Valve Endocarditis, NBK538423 | *S. aureus* in 60–70% of IVDU infective endocarditis vs <⅓ in non-users |
| Neonate + beta-hemolytic strep → group B (*S. agalactiae*) | CDC MMWR RR-59-10 (Prevention of Perinatal GBS Disease); StatPearls, GBS and Pregnancy, NBK482443; CDC ABCs neonatal sepsis | GBS is the leading cause of early-onset neonatal sepsis; note *E. coli* leads in **preterm** infants — recorded in the rule's `:note` |
| Young female + urinary + CoNS → *S. saprophyticus* | NBK482367 | "a common cause of uncomplicated urinary tract infections, particularly in young sexually active females" |
| Neutropenia → *Pseudomonas aeruginosa* as a feared bloodstream pathogen | PMC10434044; PMC5513208 | "one of the most severe and difficult-to-treat bacteria causing bloodstream infections in immunocompromised populations"; empiric antipseudomonal β-lactam is standard in febrile-neutropenia guidance |

**Weakest link, flagged honestly:** the neutropenia → *Pseudomonas* citation is
observational literature rather than a guideline paragraph naming the
association as a diagnostic prior. It supports "antipseudomonal cover is
standard in febrile neutropenia," which is adjacent to, but not identical with,
"a gram-negative rod in a neutropenic patient is more likely to be
*Pseudomonas*." The rule is authored at a deliberately modest 0.5 for that
reason, and the gap is recorded in its `:note`.