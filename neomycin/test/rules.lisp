;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: neomycin's OWN per-rule coverage, validating neomycin/rulebase.lisp.
;; Forked from Lisa's tests/rules.lisp (identical as of Slice 0; diverges once rules
;; are re-parented -- docs/chaining-belief-spike.md §7.1). Each rule is fired in
;; isolation on a minimal premise set that lets *only that rule* conclude the
;; target organism, and the resulting belief is asserted. Confirming rules
;; (1-15) must contribute exactly their :belief (CF) / [belief, 1.0] (DS); the
;; three disconfirming rules (16-18) must lower an existing hypothesis and pull
;; its plausibility below 1.0.

(in-package "LISA-TEST")

;;; Helper: assert the isolated confirming belief holds under BOTH algebras.
(defun check-rule (builder organism belief)
  "Run BUILDER under CF and DS; assert ORGANISM is concluded with BELIEF (CF)
   and [BELIEF, 1.0] (DS) — i.e. exactly this rule's contribution, alone."
  (check-cf (run-facts :certainty-factors builder) organism belief)
  (check-ds (run-facts :dempster-shafer builder) organism belief 1.0))

;;; ------------------------------------------------------------------
;;; Confirming rules (1-15) — fired in isolation
;;; ------------------------------------------------------------------

(deftest rule-gram-neg-rod-burn-pseudomonas ()      ; 0.4
  (check-rule (lambda (o p)
                (af "culture-site" "blood" *ctx-culture*)
                (af "gram" "neg" o) (af "morphology" "rod" o)
                (af "burn" "serious" p))
              "pseudomonas" 0.4))

(deftest rule-gram-pos-cocci-clumps-staphylococcus () ; 0.7
  (check-rule (lambda (o p) (declare (ignore p))
                (af "gram" "pos" o) (af "morphology" "coccus" o)
                (af "growth-conformation" "clumps" o))
              "staphylococcus" 0.7))

(deftest rule-anaerobic-gram-neg-rod-blood-bacteroides () ; 0.9
  (check-rule (lambda (o p) (declare (ignore p))
                (af "culture-site" "blood" *ctx-culture*)
                (af "gram" "neg" o) (af "morphology" "rod" o)
                (af "aerobicity" "anaerobic" o))
              "bacteroides" 0.9))

(deftest rule-gram-neg-rod-compromised-pseudomonas () ; 0.6
  (check-rule (lambda (o p)
                (af "gram" "neg" o) (af "morphology" "rod" o)
                (af "compromised-host" "t" p))
              "pseudomonas" 0.6))

;; The one-hop aerobic-gram-neg-rod -> enterobacteriaceae IDENTITY rule was retired
;; in C2 (enterobacteriaceae is now a class-only family). The same premises now
;; fire the tier-1 CLASS rule instead -- see chain-tier1-aerobic-gram-neg-rod-
;; enterobacteriaceae-class in chain-tests.lisp, which covers this evidence path.

(deftest rule-gram-pos-cocci-chains-streptococcus () ; 0.7
  (check-rule (lambda (o p) (declare (ignore p))
                (af "gram" "pos" o) (af "morphology" "coccus" o)
                (af "growth-conformation" "chains" o))
              "streptococcus" 0.7))

(deftest rule-hospital-gram-pos-cocci-clumps-staph-aureus () ; 0.8
  (check-rule (lambda (o p)
                (af "gram" "pos" o) (af "morphology" "coccus" o)
                (af "growth-conformation" "clumps" o)
                (af "hospital-acquired" "t" p))
              "staphylococcus-aureus" 0.8))

