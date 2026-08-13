;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.

;; MIT License

;; Copyright (c) 2000 David Young

;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to deal
;; in the Software without restriction, including without limitation the rights
;; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;; copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:

;; The above copyright notice and this permission notice shall be included in all
;; copies or substantial portions of the Software.

;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.

;; ==========================================================================
;; !! NOT FOR CLINICAL USE -- RESEARCH ARTIFACT ONLY !!
;;
;; Every drug, susceptibility, dose, and contraindication below is ILLUSTRATIVE
;; and SCHEMATIC, chosen to exercise the therapy solver against the organism
;; vocabulary neomycin's MYCIN rulebase concludes. It is NOT clinically
;; authoritative and must NEVER inform a treatment decision for any human or
;; animal (design doc, "NOT FOR CLINICAL USE").
;;
;; Values are best-guess, at category granularity, informed by public reference
;; frameworks -- the WHO AWaRe antibiotic classification (Access / Watch /
;; Reserve) for stewardship framing, and standard spectrum-of-activity summaries
;; (e.g. the Sanford Guide, the Johns Hopkins ABX Guide, general medical
;; microbiology). Susceptibilities are illustrative "typical proportion
;; susceptible" figures, NOT MIC data and NOT drawn from any specific antibiogram;
;; doses are simulated typical adult regimens. Under the human-vetted update loop
;; (design doc principle #3), a real deployment would replace this file with
;; sourced, per-entry-cited, vetted data landing as a tracked diff.
;;
;; -------------------------------------------------------------------------
;; BELIEF-VALUED susceptibilities (susceptibility-belief-design.md, S1)
;; -------------------------------------------------------------------------
;; Each susceptibility is a Dempster-Shafer interval BELIEF:MAKE-DS-BELIEF(bel pl),
;; NOT a bare scalar. This makes DATA SPARSITY VISIBLE on the treatment side, the
;; same way DS intervals make diagnostic ignorance visible on the identification
;; side:
;;
;;   bel (lower bound) -- what we are CONFIDENT of. The conservative coverage gate
;;                        acts on this (susceptibility->scalar; decision C).
;;   pl  (upper bound) -- the optimistic ceiling (1 - evidence of resistance).
;;   pl - bel          -- IGNORANCE: how thin / variable the illustrative
;;                        antibiogram is. Narrow = solid data; wide = provisional.
;;
;; Width tiers used below (illustrative, not measured):
;;   solid    (ignorance ~0.05-0.12) -- near-universal, textbook-stable activity.
;;   typical  (ignorance ~0.15-0.22) -- ordinary spectrum data.
;;   variable (ignorance ~0.25+, bel MAY fall below the 0.5 gate) -- high local
;;            resistance variability or sparse data; flagged [PROVISIONAL] inline.
;;
;; A [PROVISIONAL] entry whose bel < *susceptibility-threshold* does NOT count as
;; covering under the conservative (bel) gate -- an honest "we can't be sure
;; without local sensitivities." Every organism nonetheless retains at least one
;; SOLID covering agent, so the recommendation degrades gracefully. The S3
;; coverage-gate dial (:belief / :plausibility / :midpoint) is what will let an
;; optimistic policy count these provisional agents; the divergence is legible
;; precisely because the interval is explicit.
;;
;; Because susceptibility reduction is decoupled from the identification algebra
;; (decision C), these intervals behave identically under CF and DS.
;;
;; -------------------------------------------------------------------------
;; SPECTRUM BREADTH (exact-solver-design.md 3.4) -- authored, NOT YET CONSUMED
;; -------------------------------------------------------------------------
;; Each defdrug carries a :spectrum tier from *SPECTRUM-TIERS*, narrowest first:
;;   :very-narrow  :narrow  :moderate  :broad  :very-broad
;;
;; DECLARED, not derived by counting KB entries. A derived count would measure how
;; thoroughly THIS 17-organism schematic KB was curated, not breadth in medicine --
;; and would silently re-rank every drug whenever a species is added to the rulebase.
;;
;; ORDINAL ONLY. The tiers are orderable, not subtractable: the distance from
;; :narrow to :moderate is not a measured quantity, and no arithmetic should treat
;; it as one. Like every value in this file the assignment is ILLUSTRATIVE -- a
;; category-granularity judgement informed by standard spectrum-of-activity
;; summaries, not a sourced measurement.
;;
;; The assignments and why:
;;   :very-narrow  metronidazole -- obligate anaerobes essentially alone.
;;   :narrow       nafcillin     -- MSSA plus some streptococci; no gram-negative.
;;                 vancomycin    -- gram-positives only, including MRSA.
;;                 linezolid     -- gram-positives only, including VRE/MRSA.
;;   :moderate     ampicillin    -- streptococci/enterococci plus limited gram-negative.
;;                 gentamicin    -- aerobic gram-negatives.
;;                 ciprofloxacin -- gram-negatives incl. pseudomonas, limited gram-pos.
;;   :broad        ceftriaxone   -- gram-negative + gram-positive; no pseudomonas,
;;                                  no anaerobes.
;;                 ceftazidime   -- broad gram-negative incl. pseudomonas; poor gram-pos.
;;   :very-broad   piperacillin-tazobactam -- gram-pos, gram-neg, pseudomonas, anaerobes.
;;                 meropenem     -- near-universal here, excepting MRSA.
;;
;; BREADTH IS NOT RESERVE STATUS, and the two must not be conflated. Vancomycin and
;; linezolid are :narrow by spectrum while being exactly the agents a steward
;; reserves -- linezolid is WHO AWaRe *Reserve*. The AWaRe axis is annotated per
;; section below but is NOT encoded in this tier, so a "narrowest-first" objective
;; reading only :spectrum would happily reach for a Reserve agent. That is a real
;; limitation of the axis, recorded here rather than discovered later.
;;
;; CONSUMED BY *OBJECTIVE* :SPECTRUM-SPARING, and by nothing else. That objective is
;; OPT-IN: the default (:lexicographic) ignores these tiers entirely.
;;
;; What they do when turned on is tabled in exact-solver-design.md 3.6, and two rows
;; are worth knowing before authoring against them. The tiers prefer GENTAMICIN
;; monotherapy for gram-negative bacteraemia -- narrower, and not therefore better.
;; And because breadth is blind to reserve status, they move enterococcus from
;; ampicillin (WHO AWaRe Access) to linezolid (AWaRe RESERVE): narrowing spectrum
;; can escalate reserve status, and this axis cannot see it happening. Both were
;; shipped as measured rather than patched, so the dial's failure modes stay
;; visible; the narration is required to state the trade.
;;
;; Vocabulary is KEYWORDS end to end. Organism keywords match the engine's
;; keyword organism-identity values exactly (same global objects, no conversion),
;; so conclusions flow straight from the Rete facts into the KB. Leaf-species
;; organism-identities (matches organism-identity in neomycin/rules/):
;;   :pseudomonas :klebsiella :salmonella :e-coli :enterobacter :serratia
;;   :proteus :bacteroides
;;   :staphylococcus-aureus :staphylococcus-epidermidis :staphylococcus-saprophyticus
;;   :streptococcus-pneumoniae :streptococcus-pyogenes :streptococcus-agalactiae
;;   :streptococcus-viridans :enterococcus-faecalis :enterococcus-faecium
;; FOUR keywords are NOT leaf identities -- they are taxonomic CLASSES, concluded as
;; organism-CLASS facts and carried here as therapy backstop items only when no member
;; species clears the coverage gate (conclusions-for-solver):
;;   :enterobacteriaceae (family, since C2)
;;   :staphylococcus :streptococcus :enterococcus (genera, since the gram-positive
;;     increment -- each was a leaf identity before it, the same
;;     genus-masquerading-as-a-species defect C2 fixed for enterobacteriaceae)
;; Their KB sensitivities are the empiric class-level figures the roll-up inherits,
;; and that is the right home for them: empiric therapy is pitched at the genus.
;; ==========================================================================

(in-package :neomycin-therapy)

;; Load this file = rebuild the canonical KB from scratch, so the file is the
;; single source of truth and a reload never leaves stale entries behind.
(setf *therapy-kb* (make-therapy-kb))

;;; --------------------------------------------------------------------------
;;; Taxonomy: the enterobacteriaceae family (for therapy roll-up).
;;; --------------------------------------------------------------------------
;;; A family member with no sensitivity of its own inherits its family's curated
;;; figure (empiric therapy is pitched at the family level; chaining decision 4,
;;; docs/chaining-belief-spike.md §7). Membership also drives item-selection: when a
;;; member SPECIES is identified, the family is not separately treated (the species
;;; covers it); the family is treated only as a backstop when NO member species
;;; clears the gate. :e-coli / :enterobacter / :serratia / :proteus carry no
;;; species-specific entries and fall back entirely to :enterobacteriaceae. :klebsiella
;;; carries its own entries for every family drug (roll-up never triggers). :salmonella
;;; carries its own entries too, plus an explicit gentamicin override above so it does
;;; NOT inherit the family's aminoglycoside figure. Taxonomy is citable to any clinical
;;; microbiology reference.
(deffamily :enterobacteriaceae :e-coli :enterobacter :serratia :proteus :klebsiella :salmonella)

;;; --------------------------------------------------------------------------
;;; Taxonomy: the gram-positive genera.
;;; --------------------------------------------------------------------------
;;; Same mechanism, applied to the three genera the gram-positive increment promoted
;;; from leaf identities to organism-classes. The existing :staphylococcus /
;;; :streptococcus / :enterococcus sensitivity entries below were always empiric
;;; GENUS-level figures -- they simply used to be reachable as identities. Declaring
;;; membership keeps them reachable, now as the roll-up target for species that carry
;;; no entries of their own, and makes the item-selection rule work: identify
;;; S. aureus and the genus is not separately treated; pin down nothing and the genus
;;; is treated empirically as a backstop.
;;;
;;; :staphylococcus-aureus already carries its own entries for the anti-staphylococcal
;;; drugs (nafcillin, vancomycin, linezolid), so roll-up never triggers for it. The
;;; other six species have no species-specific entries and inherit wholesale.
(deffamily :staphylococcus :staphylococcus-aureus :staphylococcus-epidermidis
                           :staphylococcus-saprophyticus)
(deffamily :streptococcus :streptococcus-pneumoniae :streptococcus-pyogenes
                          :streptococcus-agalactiae :streptococcus-viridans)

;;; E. faecium inherits the :enterococcus figures, which UNDERSTATES its resistance --
;;; the very thing that makes the species split worth modeling. Ampicillin holds for
;;; most E. faecalis but commonly fails against E. faecium, and VRE is concentrated in
;;; E. faecium. The correct fix is species-level entries, deliberately deferred so this
;;; increment stays corpus-only (gram-positive-cluster-design.md §8.3); recorded here
;;; rather than left as a silent inheritance so the gap is visible at the point of use.
(deffamily :enterococcus :enterococcus-faecalis :enterococcus-faecium)

;;; --------------------------------------------------------------------------
;;; Beta-lactams: anti-pseudomonal cephalosporin (WHO AWaRe: Watch)
;;; --------------------------------------------------------------------------

(defdrug :ceftazidime :class :cephalosporin-3 :route :iv :dose "2 g IV q8h" :spectrum :broad)
(defsensitivity :pseudomonas        :ceftazidime (belief:make-ds-belief 0.70 0.90))
(defsensitivity :enterobacteriaceae :ceftazidime (belief:make-ds-belief 0.66 0.88))
(defsensitivity :klebsiella         :ceftazidime (belief:make-ds-belief 0.64 0.88)) ; ESBL variability -> wider
(defsensitivity :salmonella         :ceftazidime (belief:make-ds-belief 0.46 0.74)) ; [PROVISIONAL] not first-line for salmonella
(defcontraindication :ceftazidime :when (:allergy-cephalosporin))

;;; Non-pseudomonal 3rd-gen cephalosporin (WHO AWaRe: Watch)
(defdrug :ceftriaxone :class :cephalosporin-3 :route :iv :dose "2 g IV q24h" :spectrum :broad)
(defsensitivity :enterobacteriaceae       :ceftriaxone (belief:make-ds-belief 0.72 0.92))
(defsensitivity :klebsiella               :ceftriaxone (belief:make-ds-belief 0.68 0.92)) ; ESBL variability
(defsensitivity :salmonella               :ceftriaxone (belief:make-ds-belief 0.80 0.97)) ; drug of choice -> solid
(defsensitivity :streptococcus            :ceftriaxone (belief:make-ds-belief 0.74 0.93))
(defsensitivity :streptococcus-pneumoniae :ceftriaxone (belief:make-ds-belief 0.80 0.96))
(defsensitivity :staphylococcus           :ceftriaxone (belief:make-ds-belief 0.42 0.68)) ; [PROVISIONAL] MSSA only, borderline
(defcontraindication :ceftriaxone :when (:allergy-cephalosporin))

;;; Carbapenem -- very broad, incl. anaerobes; spares MRSA and enterococcus
;;; (WHO AWaRe: Watch). Kept SOLID across its gram-negative spectrum: the
;;; canonical demo's coverage guarantees lean on it.
(defdrug :meropenem :class :carbapenem :route :iv :dose "1 g IV q8h" :spectrum :very-broad)
(defsensitivity :pseudomonas              :meropenem (belief:make-ds-belief 0.72 0.92))
(defsensitivity :enterobacteriaceae       :meropenem (belief:make-ds-belief 0.90 0.99)) ; solid, narrow
(defsensitivity :klebsiella               :meropenem (belief:make-ds-belief 0.88 0.99)) ; carbapenem-R still low
(defsensitivity :salmonella               :meropenem (belief:make-ds-belief 0.82 0.97))
(defsensitivity :bacteroides              :meropenem (belief:make-ds-belief 0.80 0.96))
(defsensitivity :streptococcus            :meropenem (belief:make-ds-belief 0.74 0.93))
(defsensitivity :streptococcus-pneumoniae :meropenem (belief:make-ds-belief 0.82 0.96))
(defsensitivity :staphylococcus           :meropenem (belief:make-ds-belief 0.46 0.72)) ; [PROVISIONAL] MSSA only
(defcontraindication :meropenem :when (:allergy-carbapenem))

;;; Anti-pseudomonal penicillin + beta-lactamase inhibitor (WHO AWaRe: Watch)
(defdrug :piperacillin-tazobactam :class :penicillin-bli :route :iv :dose "4.5 g IV q6h" :spectrum :very-broad)
(defsensitivity :pseudomonas        :piperacillin-tazobactam (belief:make-ds-belief 0.64 0.90))
(defsensitivity :enterobacteriaceae :piperacillin-tazobactam (belief:make-ds-belief 0.70 0.92))
(defsensitivity :klebsiella         :piperacillin-tazobactam (belief:make-ds-belief 0.68 0.92))
(defsensitivity :bacteroides        :piperacillin-tazobactam (belief:make-ds-belief 0.80 0.96))
(defsensitivity :streptococcus      :piperacillin-tazobactam (belief:make-ds-belief 0.68 0.90))
(defsensitivity :enterococcus       :piperacillin-tazobactam (belief:make-ds-belief 0.48 0.85)) ; [PROVISIONAL] E. faecium variable
(defsensitivity :staphylococcus     :piperacillin-tazobactam (belief:make-ds-belief 0.45 0.72)) ; [PROVISIONAL] MSSA only
(defcontraindication :piperacillin-tazobactam :when (:allergy-penicillin))

;;; Anti-staphylococcal penicillin -- MSSA (WHO AWaRe: Access)
(defdrug :nafcillin :class :antistaph-penicillin :route :iv :dose "2 g IV q4h" :spectrum :narrow)
(defsensitivity :staphylococcus        :nafcillin (belief:make-ds-belief 0.74 0.92)) ; MSSA, not MRSA
(defsensitivity :staphylococcus-aureus :nafcillin (belief:make-ds-belief 0.72 0.92))
(defsensitivity :streptococcus         :nafcillin (belief:make-ds-belief 0.56 0.82))
(defcontraindication :nafcillin :when (:allergy-penicillin))

;;; Aminopenicillin (WHO AWaRe: Access)
(defdrug :ampicillin :class :aminopenicillin :route :iv :dose "2 g IV q6h" :spectrum :moderate)
(defsensitivity :enterococcus             :ampicillin (belief:make-ds-belief 0.72 0.93)) ; solid for susceptible enterococcus
(defsensitivity :streptococcus            :ampicillin (belief:make-ds-belief 0.66 0.90))
(defsensitivity :streptococcus-pneumoniae :ampicillin (belief:make-ds-belief 0.45 0.74)) ; [PROVISIONAL] penicillin-R pneumo variable
(defsensitivity :salmonella               :ampicillin (belief:make-ds-belief 0.45 0.72)) ; [PROVISIONAL] resistance widespread
;; enterobacteriaceae ~0.4: below *susceptibility-threshold*, so intentionally
;; NOT authored -- widespread aminopenicillin resistance means it does not cover.
(defcontraindication :ampicillin :when (:allergy-penicillin))

;;; --------------------------------------------------------------------------
;;; Fluoroquinolone (WHO AWaRe: Watch)
;;; --------------------------------------------------------------------------

(defdrug :ciprofloxacin :class :fluoroquinolone :route :iv :dose "400 mg IV q12h" :spectrum :moderate)
(defsensitivity :pseudomonas        :ciprofloxacin (belief:make-ds-belief 0.46 0.85)) ; [PROVISIONAL] anti-pseudomonal FQ coverage is antibiogram-dependent
(defsensitivity :enterobacteriaceae :ciprofloxacin (belief:make-ds-belief 0.62 0.90))
(defsensitivity :klebsiella         :ciprofloxacin (belief:make-ds-belief 0.62 0.90))
(defsensitivity :salmonella         :ciprofloxacin (belief:make-ds-belief 0.68 0.94)) ; FQ resistance in salmonella rising
(defcontraindication :ciprofloxacin :when (:pregnancy :age-pediatric))

;;; --------------------------------------------------------------------------
;;; Aminoglycoside (WHO AWaRe: Access)
;;; --------------------------------------------------------------------------

(defdrug :gentamicin :class :aminoglycoside :route :iv :dose "5-7 mg/kg IV q24h" :spectrum :moderate)
(defsensitivity :pseudomonas        :gentamicin (belief:make-ds-belief 0.48 0.88)) ; [PROVISIONAL] highly antibiogram-dependent
(defsensitivity :enterobacteriaceae :gentamicin (belief:make-ds-belief 0.64 0.90))
(defsensitivity :klebsiella         :gentamicin (belief:make-ds-belief 0.64 0.90))
;; Explicit salmonella override so the family roll-up does NOT lend salmonella the
;; family's gentamicin figure: aminoglycosides test susceptible in vitro but are
;; clinically unreliable against intracellular salmonella. [PROVISIONAL] and below
;; the coverage gate, so gentamicin does not count as covering salmonella.
(defsensitivity :salmonella         :gentamicin (belief:make-ds-belief 0.30 0.55)) ; [PROVISIONAL] poor intracellular activity
(defcontraindication :gentamicin :when (:renal-impaired :pregnancy))

;;; --------------------------------------------------------------------------
;;; Gram-positive agents
;;; --------------------------------------------------------------------------

;;; Glycopeptide -- gram-positives incl. MRSA (WHO AWaRe: Watch). Kept SOLID:
;;; the demo's gram-positive coverage guarantees lean on it.
(defdrug :vancomycin :class :glycopeptide :route :iv :dose "15-20 mg/kg IV q8-12h" :spectrum :narrow)
(defsensitivity :staphylococcus           :vancomycin (belief:make-ds-belief 0.88 0.99))
(defsensitivity :staphylococcus-aureus    :vancomycin (belief:make-ds-belief 0.88 0.99)) ; incl. MRSA
(defsensitivity :streptococcus            :vancomycin (belief:make-ds-belief 0.82 0.97))
(defsensitivity :streptococcus-pneumoniae :vancomycin (belief:make-ds-belief 0.82 0.97))
(defsensitivity :enterococcus             :vancomycin (belief:make-ds-belief 0.48 0.88)) ; [PROVISIONAL] VRE lowers the floor

;;; Oxazolidinone -- resistant gram-positives incl. VRE/MRSA (WHO AWaRe: Reserve)
(defdrug :linezolid :class :oxazolidinone :route :iv :dose "600 mg IV/PO q12h" :spectrum :narrow)
(defsensitivity :staphylococcus        :linezolid (belief:make-ds-belief 0.80 0.96))
(defsensitivity :staphylococcus-aureus :linezolid (belief:make-ds-belief 0.80 0.96))
(defsensitivity :enterococcus          :linezolid (belief:make-ds-belief 0.72 0.93)) ; holds up incl. VRE
(defsensitivity :streptococcus         :linezolid (belief:make-ds-belief 0.74 0.93))
(defcontraindication :linezolid :when (:maoi-therapy))

;;; --------------------------------------------------------------------------
;;; Anaerobe coverage (WHO AWaRe: Access)
;;; --------------------------------------------------------------------------

(defdrug :metronidazole :class :nitroimidazole :route :iv :dose "500 mg IV q8h" :spectrum :very-narrow)
(defsensitivity :bacteroides :metronidazole (belief:make-ds-belief 0.88 0.99)) ; solid, narrow
(defcontraindication :metronidazole :when (:pregnancy-first-trimester :alcohol-use))