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

;; Description: A read-only introspection surface over the COMPILED rulebase --
;; what each rule concludes, what it matches on, and what belief it carries --
;; answered from the rule objects themselves rather than from the source text.
;;
;; This is the query half of the same idea as the derivation table: the
;; derivation table records what a rule DID when it fired; this records what a
;; rule IS, whether or not it has ever fired. Together they let a client explain
;; a corpus without a second, hand-maintained copy of it.
;;
;; Everything here is domain-neutral: these functions walk PARSED-PATTERN and
;; RULE-ACTIONS structures and know nothing about any particular rulebase. The
;; accessors they reach for are internal to the engine, which is exactly why this
;; lives in the engine -- a client that wants this information should not have to
;; reach through LISA:: to get it. Callers compose domain meaning on top.

(in-package :lisa)

;;; ------------------------------------------------------------------
;;; Belief.
;;; ------------------------------------------------------------------

(defun rule-belief (rule)
  "RULE's declared belief, or NIL if it declares none. Named for the rule axis to
   keep it distinct from BELIEF:BELIEF-FACTOR, which reads the belief attached to
   a FACT."
  (belief-factor rule))

(defun knowledge-rule-p (rule)
  "True when RULE asserts domain knowledge rather than performing bookkeeping
   (reporting, formatting, driving) -- i.e. it declares a belief OR states claims.
   A corpus-wide query almost always wants these and not, say, a salience -10 print
   rule."
  (realp (rule-belief rule)))

(defun confirming-rule-p (rule)
  "True when RULE argues FOR a hypothesis.

   A rule that narrows the answer to a set of hypotheses is confirming: it says what
   its evidence establishes, never what it denies."
  (let ((b (rule-belief rule)))
    (and (realp b) (plusp b))))

(defun disconfirming-rule-p (rule)
  "True when RULE argues AGAINST its conclusion -- a negative belief.

   No rule in neomycin's corpus does: exclusion is what remains when candidate-set
   answers are intersected, never something a rule asserts. Retained because the
   engine is domain-neutral and another knowledge base may still want the shape."
  (let ((b (rule-belief rule)))
    (and (realp b) (minusp b))))

;;; ------------------------------------------------------------------
;;; Conclusions (RHS).
;;; ------------------------------------------------------------------

