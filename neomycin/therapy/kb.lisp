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

;; Description: The therapy knowledge-base abstraction (design doc 3.2). The KB is
;; pure DATA behind an accessor API: the solver (and its tests) query it through
;; the accessors below and never see the storage. A later step adds def* authoring
;; macros that populate one of these; for now fixtures build KBs with the builder
;; API. Susceptibility is belief-valued -- stored as authored (a number, or a DS
;; interval) and reduced to a scalar by the solver through the active belief
;; system -- so the belief algebra flows from identification into therapy.
;;
;; NOTE: all pharmacology here is schematic and NOT clinical (see design doc).

(in-package :neomycin-therapy)

(defstruct (therapy-kb (:constructor %make-therapy-kb))
  ;; drug id -> plist (:class :route :dose)
  (drugs (make-hash-table :test #'eq))
  ;; (organism . drug) -> susceptibility (belief-valued: a number or a DS interval)
  (sensitivities (make-hash-table :test #'equal))
  ;; (organism . drug) -> (n-susceptible . n-tested): site-local antibiogram
  ;; counts. The overlay (antibiogram.lisp) derives an empirical susceptibility
  ;; interval from these; kb-susceptibility combines it with the curated figure.
  (antibiogram (make-hash-table :test #'equal))
  ;; drug id -> list of patient-state tokens that contraindicate it
  (contraindications (make-hash-table :test #'eq))
  ;; list of (drug . drug) forbidden pairs -- stored now, consumed by a later
  ;; interaction-aware solver increment (design doc 4.3 step 4)
  (interactions '()))

(defun make-therapy-kb ()
  "Create an empty therapy knowledge base."
  (%make-therapy-kb))

;;; ------------------------------------------------------------------
;;; Builder API (used by fixtures now; by the def* authoring macros later).
;;; ------------------------------------------------------------------

(defun add-drug (kb id &key class route dose)
  "Add drug ID to KB with an optional class, route, and (simulated) dose."
  (setf (gethash id (therapy-kb-drugs kb)) (list :class class :route route :dose dose))
  id)

(defun add-sensitivity (kb organism drug susceptibility)
  "Record the (belief-valued) SUSCEPTIBILITY of ORGANISM to DRUG."
  (setf (gethash (cons organism drug) (therapy-kb-sensitivities kb)) susceptibility))

(defun add-antibiogram (kb organism drug &key susceptible tested)
  "Record a site-local antibiogram COUNT: SUSCEPTIBLE of TESTED ORGANISM isolates
   were susceptible to DRUG. Stored as (susceptible . tested); the overlay derives
   its empirical susceptibility interval from this (antibiogram.lisp,
   counts->interval). Validates 0 <= susceptible <= tested so malformed counts fail
   at authoring time, not at read. Idempotent: re-authoring the same pair overwrites."
  (check-type susceptible (integer 0))
  (check-type tested (integer 0))
  (assert (<= susceptible tested) (susceptible tested)
          "Antibiogram authoring error for ~S/~S: susceptible (~D) cannot exceed tested (~D)."
          organism drug susceptible tested)
  (setf (gethash (cons organism drug) (therapy-kb-antibiogram kb))
        (cons susceptible tested))
  (cons organism drug))

(defun add-contraindication (kb drug &rest triggers)
  "Add patient-state TRIGGERS that contraindicate DRUG (e.g. :allergy-cephalosporin).
   Idempotent: re-adding a trigger already present is a no-op, so reloading a KB
   data file (the human-vetted update loop) does not accumulate duplicates."
  (setf (gethash drug (therapy-kb-contraindications kb))
        (union (gethash drug (therapy-kb-contraindications kb)) triggers))
  drug)

;;; ------------------------------------------------------------------
;;; Accessor API (what the solver calls; pure reads, no policy/belief logic).
;;; ------------------------------------------------------------------

(defun kb-drug-ids (kb)
  "All drug ids known to KB."
  (loop for id being the hash-keys of (therapy-kb-drugs kb) collect id))

(defun kb-susceptibility (kb drug organism)
  "The belief-valued susceptibility of ORGANISM to DRUG, or NIL if unknown."
  (gethash (cons organism drug) (therapy-kb-sensitivities kb)))

(defun kb-antibiogram (kb organism drug)
  "The site-local antibiogram count (N-SUSCEPTIBLE . N-TESTED) for ORGANISM against
   DRUG, or NIL if no local isolates are recorded."
  (gethash (cons organism drug) (therapy-kb-antibiogram kb)))

(defun kb-contraindication-triggers (kb drug)
  "Patient-state tokens that contraindicate DRUG."
  (gethash drug (therapy-kb-contraindications kb)))

(defun kb-dose (kb drug)
  "The (simulated) dose for DRUG."
  (getf (gethash drug (therapy-kb-drugs kb)) :dose))

(defun kb-drug-class (kb drug)
  "The class of DRUG (e.g. cephalosporin-3)."
  (getf (gethash drug (therapy-kb-drugs kb)) :class))

(defun kb-drug-route (kb drug)
  "The route of DRUG (e.g. iv)."
  (getf (gethash drug (therapy-kb-drugs kb)) :route))