;; This file is part of Lisa, the Lisp-based Intelligent Software Agents platform.

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

;; Description: Dempster-Shafer over an OPEN frame of discernment.
;;
;; An ANSWER is the set of hypotheses a piece of evidence narrows the question to,
;; with a degree of belief. Answers combine by intersection: two answers that cannot
;; both be true produce conflict, and a hypothesis absent from an answer loses
;; plausibility WITHOUT anything having to argue against it. Exclusion is never
;; authored -- it is what remains when answers disagree.
;;
;; THE FRAME IS NEVER ENUMERATED. Everything Dempster-Shafer needs from Theta is that
;; `Theta ∩ A = A` and that `Theta contains x` for any x, and both are answerable
;; symbolically. So only the sets some rule actually names ever materialize, and a
;; knowledge base can hold ten pathogens or ten thousand with the same handful of
;; focal sets. There is no frame declaration to keep in step with the rulebase, and no
;; catch-all element: a hypothesis nobody has mentioned simply has Pl = m(Theta),
;; which is the honest answer that nothing has spoken to it.
;;
;; This file is the ALGEBRA only. It knows nothing of rules, facts, or Lisa, and
;; depends on nothing but Common Lisp. A knowledge base supplies answers; how it
;; collects them is its own business.
;;
;; See docs/narrows-to-promotion-sketch.md.

(in-package :lisa.candidates)

;;; ============================================================
;;; Sets over an open universe
;;; ============================================================
;;; A hypothesis set is a sorted list of designators, or +UNIVERSE+ for Theta. NIL is
;;; the empty set -- the intersection of two answers that cannot both hold.