(defun rule-asserted-facts (rule)
  "((class-symbol . value) ...), one entry per fact RULE asserts on its RHS.
   Only the VALUE slot is reported: it is the slot that carries the conclusion,
   the rest being context wiring (of, id)."
  (let ((acc '()))
    (dolist (action (rule-actions-actions (rule-actions rule)) (nreverse acc))
      ;; Shape: (LISA:ASSERT (class (slot value) ...))
      (when (and (consp action) (eq (first action) 'assert))
        (let* ((form (second action))
               (class (first form))
               ;; The value slot is looked up in the package of the class being
               ;; asserted, not a hardwired application package, so this reads any
               ;; application's rulebase rather than only LISA-USER's.
               (slot (and (symbolp class) (symbol-package class)
                          (find-symbol "VALUE" (symbol-package class))))
               (value (and slot (second (assoc slot (rest form))))))
          (push (cons class value) acc))))))

(defun rule-concludes-p (rule class &optional value)
  "True when RULE asserts a CLASS fact -- with VALUE, only when it asserts that
   particular value."
  (some (lambda (pair)
          (and (eq (car pair) class)
               (or (null value) (eql (cdr pair) value))))
        (rule-asserted-facts rule)))

;;; ------------------------------------------------------------------
;;; Premises (LHS).
;;; ------------------------------------------------------------------

(defun rule-premise-patterns (rule)
  "RULE's non-TEST patterns -- the fact matches, excluding predicate CEs."
  (remove-if (lambda (p) (eq (parsed-pattern-type p) :test))
             (rule-patterns rule)))

(defun rule-premise-classes (rule)
  "The fact classes RULE matches on its LHS, in pattern order."
  (mapcar #'parsed-pattern-class (rule-premise-patterns rule)))

(defun literal-slot-value-p (value)
  "True when VALUE is a literal a rule matched against, rather than a variable
   binding or a constraint form. (gram (value neg)) is a literal; (gram (value
   ?g)) binds and constrains nothing we can report as a value."
  (and value
       (or (keywordp value)
           (and (symbolp value) (not (variable-p value)))
           (numberp value)
           (stringp value))))

(defun rule-premise-values (rule class)
  "The literal VALUE slots RULE matches for premise facts of CLASS, in pattern
   order. Variables and constraint forms are skipped, so a rule that matches
   (gram (value ?g)) reports no value for GRAM."
  (let ((value-slot (and (symbolp class) (symbol-package class)
                         (find-symbol "VALUE" (symbol-package class))))
        (acc '()))
    (dolist (p (rule-premise-patterns rule) (nreverse acc))
      (when (eq (parsed-pattern-class p) class)
        (dolist (slot (parsed-pattern-slots p))
          (when (eq (pattern-slot-name slot) value-slot)
            (let ((v (pattern-slot-value slot)))
              (when (literal-slot-value-p v)
                (pushnew v acc)))))))))

(defun rule-member-test-values (rule)
  "Values named in RULE's (test (member ?value '(...))) patterns, flattened.
   This is how a rule enumerates the set of hypotheses it applies to -- the
   ruling-out rules use it to name every identity they argue against."
  (let ((acc '()))
    (dolist (p (rule-patterns rule) acc)
      (when (eq (parsed-pattern-type p) :test)
        (dolist (form (parsed-pattern-slots p))
          ;; Shape: (MEMBER ?VALUE '(:A :B ...))
          (when (and (consp form) (eq (first form) 'member))
            (let ((quoted (third form)))
              (when (and (consp quoted) (eq (first quoted) 'quote))
                (setf acc (append acc (second quoted)))))))))))

(defun rule-premises-p (rule class &optional value)
  "True when RULE matches a CLASS fact on its LHS -- with VALUE, only when it
   matches that literal value. This is what distinguishes a chained (tier-2) rule
   from a one-hop one: the chained rule premises on a class its siblings derive."
  (some (lambda (p)
          (and (eq (parsed-pattern-class p) class)
               (or (null value)
                   (member value (rule-premise-values rule class)))))
        (rule-premise-patterns rule)))
;;; ------------------------------------------------------------------
;;; Specificity between rules.
;;;
;;; When two rules reach the SAME conclusion, do their beliefs reinforce, or does one
;;; subsume the other? Measured across neomycin's corpus: 17 same-conclusion pairs, no
;;; two with identical premises, and exactly ONE where a rule's premises are a strict
;;; subset of another's. Distinct evidence should reinforce; a subsumed rule should
;;; not, because the more specific rule already accounts for everything it says --
;;; its premises are a superset -- so combining them asserts a confidence the author
;;; never stated.
;;;
;;; This is the production-rule notion of SPECIFICITY that conflict resolution already
;;; uses to order firings, applied instead to how their beliefs combine. Domain-neutral:
;;; it compares premise patterns and knows nothing of any particular rulebase.
;;; ------------------------------------------------------------------

(defun rule-premise-signature (rule)
  "RULE's literal premises as a sorted, comparable set of CLASS=VALUE strings. Values
   that are variables or constraint forms are skipped, since they impose no condition
   that another rule could subsume."
  (sort (loop for class in (remove-duplicates (rule-premise-classes rule))
              append (loop for value in (rule-premise-values rule class)
                           collect (format nil "~A=~A" class value)))
        #'string<))

(defun rule-subsumes-p (specific general)
  "True when GENERAL's premises are a STRICT subset of SPECIFIC's -- so GENERAL fires
   whenever SPECIFIC does, and tells us nothing SPECIFIC has not already conditioned
   on. Rules that merely overlap are NOT subsumed: sharing a gram stain while
   differing on the patient is distinct evidence, and treating it otherwise discards
   something real."
  (let ((s (rule-premise-signature specific))
        (g (rule-premise-signature general)))
    (and (null (set-difference g s :test #'string=))
         (set-difference s g :test #'string=)
         t)))
