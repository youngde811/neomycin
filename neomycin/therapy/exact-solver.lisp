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

;; Description: The exact set-cover therapy solver (exact-solver-design.md 2, 4).
;; Phase B only; phase A is shared (solver-common.lisp).
;;
;; Minimum set cover is NP-hard and greedy is the standard ln(n) approximation.
;; Neither fact matters at this scale: 11 drugs, and realistically 1-4 items after
;; the belief gate. Ascending-k enumeration terminates at k=1 or k=2 in nearly every
;; real case, and the worst case is 2^11 = 2048 subsets.
;;
;; WHY EXACT, given greedy's answers here are already minimum-cardinality: not
;; optimality. It is to make the objective an explicit, named, comparable thing --
;; the same move this fork already made for the belief algebra (CF vs DS) and the
;; coverage gate (belief / plausibility / midpoint). Two objectives are implemented,
;; selected by *OBJECTIVE*: :lexicographic (the default, greedy's policy declared
;; rather than incidental) and :spectrum-sparing (narrowest-first). Cardinality is
;; primary under both -- the dial only decides how ties on drug count break.
;;
;; NO DOMINANCE PRUNING, deliberately, though the design sketch lists it. Pruning
;; drops a drug whose coverage is a subset of another's -- which is exactly a drug
;; that would have appeared in ALTERNATIVE-AGENTS or ALTERNATIVE-REGIMENS. Since
;; reporting those completely is the point of this slice (1.1), an optimization that
;; silently removes them would trade the slice's purpose for speed we do not need.
;; If the KB ever grows enough to want pruning, prune the WINNER search only and
;; enumerate alternatives separately.

(in-package :neomycin-therapy)

;;; ============================================================
;;; Coverage bitmasks
;;;
;;; A candidate's coverage over the universe is a bitmask, union is LOGIOR, and
;;; "covers everything" is one comparison. Universe order is the name-sorted item
;;; order from phase A, so bit positions are stable and the search is reproducible.
;;; ============================================================

(defun coverage-mask (kb drug universe)
  "Bitmask of the organisms in UNIVERSE (by position) that DRUG covers."
  (let ((mask 0))
    (loop for org in universe
          for bit from 0
          when (>= (susceptibility->scalar (kb-susceptibility kb drug org))
                   *susceptibility-threshold*)
            do (setf mask (logior mask (ash 1 bit))))
    mask))

(defun mask->organisms (mask universe)
  "The organisms of UNIVERSE whose bits are set in MASK, in universe order."
  (loop for org in universe
        for bit from 0
        when (logbitp bit mask)
          collect org))

(defun full-mask (universe)
  "The mask with one bit set per organism in UNIVERSE."
  (1- (ash 1 (length universe))))

;;; ============================================================
;;; Ascending-k enumeration
;;; ============================================================

