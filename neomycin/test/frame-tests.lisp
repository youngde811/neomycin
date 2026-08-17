;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: End-to-end tests for the SHARED FRAME belief system -- the engine
;; accumulating rule evidence into a per-entity mass function over a declared frame,
;; rather than onto each hypothesis independently.
;;
;; These are the slice E goldens. Every value was hand-verified against the algebra
;; before being asserted here, and cross-checked against the standalone measurements
;; in docs/shared-frame-phase0-results.md -- the engine and the throwaway spike agree
;; to the printed precision, which is the main reason to believe either.
;;
;; The frame system is OPT-IN at this point: Dempster-Shafer (Barnett) remains the
;; default, so every pre-existing golden still holds and is still checked. Making the
;; frame the default is slice G.

(in-package "LISA-TEST")

(defun frame-run (scenario)
  "Run SCENARIO under the shared-frame system; return the conclusions alist."
  (run-scenario scenario :frame))

(defun the-pool (&optional (entity 'lisa-user::o1))
  "The evidence pool for ENTITY after a run."
  (gethash entity (lisa::rete-evidence-pools (lisa:inference-engine))))

(defun pool-projection (&optional (entity 'lisa-user::o1))
  (belief:pool-mass (the-pool entity)))

;;; ------------------------------------------------------------------
;;; The headline: culture-1, and the ranking the old representation inverted
;;; ------------------------------------------------------------------

(deftest frame-culture-1 ()
  ;; Hand-verified in full. Cautious accumulation collapses the two pseudomonas rules
  ;; (0.4, 0.6) to 0.6 -- they read the same gram-negative rod, so they are one
  ;; observation, not two. Combining {pseudomonas}:0.6, the widened aerobic-gram-neg-rod
  ;; set:0.8 and {klebsiella}:0.5 leaves K = 0.30 on the empty set; Dempster divides
  ;; the survivors by 0.70:
  ;;
  ;;   m{pseudomonas} = 0.30/0.70 = 0.4286      m{klebsiella} = 0.20/0.70 = 0.2857
  ;;   m{aerobic-gram-neg-rods+other} = 0.16/0.70 = 0.2286   m(Theta) = 0.04/0.70 = 0.0571
  (let ((c (frame-run 'lisa-user::culture-1)))
    (check-ds c "pseudomonas" 0.428571 0.714286)
    (check-ds c "klebsiella"  0.285714 0.571429)))

(deftest frame-culture-1-ranks-pseudomonas-first ()
  ;; THE REGRESSION THIS WHOLE LINE OF WORK EXISTS FOR. Phase 0 measured the shared
  ;; frame INVERTING this ranking -- pseudomonas 0.241 behind klebsiella 0.380 -- because
  ;; the class rule claimed a set that excluded pseudomonas while reading the very same
  ;; gram-negative rod. Slice D widened it to what its premises license. If that
  ;; correction is ever undone, this fails.
  (let* ((c (frame-run 'lisa-user::culture-1))
         (p (belief:ds-belief-bel (belief-of c "pseudomonas")))
         (k (belief:ds-belief-bel (belief-of c "klebsiella"))))
    (is (> p k) "pseudomonas must outrank klebsiella in culture-1")))

(deftest frame-beliefs-do-not-sum-past-one ()
  ;; The defect that motivated the frame, stated as an invariant. Under the Barnett
  ;; representation culture-1 reports pseudomonas 0.76 AND klebsiella 0.40 on ONE
  ;; organism -- mutually exclusive hypotheses summing to 1.16, which nothing noticed
  ;; because the two intervals lived on different frames. Mass is conserved, so this
  ;; cannot happen here.
  (dolist (scenario '(lisa-user::culture-1 lisa-user::culture-1a lisa-user::culture-2
                      lisa-user::culture-3 lisa-user::culture-4 lisa-user::culture-5))
    (let* ((c (frame-run scenario))
           (total (reduce #'+ (mapcar (lambda (pair)
                                        (belief:ds-belief-bel (cdr pair)))
                                      c)
                          :initial-value 0.0)))
      (is (<= total 1.0001)
          (format nil "~A: leaf identity beliefs sum to ~,4F, which exceeds 1"
                  scenario total)))))

;;; ------------------------------------------------------------------
;;; Free exclusion -- the payoff
;;; ------------------------------------------------------------------

(deftest frame-excludes-organisms-no-rule-mentions ()
  ;; No rule in culture-1 argues against S. aureus, and none concludes it, so it has no
  ;; fact in working memory at all. Its plausibility still falls out of the arithmetic:
  ;; mass committed to gram-NEGATIVE hypotheses is mass unavailable to a gram-positive
  ;; one. Under the Barnett system every such organism sits at pl = 1.0 forever.
  (frame-run 'lisa-user::culture-1)
  (let ((m (pool-projection)))
    (dolist (organism '(:staphylococcus-aureus :streptococcus-pyogenes
                        :enterococcus-faecalis :bacteroides))
      (is (< (belief:mass-plausibility m organism) 0.99)
          (format nil "~S should be squeezed by evidence that never mentions it"
                  organism))
      (is (zerop (belief:mass-belief m organism))
          (format nil "~S should carry no positive belief" organism)))))

(deftest frame-catch-all-stays-plausible ()
  ;; D4/D6. :other-organism must not collapse: a gram-negative rod really could be an
  ;; organism this corpus does not model, and the coarse rules say so by including it.
  (frame-run 'lisa-user::culture-1)
  (let ((m (pool-projection)))
    (is (> (belief:mass-plausibility m :other-organism) 0.1)
        "the catch-all keeps meaningful plausibility")
    (is (zerop (belief:mass-belief m :other-organism))
        "but no evidence positively supports it")))

;;; ------------------------------------------------------------------
;;; Set-valued conclusions and class projection
;;; ------------------------------------------------------------------

(deftest frame-carries-set-valued-mass ()
  ;; "It is one of these, the evidence does not say which" -- a statement the
  ;; per-hypothesis representation cannot make. neomycin's therapy layer builds this by
  ;; hand today (FAMILY-BACKSTOPS); here it falls out of the arithmetic.
  (frame-run 'lisa-user::culture-1)
  (let ((sets (belief:mass-set-valued (pool-projection))))
    (is (plusp (length sets)) "culture-1 leaves mass on a set-valued hypothesis")
    (is (approx= (cdr (first sets)) 0.228571)
        "0.16/0.70 remains on the aerobic-gram-negative-rod set")))

(deftest frame-projects-a-class-as-a-set ()
  ;; An organism-CLASS is a named subset, so its Bel is the mass that has settled
  ;; INSIDE the family however it is distributed, and its Pl is everything consistent
  ;; with it. In culture-1 the only family-internal mass is klebsiella's, so the two
  ;; coincide -- which is the correct reading, not a coincidence worth hiding.
  (frame-run 'lisa-user::culture-1)
  (let ((m (pool-projection)))
    (is (approx= (belief:mass-belief m :enterobacteriaceae) 0.285714)
        "Bel(family) is the mass committed inside it")
    (is (approx= (belief:mass-plausibility m :enterobacteriaceae) 0.571429)
        "Pl(family) is everything consistent with it")
    ;; A class can never be less plausible than one of its members.
    (is (>= (belief:mass-plausibility m :enterobacteriaceae)
            (belief:mass-plausibility m :klebsiella))
        "a family is at least as plausible as any member")))

;;; ------------------------------------------------------------------
;;; Conflict
;;; ------------------------------------------------------------------

(deftest frame-reports-unnormalized-conflict ()
  ;; K must be read from the pool, not from a normalized mass function: both
  ;; normalizations resolve conflict away by construction, so the projection always
  ;; reports zero. Culture-1's 0.30 is the mass Dempster renormalized away.
  (frame-run 'lisa-user::culture-1)
  (is (approx= (belief:pool-conflict (the-pool)) 0.30)
      "culture-1 renormalizes away 0.30 of its mass")
  (is (approx= (belief:mass-conflict (pool-projection)) 0.0)
      "the projected mass function carries no residual conflict"))

(deftest frame-conflict-falls-when-rules-agree ()
  ;; culture-5's two S. agalactiae rules support the same hypothesis, so there is
  ;; nothing to renormalize; culture-3's streptococcus and enterococcus rules genuinely
  ;; disagree, and that conflict is real rather than manufactured.
  (frame-run 'lisa-user::culture-5)
  (is (approx= (belief:pool-conflict (the-pool)) 0.0)
      "agreeing evidence produces no conflict")
  (frame-run 'lisa-user::culture-3)
  (is (> (belief:pool-conflict (the-pool)) 0.4)
      "genuinely competing hypotheses do conflict"))

(deftest frame-cautious-operator-does-not-double-count ()
  ;; culture-5's two rules both read hemolysis=beta and both conclude S. agalactiae at
  ;; 0.7. Conjunctive accumulation would compound them to 0.91; the cautious operator
  ;; recognises one observation and keeps 0.70. This is the D1 inflation phase 0 found.
  (let ((c (frame-run 'lisa-user::culture-5)))
    (check-ds c "streptococcus-agalactiae" 0.70 1.0))
  (let ((conjunctive (let ((belief:*frame-operator* :conjunctive))
                       (belief:pool-mass (the-pool) :operator :conjunctive))))
    (is (approx= (belief:mass-belief conjunctive :streptococcus-agalactiae) 0.91)
        "the conjunctive operator would have double-counted the same observation")))

;;; ------------------------------------------------------------------
;;; Engine mechanics
;;; ------------------------------------------------------------------

(deftest frame-pools-are-per-entity ()
  ;; The frame asks "which organism is this?" once per ORGANISM, which is why a
  ;; polymicrobial culture is modelled as several organisms rather than several answers
  ;; to one question. Two entities must not share a pool.
  (belief:use-system :frame)
  (let ((*standard-output* (make-broadcast-stream)))
    (lisa-user::culture-multi))
  (let ((pools (lisa::rete-evidence-pools (lisa:inference-engine))))
    (is (>= (hash-table-count pools) 2)
        "culture-multi's two organisms get their own pools")
    (maphash (lambda (entity pool)
               (is (not (belief:pool-empty-p pool))
                   (format nil "pool for ~S has evidence" entity)))
             pools)))

(deftest frame-reset-clears-pools ()
  ;; A pool is the accumulated evidence of ONE consultation and must not leak into the
  ;; next -- the same contract the derivation table has.
  (frame-run 'lisa-user::culture-1)
  (is (plusp (hash-table-count (lisa::rete-evidence-pools (lisa:inference-engine))))
      "a run populates pools")
  (lisa:reset)
  (is (zerop (hash-table-count (lisa::rete-evidence-pools (lisa:inference-engine))))
      "reset clears them"))

(deftest frame-derivations-record-the-focal-set ()
  ;; /why has to be able to say WHICH hypotheses a firing supported, not just how one
  ;; of them moved. The scalar before/after pair cannot express that, so the derivation
  ;; record carries the focal set, the mass contributed, and the pool's K.
  (frame-run 'lisa-user::culture-1)
  (let* ((fact (find-concluded-fact 'lisa-user::organism-identity :klebsiella))
         (records (and fact (lisa:fact-derivation (lisa:inference-engine) fact))))
    (is records "klebsiella has a derivation")
    (when records
      (let ((r (first records)))
        (is (integerp (lisa:derivation-record-focal-set r))
            "the firing recorded which set it supported")
        (is (plusp (lisa:derivation-record-focal-mass r))
            "and how much mass it contributed")
        (is (realp (lisa:derivation-record-conflict r))
            "and the pool's conflict after it")
        (is (member :klebsiella
                    (belief:mask->elements belief:*frame*
                                           (lisa:derivation-record-focal-set r)))
            "klebsiella is in the set its own rule supported")))))

(deftest frame-leaves-raw-evidence-alone ()
  ;; Projection must touch only facts whose value names a frame hypothesis. A gram
  ;; stain is evidence, not a hypothesis, and must keep the belief it was asserted with.
  (frame-run 'lisa-user::culture-2)
  (let ((gram-facts (remove-if-not
                     (lambda (f) (eq (lisa:fact-name f) 'lisa-user::gram))
                     (lisa:get-fact-list (lisa:inference-engine)))))
    (is (plusp (length gram-facts)) "culture-2 asserts gram facts")
    (dolist (f gram-facts)
      (let ((b (belief:belief-factor f)))
        (is (or (null b) (belief:ds-belief-p b))
            "a gram fact keeps its asserted belief, unprojected")))))

;;; ------------------------------------------------------------------
;;; The other systems are untouched
;;; ------------------------------------------------------------------

(deftest frame-does-not-disturb-the-other-systems ()
  ;; D2: the Barnett system stays, and switching away from the frame must restore its
  ;; numbers exactly. Guards against pool state or projection leaking across systems.
  (frame-run 'lisa-user::culture-1)
  (let ((ds (run-scenario 'lisa-user::culture-1 :dempster-shafer)))
    (check-ds ds "pseudomonas" 0.76 1.00)
    (check-ds ds "klebsiella" 0.40 1.00))
  (let ((cf (run-scenario 'lisa-user::culture-1 :certainty-factors)))
    (check-cf cf "pseudomonas" 0.76)
    (check-cf cf "klebsiella" 0.40)))