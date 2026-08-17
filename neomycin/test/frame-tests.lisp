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

(deftest frame-culture-1a ()
  ;; Hospital-acquired rather than burn, so a third pseudomonas rule (0.7) fires and
  ;; cautious accumulation keeps the strongest of the three.
  (let ((c (frame-run 'lisa-user::culture-1a)))
    (check-ds c "pseudomonas" 0.482759 0.689655)
    (check-ds c "klebsiella"  0.310345 0.517241)))

(deftest frame-culture-2 ()
  ;; The ambiguous gram stain: evidence enters with an explicit 0.8/0.2 belief, so the
  ;; raw premise strength is below 1 and every contribution is scaled by it.
  (let ((c (frame-run 'lisa-user::culture-2)))
    (check-ds c "bacteroides" 0.552129 0.766846)
    (check-ds c "pseudomonas" 0.198200 0.412917)))

(deftest frame-culture-3 ()
  (let ((c (frame-run 'lisa-user::culture-3)))
    (check-ds c "streptococcus-pneumoniae" 0.473684 0.631579)))

(deftest frame-culture-4 ()
  ;; The sharpest contrast with the Barnett system. There, the beta-hemolysis rule
  ;; drove S. pneumoniae to [0.216, 0.412] while S. pyogenes sat at [0.595, 1.0] --
  ;; the two never interacting. Here they compete for one pool: pyogenes rises to
  ;; 0.764 BECAUSE pneumoniae falls to 0.101, and pyogenes' plausibility is capped at
  ;; 0.899 by the mass pneumoniae still holds.
  (let ((c (frame-run 'lisa-user::culture-4)))
    (check-ds c "streptococcus-pyogenes"   0.764045 0.898876)
    (check-ds c "streptococcus-pneumoniae" 0.101124 0.134831)))

(deftest frame-culture-5 ()
  ;; Two rules, one observation (hemolysis=beta), one conclusion. Cautious accumulation
  ;; keeps 0.70 where the conjunctive operator would compound to 0.91.
  (let ((c (frame-run 'lisa-user::culture-5)))
    (check-ds c "streptococcus-agalactiae" 0.70 1.0)))

(deftest frame-conflict-goldens ()
  ;; K per scenario, read unnormalized from the pool. Worth pinning: it is the number
  ;; that says how much the corpus disagreed with itself, and a rule change that
  ;; quietly increases disagreement should show up here rather than only in a belief.
  (dolist (pair '((lisa-user::culture-1  . 0.300000)
                  (lisa-user::culture-1a . 0.420000)
                  (lisa-user::culture-2  . 0.416832)
                  (lisa-user::culture-3  . 0.525000)
                  (lisa-user::culture-4  . 0.721875)
                  (lisa-user::culture-5  . 0.000000)))
    (frame-run (car pair))
    (is (approx= (belief:pool-conflict (the-pool)) (cdr pair))
        (format nil "~A: expected K = ~,6F, got ~,6F"
                (car pair) (cdr pair) (belief:pool-conflict (the-pool))))))

(deftest frame-class-projection-goldens ()
  ;; A class's Bel is the mass settled inside the family. culture-4 is the instructive
  ;; one: Bel(streptococcus) = 0.865 is pyogenes 0.764 PLUS pneumoniae 0.101 -- the
  ;; genus is far better supported than either species, which is exactly the statement
  ;; a taxonomic hypothesis should be able to make and a per-hypothesis frame cannot.
  (frame-run 'lisa-user::culture-4)
  (let ((m (pool-projection)))
    (is (approx= (belief:mass-belief m :streptococcus) 0.865169)
        "Bel(streptococcus) sums its members")
    (is (approx= (belief:mass-plausibility m :streptococcus) 1.0)
        "and nothing argues the organism is outside the genus")))

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
;;; ------------------------------------------------------------------
;;; Slice F -- what the bridge reports
;;;
;;; These exercise the serializers directly (the same Lisp path the handlers run,
;;; minus HTTP), which is how therapy-bridge-tests.lisp covers /recommend-therapy.
;;; ------------------------------------------------------------------

(deftest frame-conclusions-carry-a-projection ()
  ;; The per-fact payload cannot show an organism no rule concluded, mass sitting on a
  ;; SET, or how much conflict was renormalized away. The frame block adds all three
  ;; ALONGSIDE the existing payload, so nothing reading /conclusions today changes.
  (frame-run 'lisa-user::culture-1)
  (let ((frame (lisa-bridge::frame-projection->json)))
    (is frame "a frame-based run reports a projection")
    (when frame
      (is (= 18 (length (gethash "elements" frame)))
          "every frame element is listed, concluded or not")
      (let* ((entities (gethash "entities" frame))
             (e (aref entities 0)))
        (is (= 1 (length entities)) "culture-1 has one organism entity")
        (is (approx= (gethash "conflict" e) 0.30)
            "K is reported UNNORMALIZED -- the mass Dempster renormalized away")
        (is (string= (gethash "operator" e) "cautious"))
        (is (= 18 (length (gethash "hypotheses" e)))
            "every hypothesis is projected, including those with no fact")
        (is (plusp (length (gethash "set_valued" e)))
            "the set-valued conclusion is reported")))))

(deftest frame-projection-reports-squeezed-organisms ()
  ;; The payload's whole reason for existing: S. aureus has no fact in working memory,
  ;; so the per-fact list cannot mention it, yet the evidence has constrained it.
  (frame-run 'lisa-user::culture-1)
  (let* ((frame (lisa-bridge::frame-projection->json))
         (e (aref (gethash "entities" frame) 0))
         (aureus (find "staphylococcus-aureus" (gethash "hypotheses" e)
                       :key (lambda (h) (gethash "value" h)) :test #'string=)))
    (is aureus "an organism no rule concluded still appears in the projection")
    (when aureus
      (is (zerop (gethash "bel" aureus)) "with no positive belief")
      (is (< (gethash "pl" aureus) 0.99) "but a plausibility the evidence has lowered"))))

(deftest frame-conclusions-omit-projection-under-other-systems ()
  ;; No false claims: the frame block must not appear when no frame is driving the
  ;; numbers, or a reader would take a stale projection for the live one.
  (run-scenario 'lisa-user::culture-1 :dempster-shafer)
  (is (null (lisa-bridge::frame-projection->json))
      "the Barnett system reports no frame projection")
  (run-scenario 'lisa-user::culture-1 :certainty-factors)
  (is (null (lisa-bridge::frame-projection->json))
      "certainty factors report no frame projection"))

(deftest frame-why-names-the-supported-set ()
  ;; /why must be able to say WHICH hypotheses a firing supported. The scalar
  ;; before/after pair cannot; `supports` can.
  (frame-run 'lisa-user::culture-1)
  (let* ((fact (lisa-bridge::find-organism-identity-fact :klebsiella))
         (json (lisa-bridge::derivation-record->json
                (first (lisa:fact-derivation (lisa:inference-engine) fact)))))
    (is (equalp #("klebsiella") (gethash "supports" json))
        "the firing names the set it committed mass to")
    (is (approx= (gethash "focal_mass" json) 0.5) "and how much")
    (is (approx= (gethash "conflict_after" json) 0.30) "and the pool's K after it")))

(deftest frame-why-narrates-sets-not-scalar-arithmetic ()
  ;; Under a frame a firing does NOT multiply one hypothesis by a factor, so narrating
  ;; "0.8 composed with 0.5 = 0.40" would describe an operation that did not happen.
  ;; The composition string states what actually occurred instead.
  (frame-run 'lisa-user::culture-1)
  (let* ((fact (lisa-bridge::find-organism-identity-fact :klebsiella))
         (composition (gethash "composition"
                               (lisa-bridge::derivation-record->json
                                (first (lisa:fact-derivation (lisa:inference-engine) fact))))))
    (is (search "committed" composition) "it says what was committed")
    (is (search "klebsiella" composition) "and to which set")
    (is (not (search "composed with" composition))
        "and does not claim a multiplication the frame never performed")))

(deftest frame-rules-catalogue-reports-focal-sets ()
  ;; Now that the engine acts on focal sets, /rules can honestly report them. `source`
  ;; separates a rule that DECLARES its set from one falling back to what it asserts --
  ;; the distinction slice D's audit turns on.
  (belief:use-system :frame)
  (let* ((declared (lisa-bridge::rule->json
                    (lisa:find-rule (lisa:inference-engine)
                                    'lisa-user::aerobic-gram-neg-rod-suggests-enterobacteriaceae-class)))
         (fallback (lisa-bridge::rule->json
                    (lisa:find-rule (lisa:inference-engine)
                                    'lisa-user::enterobacteriaceae-lactose-pos-indole-pos-suggests-e-coli)))
         (df (gethash "focal_set" declared))
         (ff (gethash "focal_set" fallback)))
    (is df "a rule reports its focal set")
    (when df
      (is (string= (gethash "source" df) "supports") "declared via :supports")
      (is (= 8 (gethash "size" df)) "the widened aerobic gram-negative rod set")
      (is (find "pseudomonas" (gethash "supports" df) :test #'string=)
          "which includes pseudomonas -- the slice D correction"))
    (when ff
      (is (string= (gethash "source" ff) "asserted")
          "an unconverted rule falls back to what it asserts")
      (is (= 1 (gethash "size" ff))))))

(deftest frame-therapy-runs-unchanged ()
  ;; Design 8's promise: because a fact carries a PROJECTED interval in the existing
  ;; representation, the therapy phase needs no change at all. Set-valued hypotheses
  ;; reaching the solver directly is deliberately left to a later phase.
  (frame-run 'lisa-user::culture-1)
  (therapy:use-solver :exact)
  (let* ((conclusions (therapy::conclusions-for-solver))
         (rec (therapy:recommend conclusions (therapy::therapy-kb) nil)))
    (is (= 2 (length conclusions)) "both organisms reach the solver")
    (dolist (pair conclusions)
      (is (belief:ds-belief-p (cdr pair))
          (format nil "~S arrives as a projected interval" (car pair))))
    (is rec "a regimen is produced under the frame system")
    (is (null (therapy:recommendation-uncovered rec)) "and it covers both organisms")))
