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

;; Description: Machinery every therapy solver shares (exact-solver-design.md 4,
;; "Shared phase A"). Extracted from greedy-solver.lisp, where it lived when greedy
;; was the only solver.
;;
;; The split is along "what to treat" vs "which drugs to pick". Phase A -- the
;; belief gate, the contraindication filter, and the two scalar reductions the gates
;; read -- is solver-INDEPENDENT and lives here. Phase B, the search itself, is the
;; solver's own and stays in its file.
;;
;; That boundary is not tidiness. Two solvers disagreeing about what to treat, or
;; about what counts as covering, would make every comparison between them
;; meaningless -- and comparison is the entire point of having more than one (the
;; same reason the belief systems share a protocol rather than each rolling its own
;; arithmetic). Anything a solver could vary and still be answering the same
;; question belongs in its own file; anything it must NOT vary belongs here.

(in-package :neomycin-therapy)

;;; ============================================================
;;; Scalar reductions -- the two gates read these
;;; ============================================================

(defun scalar-of (val)
  "Reduce an IDENTIFICATION belief to a scalar for the coverage gate and weighting.
   NIL -> 0.0; a real number is itself (a CF belief); a structured belief (e.g. a
   DS interval) is reduced through the ACTIVE belief system via BELIEF:BELIEF->NUMBER
   -- correct here precisely because identification belief IS scored by that algebra.

   For SUSCEPTIBILITY, whose uncertainty is orthogonal to the diagnostic algebra,
   use SUSCEPTIBILITY->SCALAR instead -- routing a susceptibility through this
   function errors under CF (see that function's docstring)."
  (cond ((null val) 0.0)
        ((realp val) val)
        (t (belief:belief->number belief:*belief-system* val))))

(defun susceptibility->scalar (susceptibility)
  "Reduce a (possibly belief-valued) SUSCEPTIBILITY to a scalar for coverage
   thresholding and weighting.

   Unlike SCALAR-OF, this does NOT route through BELIEF:*BELIEF-SYSTEM*. A drug's
   susceptibility against an organism is a fact about the antibiogram data, not
   about the diagnostic algebra that scored identification -- so its reduction must
   be the same no matter which algebra (CF or DS) is active. Routing it through the
   active system would ERROR under CF, whose BELIEF->NUMBER has no method for a
   ds-belief struct; that break is exactly why this reduction is decoupled
   (susceptibility-belief-design.md 4, decision C).

     NIL         -> 0.0  (no susceptibility recorded -- does not cover)
     a real      -> itself (a raw scalar, or an equivalent CF-scored susceptibility)
     a ds-belief -> the interval point chosen by *susceptibility-gate*: `bel`
                    (conservative default), `pl` (optimistic), or the midpoint.
                    A scalar has no ignorance, so every gate agrees on it.

   The gate is a stewardship policy dial (see *susceptibility-gate*); the reduction
   stays decoupled from the identification algebra regardless of gate.

   Any other value is a KB authoring error and is signalled as one."
  (cond ((null susceptibility) 0.0)
        ((realp susceptibility) susceptibility)
        ((belief:ds-belief-p susceptibility)
         (ecase *susceptibility-gate*
           (:belief (belief:ds-belief-bel susceptibility))
           (:plausibility (belief:ds-belief-pl susceptibility))
           (:midpoint (belief:ds-midpoint susceptibility))))
        (t (error "Unreducible susceptibility ~S: expected NIL, a real, or a ~
                   BELIEF:DS-BELIEF interval." susceptibility))))

;;; ============================================================
;;; Coverage and candidate filtering
;;; ============================================================

(defun patient-contraindicates-p (kb drug patient)
  "True iff any of PATIENT's state tokens triggers a contraindication for DRUG.
   PATIENT is a list of state tokens (e.g. (:allergy-cephalosporin :renal-impaired))."
  (and (intersection (kb-contraindication-triggers kb drug) patient) t))

(defun drug-covers (kb drug organisms)
  "The subset of ORGANISMS that DRUG covers: reduced susceptibility >=
   *susceptibility-threshold*."
  (remove-if-not
   #'(lambda (org)
       (>= (susceptibility->scalar (kb-susceptibility kb drug org)) *susceptibility-threshold*))
   organisms))

(defun coverage-weight (kb drug covered belief-of)
  "Score for DRUG: sum over COVERED organisms of susceptibility x the organism's
   identification belief. BELIEF-OF maps an organism to its reduced belief.

   Shared because it is the tiebreak of the :lexicographic objective, which BOTH
   solvers implement -- greedy as its per-step tiebreak, the exact search as the
   comparator over whole regimens. It is a property of that objective, not of either
   search; a different objective is free to ignore it."
  (loop for org in covered
        sum (* (susceptibility->scalar (kb-susceptibility kb drug org))
               (funcall belief-of org))))

;;; ============================================================
;;; Reporting
;;; ============================================================

(defun susceptibility-item-for (kb drug organism)
  "Build a SUSCEPTIBILITY-ITEM for ORGANISM under DRUG: the (overlaid) susceptibility
   plus its antibiogram provenance -- the local sample size and whether a local count
   contributed (design doc 6). No local count => reference-only (n-tested NIL)."
  (let ((counts (kb-antibiogram kb organism drug)))
    (make-susceptibility-item
     :organism organism
     :value (kb-susceptibility kb drug organism)
     :n-tested (and counts (cdr counts))
     :source (if counts :local-antibiogram :reference))))

(defun regimen-item-for (kb drug covered)
  "Build a REGIMEN-ITEM for DRUG over the organisms it COVERED.

   Keeps the RAW susceptibility (a scalar or a ds-belief interval), not its reduced
   scalar, so the serializer can surface the interval's {bel, pl, ignorance} to the
   clinician (S2) plus its antibiogram provenance (design doc 6). Coverage and
   weighting reduce via SUSCEPTIBILITY->SCALAR; what we REPORT stays unreduced."
  (make-regimen-item
   :drug drug
   :dose (kb-dose kb drug)
   :covers covered
   :susceptibility (mapcar #'(lambda (o) (susceptibility-item-for kb drug o))
                           covered)))

;;; ============================================================
;;; Phase A -- what to treat, and with what candidates
;;; ============================================================

(defun solve-regimen-phase-a (conclusions kb patient)
  "Phase A, shared by every solver: the belief gate and the candidate filter.

   Returns (values ITEMS EXCLUDED CANDIDATES UNIVERSE):
     ITEMS      -- the (organism . belief) pairs clearing *coverage-threshold*
     EXCLUDED   -- contraindicated drugs, each with its reason
     CANDIDATES -- the drugs left, name-sorted so downstream ties resolve
                   deterministically to the earliest name
     UNIVERSE   -- just the organisms of ITEMS: the set a regimen must cover

   Deliberately returns no regimen accumulator: how a search builds one up is the
   search's own business, and threading greedy's empty list through a shared
   entry point would be shaping the interface around one caller."
  (let* ((items (remove-if-not
                 #'(lambda (pair)
                     (>= (scalar-of (cdr pair)) *coverage-threshold*))
                 conclusions))
         (universe (mapcar #'car items))
         (all-drugs (sort (kb-drug-ids kb) #'string< :key #'symbol-name))
         (excluded (loop for d in all-drugs
                         when (patient-contraindicates-p kb d patient)
                           collect (make-exclusion :drug d :reason :contraindication)))
         (candidates (remove-if #'(lambda (d)
                                    (patient-contraindicates-p kb d patient))
                                all-drugs)))
    (values items excluded candidates universe)))