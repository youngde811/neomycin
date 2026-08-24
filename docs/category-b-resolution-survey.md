# Category B — do the context rules answer at the right resolution?

**Status: SURVEY. No code changes. Nothing here has been applied to the corpus.**
Branch: `feature/category-b-resolution`, from `develop` at v0.12.0.

## 1. What this is

Seventeen rules in the corpus premise on a patient- or culture-level context class
(`burn`, `compromised-host`, `hospital-acquired`, `recent-travel`,
`white-blood-count`, `infection-site`, `neutropenia`, `prosthetic-material`,
`iv-drug-use`, `age-group`, `culture-site`). **Sixteen of them answer with a
singleton.** Only `blood-compromised-chains-narrows-to-enterococci` names a set.

Under the representation shipped in v0.11, absence from an answer *is* exclusion. So
`burn-blood-gram-neg-rod-narrows-to-pseudomonas` does not say "Pseudomonas is likely
in a burn bacteraemia". It says the organism **is** Pseudomonas and is **not**
Klebsiella, Enterobacter, Serratia, Proteus or E. coli. Burn-unit gram-negative
bacteraemia is classically several of those.

The contrast that makes this a defect rather than a preference: after the August
audit, a **bench** marker that is merely *variable* for an organism must keep that
organism in the answer — invariant 12, `*variable-markers*`, citation-backed per
entry, enforced by `property-tests.lisp`. Epidemiological association discriminates
far *less* sharply than a bench marker. Yet these rules answer at maximum resolution
while the bench rules were made to widen. The corpus adopted set-valued answers to
stop manufacturing resolution it does not have, and then kept singletons exactly where
the evidence is thinnest.

This is the sketch's §7 "Category B is untouched" item, open since v0.9, and step 3 of
the original conditional audit.

## 2. Scope

**Resolution, not calibration.** The question asked of each rule is "does it answer at
the right resolution?", which is checkable against literature. "Is 0.40 the right
number?" is not asked — the beliefs are `:belief-basis :illustrative` throughout and
there is no plateau to measure against. Leave the numbers, fix the sets. Where a
belief and its evidence are plainly out of step, that is recorded as an observation
(§5C), not as a proposal.

**Wrong conditionals noted in passing.** `docs/belief-conditional-audit.md` predicted
that sensitivities stand in for posteriors, and predicted that context rules are where
that hides. One case is confirmed below and one is worse than a wrong conditional.

## 3. The candidate pools

A widened answer can only name organisms the corpus models. The pools are fixed by
the bench rules:

| pool | members | set by |
|---|---|---|
| aerobic gram-negative rods (7) | `e-coli klebsiella salmonella enterobacter serratia proteus pseudomonas` | `aerobic-gram-neg-rod-narrows-to-aerobic-gram-neg-rods` |
| gram-negative rods, any aerobicity (8) | the seven above + `bacteroides` | `gram-negative-narrows-to-gram-negatives` |
| staphylococci (3) | `aureus epidermidis saprophyticus` | `clumps-narrows-to-staphylococci` |
| coagulase-negative staphylococci (2) | `epidermidis saprophyticus` | `coagulase-negative-narrows-to-coagulase-negative-staph` |
| chain formers (6) | `pneumoniae pyogenes agalactiae viridans faecalis faecium` | `chains-narrows-to-chain-formers` |
| beta-hemolytic streptococci (2) | `pyogenes agalactiae` | `beta-hemolysis-narrows-to-beta-hemolytic-strep` |

Organisms outside these pools (Acinetobacter, S. lugdunensis, S. capitis) are **not**
a problem: the open frame keeps an unmodelled organism plausible as residual
ignorance. Only exclusions *among modelled organisms* are claims.

## 4. Verdicts

**Widen: 11. Survives as a singleton: 5. Of the 11, one is a retirement candidate and
one is borderline.**

