;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: Reading a consensus out of working memory.
;;
;; Under the v0.11 shape a rule states what its evidence NARROWS THE ANSWER TO and
;; asserts that set as a CANDIDATES fact carrying its own belief. Nothing accumulates
;; during inference and nothing is hidden: what the engine did is entirely in working
;; memory, and this file is the read that turns it into a differential.
;;
;; Two things happen here that the algebra cannot do on its own, because both need to
;; see the RULES rather than the numbers:
;;
;;   SPECIFICITY. When two rules assert the same answer their support reinforces --
;;   correct whenever they bring distinct evidence, which is every same-conclusion pair
;;   in this corpus but one. The exception is subsumption: a rule whose premises are a
;;   strict subset of another's fires whenever that one does and conditions on nothing
;;   extra, so counting it again asserts a confidence no author stated. Such a rule is
;;   dropped in favour of the more specific one.
;;
;;   ATTRIBUTION. Which rules produced which answer, so an explanation can name them.
;;
;; See docs/narrows-to-promotion-sketch.md.

(in-package :neomycin)

(defun candidates-facts (&optional organism)
  (loop for fact in (lisa:get-fact-list (lisa:inference-engine))
        when (and (eq (lisa:fact-name fact) 'lisa-user::candidates)
                  (or (null organism)
                      (eq (lisa:get-slot-value fact 'lisa-user::of) organism)))
          collect fact))

(defun organisms-with-answers ()
  (remove-duplicates
   (mapcar (lambda (f)
             (lisa:get-slot-value f 'lisa-user::of))
           (candidates-facts))))

(defun firing-discount (record)
  (let ((beliefs
          (remove nil (mapcar #'cdr (lisa:derivation-record-premises record)))))
    (if (and beliefs belief:*belief-system*)
        (belief:conjoin-beliefs belief:*belief-system* beliefs)
      1.0)))

(defun contributing-firings (fact)
  (remove nil
          (mapcar (lambda (record)
                    (let ((rule (lisa:find-rule (lisa:inference-engine)
                                                (lisa:derivation-record-rule record))))
                      (when rule
                        (cons rule (firing-discount record)))))
                  (lisa:fact-derivation (lisa:inference-engine) fact))))

(defun contributing-rules (fact)
  (mapcar #'car (contributing-firings fact)))

(defun surviving-rules (rules)
  (remove-if (lambda (r)
               (some (lambda (other) (lisa:rule-subsumes-p other r)) rules))
             rules))

(defun answer-value (fact)
  (lisa:get-slot-value fact 'lisa-user::value))

(defun answer-set (fact)
  (candidates:answer-support (answer-value fact)))

(defun rule-evidence-group (rule)
  (getf (lisa:rule-provenance rule) :evidence-group))

(defun strongest-in-group (rules)
  (first (sort (copy-list rules)
               (lambda (a b)
                 (let ((ba (abs (lisa:rule-belief a)))
                       (bb (abs (lisa:rule-belief b))))
                   (if (= ba bb)
                       (string< (symbol-name (lisa:rule-short-name a))
                                (symbol-name (lisa:rule-short-name b)))
                     (> ba bb)))))))

(defun drop-redundant-evidence (rules)
  (let ((by-group (make-hash-table :test #'eq))
        (ungrouped nil))
    (dolist (rule rules)
      (let ((group (rule-evidence-group rule)))
        (if group
            (push rule (gethash group by-group))
          (push rule ungrouped))))
    (let ((winners nil))
      (maphash (lambda (group members)
                 (declare (ignore group))
                 (push (strongest-in-group members) winners))
               by-group)
      (append winners ungrouped))))

(defun surviving-rules-for (organism)
  (let ((by-support (make-hash-table :test #'equal))
        (survivors nil))
    (dolist (fact (candidates-facts organism))
      (let ((support (answer-set fact)))
        (setf (gethash support by-support)
              (append (contributing-rules fact)
                      (gethash support by-support)))))
    (maphash (lambda (support rules)
               (declare (ignore support))
               (setf survivors
                     (append (surviving-rules (remove-duplicates rules))
                             survivors)))
             by-support)
    (drop-redundant-evidence survivors)))

(defun answer-mass-of (fact &optional survivors-in-scope)
  (let* ((value (answer-value fact))
         (firings (contributing-firings fact))
         (survivors (if survivors-in-scope
                        (remove-if-not (lambda (f) (member (car f) survivors-in-scope))
                                       firings)
                      (let ((keep (surviving-rules (mapcar #'car firings))))
                        (remove-if-not (lambda (f) (member (car f) keep)) firings)))))
    (cond
      ((candidates:graded-answer-p value)
       (let ((m (candidates:graded-answer value)))
         (if survivors
             (reduce #'candidates:combine-two
                     (mapcar (lambda (f) (candidates:discount m (cdr f))) survivors))
           m)))
      (survivors
       (reduce #'candidates:combine-two
               (mapcar (lambda (f)
                         (candidates:discount
                          (candidates:answer value (abs (lisa:rule-belief (car f))))
                          (cdr f)))
                       survivors)))
      (t
       ;; No derivation (a fact asserted as evidence rather than concluded)
       (let* ((b (belief:belief-factor fact))
              (answer (if (realp b) b 1.0)))
         (candidates:answer value answer))))))

(defun answer-of (fact)
  (let* ((organism (lisa:get-slot-value fact 'lisa-user::of))
         (mass (answer-mass-of fact (surviving-rules-for organism))))
    (cons (answer-set fact)
          (- 1.0 (candidates:ignorance mass)))))

(defun answer-grading (fact)
  (let ((value (answer-value fact)))
    (when (candidates:graded-answer-p value)
      (sort (mapcar (lambda (pair)
                      (cons (float (car pair) 1.0) (candidates:canonical (cdr pair))))
                    value)
            #'> :key #'car))))

(defun answers-for (organism)
  (mapcar #'answer-of (candidates-facts organism)))

(defun answer-masses-for (organism)
  (let ((survivors (surviving-rules-for organism)))
    (mapcar (lambda (fact)
              (answer-mass-of fact survivors))
            (contributing-facts organism))))

(defun consensus (organism)
  (multiple-value-bind (mass conflict)
      (candidates:combine-masses (answer-masses-for organism))
    (values mass conflict (answers-for organism))))

(defun differential (organism &key (threshold 0.0))
  (let ((mass (consensus organism)))
    (sort (loop for hypothesis in (candidates:hypotheses-named mass)
                for bel = (candidates:bel mass hypothesis)
                for pl = (candidates:pl mass hypothesis)
                when (>= bel threshold)
                  collect (list hypothesis bel pl))
          #'> :key #'second)))

(defun answer-detail (fact)
  (let* ((a (answer-of fact))
         (organism (lisa:get-slot-value fact 'lisa-user::of))
         (scope (surviving-rules-for organism)))
    (list (car a) (cdr a)
          (remove-if-not (lambda (r)
                           (member r scope))
                         (contributing-rules fact))
          (answer-grading fact))))

(defun contributing-facts (organism)
  (let ((survivors (surviving-rules-for organism)))
    (remove-if (lambda (fact)
                 (let ((contributors (contributing-rules fact)))
                   (and contributors
                        (notany (lambda (r)
                                  (member r survivors))
                                contributors))))
               (candidates-facts organism))))

(defun answer-details (organism)
  (mapcar #'answer-detail (contributing-facts organism)))

(defun entity-naming (hypothesis)
  (find-if (lambda (organism)
             (some (lambda (fact)
                     (member hypothesis (answer-set fact)))
                   (candidates-facts organism)))
           (organisms-with-answers)))

(defun catalogue-rules ()
  (remove-if-not #'lisa:knowledge-rule-p
                 (lisa:get-rule-list (lisa:inference-engine))))

(defun rule-answer (rule)
  (let ((value (rule-asserted-answer rule)))
    (when value
      (candidates:answer-support value))))

(defun rule-asserted-answer (rule)
  (loop for (class . value) in (lisa:rule-asserted-facts rule)
        when (eq class 'lisa-user::candidates)
          return (if (and (consp value) (eq (car value) 'quote))
                     (second value)
                   value)))

(defun rule-grading (rule)
  (let ((value (rule-asserted-answer rule)))
    (when (candidates:graded-answer-p value)
      (sort (mapcar (lambda (pair)
                      (cons (float (car pair) 1.0) (candidates:canonical (cdr pair))))
                    value)
            #'> :key #'car))))

(defun rules-behind (organism hypothesis)
  (loop for fact in (candidates-facts organism)
        when (member hypothesis (answer-set fact))
          append (mapcar #'lisa:rule-short-name (surviving-rules (contributing-rules fact)))
            into names
        finally (return (remove-duplicates names))))
