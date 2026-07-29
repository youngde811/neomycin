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
    (check-cf c "enterobacteriaceae" 0.80)   ; family-level identity, still one-hop (Slice A)
    (check-cf c "klebsiella" 0.40)           ; chained via organism-class: 0.8*0.5
    (check-absent c "bacteroides")))

(deftest cf-culture-1a ()
  (let ((c (run-scenario 'lisa-user::culture-1a :certainty-factors)))
    (check-cf c "pseudomonas" 0.88)
    (check-cf c "klebsiella" 0.688)          ; chained: (0.8*0.6) combine (0.8*0.5)
    (check-cf c "enterobacteriaceae" 0.80)))

(deftest cf-culture-2 ()
  ;; Ambiguous gram stain: disconfirming rules fire, lowering both hypotheses.
  (let ((c (run-scenario 'lisa-user::culture-2 :certainty-factors)))
    (check-cf c "bacteroides" 0.674419)
    (check-cf c "pseudomonas" 0.588837)))

(deftest cf-culture-3 ()
  (let ((c (run-scenario 'lisa-user::culture-3 :certainty-factors)))
    (check-cf c "streptococcus" 0.70)
    (check-cf c "streptococcus-pneumoniae" 0.75)
    (check-cf c "enterococcus" 0.70)))

;;; ------------------------------------------------------------------
;;; Dempster-Shafer
;;; ------------------------------------------------------------------

(deftest ds-culture-1 ()
  (let ((c (run-scenario 'lisa-user::culture-1 :dempster-shafer)))
    (check-ds c "pseudomonas" 0.76 1.00)
    (check-ds c "enterobacteriaceae" 0.80 1.00)
    (check-ds c "klebsiella" 0.40 1.00)))    ; chained via organism-class: 0.8*0.5

(deftest ds-culture-1a ()
  (let ((c (run-scenario 'lisa-user::culture-1a :dempster-shafer)))
    (check-ds c "pseudomonas" 0.88 1.00)
    (check-ds c "klebsiella" 0.688 1.00)     ; chained: (0.8*0.6) combine (0.8*0.5)
    (check-ds c "enterobacteriaceae" 0.80 1.00)))

(deftest ds-culture-2 ()
  ;; The conflict scenario: plausibility drops below 1.0 on both hypotheses.
  (let ((c (run-scenario 'lisa-user::culture-2 :dempster-shafer)))
    (check-ds c "bacteroides" 0.688612 0.956406)
    (check-ds c "pseudomonas" 0.611217 0.945570)))

(deftest ds-culture-3 ()
  (let ((c (run-scenario 'lisa-user::culture-3 :dempster-shafer)))
    (check-ds c "streptococcus" 0.70 1.00)
    (check-ds c "streptococcus-pneumoniae" 0.75 1.00)
    (check-ds c "enterococcus" 0.70 1.00)))

;;; ------------------------------------------------------------------
;;; Behavioral properties (the reasoning content, not just the numbers)
;;; ------------------------------------------------------------------

(deftest ds-confirmatory-keeps-full-plausibility ()
  ;; No rule argues *against* anything in culture-1, so every hypothesis keeps
  ;; pl = 1.0 — the regime in which DS carries no more than CF does.
  (let ((c (run-scenario 'lisa-user::culture-1 :dempster-shafer)))
    (dolist (name '("pseudomonas" "enterobacteriaceae" "klebsiella"))
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
    (dolist (name '("pseudomonas" "enterobacteriaceae" "klebsiella"))
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
  ;; Two organisms in one culture: o1 (aerobic gram-neg rod) must be ONLY
  ;; enterobacteriaceae; o2 (gram-pos coccus in clumps) must be ONLY
  ;; staphylococcus. Neither identity may leak onto the sibling organism --
  ;; the property the flat rulebase silently violated.
  (let ((ids (run-scenario-identities 'lisa-user::culture-multi :dempster-shafer))
        (o1 (lu "o1")) (o2 (lu "o2")))
    (is (identity-on-p ids "enterobacteriaceae" o1)
        "o1 should be identified as enterobacteriaceae")
    (is (identity-on-p ids "staphylococcus" o2)
        "o2 should be identified as staphylococcus")
    (is (not (identity-on-p ids "staphylococcus" o1))
        "staphylococcus must NOT leak onto o1")
    (is (not (identity-on-p ids "enterobacteriaceae" o2))
        "enterobacteriaceae must NOT leak onto o2")))