;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: Corpus-wide PROPERTY tests -- invariants that must hold for EVERY
;; rule, checked by introspecting the compiled rulebase rather than by enumerating
;; rules by hand (corpus-expansion-sketch.md §8).
;;
;; WHY THIS FILE EXISTS. The sketch predicted that the golden-per-rule model is "the
;; thing that breaks first" once the corpus passes ~30-40 rules: nobody hand-verifies
;; hundreds of belief goldens, and capturing them from engine output just tests the
;; engine against itself. The answer it proposed is COMPLEMENTARY, not a replacement:
;; keep hand-verified goldens for every rule fired in isolation (which neomycin still
;; does, in rules.lisp and chain-tests.lisp), and add invariants that hold mechanically
;; across the whole corpus so new rules are covered the moment they are authored.
;;
;; These tests need no update when a rule is added -- that is the entire point. They
;; iterate LISA:GET-RULE-LIST through the engine's introspection API, so a 51st rule
;; is checked automatically.
;;
;; NOT DUPLICATED HERE:
;;   * "a confirming rule fired alone contributes exactly its :belief, and CF equals
;;     DS-bel with pl 1.0" -- already enforced everywhere by CHECK-RULE and
;;     CHECK-CLASS-RULE, which assert precisely that law for each isolated rule under
;;     BOTH algebras. Restating it here would test the harness, not the corpus.
;;   * provenance well-formedness -- see every-knowledge-rule-carries-well-formed-
;;     provenance in provenance-tests.lisp, which already iterates the whole rulebase.

(in-package "LISA-TEST")

;;; ------------------------------------------------------------------
;;; Corpus selection.
;;;
;;; The MECHANICAL introspection these tests are built on -- what a rule asserts,
;;; matches, and believes -- now lives in the engine as LISA:RULE-ASSERTED-FACTS
;;; and friends (src/core/rule-introspection.lisp), because /rules serves the same
;;; queries over HTTP and neither caller should be reaching through LISA:: for
;;; them. What stays here is the part that is a JUDGEMENT rather than a fact about
;;; the rulebase: which rules these invariants are about.
;;; ------------------------------------------------------------------

