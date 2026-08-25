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
  ;; drug id -> plist (:class :route :dose :spectrum)
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
  (interactions '())
  ;; species id -> family id (taxonomy). A species with no sensitivity of its own
  ;; inherits its family's figure in KB-SUSCEPTIBILITY -- empiric therapy is pitched
  ;; at the family level, so the KB's structure mirrors the corpus's class->species
  ;; refinement (docs/attic/chaining-belief-spike.md §7, decision 4).
  (families (make-hash-table :test #'eq)))

(defun make-therapy-kb ()
  "Create an empty therapy knowledge base."
  (%make-therapy-kb))

;;; ------------------------------------------------------------------
;;; Builder API (used by fixtures now; by the def* authoring macros later).
;;; ------------------------------------------------------------------

;;; ------------------------------------------------------------------
;;; Spectrum breadth (exact-solver-design.md 3.4)
;;;
;;; An ORDINAL tier, DECLARED per drug -- deliberately not derived by counting the
;;; organisms a drug has KB entries for. Derived breadth is free and ranks plausibly
;;; today, but it measures curation of a schematic 17-organism KB rather than breadth
;;; in medicine: it would tie ampicillin with ceftazidime, and silently re-rank every
;;; drug the moment a species is added to the rulebase. A declared tier is honest
;;; about being a judgement, is stable under KB growth, and carries its own
;;; provenance note -- including the illustrative caveat, which applies here in full.
;;;
;;; Breadth is NOT reserve status. Vancomycin and linezolid are narrow-spectrum
;;; (gram-positive only) and simultaneously agents a steward reserves; the WHO AWaRe
;;; Access/Watch/Reserve axis is a different one, annotated per drug section in
;;; knowledge-base.lisp but not encoded here. A future objective could carry it; this
;;; tier must not be read as though it already did.
;;; ------------------------------------------------------------------

(defparameter *spectrum-tiers*
  '(:very-narrow :narrow :moderate :broad :very-broad)
  "The ordinal spectrum-breadth tiers, narrowest first. Position IS the ordering --
   see SPECTRUM-RANK. Five tiers rather than a number because the underlying
   judgement does not support finer resolution, and a scalar would invite arithmetic
   the data cannot bear.")

(defun spectrum-rank (spectrum)
  "SPECTRUM's position in *SPECTRUM-TIERS*, or NIL when unauthored. Lower is
   narrower. Ordinal only: rank differences are orderable, NOT subtractable -- the
   gap between :narrow and :moderate is not a measured quantity."
  (position spectrum *spectrum-tiers*))

(defun add-drug (kb id &key class route dose spectrum)
  "Add drug ID to KB with an optional class, route, (simulated) dose, and
   SPECTRUM breadth tier. SPECTRUM must be NIL or a member of *SPECTRUM-TIERS*;
   a typo fails at authoring time rather than silently reading back as NIL and
   quietly removing the drug from any breadth ordering."
  (unless (or (null spectrum) (member spectrum *spectrum-tiers*))
    (error "Unknown spectrum tier ~S for drug ~S: expected NIL or one of ~S."
           spectrum id *spectrum-tiers*))
  (setf (gethash id (therapy-kb-drugs kb))
        (list :class class :route route :dose dose :spectrum spectrum))
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

(defun add-family-member (kb species family)
  "Record that SPECIES belongs to FAMILY (taxonomy), so KB-SUSCEPTIBILITY can roll a
   species with no sensitivity of its own up to its family's figure. Idempotent:
   re-authoring a species overwrites its family."
  (setf (gethash species (therapy-kb-families kb)) family)
  species)

;;; ------------------------------------------------------------------
;;; Accessor API (what the solver calls; pure reads, no policy/belief logic).
;;; ------------------------------------------------------------------

(defun kb-drug-ids (kb)
  "All drug ids known to KB."
  (loop for id being the hash-keys of (therapy-kb-drugs kb) collect id))

(defun kb-antibiogram (kb organism drug)
  "The site-local antibiogram count (N-SUSCEPTIBLE . N-TESTED) for ORGANISM against
   DRUG, or NIL if no local isolates are recorded."
  (gethash (cons organism drug) (therapy-kb-antibiogram kb)))

(defun kb-family-of (kb organism)
  "The family ORGANISM belongs to (e.g. :enterobacteriaceae for :e-coli), or NIL if
   ORGANISM is not a mapped family member."
  (gethash organism (therapy-kb-families kb)))

(defun kb-susceptibility (kb drug organism)
  "The belief-valued susceptibility of ORGANISM to DRUG -- the solver's single read
   point. When a site-local antibiogram count exists for this (organism, drug), its
   empirical IDM interval (COUNTS->INTERVAL) is Dempster-combined with the curated
   figure (COMBINE-SUSCEPTIBILITY) so local isolate data refines the reference, its
   influence auto-scaling with the sample size. With no local count the curated
   figure is returned unchanged (pre-overlay behavior); NIL if neither is recorded.

   Belief-system-agnostic (decision C): the overlay builds/combines ds-belief
   intervals natively, so this returns a ds-belief under CF and DS alike, and
   SUSCEPTIBILITY->SCALAR reduces it through the coverage gate regardless of the
   active identification algebra."
  (let ((canonical (or (gethash (cons organism drug) (therapy-kb-sensitivities kb))
                       ;; Family roll-up: a species with no sensitivity of its own
                       ;; inherits its family's curated figure (empiric therapy is
                       ;; pitched at the family level). A species-specific entry, if
                       ;; present, always wins -- the OR short-circuits before this.
                       (let ((family (kb-family-of kb organism)))
                         (and family
                              (gethash (cons family drug) (therapy-kb-sensitivities kb))))))
        (counts (kb-antibiogram kb organism drug)))
    (if counts
        (combine-susceptibility canonical
                                (counts->interval (car counts) (cdr counts)))
        canonical)))

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

(defun kb-drug-spectrum (kb drug)
  "DRUG's declared spectrum-breadth tier, or NIL if unauthored. Read ONLY by the
   opt-in *OBJECTIVE* :spectrum-sparing; the default objective ignores it entirely.
   An unauthored tier is treated as broader than :very-broad by that objective, so a
   gap in the KB is never rewarded -- see REGIMEN-BREADTH."
  (getf (gethash drug (therapy-kb-drugs kb)) :spectrum))