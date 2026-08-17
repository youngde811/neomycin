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
  "True when RULE declares a belief -- i.e. it asserts domain knowledge rather
   than performing bookkeeping (reporting, formatting, driving). A corpus-wide
   query almost always wants these and not, say, a salience -10 print rule."
  (realp (rule-belief rule)))

(defun confirming-rule-p (rule)
  "True when RULE argues FOR its conclusion (positive belief)."
  (let ((b (rule-belief rule)))
    (and (realp b) (plusp b))))

(defun disconfirming-rule-p (rule)
  "True when RULE argues AGAINST its conclusion (negative belief) -- the
   ruling-out shape."
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
;;; Focal sets (shared frame of discernment).
;;;
;;; Under a shared frame a rule's firing commits mass to a SUBSET of the frame, not
;;; to a single hypothesis. This resolves that subset. It stays domain-neutral: it
;;; knows about declared designators, asserted literal values, and member tests --
;;; never about organisms.
;;;
;;; The two FALLBACKS are what let a corpus adopt the frame without editing every
;;; rule. A confirming rule that declares nothing falls back to the values it
;;; asserts; a ruling-out rule falls back to the complement of the values its member
;;; test names. Both resolve through the frame, so both are checked against it.
;;; See docs/shared-frame-design.md 4.2-4.4.
;;; ------------------------------------------------------------------

(defun rule-asserted-literals (rule)
  "The literal VALUEs RULE asserts, skipping variables. A ruling-out rule asserts
   (value ?value), which is a binding rather than a conclusion, so it yields none."
  (remove-if-not #'literal-slot-value-p
                 (mapcar #'cdr (rule-asserted-facts rule))))

(defun rule-focal-designator (rule)
  "What RULE says its evidence bears on, before resolution.

   Returns (values DESIGNATOR NEGATEDP KIND), or (values NIL NIL NIL) when the rule
   says nothing resolvable. NEGATEDP means the mass belongs on the COMPLEMENT --
   evidence against the designated set. KIND records which of the four sources
   answered, so a caller can tell a declaration from a fallback:

     :SUPPORTS    an explicit :supports declaration
     :OPPOSES     an explicit :opposes declaration (negated)
     :ASSERTED    fallback -- the literal values the rule concludes
     :RULING-OUT  fallback -- the complement of its member-test targets (negated)"
  (cond
    ((rule-opposes rule) (values (rule-opposes rule) t :opposes))
    ((rule-supports rule) (values (rule-supports rule) nil :supports))
    ((rule-asserted-literals rule)
     (values (rule-asserted-literals rule) nil :asserted))
    ((rule-member-test-values rule)
     (values (rule-member-test-values rule) t :ruling-out))
    (t (values nil nil nil))))

(defun rule-focal-set (rule &optional (frame belief:*frame*))
  "The frame subset RULE's firing commits mass to, as a mask.

   Returns (values MASK KIND), or (values NIL KIND) when no frame is declared or the
   rule designates nothing. Signals an error -- deliberately -- if the rule names a
   hypothesis the frame does not contain: that is the structural staleness guard,
   and it should fail loudly rather than resolve to an empty set that would silently
   stop mattering."
  (multiple-value-bind (designator negatedp kind) (rule-focal-designator rule)
    (if (or (null frame) (null designator))
        (values nil kind)
        (let ((mask (belief:resolve-mask frame designator)))
          (values (if negatedp (belief:mask-complement frame mask) mask) kind)))))

(defun rule-focal-mass (rule)
  "The SUPPORT a firing of RULE contributes to its focal set: the magnitude of its
   belief. A ruling-out rule's negative belief is a direction, not a quantity -- the
   direction is already carried by the focal set being a complement -- so the mass it
   contributes is |belief|."
  (let ((b (rule-belief rule)))
    (and (realp b) (abs b))))

;;; ------------------------------------------------------------------
;;; CLAIMS -- the general form.
;;;
;;; A rule states one or more claims about what its evidence establishes, each with
;;; its own strength. One observation, one rule, however many granularities the
;;; author can honestly assert:
;;;
;;;   (:claims ((0.75 :supports :serratia)
;;;             (0.80 :excludes (:e-coli :klebsiella :salmonella :enterobacter :proteus))))
;;;
;;; This replaces having to write the same clinical fact twice -- once as a confirming
;;; rule and once as a ruling-out rule -- with two independently chosen numbers that
;;; nothing forces to agree. :supports commits mass to the named set; :excludes commits
;;; it to the complement. There is no rule KIND: a rule that only excludes is not a
;;; different sort of thing, it is a rule whose one claim happens to name a complement,
;;; which is what a negative test result honestly establishes.
;;;
;;; Each claim becomes ONE simple support function in the entity's pool. Note what that
;;; does and does not mean: two claims from one rule are still COMBINED as though
;;; separable, because 0.75 + 0.80 exceeds 1 and they therefore cannot be a single mass
;;; assignment. Authoring them together makes the pair visible in one place; it does not
;;; by itself settle how nested claims from one observation ought to combine.
;;; ------------------------------------------------------------------

(defstruct (claim (:constructor %make-claim (mass mask kind designator)))
  "One resolved claim: MASS on MASK. KIND is :SUPPORTS or :EXCLUDES as written (MASK is
   already the complement for :EXCLUDES), or the fallback that produced it."
  mass mask kind designator)

(defun %resolve-claim (frame mass verb designator)
  (let ((mask (belief:resolve-mask frame designator)))
    (%make-claim (abs (float mass 1.0))
                 (ecase verb
                   ((:supports :support) mask)
                   ((:excludes :exclude :opposes :oppose)
                    (belief:mask-complement frame mask)))
                 verb designator)))

(defun rule-claims (rule &optional (frame belief:*frame*))
  "Every claim RULE makes, resolved against FRAME, as a list of CLAIM structs.

   Normalizes all four authoring forms into one shape, so no consumer has to know
   which was used:

     :claims ((mass verb designator) ...)   the general form
     :belief N :supports D                  single-claim shorthand
     :belief N :opposes D                   single-claim shorthand (complement)
     :belief N, no declaration              fallback -- the values the rule asserts,
                                            or the complement of its member-test list

   CLAIM-KIND reports the SOURCE that produced each claim (:supports / :excludes for a
   declared claim; :supports / :opposes / :asserted / :ruling-out for the shorthand and
   fallbacks), so a caller can still distinguish a declaration from an inference.

   Returns NIL when no frame is declared or the rule designates nothing."
  (when frame
    (let ((declared (rule-declared-claims rule)))
      (if declared
          (loop for (mass verb designator) in declared
                collect (%resolve-claim frame mass verb designator))
          (multiple-value-bind (designator negatedp source) (rule-focal-designator rule)
            (when designator
              (let ((c (%resolve-claim frame (or (rule-focal-mass rule) 0)
                                       (if negatedp :excludes :supports)
                                       designator)))
                (setf (claim-kind c) source)
                (list c))))))))

(defun rule-multi-claim-p (rule)
  (> (length (rule-declared-claims rule)) 1))
