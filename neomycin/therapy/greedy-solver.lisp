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

;; Description: The greedy weighted set-cover therapy solver (design doc 4.3) --
;; phase B only. Phase A (the belief gate, the contraindication filter, and the
;; scalar reductions both gates read) is solver-independent and lives in
;; solver-common.lisp; see that file's header for why the boundary sits there.
;;
;; Phase B (set cover): repeatedly pick the drug covering the most still-uncovered
;; items, ties broken by summed susceptibility x belief, then by drug name -- a
;; total order, so the result is DETERMINISTIC.
;;
;; Objective: minimum drug COUNT, and nothing beyond it. This is NOT narrow-spectrum
;; stewardship and must not be described as such. At this KB scale (11 drugs, 1-4
;; items after the gate) cardinality ties almost immediately, so the tiebreak above --
;; summed susceptibility x identification belief -- is what actually decides, and
;; breadth correlates with susceptibility by construction: the agents we reserve are
;; the ones carrying the best coverage numbers. The effect is carbapenem-first,
;; including for a single organism already resolved from a family down to a species.
;; See exact-solver-design.md 1, and 1.1 for that behaviour reaching a clinician.
;;
;; This solver has NO notion of spectrum. A declared, selectable objective -- one
;; option being spectrum-sparing -- is designed in exact-solver-design.md and is NOT
;; implemented here.
;;
;; Interactions are NOT handled in this increment (design doc 4.3 step 4 is a later,
;; separately-tested addition). If some item cannot be covered by any candidate drug,
;; it is reported in the recommendation's UNCOVERED list rather than silently dropped.

(in-package :neomycin-therapy)

(defclass greedy-solver (solver) ()
  (:documentation "Greedy weighted set-cover therapy solver (design doc 4.3).
   Deterministic: fewest drugs, ties broken by summed susceptibility x belief then
   drug name -- and at this KB scale the tiebreak is usually what decides, so read
   the file header on what that does and does not amount to. No notion of spectrum.
   No interaction handling in this increment."))

(defun solve-regimen-phase-b (kb conclusions items excluded candidates uncovered regimen)
  "Solve Regimen Phase B: greedy weighted set cover. BELIEF-OF is rebuilt here as
   a local closure over CONCLUSIONS -- it is the only consumer."
  ;; The loop rebinds CANDIDATES and UNCOVERED as it consumes them, so capture the
  ;; originals first: ALTERNATIVE-AGENTS is about what was available at the start,
  ;; not what survived to the end.
  (let ((all-candidates candidates)
        (universe uncovered)
        (chosen '()))
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
          (push (regimen-item-for kb best best-cov) regimen)
          (push best chosen)
          (setf uncovered (set-difference uncovered best-cov))
          (setf candidates (remove best candidates))))
      (make-recommendation
       :regimen (nreverse regimen)
       :items-to-treat (mapcar #'(lambda (p)
                                   (make-treat-item :organism (car p) :belief (cdr p)))
                               items)
       :excluded excluded
       ;; name-sort the leftovers for a deterministic report
       :uncovered (sort (copy-list uncovered) #'string< :key #'symbol-name)
       ;; Greedy CAN report this: it is a KB fact about the gated items, not a
       ;; by-product of the search. It cannot report ALTERNATIVE-REGIMENS, which
       ;; needs the enumeration only the exact solver performs -- so that field
       ;; stays empty here rather than being faked from the drugs greedy happened
       ;; to pass over.
       :alternative-agents (alternative-agents-for kb all-candidates universe chosen)))))

(defmethod solve-regimen ((solver greedy-solver) conclusions kb patient)
  "CONCLUSIONS: alist (organism . belief). KB: a THERAPY-KB. PATIENT: a list of
   patient-state tokens. Returns a RECOMMENDATION."
  (declare (ignore solver))
  ;; Phase A is shared (solver-common.lisp); the empty regimen accumulator is
  ;; greedy's own, so it starts here rather than being handed back by phase A.
  (multiple-value-bind (items excluded candidates universe)
      (solve-regimen-phase-a conclusions kb patient)
    (solve-regimen-phase-b kb conclusions items excluded candidates universe '())))

;; Register on load so (use-solver :greedy) works out of the box.
(register-solver :greedy (make-instance 'greedy-solver :name "greedy"))

(defmacro with-greedy-solver (&body body)
  `(progn
     (therapy:use-solver :greedy)
     ,@body))
