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

;; Description: Dempster-Shafer over a SHARED FRAME OF DISCERNMENT -- mass
;; functions on arbitrary subsets of a declared frame, rather than the dichotomous
;; {H, not-H} frame per hypothesis that dempster-shafer.lisp implements.
;;
;; WHY THIS EXISTS. Under the Barnett simplification each hypothesis carries its own
;; private two-element frame, so two hypotheses' beliefs never interact: evidence for
;; one cannot lower another, and a taxonomic class cannot be represented as the SET of
;; its members. Every consequence of that is documented and measured in
;; docs/shared-frame-design.md and docs/shared-frame-phase0-results.md.
;;
;; This file is the ALGEBRA only -- frames, sparse mass functions, the two
;; accumulation operators, the two normalizations, and Bel/Pl projection. It knows
;; nothing about rules, facts, or the belief-system protocol, and depends on nothing
;; but Common Lisp. The belief-system class that plugs it into Lisa is separate.
;;
;; SETS ARE BITMASKS. A frame's elements are numbered, a subset is an integer whose
;; nth bit is set iff element n is in it. Intersection is LOGAND, subset test is a
;; LOGAND comparison, and a mask is a valid EQL hash key. Frames of practical size
;; (neomycin's is 18) keep masks well inside a fixnum.

(in-package :belief)

;;; ============================================================
;;; Frames
;;; ============================================================

(defstruct (frame (:constructor %make-frame (elements index))
                  (:print-function print-frame))
  "A frame of discernment: the exhaustive, mutually exclusive set of answers to one
   question. ELEMENTS is a simple-vector in declaration order; INDEX maps an element
   to its bit position; SUBSETS names distinguished subsets (a taxonomy, typically),
   so a rule can support :ENTEROBACTERIACEAE without restating its six members."
  (elements #() :type simple-vector)
  (index (make-hash-table :test #'eql) :type hash-table)
  (subsets (make-hash-table :test #'eql) :type hash-table))

(defun print-frame (f stream depth)
  (declare (ignore depth))
  (format stream "#<FRAME ~D: ~{~A~^ ~}>"
          (frame-size f) (coerce (frame-elements f) 'list)))

(defun make-frame (elements &optional subsets)
  "Build a frame over ELEMENTS with optional named SUBSETS, an alist
   ((NAME . MEMBER-ELEMENTS) ...). See %MAKE-FRAME-1 for the element rules."
  (let ((f (%make-frame-1 elements)))
    (loop for (name . members) in subsets
          do (add-frame-subset f name members))
    f))

(defun %make-frame-1 (elements)
  "Build a frame over ELEMENTS, a list of distinct designators (typically keywords).
   Signals an error on duplicates -- a repeated element would silently collapse two
   hypotheses into one bit."
  (let ((vec (coerce elements 'simple-vector))
        (index (make-hash-table :test #'eql)))
    (loop for e across vec
          for i from 0
          do (when (gethash e index)
               (error "Duplicate element ~S in frame." e))
             (setf (gethash e index) i))
    (%make-frame vec index)))

(defun add-frame-subset (f name members)
  "Name the subset of F consisting of MEMBERS. Errors if any member is not an
   element -- so a subset cannot silently go stale when an element is retired."
  (setf (gethash name (frame-subsets f)) (elements->mask f members)))

(defun frame-subset (f name)
  "Mask of the named subset, or NIL."
  (gethash name (frame-subsets f)))

(defun frame-subset-names (f)
  (loop for k being the hash-keys of (frame-subsets f) collect k))

(defun resolve-mask (f designator)
  "Mask for DESIGNATOR: a named subset, a single element, or a list of either.
   This is the one place a rule's declared focal set becomes a mask, so it is also
   the one place a reference to a retired hypothesis is caught."
  (cond
    ((integerp designator) designator)
    ((listp designator)
     (reduce #'logior (mapcar (lambda (d) (resolve-mask f d)) designator)
             :initial-value 0))
    ((frame-subset f designator))
    ((frame-bit f designator) (ash 1 (frame-bit f designator)))
    (t (error "~S names neither an element nor a subset of ~S." designator f))))

(defun frame-size (f)
  (length (frame-elements f)))

(defun frame-theta (f)
  "Theta -- the mask denoting the whole frame. Mass here is pure ignorance."
  (1- (ash 1 (frame-size f))))

(defun frame-bit (f element)
  "Bit position of ELEMENT, or NIL if it is not in the frame."
  (gethash element (frame-index f)))

(defun frame-member-p (f element)
  (and (frame-bit f element) t))

(defun elements->mask (f elements)
  "Mask for ELEMENTS. Signals an error naming any element not in the frame -- that
   is the check that catches a rule referring to a retired hypothesis."
  (let ((mask 0))
    (dolist (e elements mask)
      (let ((bit (frame-bit f e)))
        (unless bit
          (error "~S is not an element of ~S." e f))
        (setf mask (logior mask (ash 1 bit)))))))

(defun mask->elements (f mask)
  "The elements of MASK, in frame declaration order."
  (loop for e across (frame-elements f)
        for i from 0
        when (logbitp i mask) collect e))

(defun mask-complement (f mask)
  "Theta minus MASK -- the focal set of a rule that argues AGAINST the members of
   MASK. This is what makes a ruling-out rule the same mechanism as a confirming one
   rather than a separate rule kind."
  (logandc2 (frame-theta f) mask))

(defun mask-singleton-p (mask)
  (and (plusp mask) (zerop (logand mask (1- mask)))))

(defun mask-size (mask)
  (logcount mask))

;;; ============================================================
;;; Sparse mass functions
;;; ============================================================

(defstruct (mass-fn (:constructor %make-mass-fn (frame table))
                    (:print-function print-mass-fn))
  "A basic probability assignment: a sparse map from subset mask to mass. Only
   subsets carrying mass appear. Mass on mask 0 (the empty set) is CONFLICT, which
   this representation keeps rather than normalizing away -- see POOL-MASS."
  frame
  (table (make-hash-table :test #'eql) :type hash-table))

(defun print-mass-fn (m stream depth)
  (declare (ignore depth))
  (format stream "#<MASS-FN ~D focal, K=~,3F>"
          (hash-table-count (mass-fn-table m)) (mass-conflict m)))

(defun make-mass-fn (frame)
  (%make-mass-fn frame (make-hash-table :test #'eql)))

(defun mass-ref (m mask)
  (gethash mask (mass-fn-table m) 0.0d0))

(defun mass-incf (m mask delta)
  (incf (gethash mask (mass-fn-table m) 0.0d0) delta)
  m)

(defmacro do-mass ((mask-var mass-var m &optional result) &body body)
  "Iterate over the focal elements of mass function M."
  `(progn
     (maphash (lambda (,mask-var ,mass-var) ,@body) (mass-fn-table ,m))
     ,result))

(defun mass-conflict (m)
  "K -- the mass this combination assigned to the empty set. Reported rather than
   hidden: a consultation that resolved away most of its mass should say so."
  (mass-ref m 0))

(defun mass-total (m)
  (let ((sum 0.0d0)) (do-mass (k v m sum) (declare (ignore k)) (incf sum v))))

(defun mass-focal-count (m)
  "Number of NON-EMPTY focal sets."
  (let ((n 0)) (do-mass (k v m n) (declare (ignore v)) (unless (zerop k) (incf n)))))

(defun vacuous-mass (frame)
  "Total ignorance: all mass on Theta. The identity for conjunctive combination."
  (let ((m (make-mass-fn frame)))
    (mass-incf m (frame-theta frame) 1.0d0)))

(defun simple-support (frame mask support)
  "The only shape a rule can contribute: SUPPORT on MASK, the remainder on Theta.
   In canonical-decomposition terms this is MASK^w with weight w = 1 - SUPPORT,
   which is what makes the cautious rule cheap here (see POOL-MASS)."
  (let ((s (max 0.0d0 (min 1.0d0 (float support 1.0d0))))
        (m (make-mass-fn frame)))
    (mass-incf m mask s)
    (when (< s 1.0d0)
      (mass-incf m (frame-theta frame) (- 1.0d0 s)))
    m))

(defun conjunctive-combine (m1 m2)
  "The UNNORMALIZED conjunctive rule: mass m1(A)*m2(B) lands on A and B intersected,
   with mass landing on the empty set accumulating as conflict.

   Unnormalized and therefore associative and commutative, so the result does not
   depend on the order rules fired -- which matters in a Rete system, where firing
   order is a conflict-resolution artifact. Normalization is a READOUT choice
   (DEMPSTER-NORMALIZE / YAGER-NORMALIZE), not a combination-time commitment;
   Yager's rule applied pairwise is not associative, and deferring it this way
   sidesteps that entirely."
  (let ((out (make-mass-fn (mass-fn-frame m1))))
    (do-mass (a ma m1 out)
      (do-mass (b mb m2)
        (mass-incf out (logand a b) (* ma mb))))))

(defun combine-all (frame mass-fns)
  (if (null mass-fns)
      (vacuous-mass frame)
      (reduce #'conjunctive-combine mass-fns)))

;;; ============================================================
;;; Normalizations -- two readouts of one accumulation
;;; ============================================================

(defun dempster-normalize (m)
  "m(A) / (1 - K) for A non-empty. Redistributes conflict proportionally among the
   survivors. Sharpens, but at high K produces narrow intervals that are artifacts of
   the renormalization rather than of the evidence."
  (let ((k (mass-conflict m))
        (out (make-mass-fn (mass-fn-frame m))))
    (if (>= k 1.0d0)
        (vacuous-mass (mass-fn-frame m))       ; total conflict: refuse to divide by 0
        (let ((norm (- 1.0d0 k)))
          (do-mass (mask mass m out)
            (unless (zerop mask)
              (mass-incf out mask (/ mass norm))))))))

(defun yager-normalize (m)
  "Conflict is moved to Theta instead of being redistributed: m(Theta) + K. Never
   inflates a hypothesis, and widens intervals in proportion to how much the sources
   disagreed. Conservative, and uninformative when K is large."
  (let ((theta (frame-theta (mass-fn-frame m)))
        (out (make-mass-fn (mass-fn-frame m))))
    (do-mass (mask mass m)
      (unless (zerop mask)
        (mass-incf out mask mass)))
    (mass-incf out theta (mass-conflict m))
    out))

(defvar *frame-normalization* :dempster
  "Which readout POOL-MASS applies: :DEMPSTER or :YAGER. Deferred decision D3 --
   phase 0.5 measured both and recommended holding off on a default until conflict
   is at a realistic level. Both are exposed so the comparison stays runnable.")

(defun normalize-mass (m &optional (how *frame-normalization*))
  (ecase how
    (:dempster (dempster-normalize m))
    (:yager (yager-normalize m))
    (:none m)))

;;; ============================================================
;;; Projection -- what a caller actually reads
;;; ============================================================

(defun mask-belief (m probe)
  "Bel(PROBE): total mass committed to subsets that IMPLY it -- every focal set
   contained in PROBE. For a singleton this reduces to m({x}); for a taxonomic subset
   it is the mass that has settled inside that family, however it is distributed
   among the members."
  (let ((sum 0.0d0))
    (do-mass (mask mass m sum)
      (when (and (plusp mask) (= mask (logand mask probe)))
        (incf sum mass)))))

(defun mask-plausibility (m probe)
  "Pl(PROBE): total mass on subsets CONSISTENT with it -- every focal set that
   intersects PROBE. This is where free exclusion comes from: mass committed to a set
   DISJOINT from PROBE lowers its plausibility with no rule arguing against it."
  (let ((sum 0.0d0))
    (do-mass (mask mass m sum)
      (unless (zerop (logand mask probe))
        (incf sum mass)))))

(defun hypothesis-mask (m hypothesis)
  "Mask for HYPOTHESIS -- a frame element or a named subset -- or NIL if it is
   neither. NIL rather than an error: a projection is asked for speculatively, over
   whatever facts happen to be in working memory."
  (let ((f (mass-fn-frame m)))
    (cond ((integerp hypothesis) hypothesis)
          ((frame-subset f hypothesis))
          ((frame-bit f hypothesis) (ash 1 (frame-bit f hypothesis))))))

(defun mass-belief (m hypothesis)
  "Bel for a frame element OR a named subset. 0 if HYPOTHESIS is neither."
  (let ((probe (hypothesis-mask m hypothesis)))
    (if probe (mask-belief m probe) 0.0d0)))

(defun mass-plausibility (m hypothesis)
  "Pl for a frame element OR a named subset. 0 if HYPOTHESIS is neither."
  (let ((probe (hypothesis-mask m hypothesis)))
    (if probe (mask-plausibility m probe) 0.0d0)))

(defun mass-interval (m hypothesis)
  (values (mass-belief m hypothesis) (mass-plausibility m hypothesis)))

(defun mass-set-valued (m)
  "((mask . mass) ...) for focal sets that are neither singletons, Theta, nor empty
   -- i.e. genuine set-valued conclusions such as 'some member of this family'.
   Sorted by mass, descending."
  (let ((theta (frame-theta (mass-fn-frame m)))
        (acc '()))
    (do-mass (mask mass m)
      (unless (or (zerop mask) (= mask theta) (mask-singleton-p mask))
        (push (cons mask mass) acc)))
    (sort acc #'> :key #'cdr)))

;;; ============================================================
;;; Evidence pools -- the accumulator a consultation actually holds
;;; ============================================================
;;; A pool is the list of simple support functions contributed so far, NOT a
;;; combined mass function. Keeping the contributions lets POOL-MASS apply either
;;; operator on demand, and makes the cautious rule exact and cheap (below).

(defstruct (evidence-pool (:constructor %make-evidence-pool (frame))
                          (:print-function print-evidence-pool))
  "The accumulated evidence about ONE question. CONTRIBUTIONS is a list of
   (MASK . SUPPORT), one per rule firing; TAGS carries a caller-supplied label per
   contribution so a derivation can name what produced it."
  frame
  (contributions '() :type list))

(defun print-evidence-pool (p stream depth)
  (declare (ignore depth))
  (format stream "#<EVIDENCE-POOL ~D contributions>"
          (length (evidence-pool-contributions p))))

(defun make-evidence-pool (frame)
  (%make-evidence-pool frame))

(defun pool-add (pool mask support &optional tag)
  "Record one rule's contribution: SUPPORT on MASK. TAG is opaque here and exists so
   a caller can attribute the contribution later."
  (push (list mask (float support 1.0d0) tag) (evidence-pool-contributions pool))
  pool)

(defun pool-empty-p (pool)
  (null (evidence-pool-contributions pool)))

(defvar *frame* nil
  "The active frame of discernment, or NIL when none is declared. Set by LISA:DEFRAME
   and read by LISA:FRAME-OF-DISCERNMENT; it lives here because a frame is a
   belief-system concept and this file loads before the engine.")

(defvar *frame-operator* :cautious
  "How POOL-MASS accumulates: :CAUTIOUS or :CONJUNCTIVE.

   :CAUTIOUS is the default on the strength of phase 0.5, which measured both. It
   lowered conflict in every scenario where the two differ, never worsened a ranking,
   and removed the double-counting that let two rules reading ONE observation credit
   it twice. :CONJUNCTIVE is retained for comparison, on the same argument that keeps
   certainty factors and the Barnett DS system alive.")

(defun cautious-supports (contributions)
  "Per focal set, the MAXIMUM support any contribution offered.

   This is Denoeux's cautious conjunctive rule, and it is exact here rather than an
   approximation. In general the rule takes the minimum WEIGHT per focal set over the
   canonical decompositions of its operands, which needs a Moebius transform over the
   superset lattice. But every contribution here is already a simple support function
   -- SUPPORT on MASK, the rest on Theta -- which IS its own canonical decomposition,
   MASK^w with w = 1 - SUPPORT. Minimum weight is therefore maximum support, and no
   transform is needed.

   The consequence that matters: the operator is IDEMPOTENT, so a rule contributing
   the same thing twice, or two rules reading the same observation to the same
   conclusion, count once."
  (let ((best (make-hash-table :test #'eql)))
    (dolist (c contributions)
      (destructuring-bind (mask support tag) c
        (declare (ignore tag))
        (let ((cur (gethash mask best)))
          (when (or (null cur) (> support cur))
            (setf (gethash mask best) support)))))
    best))

(defun pool-conflict (pool &key (operator *frame-operator*))
  "K -- the mass this pool's evidence assigns to the empty set, BEFORE normalization.

   Must be read here rather than off the result of POOL-MASS: both normalizations
   resolve conflict away by construction, so a normalized mass function always reports
   zero. This is the number worth surfacing -- a consultation that renormalized away
   30% of its mass has told you something about how much its rules disagree."
  (mass-conflict (pool-mass pool :operator operator :normalization :none)))

(defun pool-mass (pool &key (operator *frame-operator*)
                            (normalization *frame-normalization*))
  "Materialize POOL as a mass function under OPERATOR, then NORMALIZATION.

   Recomputed from the contributions on each call rather than maintained
   incrementally. That keeps the accumulation order-independent by construction and
   is cheap at the sizes involved (a consultation contributes a handful of rules);
   revisit if a corpus ever makes it hot."
  (let* ((frame (evidence-pool-frame pool))
         (contributions (evidence-pool-contributions pool))
         (supports
           (ecase operator
             (:cautious
              (let ((acc '()))
                (maphash (lambda (mask support) (push (cons mask support) acc))
                         (cautious-supports contributions))
                acc))
             (:conjunctive
              (mapcar (lambda (c) (cons (first c) (second c))) contributions)))))
    (normalize-mass
     (combine-all frame
                  (mapcar (lambda (s) (simple-support frame (car s) (cdr s)))
                          supports))
     normalization)))

;;; ============================================================
;;; The belief system
;;; ============================================================
;;; Deliberately a SUBCLASS of DEMPSTER-SHAFER-SYSTEM, and deliberately storing a
;;; DS-BELIEF on each fact.
;;;
;;; The evidence pool on the engine is the AUTHORITY; a fact's [Bel, Pl] is a
;;; PROJECTION of it, refreshed whenever the pool changes. Storing that projection in
;;; the existing representation means every reader keeps working unchanged --
;;; /conclusions, the therapy solver's SCALAR-OF, BELIEF->JSON, the test harness --
;;; and the read-side protocol methods are inherited rather than reimplemented.
;;;
;;; What this class does NOT inherit in practice is the accumulation path.
;;; COMBINE-BELIEFS / WEAKEN-BELIEF / CONJOIN-BELIEFS are bypassed for rule-concluded
;;; facts, because a rule's contribution goes to the pool as a focal set rather than
;;; to a fact as a scalar. They remain live for evidence asserted with an explicit
;;; numeric :belief, which still normalizes to an interval the same way.

(defclass frame-belief-system (dempster-shafer-system)
  ()
  (:default-initargs :name "Dempster-Shafer (shared frame)"))

(defgeneric frame-based-p (system)
  (:documentation "True when SYSTEM accumulates evidence into a per-entity pool over a
   shared frame, rather than onto each fact independently. The engine branches on
   this: a frame-based system needs the rule's FOCAL SET, which a per-hypothesis
   system has no use for.")
  (:method ((system belief-system)) nil)
  (:method ((system frame-belief-system)) t))

(defun project-mass (m element)
  "The [Bel, Pl] interval for ELEMENT, in the representation facts already carry."
  (make-ds-belief (float (mass-belief m element) 1.0)
                  (float (mass-plausibility m element) 1.0)))

(defvar *frame-system* (make-instance 'frame-belief-system)
  "Singleton shared-frame system instance.")