| # | rule | belief | verdict |
|---|---|---|---|
| 1 | `burn-blood-gram-neg-rod-narrows-to-pseudomonas` | 0.4 | **widen** (borderline vacuous) |
| 2 | `compromised-gram-neg-rod-narrows-to-pseudomonas` | 0.6 | **widen** |
| 3 | `hospital-acquired-aerobic-gram-neg-rod-narrows-to-pseudomonas` | 0.7 | **widen** |
| 4 | `neutropenia-aerobic-gram-neg-rod-narrows-to-pseudomonas` | 0.5 | **widen** |
| 5 | `anaerobic-gram-neg-rod-in-blood-narrows-to-bacteroides` | 0.9 | survives |
| 6 | `anaerobic-gram-neg-rod-in-abdomen-narrows-to-bacteroides` | 0.8 | survives |
| 7 | `hospital-acquired-compromised-aerobic-gram-neg-rod-narrows-to-klebsiella` | 0.6 | **widen** |
| 8 | `compromised-aerobic-gram-neg-rod-narrows-to-klebsiella` | 0.5 | **widen** |
| 9 | `tropical-travel-aerobic-gram-neg-rod-narrows-to-salmonella` | 0.65 | **widen** (modestly) |
| 10 | `blood-low-wbc-aerobic-gram-neg-rod-narrows-to-salmonella` | 0.55 | **retire candidate** |
| 11 | `hospital-acquired-clumps-narrows-to-aureus` | 0.8 | **widen** |
| 12 | `iv-drug-use-clumps-narrows-to-aureus` | 0.55 | survives |
| 13 | `respiratory-chains-narrows-to-pneumoniae` | 0.75 | **widen** |
| 14 | `neonate-beta-hemolytic-narrows-to-agalactiae` | 0.7 | survives — **but premise defect** |
| 15 | `prosthetic-material-coag-neg-narrows-to-epidermidis` | 0.6 | survives |
| 16 | `urinary-coag-neg-narrows-to-saprophyticus` | 0.65 | **widen** |

---

### 1. `burn-blood-gram-neg-rod-narrows-to-pseudomonas` — 0.4 — **widen**

*Premises:* culture-site blood, gram neg, rod, burn serious. **No aerobicity gate.**
*Current answer:* `{pseudomonas}`

**What the literature supports.** In burn-associated bacteraemia, gram-negatives are
~63% of isolates, of which *P. aeruginosa* 34%, *K. pneumoniae* 12%, *A. baumannii*
9%, *E. cloacae* 8%. A nine-year gram-negative-bacilli bloodstream cohort in severe
burns gives *Pseudomonas* spp. 50.7%, *A. baumannii* 46.4%, *Klebsiella* spp. 13.8%.
The commonest gram-negative burn wound pathogens are named as *P. aeruginosa*,
*K. pneumoniae*, *A. baumannii*, *Enterobacter* spp., *Proteus* spp. and *E. coli*.

**Genuinely single-organism?** No. Pseudomonas leads, at a third to a half — not all.

**Proposed answer:** `{pseudomonas klebsiella enterobacter proteus e-coli serratia}`
— the aerobic seven less Salmonella, which is not described as a burn pathogen.

**Also, a premise defect.** With no aerobicity gate this rule fires on an *anaerobic*
gram-negative rod and answers `{pseudomonas}`, excluding Bacteroides on no evidence.
The authoring policy's "narrow the premises" move applies: add
`(aerobicity (value aerobic) (of ?o))`.

**Borderline vacuous.** Six of seven is a weak claim. If you would rather not carry a
rule that barely narrows, retirement is defensible — see §5D.

