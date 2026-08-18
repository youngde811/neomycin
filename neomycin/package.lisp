;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: neomycin's own package -- the consensus layer that reads a
;; differential out of working memory. Distinct from LISA-USER, which holds the
;; rulebase's vocabulary, and from NEOMYCIN-THERAPY, which holds the therapy phase.

(defpackage :neomycin
  (:use :common-lisp)
  (:documentation
   "Reading a consensus out of working memory. Rules assert ANSWERS -- sets of
    organisms their evidence narrows the question to -- and this package combines
    them, applying rule specificity, and reports the differential.")
  (:export #:candidates-facts
           #:organisms-with-answers
           #:contributing-rules
           #:surviving-rules
           #:answer-of
           #:answers-for
           #:consensus
           #:differential
           #:rules-behind
           #:differential->json
           #:conclusions-payload))
