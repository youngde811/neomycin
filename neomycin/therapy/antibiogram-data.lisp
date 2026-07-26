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
;; A SEPARATE, swappable site-local antibiogram (design doc 5): (organism, drug)
;; -> (n-susceptible . n-tested) isolate counts. The overlay (antibiogram.lisp)
;; turns each count into an empirical susceptibility interval whose WIDTH reflects
;; the sample size -- few isolates read as provisional (wide), many as solid
;; (narrow) -- and kb-susceptibility (a later increment) Dempster-combines it with
;; the curated figure in knowledge-base.lisp.
;;
;; These counts are INVENTED to exercise the machinery -- NOT drawn from any real
;; surveillance and NEVER a basis for prescribing. They are kept in their own file
;; precisely so a real deployment replaces THIS file (its local antibiogram)
;; without touching the curated reference KB.
;;
;; The entries deliberately target the WIDE / [PROVISIONAL] canonical figures,
;; where local data has the most to say -- e.g. antibiogram-dependent
;; anti-pseudomonal fluoroquinolone/aminoglycoside coverage, and ESBL-variable
;; klebsiella cephalosporin coverage. A tiny sample (pseudomonas/meropenem, n=4)
;; is included to show the overlay barely moving a solid canonical figure.
;; ==========================================================================

(in-package :neomycin-therapy)

;; This file owns the antibiogram LAYER only. Clear just that table on (re)load so
;; the file stays the single source of truth for local counts, without disturbing
;; the curated drugs/sensitivities that knowledge-base.lisp populates in the same
;; *therapy-kb*.
(clrhash (therapy-kb-antibiogram *therapy-kb*))

;;; Anti-pseudomonal agents whose real-world coverage is highly antibiogram-
;;; dependent (canonical figures flagged [PROVISIONAL], wide intervals).
(defantibiogram :pseudomonas :ciprofloxacin :susceptible 34 :tested 50) ; 68% over a decent sample
(defantibiogram :pseudomonas :gentamicin    :susceptible 41 :tested 48) ; 85%, better than the wide canonical
(defantibiogram :pseudomonas :ceftazidime   :susceptible 30 :tested 50) ; 60%, local resistance drags it down

;;; Klebsiella cephalosporin coverage -- a local ESBL signal pulling well below the
;;; curated figure.
(defantibiogram :klebsiella :ceftazidime :susceptible 18 :tested 40)    ; 45%, an ESBL-heavy ward

;;; Enterobacteriaceae fluoroquinolone -- a solid, moderately large local sample.
(defantibiogram :enterobacteriaceae :ciprofloxacin :susceptible 44 :tested 60) ; 73%

;;; A deliberately TINY sample: too few isolates to move the solid canonical
;;; meropenem figure much -- the overlay's influence auto-scales to near-zero.
(defantibiogram :pseudomonas :meropenem :susceptible 3 :tested 4)       ; n=4, near-vacuous