(deftest rule-hospital-compromised-klebsiella-combines () ; 0.688 = (0.8*0.6) combine (0.8*0.5)
  ;; NOT an isolation: with hospital-acquired + compromised, BOTH klebsiella rules
  ;; fire off the shared organism-class -- the hospital rule (0.8*0.6 = 0.48) and the
  ;; compromised rule (0.8*0.5 = 0.40) -- and their masses combine to 0.688 (this is
  ;; culture-1a's klebsiella). The hospital rule's premises are a superset of the
  ;; compromised rule's, so once both key off the class it cannot be fired alone; the
  ;; compromised rule IS isolated separately (rule-enterobacteriaceae-compromised-klebsiella).
  (check-rule (lambda (o p)
                (af "gram" "neg" o) (af "morphology" "rod" o)
                (af "aerobicity" "aerobic" o)
                (af "hospital-acquired" "t" p) (af "compromised-host" "t" p))
              "klebsiella" 0.688))

(deftest rule-hospital-aerobic-gram-neg-rod-pseudomonas () ; 0.7
  (check-rule (lambda (o p)
                (af "gram" "neg" o) (af "morphology" "rod" o)
                (af "aerobicity" "aerobic" o) (af "hospital-acquired" "t" p))
              "pseudomonas" 0.7))

(deftest rule-enterobacteriaceae-compromised-klebsiella () ; chained: 0.8*0.5 = 0.40
  ;; Tier-2: organism-class (0.8) + compromised host refines to klebsiella (rule 0.5) = 0.40.
  (check-rule (lambda (o p)
                (af "gram" "neg" o) (af "morphology" "rod" o)
                (af "aerobicity" "aerobic" o) (af "compromised-host" "t" p))
              "klebsiella" 0.40))

(deftest rule-respiratory-gram-pos-cocci-chains-strep-pneumoniae () ; 0.75
  (check-rule (lambda (o p)
                (af "gram" "pos" o) (af "morphology" "coccus" o)
                (af "growth-conformation" "chains" o)
                (af "infection-site" "respiratory" p))
              "streptococcus-pneumoniae" 0.75))

(deftest rule-enterobacteriaceae-travel-salmonella () ; chained: 0.8*0.65 = 0.52
  ;; Tier-2: organism-class (0.8) + tropical travel refines to salmonella (rule 0.65) = 0.52.
  (check-rule (lambda (o p)
                (af "gram" "neg" o) (af "morphology" "rod" o)
                (af "aerobicity" "aerobic" o)
                (af "recent-travel" "tropical" p))
              "salmonella" 0.52))

(deftest rule-gram-pos-cocci-chains-blood-compromised-enterococcus () ; 0.7
  (check-rule (lambda (o p)
                (af "culture-site" "blood" *ctx-culture*)
                (af "gram" "pos" o) (af "morphology" "coccus" o)
                (af "growth-conformation" "chains" o)
                (af "compromised-host" "t" p))
              "enterococcus" 0.7))

(deftest rule-enterobacteriaceae-blood-low-wbc-salmonella () ; chained: 0.8*0.55 = 0.44
  ;; Tier-2: organism-class (0.8) + blood + low WBC refines to salmonella (rule 0.55) = 0.44.
  (check-rule (lambda (o p)
                (af "culture-site" "blood" *ctx-culture*)
                (af "gram" "neg" o) (af "morphology" "rod" o)
                (af "aerobicity" "aerobic" o)
                (af "white-blood-count" "low" p))
              "salmonella" 0.44))

(deftest rule-anaerobic-gram-neg-rod-abdomen-bacteroides () ; 0.8
  (check-rule (lambda (o p)
                (af "gram" "neg" o) (af "morphology" "rod" o)
                (af "aerobicity" "anaerobic" o)
                (af "infection-site" "abdominal" p))
              "bacteroides" 0.8))

;;; ------------------------------------------------------------------
;;; Disconfirming rules (16-18) — must lower a live hypothesis (pl < 1.0)
;;; ------------------------------------------------------------------

(defun check-disconfirms (builder organism confirming-belief)
  "Run BUILDER under DS; assert ORGANISM is still present but its belief fell
   below CONFIRMING-BELIEF and its plausibility below 1.0 (a disconfirming rule
   fired). Also verify the CF belief dropped below the confirming value."
  (let ((ds (run-facts :dempster-shafer builder))
        (cf (run-facts :certainty-factors builder)))
    (let ((b (belief-of ds organism)))
      (cond ((null b) (record-fail "~A: expected present (disconfirmed), absent" organism))
            (t (is (< (belief:ds-belief-pl b) 1.0)
                   (format nil "~A plausibility should be < 1.0 after disconfirmation" organism))
               (is (< (belief:ds-belief-bel b) confirming-belief)
                   (format nil "~A belief should fall below ~,2F after disconfirmation"
                           organism confirming-belief)))))
    (is (< (belief-of cf organism) confirming-belief)
        (format nil "~A CF should fall below ~,2F after disconfirmation"
                organism confirming-belief))))

(deftest rule-gram-pos-argues-against-gram-neg-organism ()
  ;; A gram-positive reading disconfirms a gram-negative hypothesis (pseudomonas
  ;; established at 0.6 via the compromised-host rule).
  (check-disconfirms (lambda (o p)
                       (af "compromised-host" "t" p)
                       (af "gram" "neg" o) (af "morphology" "rod" o)
                       (af "gram" "pos" o))
                     "pseudomonas" 0.6))

(deftest rule-gram-neg-argues-against-gram-pos-organism ()
  ;; A gram-negative reading disconfirms a gram-positive hypothesis
  ;; (streptococcus established at 0.7 via the cocci-in-chains rule).
  (check-disconfirms (lambda (o p) (declare (ignore p))
                       (af "gram" "pos" o) (af "morphology" "coccus" o)
                       (af "growth-conformation" "chains" o)
                       (af "gram" "neg" o))
                     "streptococcus" 0.7))

(deftest rule-aerobic-argues-against-anaerobe ()
  ;; Aerobic growth disconfirms bacteroides (a strict anaerobe), established at
  ;; 0.9 via the anaerobic-blood rule; the contradictory aerobic fact fires the
  ;; ruling-out rule.
  (check-disconfirms (lambda (o p) (declare (ignore p))
                       (af "culture-site" "blood" *ctx-culture*)
                       (af "gram" "neg" o) (af "morphology" "rod" o)
                       (af "aerobicity" "anaerobic" o)
                       (af "aerobicity" "aerobic" o))
                     "bacteroides" 0.9))