(defparameter *reporting-rules* '(lisa-user::conclusion)
  "Rules that carry no domain knowledge and are exempt from the knowledge-rule
   invariants (the same exemption provenance-tests.lisp makes).")

(defun domain-rules ()
  "Every knowledge-bearing rule in the compiled rulebase. Matches on RULE-SHORT-NAME:
   LISA:RULE-NAME is module-qualified (INITIAL-CONTEXT.CONCLUSION), so the short name
   is what compares against a LISA-USER symbol -- the same accessor
   provenance-tests.lisp uses for its exemption.

   Deliberately NOT LISA:KNOWLEDGE-RULE-P, which selects on `declares a belief'.
   That predicate is the right one for a client asking what the corpus contains,
   but using it here would make invariant 1 -- every domain rule declares a usable
   belief -- true by construction, and a rule that forgot its :belief would drop
   out of the population instead of failing the test."
  (remove-if (lambda (r) (member (lisa:rule-short-name r) *reporting-rules*))
             (lisa:get-rule-list (lisa:inference-engine))))

(defun candidates-rule-p (rule)
  "True when RULE asserts a CANDIDATES fact -- i.e. it states the SET its evidence
   narrows the answer to, which every rule in the corpus now does."
  (some (lambda (pair) (eq (car pair) 'lisa-user::candidates))
        (lisa:rule-asserted-facts rule)))

(defun candidates-rules ()
  (remove-if-not #'candidates-rule-p (domain-rules)))

(defun concluded-values (class &key (predicate #'lisa:confirming-rule-p))
  "Every VALUE asserted as a CLASS fact by a rule satisfying PREDICATE."
  (let ((acc '()))
    (dolist (rule (domain-rules) (remove-duplicates acc))
      (when (funcall predicate rule)
        (dolist (pair (lisa:rule-asserted-facts rule))
          (when (eq (car pair) class) (pushnew (cdr pair) acc)))))))

;;; ------------------------------------------------------------------
;;; Invariant 1 -- every domain rule declares a usable belief.
;;; ------------------------------------------------------------------

(deftest property-every-rule-declares-a-usable-belief ()
  ;; A rule must say how strongly it believes what it says. Positive and non-zero: a
  ;; rule states the SET its evidence narrows to, so direction is carried by which
  ;; organisms are in the answer, never by a sign. Zero would be a rule that cannot
  ;; affect any conclusion, which is almost certainly an authoring slip.
  (dolist (rule (domain-rules))
    (let ((b (lisa:rule-belief rule)))
      (is (and (realp b) (< 0 b) (<= b 1))
          (format nil "~A: belief ~S must be a real in (0, 1]"
                  (lisa:rule-short-name rule) b)))))

(deftest property-every-organism-an-answer-names-is-treatable ()
  ;; A rule may narrow to an organism the therapy KB cannot treat, directly or by
  ;; family roll-up -- and that gap would only surface when a clinician asked for a
  ;; regimen. Checked over every organism any answer names, so a new species cannot
  ;; land without its therapy wiring.
  (let ((kb (therapy::therapy-kb))
        (named '()))
    (dolist (rule (candidates-rules))
      (dolist (organism (or (rule-answer rule) '()))
        (pushnew organism named)))
    (is (plusp (length named)) "the corpus names organisms at all")
    (dolist (organism named)
      (is (or (some (lambda (drug) (therapy::kb-susceptibility kb drug organism))
                    (therapy::kb-drug-ids kb))
              (therapy::kb-family-of kb organism))
          (format nil "~S is named by a rule but is not treatable, directly or by ~
                       family roll-up" organism)))))

(defun rule-answer (rule)
  "The SET a rule asserts -- its answer -- canonicalized so two rules asserting the
   same set compare equal.

   The RHS writes the set QUOTED, since Lisa evaluates slot values, so what comes back
   from introspection is (QUOTE (...)) and has to be unwrapped."
  (let* ((pair (first (lisa:rule-asserted-facts rule)))
         (value (and pair (cdr pair)))
         (set (if (and (consp value) (eq (first value) 'quote))
                  (second value)
                  value)))
    (and (consp set) (every #'keywordp set) (candidates:canonical set))))

(defun same-conclusion-pairs ()
  "((rule-a rule-b) ...) for every pair of rules asserting the SAME answer."
  (let ((by-answer (make-hash-table :test #'equal))
        (acc '()))
    (dolist (rule (candidates-rules))
      (let ((answer (rule-answer rule)))
        (when answer (push rule (gethash answer by-answer)))))
    (maphash (lambda (answer rules)
               (declare (ignore answer))
               (loop for (a . rest) on rules
                     do (dolist (b rest) (push (list a b) acc))))
             by-answer)
    acc))

(deftest property-no-two-rules-share-identical-premises ()
  ;; If two rules reaching one conclusion had IDENTICAL premises they would be the
  ;; same observation written twice, and combining them would double-count. Measured
  ;; across the corpus: none do. This is what makes reinforcement the right default --
  ;; deduplicating by conclusion would always discard something real.
  (dolist (pair (same-conclusion-pairs))
    (destructuring-bind (a b) pair
      (is (not (equal (lisa:rule-premise-signature a)
                      (lisa:rule-premise-signature b)))
          (format nil "~A and ~A reach the same conclusion from IDENTICAL premises"
                  (lisa:rule-short-name a) (lisa:rule-short-name b))))))

(deftest property-subsumption-is-detected-where-it-exists ()
  ;; The one real case in the corpus: enterobacteriaceae-in-compromised-host-suggests-
  ;; klebsiella has premises that are a strict subset of the hospital-acquired variant,
  ;; so it fires whenever that one does and conditions on nothing extra. Pinned by
  ;; NAME because it is the case the specificity policy exists for -- if a corpus edit
  ;; breaks the relationship, that is worth knowing deliberately.
  (let ((general (lisa:find-rule (lisa:inference-engine)
                                 'lisa-user::compromised-aerobic-gram-neg-rod-narrows-to-klebsiella))
        (specific (lisa:find-rule (lisa:inference-engine)
                                  'lisa-user::hospital-acquired-compromised-aerobic-gram-neg-rod-narrows-to-klebsiella)))
    (is (and general specific) "both klebsiella context rules are present")
    (when (and general specific)
      (is (lisa:rule-subsumes-p specific general)
          "the hospital-acquired rule subsumes the general compromised-host one")
      (is (not (lisa:rule-subsumes-p general specific))
          "and subsumption is asymmetric, as it must be"))))

(deftest property-overlapping-premises-are-not-subsumption ()
  ;; The distinction I got wrong in phase 0.5 and that this invariant exists to hold:
  ;; sharing SOME premises is not being the same observation. The two pseudomonas
  ;; context rules both read a gram-negative rod, but one adds a burn and the other an
  ;; immunocompromised host -- different facts about the patient, so neither subsumes.
  (let ((burn (lisa:find-rule (lisa:inference-engine)
                              'lisa-user::burn-blood-gram-neg-rod-narrows-to-pseudomonas))
        (compromised (lisa:find-rule (lisa:inference-engine)
                                     'lisa-user::compromised-gram-neg-rod-narrows-to-pseudomonas)))
    (is (and burn compromised) "both pseudomonas context rules are present")
    (when (and burn compromised)
      (is (intersection (lisa:rule-premise-signature burn)
                        (lisa:rule-premise-signature compromised) :test #'string=)
          "they do share premises")
      (is (not (lisa:rule-subsumes-p burn compromised))
          "but neither subsumes the other, so their evidence is distinct")
      (is (not (lisa:rule-subsumes-p compromised burn))))))


;;; ------------------------------------------------------------------
;;; Invariant 11 -- the v0.11 rules must be citable BEFORE they are authoritative.
;;;
;;; The candidates rules were written as a spike and carry no :provenance. Every
;;; pre-v0.11 rule carries an origin, verified literature evidence and a belief-basis,
;;; and the WHY/HOW facility exists to quote them. Shipping a corpus that cannot cite
;;; itself would be a real regression, so rather than defer it quietly this fails the
;;; moment those rules become the default -- and stays silent while they are only a
;;; parallel shape under review.
;;; ------------------------------------------------------------------

