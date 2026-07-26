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

;; Description: Package for neomycin's therapy-recommendation phase. See
;; docs/therapy-phase-design.md. The therapy phase is a deterministic,
;; auditable solver behind a pluggable protocol (modelled on the belief-system
;; protocol); the LLM narrates its result but never chooses a drug.

(in-package :cl-user)

(defpackage :neomycin-therapy
  (:use :common-lisp)
  (:nicknames :therapy)
  (:export
   ;; --- solver protocol ---
   #:solver #:solver-name
   #:*solver*
   #:solve-regimen
   #:register-solver #:use-solver #:available-solvers
   #:recommend
   ;; --- recommendation object (the auditable result; design doc 4.4) ---
   #:recommendation #:make-recommendation #:recommendation-p
   #:recommendation-regimen #:recommendation-items-to-treat #:recommendation-excluded
   #:recommendation-uncovered
   #:regimen-item #:make-regimen-item #:regimen-item-drug #:regimen-item-dose
   #:regimen-item-covers #:regimen-item-susceptibility
   #:treat-item #:make-treat-item #:treat-item-organism #:treat-item-belief
   #:exclusion #:make-exclusion #:exclusion-drug #:exclusion-reason
   ;; --- knowledge base abstraction (design doc 3.2) ---
   #:therapy-kb #:make-therapy-kb #:therapy-kb-p
   #:add-drug #:add-sensitivity #:add-contraindication #:add-antibiogram
   #:kb-drug-ids #:kb-susceptibility #:kb-contraindication-triggers #:kb-antibiogram
   #:kb-dose #:kb-drug-class #:kb-drug-route
   ;; --- def* authoring surface (design doc 3.2) + the canonical KB it fills ---
   #:*therapy-kb*
   #:defdrug #:defsensitivity #:defcontraindication #:defantibiogram
   #:with-therapy-kb #:therapy-kb #:with-greedy-solver
   ;; --- solvers ---
   #:greedy-solver
   ;; --- bridge glue (design doc step (c); HTTP handler registers itself) ---
   #:conclusions-for-solver #:recommendation->json
   ;; --- policy dials (design doc 4.2; per-session tunable, NOT clinical constants) ---
   #:*coverage-threshold* #:*susceptibility-threshold* #:*susceptibility-gate*
   ;; --- antibiogram overlay: empirical interval from isolate counts (design doc 3) ---
   #:*antibiogram-concentration* #:counts->interval #:combine-susceptibility))