Sources: [PMC4128596](https://pmc.ncbi.nlm.nih.gov/articles/PMC4128596/) ·
[PMC11476612](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11476612/) ·
[PLOS One 0095042](https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0095042)

---

### 2. `compromised-gram-neg-rod-narrows-to-pseudomonas` — 0.6 — **widen**

*Premises:* gram neg, rod, compromised-host. **No aerobicity gate, no site gate.**
*Current answer:* `{pseudomonas}`

**What the literature supports.** *E. coli* is the most frequently reported organism
in gram-negative bacteraemia in solid-tumour patients (47%). In haematological
neutropenic patients *E. coli* and *P. aeruginosa* are jointly the primary agents.
Across nosocomial gram-negative bacteraemia generally, *E. coli* 40.5%, *K.
pneumoniae* 22.5%, *P. aeruginosa* 10%.

**Genuinely single-organism?** No — and Pseudomonas is not even the leading candidate
in most compromised populations.

**Proposed answer:** `{e-coli klebsiella pseudomonas enterobacter serratia}`

**Premise defect:** same missing aerobicity gate as #1.

Sources: [PMC12233224](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12233224/) ·
[CMR 10.1128/cmr.00234-20](https://journals.asm.org/doi/10.1128/cmr.00234-20) ·
[PubMed 23640443](https://pubmed.ncbi.nlm.nih.gov/23640443/)

---

### 3. `hospital-acquired-aerobic-gram-neg-rod-narrows-to-pseudomonas` — 0.7 — **widen**

*Premises:* gram neg, rod, aerobic, hospital-acquired.
*Current answer:* `{pseudomonas}`

**What the literature supports.** Nosocomial gram-negative bacteraemia: *E. coli*
40.5%, *K. pneumoniae* 22.5%, *P. aeruginosa* 10%, *A. baumannii* 10%. A second series
gives *E. coli* 25.5% as the principal organism, *K. pneumoniae* 11.2%. NHSN CLABSI
data (2006–07) rank the gram-negatives *Klebsiella* 5.8%, *Enterobacter* 3.9%,
*Pseudomonas* 3.1%, *E. coli* 2.7%.

**Genuinely single-organism?** No. **This is the worst offender in the set on the
belief axis** — 0.7, the highest of the four Pseudomonas context rules, asserted on
the organism that ranks third at roughly 10%.

**Proposed answer:** `{e-coli klebsiella pseudomonas enterobacter serratia proteus}`

Sources: [PubMed 23640443](https://pubmed.ncbi.nlm.nih.gov/23640443/) ·
[PMC4288947](https://pmc.ncbi.nlm.nih.gov/articles/PMC4288947/) ·
[NBK430891](https://www.ncbi.nlm.nih.gov/books/NBK430891/)

---

### 4. `neutropenia-aerobic-gram-neg-rod-narrows-to-pseudomonas` — 0.5 — **widen**

*Premises:* gram neg, rod, aerobic, neutropenia.
*Current answer:* `{pseudomonas}`

**What the literature supports.** Stated directly in the febrile-neutropenia
literature: *"Pseudomonas aeruginosa is still the third most common Gram-negative
cause of bacteremia in FN patients, after Klebsiella pneumoniae and Escherichia
coli."* Among gram-negative bacteraemias in febrile neutropenia, *E. coli* is 39.5%
and *K. pneumoniae* 23.3% of gram-negative isolates.

**Genuinely single-organism?** No — **the rule names the third-place organism as the
sole answer**, which is the cleanest single defect in the survey.

**Proposed answer:** `{e-coli klebsiella pseudomonas enterobacter serratia}`

**Note the rule's own confession.** Its `:note` already records that this is "the
WEAKEST CITATION IN THE CORPUS — the sources support empiric coverage rather than the
claim that the organism is more likely to be Pseudomonas." That is not a wrong
conditional; it is *no* conditional. "Cover Pseudomonas empirically because missing it
is catastrophic" is a **therapy** policy, and the corpus has a therapy phase to
express it. It was encoded as an identification claim, where it says something false.

Sources: [PMC3764750](https://ncbi.nlm.nih.gov/pmc/articles/PMC3764750) ·
[PMC5513208](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5513208/) ·
[Ann Hematol 10.1007/s00277-020-04144-w](https://link.springer.com/article/10.1007/s00277-020-04144-w)

---

### 5. `anaerobic-gram-neg-rod-in-blood-narrows-to-bacteroides` — 0.9 — **survives**
### 6. `anaerobic-gram-neg-rod-in-abdomen-narrows-to-bacteroides` — 0.8 — **survives**

*Current answer:* `{bacteroides}` in both.

**Genuinely single-organism?** Yes, but for a reason worth stating rather than
enjoying: **the corpus models exactly one anaerobic gram-negative rod.** The answer
already equals the entire anaerobic pool, so neither rule makes a resolution claim at
all — there is nothing it could have excluded.

**Proposed change: none to the answer.** But both notes should disclose that the
narrowness is an artifact of corpus coverage rather than of evidence — precisely the
disclosure `novobiocin-sensitive-narrows-to-epidermidis` already makes for the
unmodelled coagulase-negative staphylococci. Real anaerobic gram-negative bacteraemia
also includes *Fusobacterium* and *Prevotella*; the open frame keeps them plausible,
but the note should say so out loud.

---

### 7. `hospital-acquired-compromised-aerobic-gram-neg-rod-narrows-to-klebsiella` — 0.6 — **widen**
### 8. `compromised-aerobic-gram-neg-rod-narrows-to-klebsiella` — 0.5 — **widen**

*Current answer:* `{klebsiella}` in both. #7's premises are a strict superset of #8's,
so `consensus.lisp` drops #8 when both fire.

**What the literature supports.** *Klebsiella* is a solid #2 in nosocomial
gram-negative bacteraemia (22.5%, or 11.2% in the second series) — behind *E. coli*
(40.5% / 25.5%). Naming Klebsiella alone excludes the leader.

**Proposed answer (both):** `{e-coli klebsiella pseudomonas enterobacter serratia}`

**Premises unchanged**, so the subsumption relation #7 ⊃ #8 survives the widening and
`consensus.lisp` keeps behaving as documented.

**This is where the conflict lives.** Rules #2 and #8 fire on nearly identical
premises (`compromised-host` + gram-negative rod) and currently answer **disjoint
singletons** — `{pseudomonas} ∩ {klebsiella} = ∅`. Same for #3 and #7. Under the
intersection semantics that is a flat contradiction between two rules that are both
right. See §5E.

Sources: [PubMed 23640443](https://pubmed.ncbi.nlm.nih.gov/23640443/) ·
[PMC4288947](https://pmc.ncbi.nlm.nih.gov/articles/PMC4288947/) ·
[PMC12233224](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12233224/)

---

### 9. `tropical-travel-aerobic-gram-neg-rod-narrows-to-salmonella` — 0.65 — **widen modestly**

*Current answer:* `{salmonella}`

**What the literature supports.** Enteric fever accounts for ~2% of all fever and ~6%
of undifferentiated fever in returned travellers. Enteric bacteria — *E. coli*,
*Campylobacter*, *Salmonella*, *Shigella* — are the commonest bacterial causes of
fever from the tropics.

**Genuinely single-organism?** Nearly. This is the strongest of the widen cases
against widening, because the rule does not fire on *fever*; it fires on a blood
culture already growing an aerobic gram-negative rod. Conditioned on that, travel to
an endemic region genuinely raises Salmonella a long way. But *E. coli* bacteraemia
does not stop happening because the patient travelled.

**Proposed answer:** `{salmonella e-coli klebsiella}`

Sources: [PMC7152027](https://pmc.ncbi.nlm.nih.gov/articles/PMC7152027/) ·
[NBK620886 — CDC Yellow Book, Typhoid & Paratyphoid](https://www.ncbi.nlm.nih.gov/books/NBK620886/)

---

### 10. `blood-low-wbc-aerobic-gram-neg-rod-narrows-to-salmonella` — 0.55 — **retire candidate**

*Current answer:* `{salmonella}`

**What the literature supports.** Leukopenia is *classically described* in typhoid but
occurs in only about 25% of patients (24.6% in a 191-patient series); a normal or
elevated count is more common and does not exclude the diagnosis.

**The wrong conditional is confirmed.** The rule fires **on** a low white count and
must therefore answer P(Salmonella | low WBC, aerobic GNR in blood). The 15–25% figure
its note cites is P(low WBC | typhoid) — a **sensitivity**, and a poor one. The rule's
own `:note` already flags this, carried across from
`docs/belief-conditional-audit.md` §3.3 without adjustment.

**And the posterior is near-vacuous.** Leukopenia in gram-negative bacteraemia is a
marker of *severity*, not of species — it occurs across *E. coli*, *Klebsiella* and
*Pseudomonas* sepsis. So the honest widened answer approaches the full aerobic set,
which adds no information to what the stain already said.

**Recommendation: retire the rule.** A rule whose honest answer is "one of the seven"
should not be a rule. If you would rather keep it, the widened answer is
`{e-coli klebsiella salmonella pseudomonas enterobacter serratia}` — but see §5D
before choosing.

Sources: [PMC9018254 — Laboratory Findings in Typhoid](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9018254/) ·
[PubMed 1496717 — The white cell count in typhoid fever](https://pubmed.ncbi.nlm.nih.gov/1496717/) ·
[NBK557513](https://www.ncbi.nlm.nih.gov/books/NBK557513/)

---

### 11. `hospital-acquired-clumps-narrows-to-aureus` — 0.8 — **widen**

*Premises:* gram pos, coccus, clumps, hospital-acquired.
*Current answer:* `{staphylococcus-aureus}`

**What the literature supports.** Coagulase-negative staphylococci were the *most
common* pathogen in ICU bloodstream infections at 37.3%, against 12.6% for *S. aureus*
(1990–99 surveillance). More recent blood-culture data (2018–21) put *S. aureus* at
33.9% with CoNS distributed across *S. capitis* (18.6%), *S. hominis* (18.1%) and
others. Whichever series you take, CoNS is comparable to or larger than *S. aureus* in
the nosocomial setting.

**Genuinely single-organism?** No — and at 0.8 this is the joint-highest belief in the
whole Category B set, asserted on a singleton the surveillance data contradict.

**Proposed answer:** `{staphylococcus-aureus staphylococcus-epidermidis}`

**The contamination caveat, stated fairly.** Much CoNS in blood culture is skin
contaminant rather than infection, which is a genuine argument for *S. aureus*
carrying more weight. It is not an argument for **excluding** *S. epidermidis*, which
is what a singleton does — and hospital-acquired line infection is exactly the setting
where CoNS is most often real.

Sources: [PMC10305610](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10305610/) ·
[NBK430891 — CLABSI](https://www.ncbi.nlm.nih.gov/books/NBK430891/) ·
[Infectious Disease Advisor — CoNS](https://www.infectiousdiseaseadvisor.com/ddi/coagulase-negative-staphylococcus/)

---

### 12. `iv-drug-use-clumps-narrows-to-aureus` — 0.55 — **survives**

*Current answer:* `{staphylococcus-aureus}`

**What the literature supports.** *S. aureus* is the main organism isolated in
infective endocarditis in people who inject drugs — 70% in the Italian registry, with
viridans streptococci second at 10% and enterococci 10–15%. CoNS is distinctly less
common in PWID endocarditis than in prosthetic-valve endocarditis.

**Genuinely single-organism?** Yes, **given the premises**. The rule gates on
*clumps*, so the streptococci and enterococci that make up most of the non-*aureus*
share are already excluded by morphology. Within the clumping organisms, *S. aureus*
really does dominate. **Keep as authored.**

This is the best-evidenced singleton in the set — and it carries the *lowest* belief
of the six gram-positive context rules. See §5C.

Sources: [PMC9319987 — Italian Registry](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9319987/) ·
[NBK557641](https://www.ncbi.nlm.nih.gov/books/NBK557641/) ·
[PMC5266062](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5266062/)

---

### 13. `respiratory-chains-narrows-to-pneumoniae` — 0.75 — **widen**

*Premises:* infection-site respiratory, gram pos, coccus, chains.
*Current answer:* `{streptococcus-pneumoniae}`

**What the literature supports.** *S. pneumoniae* is the most commonly identified CAP
pathogen (pooled 19% in one meta-analysis). But viridans streptococci are a genuine
CAP pathogen in their own right — isolated from blood or pleural fluid in 5.9% of 455
consecutive CAP patients, and implicated in ~20% of CAP cases in a more recent source,
typically presenting as complicated parapneumonic effusion or empyema.

**Genuinely single-organism?** No. Viridans streptococci also dominate oropharyngeal
flora, so a respiratory specimen growing gram-positive cocci in chains is very often
viridans. **Excluding viridans from a respiratory chain-former is the most clinically
misleading exclusion in the gram-positive half.**

**Proposed answer:** `{streptococcus-pneumoniae streptococcus-viridans
streptococcus-pyogenes}` — pyogenes included because it causes pneumonia and empyema;
the enterococci left out, as enterococcal pneumonia is genuinely rare.

Sources: [PMC6669839](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6669839/) ·
[PubMed 16737994 — Viridans streptococci causing CAP](https://pubmed.ncbi.nlm.nih.gov/16737994/) ·
[PubMed 26175772](https://pubmed.ncbi.nlm.nih.gov/26175772/)

---

### 14. `neonate-beta-hemolytic-narrows-to-agalactiae` — 0.7 — **survives, but has a premise defect**

*Premises:* age-group neonate, hemolysis beta. **No gram gate, no morphology gate.**
*Current answer:* `{streptococcus-agalactiae}`

**On the answer axis: keep it.** Group B streptococcus is the leading gram-positive
cause of early-onset neonatal sepsis, and group A strep in neonates is rare. Among
*beta-hemolytic gram-positive cocci* in a neonate, GBS genuinely dominates.

**On the premise axis: this is the sharpest find in the gram-positive half.** The rule
gates on beta hemolysis and nothing else — no stain, no morphology. So it fires on a
**beta-hemolytic *E. coli*** and answers `{streptococcus-agalactiae}`. And *E. coli*
is precisely the organism the literature names as GBS's rival here: GBS and *E. coli*
together cause about two-thirds of early-onset infections, with *E. coli* now the
leading pathogen overall and close to GBS even in full-term neonates.

Compare `respiratory-chains-narrows-to-pneumoniae`, which is also pure context and
whose note says explicitly that it "gates on the stain and morphology that would have
derived the streptococcus class." The neonate rule needed the same gate and did not
get it.

**Proposed change:** add `(gram (value pos) (of ?o))` and
`(morphology (value coccus) (of ?o))`. Answer unchanged.

Sources: [PMC9607315 — E. coli overtaking GBS in EOS](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9607315/) ·
[Merck Manual — Neonatal Sepsis](https://www.merckmanuals.com/professional/pediatrics/infections-in-neonates/neonatal-sepsis) ·
[NBK531478](https://www.ncbi.nlm.nih.gov/books/NBK531478/)

---

### 15. `prosthetic-material-coag-neg-narrows-to-epidermidis` — 0.6 — **survives**

*Current answer:* `{staphylococcus-epidermidis}`

**What the literature supports.** CoNS account for 46.2% of prosthetic joint
infections and 20–25% of prosthetic valve endocarditis, and *S. epidermidis* is the
most prevalent CoNS in device infection generally and in PVE specifically.
*S. saprophyticus* is essentially never a device pathogen.

**Genuinely single-organism?** Yes, among the two coagulase-negative species the
corpus models. **Keep as authored.**

**Disclosure to add.** The narrowness is partly a corpus artifact — *S. lugdunensis*,
*S. capitis* and *S. hominis* are all real device pathogens the corpus cannot name.
The note should say so, exactly as `novobiocin-sensitive-narrows-to-epidermidis`
already does for the same species set.

**Minor premise gap:** unlike the bench rule
`coagulase-negative-narrows-to-coagulase-negative-staph`, this rule does not gate on
gram/morphology/clumps. Lower stakes than #14, since a coagulase result presupposes a
staphylococcus, but the corpus is inconsistent about it.

Sources: [Brieflands — PJI due to CoNS](https://brieflands.com/journals/iji/articles/14741) ·
[NBK567731 — Prosthetic Valve Endocarditis](https://www.ncbi.nlm.nih.gov/books/NBK567731/) ·
[NBK563240](https://www.ncbi.nlm.nih.gov/books/NBK563240/)

---

### 16. `urinary-coag-neg-narrows-to-saprophyticus` — 0.65 — **widen**

*Premises:* coagulase negative, infection-site urinary.
*Current answer:* `{staphylococcus-saprophyticus}`

**What the literature supports.** *S. saprophyticus* causes uncomplicated cystitis in
young, sexually active women. *S. epidermidis* is the CoNS of **catheterised and
complicated** urinary infection — "*S. saprophyticus* was isolated from young female
patients suffering from uncomplicated acute cystitis and *S. epidermidis* was mainly
from patients with indwelling catheters and complicated cases."

**Genuinely single-organism?** No — **for the population this rule actually fires
on.** The premises say only "urinary" and "coagulase-negative", so the rule fires
just as readily for a catheterised elderly inpatient, where *S. epidermidis* is the
likelier CoNS. The rule's evidence is about a population its premises do not select.

**Proposed answer:** `{staphylococcus-saprophyticus staphylococcus-epidermidis}`

**The sharper fix is not available.** "Narrow the premises" would be better here —
gate on young/female/uncatheterised — but the corpus has `age-group` and no sex and no
catheter parameter. Adding one is corpus expansion, outside this survey. Widening is
the move that is available and it is the conservative one.

Sources: [NBK482367](https://www.ncbi.nlm.nih.gov/books/NBK482367/) ·
[PMC9967252](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9967252/) ·
[antimicrobe.org — S. epidermidis and other CoNS](http://www.antimicrobe.org/b234.asp)

---

## 5. Cross-cutting findings

### A. Three of the sixteen are premise defects, not answer defects

`neonate-beta-hemolytic` (#14) does not gate on stain or morphology and will fire on a
beta-hemolytic *E. coli*. `burn-blood-gram-neg-rod` (#1) and
`compromised-gram-neg-rod` (#2) do not gate on aerobicity and will fire on an
anaerobe, excluding Bacteroides silently. The two coagulase-negative context rules
(#15, #16) are less gated than their bench counterpart.

**Widening the answers without closing these gates would leave the neonate rule firing
on the wrong organism** — and #14 is one of the rules whose answer I am recommending
you *keep*. This half of the work is independent of the resolution question and could
ship first if you wanted a smaller change.

### B. The wrong conditional: one confirmed, one worse

`blood-low-wbc → salmonella` (#10) is a confirmed sensitivity-for-posterior swap; the
~25% figure answers the opposite question to the one the rule asks.
`neutropenia → pseudomonas` (#4) is worse than a wrong conditional — its sources
support *empiric antipseudomonal coverage*, which is a therapy policy, and the corpus
has a therapy phase in which to say it. It was written into the identification corpus,
where it makes a claim about likelihood that its citations do not support.

### C. Belief ordering runs opposite to evidential strength

Recorded as an observation, **not** as a recalibration proposal — the beliefs are
`:illustrative` and §2 rules calibration out of scope.

| rule | evidence | belief |
|---|---|---|
| `iv-drug-use-clumps → aureus` | ~70%, best in the set | **0.55**, lowest of its half |
| `hospital-acquired-clumps → aureus` | contradicted by surveillance | **0.8**, joint-highest |
| `hospital-acquired-aerobic-gnr → pseudomonas` | ~10%, third place | **0.7** |
| `neutropenia-aerobic-gnr → pseudomonas` | third place; citations support coverage only | 0.5 |

The numbers were never tied to the evidence. That is consistent with what
`:belief-basis :illustrative` declares, and it is an argument for keeping that
declaration loud rather than for changing the numbers.

### D. Two rules become vacuous if widened honestly — decision needed

`blood-low-wbc → salmonella` (#10) and, more arguably, `burn-blood-gram-neg-rod →
pseudomonas` (#1). If the defensible answer is six or seven of seven, the rule adds
nothing the stain did not already say, and **retirement is the honest outcome, not
widening**. Retiring #10 also removes the corpus's one confirmed wrong conditional.

This is your call, and it is the one place the survey does not make a firm
recommendation for both rules: I recommend retiring #10 and widening #1.

### E. Widening will collapse conflict — expect the numbers to move a lot

Rules #2 and #8 fire on nearly the same premises and answer **disjoint** singletons.
So do #3 and #7. Under intersection, `{pseudomonas} ∩ {klebsiella} = ∅` — two rules
that are each defensible are made to contradict each other by a representation choice,
and the conflict mass K absorbs it. Widening makes them **agree** on an overlapping
set instead of fighting.

This is the same effect slice D measured for culture-3, where widening the chain-
former answer dropped K from 0.647 to 0.525 because the enterococcus and streptococcus
rules stopped contradicting each other
(`docs/slice-d-focal-width.md` §4).

Expect: K to fall sharply on culture-1, culture-1a and culture-1b; the burn-ICU
figures (`K=0.557, margin=0.740`) to move most of all, since culture-1b fires the
burn, hospital-acquired and compromised-host rules together; and the pseudomonas /
klebsiella ranking that culture-1's regression test pins to be the thing worth
watching, since it is what stayed stable across the last representation change.

### F. Blast radius

Every published number moves: the culture-* goldens in
`neomycin/test/scenarios.lisp`, the therapy recommendations that depend on them
(culture-1b is the only scenario exercising `below_threshold` against real rules), the
figures in `neomycin/clinician-samples/v011-burn-icu-release-check.md`, and the
README's worked examples. v0.12 moved two recommendations; this will move most of
them.

**This should be its own release, with goldens re-captured deliberately and a full
release check** (prompt + tool schemas + bridge + engine) before tagging.

## 6. Proposed order of work, if you approve

1. **Premise gates (§5A)** — independent of everything else, small, and fixes a rule
   whose answer is otherwise correct. Could ship alone.
2. **The nine clear widenings** — #2, #3, #4, #7, #8, #9, #11, #13, #16.
3. **The two judgement calls (§5D)** — #1 widen or retire, #10 retire (recommended)
   or widen.
4. **The two disclosure notes** — #5/#6 and #15, recording that narrowness is corpus
   coverage rather than evidence.
5. **Re-capture goldens**, run the suite, run `bin/*.sh` against a live bridge (they
   drift silently), then the full release check.

Nothing in steps 1–4 has been done. This document is the survey only.
