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
;; iterate LISA::GET-RULE-LIST, so a 51st rule is checked automatically.
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
;;; Introspection helpers over the compiled rulebase.
;;; ------------------------------------------------------------------

(defparameter *reporting-rules* '(lisa-user::conclusion)
  "Rules that carry no domain knowledge and are exempt from the knowledge-rule
   invariants (the same exemption provenance-tests.lisp makes).")

(defun domain-rules ()
  "Every knowledge-bearing rule in the compiled rulebase. Matches on RULE-SHORT-NAME:
   LISA:RULE-NAME is module-qualified (INITIAL-CONTEXT.CONCLUSION), so the short name
   is what compares against a LISA-USER symbol -- the same accessor
   provenance-tests.lisp uses for its exemption."
  (remove-if (lambda (r) (member (lisa:rule-short-name r) *reporting-rules*))
             (lisa::get-rule-list (lisa:inference-engine))))

(defun rule-asserted-facts (rule)
  "((class-symbol . value) ...) for each fact RULE asserts on its RHS."
  (let ((acc '()))
    (dolist (action (lisa::rule-actions-actions (lisa::rule-actions rule)) (nreverse acc))
      ;; Shape: (LISA:ASSERT (class (slot value) ...))
      (when (and (consp action) (eq (first action) 'lisa:assert))
        (let* ((form (second action))
               (class (first form))
               (value (second (assoc 'lisa-user::value (rest form)))))
          (push (cons class value) acc))))))

(defun rule-premise-classes (rule)
  "The fact classes RULE matches on its LHS (test patterns excluded)."
  (remove nil
          (mapcar (lambda (p)
                    (unless (eq (lisa::parsed-pattern-type p) :test)
                      (lisa::parsed-pattern-class p)))
                  (lisa::rule-patterns rule))))

(defun rule-premise-values (rule class)
  "The literal VALUE slots RULE matches for premise facts of CLASS."
  (let ((acc '()))
    (dolist (p (lisa::rule-patterns rule) (nreverse acc))
      (when (and (not (eq (lisa::parsed-pattern-type p) :test))
                 (eq (lisa::parsed-pattern-class p) class))
        (dolist (slot (lisa::parsed-pattern-slots p))
          (when (eq (lisa::pattern-slot-name slot) 'lisa-user::value)
            (let ((v (lisa::pattern-slot-value slot)))
              (when (keywordp v) (push v acc)))))))))

(defun rule-member-test-values (rule)
  "Values named in RULE's (test (member ?value '(...))) patterns, flattened."
  (let ((acc '()))
    (dolist (p (lisa::rule-patterns rule) acc)
      (when (eq (lisa::parsed-pattern-type p) :test)
        (dolist (form (lisa::parsed-pattern-slots p))
          ;; Shape: (MEMBER ?VALUE '(:A :B ...))
          (when (and (consp form) (eq (first form) 'member))
            (let ((quoted (third form)))
              (when (and (consp quoted) (eq (first quoted) 'quote))
                (setf acc (append acc (second quoted)))))))))))

(defun disconfirming-rule-p (rule)
  (let ((b (lisa::belief-factor rule)))
    (and (realp b) (minusp b))))

(defun confirming-rule-p (rule)
  (let ((b (lisa::belief-factor rule)))
    (and (realp b) (plusp b))))

(defun concluded-values (class &key (predicate #'confirming-rule-p))
  "Every VALUE asserted as a CLASS fact by a rule satisfying PREDICATE."
  (let ((acc '()))
    (dolist (rule (domain-rules) (remove-duplicates acc))
      (when (funcall predicate rule)
        (dolist (pair (rule-asserted-facts rule))
          (when (eq (car pair) class) (pushnew (cdr pair) acc)))))))

;;; ------------------------------------------------------------------
;;; Invariant 1 -- every domain rule declares a usable belief.
;;; ------------------------------------------------------------------

(deftest property-every-rule-belief-is-in-range ()
  ;; A belief outside [-1, 1] is meaningless to both algebras, and a zero belief is
  ;; a rule that cannot affect any conclusion -- almost certainly an authoring slip.
  ;; DS additionally clamps defensively at combination time; this catches the problem
  ;; at the source instead.
  (dolist (rule (domain-rules))
    (let ((b (lisa::belief-factor rule)))
      (is (and (realp b) (<= -1 b 1) (not (zerop b)))
          (format nil "~A: belief ~S must be a non-zero real in [-1, 1]"
                  (lisa:rule-short-name rule) b)))))

;;; ------------------------------------------------------------------
;;; Invariant 2 -- disconfirming rules follow the ruling-out template.
;;; ------------------------------------------------------------------

(deftest property-disconfirming-rules-reassert-what-they-match ()
  ;; The established pattern (corpus sketch §2): a ruling-out rule keys off a LIVE
  ;; hypothesis plus a contradicting parameter on the same organism, then RE-ASSERTS
  ;; that hypothesis with a negative belief. A negative-belief rule that asserted
  ;; something it does not also match would not be disconfirming anything -- it would
  ;; be quietly creating a hypothesis with negative mass.
  (dolist (rule (domain-rules))
    (when (disconfirming-rule-p rule)
      (let ((asserted (mapcar #'car (rule-asserted-facts rule)))
            (matched (rule-premise-classes rule)))
        (is (and asserted (every (lambda (c) (member c matched)) asserted))
            (format nil "~A: disconfirming rule must re-assert a fact type it matches ~
                         (asserts ~S, matches ~S)"
                    (lisa:rule-short-name rule) asserted matched))))))

(deftest property-disconfirming-rules-name-only-reachable-identities ()
  ;; THE STALENESS GUARD, and the reason this file exists.
  ;;
  ;; Ruling-out rules select their targets with (test (member ?value '(...))). When a
  ;; species is renamed, retired, or promoted from a leaf identity to an organism-class
  ;; -- which happened three times in this increment and once in C2 -- those literal
  ;; lists go stale SILENTLY: the rule still compiles, still fires, and simply never
  ;; matches the dead value again. Nothing else in the suite notices, because a
  ;; disconfirming rule that quietly stops disconfirming still passes every golden
  ;; that does not exercise it.
  ;;
  ;; So: every value a disconfirming rule names must be a value some confirming rule
  ;; can actually conclude.
  (let ((reachable (concluded-values 'lisa-user::organism-identity)))
    (dolist (rule (domain-rules))
      (when (disconfirming-rule-p rule)
        (dolist (value (rule-member-test-values rule))
          (is (member value reachable)
              (format nil "~A: names ~S, which NO confirming rule concludes ~
                           (retired, renamed, or promoted to an organism-class?)"
                      (lisa:rule-short-name rule) value)))))))

;;; ------------------------------------------------------------------
;;; Invariant 3 -- the chained clusters are wired end to end.
;;; ------------------------------------------------------------------

(deftest property-every-organism-class-is-consumed ()
  ;; A derived organism-class exists to be refined. One that no rule reads as a
  ;; premise is an intermediate that leads nowhere: belief accumulates on it and
  ;; stops, and (because /conclusions reports identities only) it becomes invisible
  ;; except as a therapy backstop. That is a real failure mode -- it is exactly the
  ;; state slice A left the gram-positive genera in before slice B refined them --
  ;; so the wiring is asserted rather than assumed.
  (let ((concluded (concluded-values 'lisa-user::organism-class))
        (consumed '()))
    (dolist (rule (domain-rules))
      (setf consumed
            (append consumed (rule-premise-values rule 'lisa-user::organism-class))))
    (dolist (class concluded)
      (is (member class consumed)
          (format nil "organism-class ~S is concluded but never read as a premise ~
                       -- a dead-end intermediate" class)))))

(deftest property-every-chained-species-reads-a-real-class ()
  ;; The mirror image: a rule that refines FROM a class must name a class some rule
  ;; actually concludes. A typo here yields a rule that can never fire, which no
  ;; golden would catch (an absent conclusion looks like an unexercised path).
  (let ((concluded (concluded-values 'lisa-user::organism-class)))
    (dolist (rule (domain-rules))
      (dolist (class (rule-premise-values rule 'lisa-user::organism-class))
        (is (member class concluded)
            (format nil "~A: reads organism-class ~S, which no rule concludes"
                    (lisa:rule-short-name rule) class))))))

;;; ------------------------------------------------------------------
;;; Invariant 4 -- the corpus keeps its DS-stressing shape (sketch §6).
;;; ------------------------------------------------------------------

(deftest property-corpus-retains-disconfirming-mass ()
  ;; "Shape is the spec; size is a byproduct." A corpus that grows only confirmatory
  ;; rules leaves plausibility pinned at 1.0 and DS collapses toward CF, which would
  ;; quietly defeat the reason this fork exists. The sketch's guidance is to pair
  ;; disconfirming rules with each new confirming cluster; this asserts the corpus
  ;; has not drifted away from that. The floor (20%) is well below the current ratio
  ;; -- it is a drift alarm, not a target to optimize.
  (let* ((rules (domain-rules))
         (total (length rules))
         (disconfirming (count-if #'disconfirming-rule-p rules)))
    (is (>= (/ disconfirming total) 1/5)
        (format nil "only ~D of ~D rules are disconfirming (~,1F%) -- below the 20% ~
                     floor; new confirming clusters need paired ruling-out rules ~
                     (corpus-expansion-sketch.md §6)"
                disconfirming total (* 100.0 (/ disconfirming total))))))