(defconstant +universe+ :universe
  "Theta, as a symbol rather than a list. It is the identity for intersection and
   contains every hypothesis, which is all the algebra ever asks of it.")

(defun canonical (elements)
  "Sorted, duplicate-free -- so a set has one representation and can be an EQUAL key."
  (sort (remove-duplicates (copy-list elements)) #'string< :key #'string))

(defun universe-p (s) (eq s +universe+))

(defun set-intersect (a b)
  (cond ((universe-p a) b)
        ((universe-p b) a)
        (t (canonical (intersection a b)))))

(defun set-contains-p (s x)
  "Theta contains everything -- including hypotheses this knowledge base has never
   heard of. That is what lets Pl be meaningful without an enumeration."
  (or (universe-p s) (and (member x s) t)))

(defun set-subset-p (a b)
  (cond ((universe-p b) t)
        ((universe-p a) nil)
        (t (subsetp a b))))

(defun set-size (s)
  "Number of hypotheses, or :UNBOUNDED for Theta."
  (if (universe-p s) :unbounded (length s)))

(defun set-name (s)
  (if (universe-p s) "Θ" (format nil "{~{~(~a~)~^, ~}}" s)))

;;; ============================================================
;;; Mass functions
;;; ============================================================
;;; A sparse alist from set to mass. Mass on NIL is conflict, kept rather than
;;; normalized away, so the accumulation stays associative and the normalization
;;; stays a readout choice.

(defun mass-ref (m s) (or (cdr (assoc s m :test #'equal)) 0.0d0))

(defun mass-incf (m s delta)
  (let ((cell (assoc s m :test #'equal)))
    (if cell (progn (incf (cdr cell) delta) m) (cons (cons s delta) m))))

(defun to-double (x)
  "Widen without dragging single-float noise along: promoting 0.6f0 straight to double
   gives 0.6000000238418579, and that error propagates into every serialized number."
  (if (typep x 'single-float) (float (rationalize x) 1.0d0) (float x 1.0d0)))

(defun answer (set belief)
  "One answer as a mass function: BELIEF on SET, the remainder on Theta. This is the
   only shape a rule produces -- a simple support function."
  (let ((b (max 0.0d0 (min 1.0d0 (to-double belief))))
        (s (if (universe-p set) set (canonical set))))
    (if (>= b 1.0d0)
        (list (cons s 1.0d0))
        (list (cons s b) (cons +universe+ (- 1.0d0 b))))))

(defun combine-two (m1 m2)
  "The unnormalized conjunctive rule -- associative and commutative, so the order in
   which rules happened to fire cannot reach the numbers."
  (let ((out '()))
    (dolist (a m1 out)
      (dolist (b m2)
        (setf out (mass-incf out (set-intersect (car a) (car b)) (* (cdr a) (cdr b))))))))

(defun vacuous ()
  "Total ignorance: all mass on Theta. The identity for combination."
  (list (cons +universe+ 1.0d0)))

(defun conflict-of (m)
  "K -- mass this combination put on the empty set. Read it BEFORE normalizing; both
   normalizations resolve it away by construction, so a normalized mass function
   always reports zero."
  (mass-ref m nil))

;;; ------------------------------------------------------------
;;; Normalization -- two readouts of one accumulation
;;; ------------------------------------------------------------

(defvar *normalization* :dempster
  "Which readout COMBINE-ANSWERS applies: :DEMPSTER redistributes conflict among the
   survivors, :YAGER moves it to Theta, :NONE leaves it exposed.")

(defun dempster-normalize (m)
  (let ((k (conflict-of m)))
    (if (>= k 1.0d0)
        (vacuous)
        (loop for (s . mass) in m unless (null s)
              collect (cons s (/ mass (- 1.0d0 k)))))))

(defun yager-normalize (m)
  (let ((out '()))
    (loop for (s . mass) in m unless (null s) do (setf out (mass-incf out s mass)))
    (mass-incf out +universe+ (conflict-of m))))

(defun normalize (m &optional (how *normalization*))
  (ecase how
    (:dempster (dempster-normalize m))
    (:yager (yager-normalize m))
    (:none m)))

;;; ============================================================
;;; Combining answers
;;; ============================================================

(defun combine-answers (answers &key (normalization *normalization*))
  "Combine ANSWERS -- a list of (SET . BELIEF) -- into one mass function.

   Returns (values MASS CONFLICT), the conflict read before normalization."
  (let ((raw (if (null answers)
                 (vacuous)
                 (reduce #'combine-two
                         (mapcar (lambda (a) (answer (car a) (cdr a))) answers)))))
    (values (normalize raw normalization) (conflict-of raw))))

;;; ============================================================
;;; Reading the result -- no enumeration required
;;; ============================================================

(defun bel (m x)
  "Bel(x): mass committed to sets that IMPLY x. For a single hypothesis that is the
   mass on the singleton alone."
  (mass-ref m (canonical (list x))))

(defun pl (m x)
  "Pl(x): mass on sets CONSISTENT with x. Answerable for any hypothesis, including one
   no rule has ever named -- such a hypothesis picks up m(Theta) and nothing else,
   which is the honest statement that nothing has spoken to it."
  (let ((sum 0.0d0))
    (dolist (e m sum)
      (when (and (car e) (set-contains-p (car e) x)) (incf sum (cdr e))))))

(defun interval (m x) (values (bel m x) (pl m x)))

(defun bel-of-set (m probe)
  "Bel for a SET of hypotheses -- e.g. a whole genus. The mass that has settled inside
   it, however it is distributed among the members."
  (let ((p (canonical probe)) (sum 0.0d0))
    (dolist (e m sum)
      (when (and (car e) (set-subset-p (car e) p)) (incf sum (cdr e))))))

(defun pl-of-set (m probe)
  (let ((p (canonical probe)) (sum 0.0d0))
    (dolist (e m sum)
      (when (and (car e)
                 (or (universe-p (car e)) (intersection (car e) p)))
        (incf sum (cdr e))))))

(defun ignorance (m) (mass-ref m +universe+))

(defun hypotheses-named (m)
  "Every hypothesis any focal set mentions -- what this consultation can speak about,
   as opposed to what exists."
  (let ((acc '()))
    (dolist (e m (canonical acc))
      (unless (or (null (car e)) (universe-p (car e)))
        (dolist (x (car e)) (pushnew x acc))))))

(defun set-valued (m)
  "((set . mass) ...) for focal sets that name more than one hypothesis and are not
   Theta -- genuine set-valued conclusions, sorted by mass. Often the honest headline:
   the group is well supported and the member is not."
  (let ((acc '()))
    (dolist (e m)
      (unless (or (null (car e)) (universe-p (car e)) (= 1 (length (car e))))
        (push e acc)))
    (sort acc #'> :key #'cdr)))

(defun leading-focus (m)
  "The focal set carrying the most mass, Theta excluded -- the answer the evidence has
   settled on, at whatever resolution it settled. Ties break by set name, so the choice
   is deterministic. NIL when nothing but Theta is focal."
  (let ((best nil) (best-mass -1.0d0))
    (dolist (e m best)
      (let ((s (car e)))
        (unless (or (null s) (universe-p s))
          (when (or (> (cdr e) best-mass)
                    (and (= (cdr e) best-mass)
                         (string< (set-name s) (set-name best))))
            (setf best s best-mass (cdr e))))))))

(defun margin (m)
  "How far the leading answer sits above the best answer that CONTRADICTS it.

   Returns (values MARGIN LEADER RIVAL): the mass gap, the focal set that leads, and
   the disjoint focal set nearest it (NIL when nothing contradicts the leader).

   COMPARED AGAINST DISJOINT SETS ONLY, which is the whole subtlety. A coarser answer
   that CONTAINS the leader -- `one of the seven aerobic gram-negative rods' sitting
   under `pseudomonas' -- is not a rival at all; it is the same claim at lower
   resolution, and it agrees. Only a set the leader is absent from competes.

   That also makes a SET-SHAPED rival count, which a singleton-only reading misses.
   Measured on the corpus: a respiratory gram-positive coccus in chains with beta
   hemolysis puts 0.429 on {pneumoniae} and 0.429 on {pyogenes, agalactiae}. Both
   members of that pair have Bel 0 individually, so `leader minus runner-up singleton'
   would report a decisive 0.429 for a case that is exactly tied. This reports 0.000.

   THE COMPANION TO CONFLICT-OF, AND IT IS NOT OPTIONAL. K alone cannot be read as a
   measure of how much the evidence disagrees, because in this algebra two answers
   naming different hypotheses conflict TOTALLY -- so K counts how much rival mass was
   overruled, and grows as the winning side strengthens. Measured on the corpus:

     {pseudomonas} 0.928 vs {klebsiella} 0.60  ->  K=0.557, margin=0.740
     {pseudomonas} 0.760 vs {klebsiella} 0.760 ->  K=0.578, margin=0.000

   Near-identical conflict; the first is as decisive as this corpus gets and the
   second is a dead tie. K is not even monotone in disagreement -- a clear three-way
   winner scores K=0.700 where a genuine three-way tie scores 0.500. Reporting K
   without MARGIN invites exactly the reading the numbers do not support.

   MARGIN IS NOT A CONFIDENCE SCORE, and must not be pressed into service as one. A
   wide margin says the evidence has converged on ONE ANSWER; it says nothing about
   how precise that answer is. Settling firmly on a seven-member set scores exactly as
   decisively as settling on a species, because it IS decisive -- about a coarser
   question. SET-SIZE of the leader is what reports the resolution, and SET-VALUED
   what reports the alternatives. Three readouts, three questions, none a substitute
   for another."
  (let ((leader (leading-focus m)))
    (if (null leader)
        (values 0.0d0 nil nil)
        (let ((rival nil) (rival-mass 0.0d0))
          (dolist (e m)
            (let ((s (car e)))
              (when (and s (not (universe-p s)) (not (equal s leader))
                         (null (set-intersect s leader))
                         (> (cdr e) rival-mass))
                (setf rival s rival-mass (cdr e)))))
          (values (- (mass-ref m leader) rival-mass) leader rival)))))

(defun total-mass (m) (loop for e in m sum (cdr e)))