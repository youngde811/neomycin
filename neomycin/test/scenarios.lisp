;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: neomycin's OWN end-to-end golden-master tests, validating
;; neomycin/rulebase.lisp (the canonical rulebase) under both belief systems.
;; Forked from Lisa's tests/scenarios.lisp: as of Slice 0 the values are identical
;; to Lisa's, but neomycin's rulebase diverges from examples/mycin.lisp once rules
;; are re-parented (chained cluster; docs/chaining-belief-spike.md §7.1), so these
;; goldens live here and move independently of Lisa's.
;; The expected values were captured from the engine and hand-verified; they are
;; the guardrail against regression.
;; The final tests assert *behavioral* properties (confirmatory evidence keeps
;; plausibility at 1.0; conflicting evidence drops it below 1.0; CF and DS agree
;; without conflict and diverge with it) rather than just numbers.

(in-package "LISA-TEST")

;;; ------------------------------------------------------------------
;;; Certainty factors
;;; ------------------------------------------------------------------

(deftest cf-culture-1 ()
  (let ((c (run-scenario 'lisa-user::culture-1 :certainty-factors)))
    (check-cf c "pseudomonas" 0.76)
    (check-cf c "klebsiella" 0.40)             ; chained via organism-class: 0.8*0.5
    (check-absent c "enterobacteriaceae")      ; C2: family is a CLASS, not a leaf identity
    (check-absent c "bacteroides")))

(deftest cf-culture-1a ()
  (let ((c (run-scenario 'lisa-user::culture-1a :certainty-factors)))
    (check-cf c "pseudomonas" 0.88)
    (check-cf c "klebsiella" 0.688)          ; chained: (0.8*0.6) combine (0.8*0.5)
    (check-absent c "enterobacteriaceae")))  ; C2: family is a CLASS, not a leaf identity

(deftest cf-culture-2 ()
  ;; Ambiguous gram stain: disconfirming rules fire, lowering both hypotheses.
  (let ((c (run-scenario 'lisa-user::culture-2 :certainty-factors)))
    (check-cf c "bacteroides" 0.674419)
    (check-cf c "pseudomonas" 0.588837)))

(deftest cf-culture-3 ()
  (let ((c (run-scenario 'lisa-user::culture-3 :certainty-factors)))
    (check-cf c "streptococcus-pneumoniae" 0.525)   ; chained after slice B: 0.7*0.75
    ;; Slice A: streptococcus and enterococcus are genus CLASSes now, not leaf
    ;; identities (the same move C2 made for enterobacteriaceae). Their class-side
    ;; coverage lives in chain-tests.lisp. No enterococcus SPECIES appears because
    ;; culture-3 runs no sugar tests.
    (check-absent c "streptococcus")
    (check-absent c "enterococcus")))

(deftest cf-culture-4 ()
  ;; Gram-positive differential: two rules refine the same streptococcus class along
  ;; different axes -- biochemical (beta + bacitracin-sensitive -> S. pyogenes, 0.595)
  ;; and clinical (respiratory site -> S. pneumoniae, 0.525). Slice C's beta-hemolysis
  ;; rule then argues against the alpha-hemolytic pneumococcus at -0.75.
  ;;
  ;; Under CF the pneumococcus collapses to a single NEGATIVE number:
  ;; (0.525 - 0.75) / (1 - 0.525) = -0.473684. That reads as "disbelieved" and stops
  ;; there -- it cannot distinguish evidence-against from room-left-over. Compare
  ;; ds-culture-4, where the same evidence yields a bounded interval.
  (let ((c (run-scenario 'lisa-user::culture-4 :certainty-factors)))
    (check-cf c "streptococcus-pyogenes" 0.595)
    (check-cf c "streptococcus-pneumoniae" -0.473684)))

(deftest cf-culture-5 ()
  ;; Host factor REINFORCING a biochemical call rather than contradicting it: the
  ;; biochemical path (beta + bacitracin-resistant, 0.49) and the host-factor path
  ;; (neonate + beta-hemolytic, 0.49) both reach S. agalactiae and combine to
  ;; 0.49 + 0.49 - 0.49*0.49 = 0.7399. No conflict, so CF and DS agree exactly --
  ;; the deliberate counterpart to culture-4, where two paths reached mutually
  ;; exclusive species and the algebras diverged.
  (let ((c (run-scenario 'lisa-user::culture-5 :certainty-factors)))
    (check-cf c "streptococcus-agalactiae" 0.7399)))

;;; ------------------------------------------------------------------
;;; Dempster-Shafer
;;; ------------------------------------------------------------------

(deftest ds-culture-1 ()
  (let ((c (run-scenario 'lisa-user::culture-1 :dempster-shafer)))
    (check-ds c "pseudomonas" 0.76 1.00)
    (check-ds c "klebsiella" 0.40 1.00)       ; chained via organism-class: 0.8*0.5
    (check-absent c "enterobacteriaceae")))   ; C2: family is a CLASS, not a leaf identity

(deftest ds-culture-1a ()
  (let ((c (run-scenario 'lisa-user::culture-1a :dempster-shafer)))
    (check-ds c "pseudomonas" 0.88 1.00)
    (check-ds c "klebsiella" 0.688 1.00)      ; chained: (0.8*0.6) combine (0.8*0.5)
    (check-absent c "enterobacteriaceae")))   ; C2: family is a CLASS, not a leaf identity

(deftest ds-culture-2 ()
  ;; The conflict scenario: plausibility drops below 1.0 on both hypotheses.
  (let ((c (run-scenario 'lisa-user::culture-2 :dempster-shafer)))
    (check-ds c "bacteroides" 0.688612 0.956406)
    (check-ds c "pseudomonas" 0.611217 0.945570)))

(deftest ds-culture-3 ()
  (let ((c (run-scenario 'lisa-user::culture-3 :dempster-shafer)))
    (check-ds c "streptococcus-pneumoniae" 0.525 1.00)  ; chained: 0.7*0.75
    (check-absent c "streptococcus")     ; slice A: genus CLASS, not a leaf identity
    (check-absent c "enterococcus")))    ; slice A: genus CLASS, not a leaf identity

(deftest ds-culture-4 ()
  ;; The slice C payoff, and the sharpest CF-vs-DS contrast in the corpus.
  ;;
  ;; A beta-hemolytic organism cannot be the alpha-hemolytic S. pneumoniae. Before
  ;; slice C both siblings sat at pl 1.0 with neither pulling the other down -- the
  ;; gap observed live on the enterobacteriaceae siblings before v0.5.0. Now the
  ;; beta-hemolysis rule (-0.75) meets the respiratory-site confirmation (0.525) and
  ;; Dempster produces real conflict: K = 0.525*0.75 = 0.39375, so
  ;;   bel = 0.13125/0.60625 = 0.216495,  pl = 1 - 0.35625/0.60625 = 0.412371.
  ;;
  ;; The interval says two things CF's single -0.473684 cannot: some belief survives
  ;; (the respiratory site genuinely did suggest pneumococcus) AND the ceiling has
  ;; dropped to 0.41 (the hemolysis caps how plausible it can now be).
  ;;
  ;; Conflict stays LOCALIZED: nothing argues against S. pyogenes, so it holds clean
  ;; at [0.595, 1.0] rather than being dragged down alongside its sibling.
  (let ((c (run-scenario 'lisa-user::culture-4 :dempster-shafer)))
    (check-ds c "streptococcus-pyogenes" 0.595 1.00)
    (check-ds c "streptococcus-pneumoniae" 0.216495 0.412371)))

(deftest ds-culture-5 ()
  ;; Confirmatory regime: nothing argues against S. agalactiae, so plausibility stays
  ;; at 1.0 and DS-bel equals the CF number. Two independent masses ADD rather than
  ;; conflict -- which is what distinguishes a host factor from a discriminator.
  (let ((c (run-scenario 'lisa-user::culture-5 :dempster-shafer)))
    (check-ds c "streptococcus-agalactiae" 0.7399 1.00)))

;;; ------------------------------------------------------------------
;;; Behavioral properties (the reasoning content, not just the numbers)
;;; ------------------------------------------------------------------

(deftest ds-confirmatory-keeps-full-plausibility ()
  ;; No rule argues *against* anything in culture-1, so every hypothesis keeps
  ;; pl = 1.0 — the regime in which DS carries no more than CF does.
  (let ((c (run-scenario 'lisa-user::culture-1 :dempster-shafer)))
    (dolist (name '("pseudomonas" "klebsiella"))
      (is (approx= (belief:ds-belief-pl (belief-of c name)) 1.0)
          (format nil "~A plausibility should be 1.0 in the confirmatory regime" name)))))

(deftest ds-conflict-drops-plausibility ()
  ;; The ambiguous stain fires a disconfirming rule, so plausibility < 1.0.
  (let ((c (run-scenario 'lisa-user::culture-2 :dempster-shafer)))
    (dolist (name '("bacteroides" "pseudomonas"))
      (is (< (belief:ds-belief-pl (belief-of c name)) 1.0)
          (format nil "~A plausibility should fall below 1.0 under conflict" name)))))

(deftest cf-and-ds-agree-without-conflict ()
  ;; Without disconfirming evidence, DS belief equals the CF number.
  (let ((cf (run-scenario 'lisa-user::culture-1 :certainty-factors))
        (ds (run-scenario 'lisa-user::culture-1 :dempster-shafer)))
    (dolist (name '("pseudomonas" "klebsiella"))
      (is (approx= (belief-of cf name) (belief:ds-belief-bel (belief-of ds name)))
          (format nil "~A: CF and DS-bel should match on confirmatory evidence" name)))))

(deftest cf-and-ds-diverge-under-conflict ()
  ;; Under conflict, Dempster renormalization keeps belief above the CF number
  ;; (it redistributes conflict mass rather than simply subtracting it).
  (let ((cf (run-scenario 'lisa-user::culture-2 :certainty-factors))
        (ds (run-scenario 'lisa-user::culture-2 :dempster-shafer)))
    (is (> (belief:ds-belief-bel (belief-of ds "bacteroides"))
           (belief-of cf "bacteroides"))
        "DS belief should exceed CF under conflict (bacteroides)")
    (is (> (belief:ds-belief-bel (belief-of ds "pseudomonas"))
           (belief-of cf "pseudomonas"))
        "DS belief should exceed CF under conflict (pseudomonas)")))

;;; ------------------------------------------------------------------
;;; Multi-organism lineage scoping (the reason the context tree exists)
;;; ------------------------------------------------------------------

(deftest multi-organism-identities-stay-scoped ()
  ;; Two organisms in one culture. o2 (gram-pos coccus in clumps, coagulase-POSITIVE)
  ;; must be identified as S. aureus -- chained through the staphylococcus class, so
  ;; 0.7*0.85 = 0.595 -- scoped to o2 and NOT leaking onto o1, the property the flat
  ;; rulebase silently violated. o1 (a bare aerobic gram-neg rod) produces NO leaf
  ;; identity after C2, only the enterobacteriaceae CLASS, so the sole organism-identity
  ;; in play must sit on o2 alone.
  ;;
  ;; Slice A had left this test asserting mere emptiness (both organisms stopped at
  ;; their genus); the coagulase slice B added to the driver restores the real
  ;; identity-level scoping assertion.
  (let ((ids (run-scenario-identities 'lisa-user::culture-multi :dempster-shafer))
        (o1 (lu "o1")) (o2 (lu "o2")))
    (is (identity-on-p ids "staphylococcus-aureus" o2)
        "o2 should be identified as staphylococcus-aureus")
    (is (not (identity-on-p ids "staphylococcus-aureus" o1))
        "staphylococcus-aureus must NOT leak onto o1")
    (is (every (lambda (pair) (eq (cdr pair) o2)) ids)
        "o1 carries no leaf identity -- every organism-identity is scoped to o2")))