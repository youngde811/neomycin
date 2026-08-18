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
  "Every CANDIDATES fact in working memory, optionally scoped to one ORGANISM."
  (loop for fact in (lisa:get-fact-list (lisa:inference-engine))
        when (and (eq (lisa:fact-name fact) 'lisa-user::candidates)
                  (or (null organism)
                      (eq (lisa:get-slot-value fact 'lisa-user::of) organism)))
          collect fact))

(defun organisms-with-answers ()
  "Every organism some rule has answered about."
  (remove-duplicates
   (mapcar (lambda (f) (lisa:get-slot-value f 'lisa-user::of)) (candidates-facts))))

(defun contributing-rules (fact)
  "The rules whose firing produced FACT, from the engine's own derivation record."
  (remove nil
          (mapcar (lambda (record)
                    (lisa:find-rule (lisa:inference-engine)
                                    (lisa:derivation-record-rule record)))
                  (lisa:fact-derivation (lisa:inference-engine) fact))))

(defun surviving-rules (rules)
  "RULES minus any that another in the set SUBSUMES.

   A subsumed rule's premises are a strict subset of a survivor's, so it fires
   whenever that one does and tells us nothing the survivor has not already
   conditioned on. Rules that merely OVERLAP -- sharing a gram stain while differing
   on the patient -- are distinct evidence and all survive."
  (remove-if (lambda (r)
               (some (lambda (other) (lisa:rule-subsumes-p other r)) rules))
             rules))

(defun answer-of (fact)
  "(SET . BELIEF) for one CANDIDATES fact.

   Belief is recomputed from the SURVIVING rules rather than read off the fact,
   because the engine combined every contributor when it asserted duplicates and had
   no way to know one of them was subsumed. Where nothing is subsumed the two agree."
  (let* ((set (candidates:canonical
               (lisa:get-slot-value fact 'lisa-user::value)))
         (rules (contributing-rules fact))
         (survivors (surviving-rules rules)))
    (cons set
          (if survivors
              (reduce (lambda (a b) (- (+ a b) (* a b)))
                      (mapcar (lambda (r) (abs (lisa:rule-belief r))) survivors))
              ;; No derivation (a fact asserted as evidence rather than concluded):
              ;; take what it carries.
              (let ((b (belief:belief-factor fact)))
                (if (realp b) b 1.0))))))

(defun answers-for (organism)
  "((SET . BELIEF) ...) -- every answer any rule gave about ORGANISM."
  (mapcar #'answer-of (candidates-facts organism)))

(defun consensus (organism)
  "Combine every answer about ORGANISM.

   Returns (values MASS CONFLICT ANSWERS): the combined mass function, the conflict
   read BEFORE normalization -- both normalizations resolve it away, so it cannot be
   recovered afterwards -- and the answers it was built from, for explanation."
  (let ((answers (answers-for organism)))
    (multiple-value-bind (mass conflict) (candidates:combine-answers answers)
      (values mass conflict answers))))

(defun differential (organism &key (threshold 0.0))
  "((organism-keyword bel pl) ...) for ORGANISM's differential, strongest first.

   Reports every hypothesis the corpus has NAMED in this consultation. A hypothesis no
   rule mentioned is not listed -- but it is not thereby excluded either, and its
   plausibility remains answerable through CONSENSUS: it is m(Theta), the honest
   statement that nothing has spoken to it."
  (let ((mass (consensus organism)))
    (sort (loop for hypothesis in (candidates:hypotheses-named mass)
                for bel = (candidates:bel mass hypothesis)
                for pl = (candidates:pl mass hypothesis)
                when (>= bel threshold)
                  collect (list hypothesis bel pl))
          #'> :key #'second)))

(defun rules-behind (organism hypothesis)
  "The rules whose answers admit HYPOTHESIS -- what an explanation quotes.

   Deliberately the rules that ADMITTED it, not those that excluded others: under this
   shape nothing argues against anything, so the honest account of why a hypothesis
   survives is which evidence kept admitting it."
  (loop for fact in (candidates-facts organism)
        when (member hypothesis (lisa:get-slot-value fact 'lisa-user::value))
          append (mapcar #'lisa:rule-short-name (surviving-rules (contributing-rules fact)))
            into names
        finally (return (remove-duplicates names))))