(defun k-subsets (items k)
  "Every K-element subset of ITEMS, each in ITEMS order, the collection in
   lexicographic order by position. ITEMS is name-sorted upstream, so this ordering
   is deterministic and the first minimal cover found is always the same one."
  (cond ((zerop k) (list '()))
        ((null items) '())
        ((> k (length items)) '())
        (t (nconc
            (mapcar #'(lambda (rest) (cons (first items) rest))
                    (k-subsets (rest items) (1- k)))
            (k-subsets (rest items) k)))))

(defun subset-covers-p (subset masks target)
  "True iff the union of SUBSET's coverage masks reaches TARGET."
  (let ((union 0))
    (dolist (d subset)
      (setf union (logior union (gethash d masks))))
    (= (logand union target) target)))

(defun minimum-covers (candidates masks target)
  "ALL covers of minimum size: ascending k, stopping at the first k that yields any.
   Returns NIL when TARGET is unreachable even by every candidate together."
  (when (zerop target)
    (return-from minimum-covers (list '())))
  (loop for k from 1 to (length candidates)
        for found = (remove-if-not #'(lambda (s) (subset-covers-p s masks target))
                                   (k-subsets candidates k))
        when found
          do (return found)
        finally (return nil)))

;;; ============================================================
;;; The :lexicographic objective
;;;
;;; Today's greedy behaviour, stated as policy: minimize drug count (already fixed
;;; by taking only minimum-size covers), then maximize summed susceptibility x
;;; identification belief, then drug name.
;;;
;;; Regimen-level weight needs care that greedy's per-step weight did not. Greedy
;;; removes each organism as it is covered, so its weights never double-count. A
;;; whole subset can cover one organism twice, so we score each organism ONCE, by
;;; the best drug in the subset covering it. That also yields the disjoint COVERS
;;; assignment the regimen report wants -- one organism attributed to one drug,
;;; the same shape greedy produces.
;;; ============================================================

(defun best-drug-for (kb organism drugs belief-of)
  "The drug in DRUGS covering ORGANISM with the highest susceptibility x belief,
   ties broken by name (DRUGS arrives name-sorted). NIL if none covers it."
  (let ((best nil) (best-w -1))
    (dolist (d drugs)
      (let ((s (susceptibility->scalar (kb-susceptibility kb d organism))))
        (when (>= s *susceptibility-threshold*)
          (let ((w (* s (funcall belief-of organism))))
            (when (> w best-w)
              (setf best d best-w w))))))
    (values best best-w)))

(defun assign-organisms (kb subset universe belief-of)
  "Attribute each covered organism in UNIVERSE to exactly one drug of SUBSET.
   Returns (values ALIST TOTAL-WEIGHT) where ALIST maps drug -> organisms, in
   SUBSET order, and TOTAL-WEIGHT is the objective score for the whole subset."
  (let ((assignment (mapcar #'(lambda (d) (cons d '())) subset))
        (total 0))
    (dolist (org universe)
      (multiple-value-bind (drug w) (best-drug-for kb org subset belief-of)
        (when drug
          (push org (cdr (assoc drug assignment)))
          (incf total w))))
    (values (loop for (d . orgs) in assignment
                  when orgs collect (cons d (nreverse orgs)))
            total)))

(defun subset-name-key (subset)
  "A total, stable string key for SUBSET -- the last tiebreak under every objective,
   so no comparison can ever fall through to an arbitrary order."
  (format nil "~{~A~^,~}" (mapcar #'symbol-name subset)))

(defun regimen-breadth (kb subset)
  "Summed declared spectrum rank over SUBSET -- lower is narrower.

   A drug with NO authored tier counts as one step BROADER than :very-broad. Ranking
   it narrowest would let unauthored data win the objective outright, which is the
   failure mode where a gap in the KB reads as a clinical virtue. Under-known is
   treated as unfavoured, never as preferred."
  (let ((unknown (length *spectrum-tiers*)))
    (loop for d in subset
          sum (or (spectrum-rank (kb-drug-spectrum kb d)) unknown))))

(defun objective-better-p (kb a b)
  "Compare two scored subsets under the active *OBJECTIVE*. Each argument is
   (SUBSET . WEIGHT), WEIGHT being summed susceptibility x identification belief.

   Cardinality is not compared here: both candidates are already minimum-size, which
   is what makes this a TIEBREAK dial rather than a different search. Every branch
   ends at SUBSET-NAME-KEY, so every objective is deterministic."
  (let ((wa (cdr a)) (wb (cdr b)))
    (ecase *objective*
      (:lexicographic
       (cond ((> wa wb) t)
             ((< wa wb) nil)
             (t (string< (subset-name-key (car a)) (subset-name-key (car b))))))
      (:spectrum-sparing
       (let ((ba (regimen-breadth kb (car a)))
             (bb (regimen-breadth kb (car b))))
         (cond ((< ba bb) t)
               ((> ba bb) nil)
               ;; Equal breadth -- fall back to the lexicographic key, so the two
               ;; objectives agree wherever spectrum has nothing to say.
               ((> wa wb) t)
               ((< wa wb) nil)
               (t (string< (subset-name-key (car a)) (subset-name-key (car b))))))))))

;;; ============================================================
;;; The solver
;;; ============================================================

(defclass exact-solver (solver) ()
  (:documentation "Exact set-cover therapy solver (exact-solver-design.md 4).
   Enumerates every minimum-size cover by ascending k, then picks among them by the
   declared objective -- currently :lexicographic only, which reproduces greedy's
   policy exactly rather than approximating it. Reports the covers it did not pick
   as ALTERNATIVE-REGIMENS. Deterministic."))

(defun regimen-from-assignment (kb assignment)
  "Build the regimen-item list for an ASSIGNMENT alist (drug . organisms)."
  (loop for (drug . orgs) in assignment
        collect (regimen-item-for kb drug orgs)))

(defmethod solve-regimen ((solver exact-solver) conclusions kb patient)
  "CONCLUSIONS: alist (organism . belief). KB: a THERAPY-KB. PATIENT: a list of
   patient-state tokens. Returns a RECOMMENDATION."
  (declare (ignore solver))
  (multiple-value-bind (items excluded candidates universe)
      (solve-regimen-phase-a conclusions kb patient)
    (flet ((belief-of (org) (scalar-of (cdr (assoc org conclusions)))))
      (let* ((masks (let ((h (make-hash-table :test #'eq)))
                      (dolist (d candidates h)
                        (setf (gethash d h) (coverage-mask kb d universe)))))
             ;; An organism no candidate covers cannot be part of any cover. Solve
             ;; exactly over the COVERABLE ones and report the rest as uncovered --
             ;; the same honest partial result greedy produces, rather than failing
             ;; to return a regimen at all because one organism was untreatable.
             (reachable (let ((u 0))
                          (maphash #'(lambda (k v) (declare (ignore k))
                                       (setf u (logior u v)))
                                   masks)
                          u))
             (target (logand (full-mask universe) reachable))
             (uncovered (set-difference universe (mask->organisms target universe)))
             (covers (minimum-covers candidates masks target))
             (scored (loop for s in covers
                           collect (multiple-value-bind (assignment total)
                                       (assign-organisms kb s universe #'belief-of)
                                     (list s assignment total))))
             (ranked (sort (mapcar #'(lambda (e) (cons (first e) (third e))) scored)
                           #'(lambda (a b) (objective-better-p kb a b))))
             (winner (car (first ranked)))
             (winning-assignment (second (find winner scored :key #'first :test #'equal))))
        (make-recommendation
         :regimen (regimen-from-assignment kb winning-assignment)
         :items-to-treat (mapcar #'(lambda (p)
                                     (make-treat-item :organism (car p) :belief (cdr p)))
                                 items)
         :excluded excluded
         :uncovered (sort (copy-list uncovered) #'string< :key #'symbol-name)
         :alternative-agents (alternative-agents-for kb candidates universe winner)
         ;; Every OTHER minimum-size cover, in objective order -- the runners-up the
         ;; tiebreak chose against, not a ranking of clinical merit.
         :alternative-regimens
         (loop for (subset . nil) in (rest ranked)
               collect (make-alternative-regimen
                        :drugs (regimen-from-assignment
                                kb (second (find subset scored :key #'first
                                                              :test #'equal))))))))))

;; Register on load so (use-solver :exact) works out of the box.
(register-solver :exact (make-instance 'exact-solver :name "exact"))

(defmacro with-exact-solver (&body body)
  `(progn
     (therapy:use-solver :exact)
     ,@body))