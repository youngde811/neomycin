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

;; Description: The greedy weighted set-cover therapy solver (design doc 4.3).
;;
;; Phase A (belief gate): an organism is an "item to treat" iff its reduced
;; identification belief >= *coverage-threshold*.
;; Phase B (set cover): drop contraindicated drugs; then repeatedly pick the drug
;; covering the most still-uncovered items, ties broken by summed susceptibility x
;; belief, then by drug name -- a total order, so the result is DETERMINISTIC.
;;
;; Objective: fewest drugs (minimality = stewardship). Interactions are NOT handled
;; in this increment (design doc 4.3 step 4 is a later, separately-tested addition).
;; If some item cannot be covered by any candidate drug, it is reported in the
;; recommendation's UNCOVERED list rather than silently dropped.

(in-package :neomycin-therapy)

(defun scalar-of (val)
  "Reduce a belief-valued quantity to a scalar for thresholding and weighting.
   NIL -> 0.0; a real number is itself (a CF belief, or a raw susceptibility);
   anything else is reduced through the active belief system (e.g. a DS interval
   -> its lower bound, via BELIEF:BELIEF->NUMBER)."
  (cond ((null val) 0.0)
        ((realp val) val)
        (t (belief:belief->number belief:*belief-system* val))))

(defun patient-contraindicates-p (kb drug patient)
  "True iff any of PATIENT's state tokens triggers a contraindication for DRUG.
   PATIENT is a list of state tokens (e.g. (:allergy-cephalosporin :renal-impaired))."
  (and (intersection (kb-contraindication-triggers kb drug) patient) t))

(defun drug-covers (kb drug organisms)
  "The subset of ORGANISMS that DRUG covers: reduced susceptibility >=
   *susceptibility-threshold*."
  (remove-if-not
   #'(lambda (org)
       (>= (scalar-of (kb-susceptibility kb drug org)) *susceptibility-threshold*))
   organisms))

(defun coverage-weight (kb drug covered belief-of)
  "Tie-break score for DRUG: sum over COVERED organisms of susceptibility x the
   organism's identification belief. BELIEF-OF maps an organism to its reduced belief."
  (loop for org in covered
        sum (* (scalar-of (kb-susceptibility kb drug org))
               (funcall belief-of org))))

(defclass greedy-solver (solver) ()
  (:documentation "Greedy weighted set-cover therapy solver (design doc 4.3).
   Deterministic: fewest drugs, ties broken by summed susceptibility x belief then
   drug name. No interaction handling in this increment."))

(defun solve-regimen-phase-a (conclusions kb patient)
  "Solve regimen Phase A: items to treat (belief gate) + candidate drug filter.
   Returns (values items excluded candidates uncovered regimen) for Phase B --
   UNCOVERED starts as the full universe, REGIMEN starts empty."
  (let* ((items (remove-if-not
                 #'(lambda (pair)
                     (>= (scalar-of (cdr pair)) *coverage-threshold*))
                 conclusions))
         (universe (mapcar #'car items))
         ;; Candidate filter -- drop contraindicated drugs, recording exclusions.
         ;; Name-sort so ties later resolve deterministically to the first name.
         (all-drugs (sort (kb-drug-ids kb) #'string< :key #'symbol-name))
         (excluded (loop for d in all-drugs
                         when (patient-contraindicates-p kb d patient)
                           collect (make-exclusion :drug d :reason :contraindication)))
         (candidates (remove-if #'(lambda (d)
                                    (patient-contraindicates-p kb d patient))
                                all-drugs)))
    (values items excluded candidates universe '())))

(defun solve-regimen-phase-b (kb conclusions items excluded candidates uncovered regimen)
  "Solve Regimen Phase B: greedy weighted set cover. BELIEF-OF is rebuilt here as
   a local closure over CONCLUSIONS -- it is the only consumer."
  (flet ((belief-of (org)
           (scalar-of (cdr (assoc org conclusions)))))
    (loop
      (when (null uncovered)
        (return))
      (let ((best nil) (best-cov '()) (best-n -1) (best-w -1))
        (dolist (d candidates)
          (let* ((cov (drug-covers kb d uncovered))
                 (n (length cov)))
            (when (plusp n)
              (let ((w (coverage-weight kb d cov #'belief-of)))
                ;; Total order: more covered, then higher weight. Candidates are
                ;; already name-sorted and we only replace on a STRICT win, so a
                ;; full (n,w) tie keeps the earliest name -> deterministic.
                (when (or (> n best-n)
                          (and (= n best-n) (> w best-w)))
                  (setf best d best-cov cov best-n n best-w w))))))
        (when (null best)
          (return)) ; nothing covers any remaining item
        (push (make-regimen-item
               :drug best
               :dose (kb-dose kb best)
               :covers best-cov
               :susceptibility (mapcar #'(lambda (o)
                                           (cons o (scalar-of (kb-susceptibility kb best o))))
                                       best-cov))
              regimen)
        (setf uncovered (set-difference uncovered best-cov))
        (setf candidates (remove best candidates))))
    (make-recommendation
     :regimen (nreverse regimen)
     :items-to-treat (mapcar #'(lambda (p)
                                 (make-treat-item :organism (car p) :belief (cdr p)))
                             items)
     :excluded excluded
     ;; name-sort the leftovers for a deterministic report
     :uncovered (sort (copy-list uncovered) #'string< :key #'symbol-name))))

(defmethod solve-regimen ((solver greedy-solver) conclusions kb patient)
  "CONCLUSIONS: alist (organism . belief). KB: a THERAPY-KB. PATIENT: a list of
   patient-state tokens. Returns a RECOMMENDATION."
  (declare (ignore solver))
  (multiple-value-bind (items excluded candidates uncovered regimen)
      (solve-regimen-phase-a conclusions kb patient)
    (solve-regimen-phase-b kb conclusions items excluded candidates uncovered regimen)))

;; Register on load so (use-solver :greedy) works out of the box.
(register-solver :greedy (make-instance 'greedy-solver :name "greedy"))

(defmacro with-greedy-solver (() &body body)
  `(progn
     (therapy:use-solver :greedy)
     ,@body))
