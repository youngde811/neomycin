;;; -*- Mode: Lisp -*-
;;;
;;; ATTIC -- historical record.
;;; Throwaway audit tool for the shared-frame slice D. The frame system it reads was deleted at v0.11. Will not run against the current tree.
;;;
;;; SLICE D ANALYSIS for docs/attic/shared-frame-design.md. Throwaway audit tool.
;;; NOT part of any ASDF system, NOT loaded by anything, NOT tested.
;;;
;;; QUESTION: for each rule, is its focal set as wide as its premises license?
;;;
;;; Phase 0.5 found that culture-1's ranking inversion came from co-triggered rules
;;; concluding DISJOINT sets from one observation, and that correcting a single focal
;;; set fixed it. This audits the other 49 for the same defect.
;;;
;;; METHOD -- the corpus is its own source of truth. Rather than working from recall
;;; about which organisms are gram-negative, this derives an organism/property table
;;; FROM THE COMPILED RULEBASE, in two directions:
;;;
;;;   POSITIVE. A rule requiring GRAM=NEG whose focal set is S tells us every member
;;;             of S is gram-negative. (For a class rule, that is the whole family.)
;;;   NEGATIVE. A ruling-out rule saying GRAM=POS argues against L tells us no member
;;;             of L is gram-positive.
;;;
;;; Then LICENSED(rule) = every frame element not KNOWN to contradict one of the
;;; rule's organism-intrinsic premises. Unknown never excludes -- if the corpus does
;;; not record an organism's indole reaction, an indole premise cannot rule it out.
;;; That makes the licensed set an UPPER bound and the audit conservative: it flags a
;;; focal set as too narrow only on evidence the corpus itself supplies.
;;;
;;; Usage, from an SBCL REPL at project root with :neomycin loaded:
;;;   (load "docs/attic/focal-width-audit.lisp")
;;;   (focal-audit:report)

