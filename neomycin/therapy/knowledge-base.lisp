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
;; susceptible" figures on [0,1], NOT MIC data and NOT drawn from any specific
;; antibiogram; doses are simulated typical adult regimens. Under the human-vetted
;; update loop (design doc principle #3), a real deployment would replace this
;; file with sourced, per-entry-cited, vetted data landing as a tracked diff.
;;
;; Vocabulary is KEYWORDS end to end. Organism keywords match the engine's
;; keyword organism-identity values exactly (same global objects, no conversion),
;; so conclusions flow straight from the Rete facts into the KB. Organisms
;; (matches organism-identity in neomycin/rulebase.lisp):
;;   :pseudomonas :enterobacteriaceae :klebsiella :salmonella :bacteroides
;;   :streptococcus :streptococcus-pneumoniae :staphylococcus
;;   :staphylococcus-aureus :enterococcus
;; ==========================================================================

(in-package :neomycin-therapy)

;; Load this file = rebuild the canonical KB from scratch, so the file is the
;; single source of truth and a reload never leaves stale entries behind.
(setf *therapy-kb* (make-therapy-kb))

;;; --------------------------------------------------------------------------
;;; Beta-lactams: anti-pseudomonal cephalosporin (WHO AWaRe: Watch)
;;; --------------------------------------------------------------------------

(defdrug :ceftazidime :class :cephalosporin-3 :route :iv :dose "2 g IV q8h")
(defsensitivity :pseudomonas        :ceftazidime 0.85)
(defsensitivity :enterobacteriaceae :ceftazidime 0.80)
(defsensitivity :klebsiella         :ceftazidime 0.80)
(defsensitivity :salmonella         :ceftazidime 0.60)
(defcontraindication :ceftazidime :when (:allergy-cephalosporin))

;;; Non-pseudomonal 3rd-gen cephalosporin (WHO AWaRe: Watch)
(defdrug :ceftriaxone :class :cephalosporin-3 :route :iv :dose "2 g IV q24h")
(defsensitivity :enterobacteriaceae       :ceftriaxone 0.85)
(defsensitivity :klebsiella               :ceftriaxone 0.85)
(defsensitivity :salmonella               :ceftriaxone 0.90)
(defsensitivity :streptococcus            :ceftriaxone 0.85)
(defsensitivity :streptococcus-pneumoniae :ceftriaxone 0.90)
(defsensitivity :staphylococcus           :ceftriaxone 0.55) ; MSSA only, borderline
(defcontraindication :ceftriaxone :when (:allergy-cephalosporin))

;;; Carbapenem -- very broad, incl. anaerobes; spares MRSA and enterococcus
;;; (WHO AWaRe: Watch)
(defdrug :meropenem :class :carbapenem :route :iv :dose "1 g IV q8h")
(defsensitivity :pseudomonas              :meropenem 0.85)
(defsensitivity :enterobacteriaceae       :meropenem 0.95)
(defsensitivity :klebsiella               :meropenem 0.95)
(defsensitivity :salmonella               :meropenem 0.90)
(defsensitivity :bacteroides              :meropenem 0.90)
(defsensitivity :streptococcus            :meropenem 0.85)
(defsensitivity :streptococcus-pneumoniae :meropenem 0.90)
(defsensitivity :staphylococcus           :meropenem 0.60) ; MSSA
(defcontraindication :meropenem :when (:allergy-carbapenem))

;;; Anti-pseudomonal penicillin + beta-lactamase inhibitor (WHO AWaRe: Watch)
(defdrug :piperacillin-tazobactam :class :penicillin-bli :route :iv :dose "4.5 g IV q6h")
(defsensitivity :pseudomonas        :piperacillin-tazobactam 0.80)
(defsensitivity :enterobacteriaceae :piperacillin-tazobactam 0.85)
(defsensitivity :klebsiella         :piperacillin-tazobactam 0.85)
(defsensitivity :bacteroides        :piperacillin-tazobactam 0.90)
(defsensitivity :streptococcus      :piperacillin-tazobactam 0.80)
(defsensitivity :enterococcus       :piperacillin-tazobactam 0.70)
(defsensitivity :staphylococcus     :piperacillin-tazobactam 0.60) ; MSSA
(defcontraindication :piperacillin-tazobactam :when (:allergy-penicillin))

;;; Anti-staphylococcal penicillin -- MSSA (WHO AWaRe: Access)
(defdrug :nafcillin :class :antistaph-penicillin :route :iv :dose "2 g IV q4h")
(defsensitivity :staphylococcus        :nafcillin 0.85) ; MSSA, not MRSA
(defsensitivity :staphylococcus-aureus :nafcillin 0.85)
(defsensitivity :streptococcus         :nafcillin 0.70)
(defcontraindication :nafcillin :when (:allergy-penicillin))

;;; Aminopenicillin (WHO AWaRe: Access)
(defdrug :ampicillin :class :aminopenicillin :route :iv :dose "2 g IV q6h")
(defsensitivity :enterococcus             :ampicillin 0.85)
(defsensitivity :streptococcus            :ampicillin 0.80)
(defsensitivity :streptococcus-pneumoniae :ampicillin 0.60)
(defsensitivity :salmonella               :ampicillin 0.60)
;; enterobacteriaceae ~0.4: below *susceptibility-threshold*, so intentionally
;; NOT authored -- widespread aminopenicillin resistance means it does not cover.
(defcontraindication :ampicillin :when (:allergy-penicillin))

;;; --------------------------------------------------------------------------
;;; Fluoroquinolone (WHO AWaRe: Watch)
;;; --------------------------------------------------------------------------

(defdrug :ciprofloxacin :class :fluoroquinolone :route :iv :dose "400 mg IV q12h")
(defsensitivity :pseudomonas        :ciprofloxacin 0.70)
(defsensitivity :enterobacteriaceae :ciprofloxacin 0.80)
(defsensitivity :klebsiella         :ciprofloxacin 0.80)
(defsensitivity :salmonella         :ciprofloxacin 0.85)
(defcontraindication :ciprofloxacin :when (:pregnancy :age-pediatric))

;;; --------------------------------------------------------------------------
;;; Aminoglycoside (WHO AWaRe: Access)
;;; --------------------------------------------------------------------------

(defdrug :gentamicin :class :aminoglycoside :route :iv :dose "5-7 mg/kg IV q24h")
(defsensitivity :pseudomonas        :gentamicin 0.75)
(defsensitivity :enterobacteriaceae :gentamicin 0.80)
(defsensitivity :klebsiella         :gentamicin 0.80)
(defcontraindication :gentamicin :when (:renal-impaired :pregnancy))

;;; --------------------------------------------------------------------------
;;; Gram-positive agents
;;; --------------------------------------------------------------------------

;;; Glycopeptide -- gram-positives incl. MRSA (WHO AWaRe: Watch)
(defdrug :vancomycin :class :glycopeptide :route :iv :dose "15-20 mg/kg IV q8-12h")
(defsensitivity :staphylococcus           :vancomycin 0.95)
(defsensitivity :staphylococcus-aureus    :vancomycin 0.95) ; incl. MRSA
(defsensitivity :streptococcus            :vancomycin 0.90)
(defsensitivity :streptococcus-pneumoniae :vancomycin 0.90)
(defsensitivity :enterococcus             :vancomycin 0.75) ; VRE lowers this

;;; Oxazolidinone -- resistant gram-positives incl. VRE/MRSA (WHO AWaRe: Reserve)
(defdrug :linezolid :class :oxazolidinone :route :iv :dose "600 mg IV/PO q12h")
(defsensitivity :staphylococcus        :linezolid 0.90)
(defsensitivity :staphylococcus-aureus :linezolid 0.90)
(defsensitivity :enterococcus          :linezolid 0.85)
(defsensitivity :streptococcus         :linezolid 0.85)
(defcontraindication :linezolid :when (:maoi-therapy))

;;; --------------------------------------------------------------------------
;;; Anaerobe coverage (WHO AWaRe: Access)
;;; --------------------------------------------------------------------------

(defdrug :metronidazole :class :nitroimidazole :route :iv :dose "500 mg IV q8h")
(defsensitivity :bacteroides :metronidazole 0.95)
(defcontraindication :metronidazole :when (:pregnancy-first-trimester :alcohol-use))