(defpackage :focal-audit
  (:use :common-lisp)
  (:export #:report))

(in-package :focal-audit)

(defun frame () (lisa:frame-of-discernment))
(defun engine () (lisa:inference-engine))

;;; ============================================================
;;; Which premises constrain WHICH ORGANISM, and which do not
;;; ============================================================
;;; A domain judgement, stated explicitly rather than buried. Burns, neutropenia and
;;; culture sites shift how LIKELY an organism is; they do not make any organism
;;; impossible, so they cannot narrow a focal set. Only organism-INTRINSIC properties
;;; -- what the isolate is and how it behaves on the bench -- exclude anything.

(defparameter *intrinsic-params*
  '(lisa-user::gram lisa-user::morphology lisa-user::aerobicity
    lisa-user::growth-conformation lisa-user::lactose lisa-user::indole
    lisa-user::urease lisa-user::motility lisa-user::pigment
    lisa-user::catalase lisa-user::coagulase lisa-user::hemolysis
    lisa-user::optochin lisa-user::bacitracin lisa-user::novobiocin
    lisa-user::bile-esculin lisa-user::salt-tolerance
    lisa-user::arabinose lisa-user::sorbitol)
  "Bench/morphological properties of the isolate itself. These exclude organisms.")

(defparameter *context-params*
  '(lisa-user::culture-site lisa-user::culture-age lisa-user::burn
    lisa-user::compromised-host lisa-user::hospital-acquired
    lisa-user::neutropenia lisa-user::iv-drug-use lisa-user::age-group
    lisa-user::prosthetic-material lisa-user::urinary-source
    lisa-user::travel-history lisa-user::infection)
  "Patient and culture context. These shift priors; they exclude nothing, so a rule
   premised only on context licenses the WHOLE frame and its focal set is a prior,
   not a deduction. Listed for completeness -- the audit simply ignores them.")

;;; ============================================================
;;; The organism/property table, derived from the corpus
;;; ============================================================

(defstruct (knowledge (:conc-name kb-))
  (positive (make-hash-table :test #'equal))   ; (param . organism) -> value
  (negative (make-hash-table :test #'equal)))  ; (param . organism) -> list of excluded values

(defun rule-intrinsic-premises (rule)
  "((param . value) ...) for RULE's organism-intrinsic premises with literal values."
  (loop for param in *intrinsic-params*
        append (loop for v in (lisa:rule-premise-values rule param)
                     collect (cons param v))))

(defparameter *catch-all* :other-organism
  "The frame's catch-all element. It must NEVER acquire properties: it stands for
   organisms of ANY description, so recording 'other-organism is gram-negative' from
   one rule and 'gram-positive' from another would make it contradict every rule that
   names it. Excluded from the property table in both directions.")

(defun build-knowledge ()
  "Derive what the corpus knows about each organism's properties, from both the
   confirming rules' premises and the ruling-out rules' member lists."
  (let ((kb (make-knowledge))
        (f (frame)))
    (dolist (rule (lisa:get-rule-list (engine)) kb)
      (when (lisa:knowledge-rule-p rule)
        (let ((premises (rule-intrinsic-premises rule)))
          (when premises
            (cond
              ;; POSITIVE: a confirming rule's focal set all share its premises.
              ((lisa:confirming-rule-p rule)
               (let ((mask (lisa:rule-focal-set rule f)))
                 (dolist (org (remove *catch-all* (belief:mask->elements f mask)))
                   (loop for (param . value) in premises
                         do (setf (gethash (cons param org) (kb-positive kb)) value)))))
              ;; NEGATIVE: a ruling-out rule's TARGETS lack its premise values.
              ((lisa:disconfirming-rule-p rule)
               (dolist (org (remove *catch-all* (lisa:rule-member-test-values rule)))
                 (loop for (param . value) in premises
                       do (pushnew value
                                   (gethash (cons param org) (kb-negative kb)))))))))))))

(defun contradicts-p (kb param value organism)
  "True when the corpus KNOWS ORGANISM cannot have PARAM = VALUE."
  (let ((known (gethash (cons param organism) (kb-positive kb)))
        (excluded (gethash (cons param organism) (kb-negative kb))))
    (or (and known (not (eql known value)))
        (member value excluded))))

;;; ============================================================
;;; Licensed sets
;;; ============================================================

(defun class-premise-mask (rule)
  "If RULE premises on an organism-class, the mask of that class -- the chained rules'
   strongest constraint. NIL if it premises on no class."
  (let ((f (frame))
        (values (lisa:rule-premise-values rule 'lisa-user::organism-class)))
    (when values
      (reduce #'logior (mapcar (lambda (v) (belief:resolve-mask f v)) values)
              :initial-value 0))))

(defun licensed-mask (rule kb)
  "Every frame element consistent with RULE's organism-intrinsic premises."
  (let* ((f (frame))
         (premises (rule-intrinsic-premises rule))
         (mask (or (class-premise-mask rule) (belief:frame-theta f))))
    (dolist (org (belief:mask->elements f mask) mask)
      (when (loop for (param . value) in premises
                    thereis (contradicts-p kb param value org))
        (setf mask (logandc2 mask (belief:resolve-mask f org)))))))

;;; ============================================================
;;; Report
;;; ============================================================

(defun names (mask)
  (mapcar (lambda (k) (string-downcase (symbol-name k)))
          (belief:mask->elements (frame) mask)))

(defun audit-rule (rule kb)
  (let* ((f (frame))
         (focal (lisa:rule-focal-set rule f))
         (licensed (licensed-mask rule kb))
         (intrinsic (rule-intrinsic-premises rule)))
    (list :rule (lisa:rule-short-name rule)
          :belief (lisa:rule-belief rule)
          :confirming (lisa:confirming-rule-p rule)
          :focal focal
          :licensed licensed
          :missing (logandc2 licensed focal)      ; licensed but not claimed
          :overclaim (logandc2 focal licensed)    ; claimed but not licensed
          :intrinsic-count (length intrinsic)
          :context-only (null intrinsic))))

(defun report ()
  (let* ((kb (build-knowledge))
         (rules (remove-if-not #'lisa:knowledge-rule-p (lisa:get-rule-list (engine))))
         (audits (mapcar (lambda (r) (audit-rule r kb)) rules)))
    (format t "~&~%================================================================~%")
    (format t "SLICE D -- focal-set width audit, derived from the compiled corpus~%")
    (format t "frame: ~D elements   rules: ~D~%" (belief:frame-size (frame)) (length rules))
    (format t "================================================================~%")

    ;; 1. Rules premised only on patient/culture context.
    (let ((ctx (remove-if-not (lambda (a) (getf a :context-only)) audits)))
      (format t "~&~%--- (1) CONTEXT-ONLY rules: ~D ---~%" (length ctx))
      (format t "No organism-intrinsic premise, so nothing is excluded and the licensed~%")
      (format t "set is the whole frame. Their focal set is a PRIOR, not a deduction --~%")
      (format t "widening them to Theta would make them say nothing. Left alone.~%")
      (dolist (a ctx)
        (format t "  ~,2F ~A -> ~{~A~^, ~}~%"
                (getf a :belief) (string-downcase (string (getf a :rule)))
                (names (getf a :focal)))))

    ;; 2. Overclaims -- focal set contains organisms the premises exclude.
    (let ((over (remove-if (lambda (a) (zerop (getf a :overclaim))) audits)))
      (format t "~&~%--- (2) OVERCLAIMS: ~D ---~%" (length over))
      (format t "Focal set contains an organism the rule's OWN premises rule out.~%")
      (dolist (a over)
        (format t "  ~A~%    claims but cannot: ~{~A~^, ~}~%"
                (string-downcase (string (getf a :rule)))
                (names (getf a :overclaim)))))

    ;; 3b. Rules that differ from their licensed set ONLY by the catch-all.
    ;; Decision D6: the catch-all belongs in a COARSE, already set-valued focal set,
    ;; and not in a rule that names one organism -- adding it to a singleton drops
    ;; that organism's Bel to ZERO, because mass on {X, other} says "one of these
    ;; two", not "X". These are therefore correct as they stand.
    (let* ((catch-all-mask (belief:resolve-mask (frame) *catch-all*))
           (d6 (remove-if-not (lambda (a)
                                (and (not (getf a :context-only))
                                     (getf a :confirming)
                                     (= (getf a :missing) catch-all-mask)))
                              audits)))
      (format t "~&~%--- (3b) DIFFER ONLY BY THE CATCH-ALL (D6): ~D ---~%" (length d6))
      (format t "Singleton focal sets. Correct as they stand: adding the catch-all to a~%")
      (format t "singleton would drop its Bel to zero.~%")
      (dolist (a d6)
        (format t "  ~,2F ~A -> ~{~A~^, ~}~%"
                (getf a :belief) (string-downcase (string (getf a :rule)))
                (names (getf a :focal))))

    ;; 3. Too-narrow confirming rules -- the culture-1 defect.
    (let ((narrow (sort (remove-if (lambda (a)
                                     (or (getf a :context-only)
                                         (not (getf a :confirming))
                                         (zerop (getf a :missing))
                                         (= (getf a :missing) catch-all-mask)))
                                   audits)
                        #'> :key (lambda (a) (belief:mask-size (getf a :missing))))))
      (format t "~&~%--- (3) TOO NARROW (confirming): ~D ---~%" (length narrow))
      (format t "The premises license MORE than the rule claims. Each missing organism~%")
      (format t "is one the corpus cannot distinguish on this evidence, so committing~%")
      (format t "mass to the conclusion alone overstates it -- and, when a co-triggered~%")
      (format t "rule names one of the missing organisms, manufactures conflict.~%")
      (dolist (a narrow)
        (format t "~&  ~,2F ~A~%" (getf a :belief) (string-downcase (string (getf a :rule))))
        (format t "      claims:  ~{~A~^, ~}~%" (names (getf a :focal)))
        (format t "      + also licensed: ~{~A~^, ~}~%" (names (getf a :missing))))))

    ;; 4. Ruling-out rules.
    (let ((ruling (remove-if (lambda (a)
                               (or (getf a :confirming) (zerop (getf a :missing))))
                             audits)))
      (format t "~&~%--- (4) RULING-OUT rules whose complement is narrower than licensed: ~D ---~%"
              (length ruling))
      (dolist (a ruling)
        (format t "  ~A~%    focal ~D, licensed ~D, missing: ~{~A~^, ~}~%"
                (string-downcase (string (getf a :rule)))
                (belief:mask-size (getf a :focal))
                (belief:mask-size (getf a :licensed))
                (names (getf a :missing)))))

    ;; 5. Clean.
    (let ((clean (remove-if-not (lambda (a)
                                  (and (not (getf a :context-only))
                                       (zerop (getf a :missing))
                                       (zerop (getf a :overclaim))))
                                audits)))
      (format t "~&~%--- (5) EXACT: ~D rules claim precisely what they license ---~%"
              (length clean))
      (dolist (a clean)
        (format t "  ~A~%" (string-downcase (string (getf a :rule))))))
    (format t "~&~%================================================================~%")
    (values)))