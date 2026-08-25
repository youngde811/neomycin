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

(defun firing-discount (record)
  "How strongly the PREMISES of one firing were believed, conjoined by the active
   belief system -- 1.0 when the record carries no premise beliefs.

   The engine snapshots each premise's belief at fire time (DERIVATION-RECORD-PREMISES
   is a list of (FACT . BELIEF)), which is the only place this survives per RULE. The
   conclusion fact carries a belief too, but it is the COMBINED result of every
   contributor and cannot be decomposed back into what each rule brought."
  (let ((beliefs (remove nil (mapcar #'cdr (lisa:derivation-record-premises record)))))
    (if (and beliefs belief:*belief-system*)
        (belief:conjoin-beliefs belief:*belief-system* beliefs)
        1.0)))

(defun contributing-firings (fact)
  "((RULE . DISCOUNT) ...) -- one entry per firing that produced FACT.

   A rule that fired twice appears twice, as it must: each firing is its own assertion
   of the answer and carries its own evidence strength."
  (remove nil
          (mapcar (lambda (record)
                    (let ((rule (lisa:find-rule (lisa:inference-engine)
                                                (lisa:derivation-record-rule record))))
                      (when rule (cons rule (firing-discount record)))))
                  (lisa:fact-derivation (lisa:inference-engine) fact))))

(defun contributing-rules (fact)
  "The rules whose firing produced FACT, from the engine's own derivation record."
  (mapcar #'car (contributing-firings fact)))

(defun surviving-rules (rules)
  "RULES minus any that another in the set SUBSUMES.

   A subsumed rule's premises are a strict subset of a survivor's, so it fires
   whenever that one does and tells us nothing the survivor has not already
   conditioned on. Rules that merely OVERLAP -- sharing a gram stain while differing
   on the patient -- are distinct evidence and all survive."
  (remove-if (lambda (r)
               (some (lambda (other) (lisa:rule-subsumes-p other r)) rules))
             rules))

(defun answer-value (fact)
  "The raw VALUE slot of a CANDIDATES fact -- a flat set, or a graded answer."
  (lisa:get-slot-value fact 'lisa-user::value))

(defun answer-set (fact)
  "The set FACT admits: itself if flat, the union of its focal sets if graded.

   This is what `narrows to' means, and it is the only thing callers asking `does this
   answer admit klebsiella?' should consult. A graded answer's grading says how mass
   is distributed INSIDE this set; it never admits anything the set does not."
  (candidates:answer-support (answer-value fact)))

(defun rule-evidence-group (rule)
  "The :evidence-group RULE declares in its provenance, or NIL.

   A group name says: THESE RULES REST ON THE SAME UNDERLYING EVIDENCE. They are not
   independent observations, so combining them by Dempster's rule -- which assumes they
   are -- counts one fact more than once."
  (getf (lisa:rule-provenance rule) :evidence-group))

(defun strongest-in-group (rules)
  "The single rule that should speak for an evidence group.

   Most committed first; ties broken by name so the choice is deterministic and a
   corpus edit cannot silently swap which rule is quoted. `Most committed' is the
   defensible reading of `most specific' when premises do not nest: it is the rule whose
   author was willing to claim the most from this evidence."
  (first (sort (copy-list rules)
               (lambda (a b)
                 (let ((ba (abs (lisa:rule-belief a))) (bb (abs (lisa:rule-belief b))))
                   (if (= ba bb)
                       (string< (symbol-name (lisa:rule-short-name a))
                                (symbol-name (lisa:rule-short-name b)))
                       (> ba bb)))))))

(defun drop-redundant-evidence (rules)
  "RULES minus every member of an evidence group except the one that speaks for it.

   THE SECOND HALF OF SPECIFICITY. Subsumption handles rules whose premises NEST: the
   general one conditions on nothing extra, so it is dropped. This handles rules whose
   premises do not nest but whose EVIDENCE is the same -- which subsumption cannot see,
   because it reads premises rather than sources.

   The case that forced it: four gram-negative opportunist rules encode substantially
   the same distribution, because all four rest on the same epidemiology of
   gram-negative bacteraemia. `compromised-host' and `neutropenia' do not subsume each
   other, so a patient who was both fired both, and Dempster's rule read agreement as
   corroboration -- inflating the leading organism's belief ABOVE what either finding
   alone supports (e-coli 0.28/0.20 alone, 0.3492 together) while simultaneously
   inflating conflict to 0.2096 between two rules that AGREE about the shape of the
   answer. Measured in docs/base-rate-investigation.md.

   Dropping all but the strongest leaves exactly the answer that rule gives on its own,
   which is the correct reading when the two are one piece of evidence. Rules with no
   :evidence-group are untouched, so a genuinely distinct context -- a burn, a tropical
   journey -- still combines normally."
  (let ((by-group (make-hash-table :test #'eq))
        (ungrouped '()))
    (dolist (rule rules)
      (let ((group (rule-evidence-group rule)))
        (if group
            (push rule (gethash group by-group))
            (push rule ungrouped))))
    (let ((winners '()))
      (maphash (lambda (group members)
                 (declare (ignore group))
                 (push (strongest-in-group members) winners))
               by-group)
      (append winners ungrouped))))

(defun surviving-rules-for (organism)
  "Every rule behind ORGANISM's answers, minus any that a SAME-ANSWER rule subsumes.

   Subsumption is scoped to rules whose answers have the same SUPPORT, which is what
   `same-conclusion rules reinforce, unless one subsumes the other' has always meant.
   The scoping is not a detail -- dropping it is wrong, and measurably so. Applied
   across ALL of an organism's answers instead, this drops
   CHAINS-NARROWS-TO-CHAIN-FORMERS whenever BACITRACIN-SENSITIVE-NARROWS-TO-PYOGENES
   fires, and GRAM-NEGATIVE-NARROWS-TO-GRAM-NEGATIVES whenever the bacteroides rule
   does. A specific finding does not make the stain that framed it redundant: those
   rules bring distinct evidence to nested answers, and they must reinforce.

   What DID have to change is the granularity. This check used to be applied per FACT,
   which was sound only by coincidence -- subsumption in the pre-graded corpus always
   occurred between rules asserting the same FLAT set, and the engine collapsed those
   into one fact. Graded answers broke the coincidence: two rules on nested premises
   now assert different DISTRIBUTIONS over the same support, so they land on separate
   facts and a per-fact check never sees the pair. Measured on culture-1a, where the
   compromised-host evidence was counted twice -- once through the compromised-host
   rule and again through the hospital-acquired rule that subsumes it -- driving K to
   0.533. Grouping by support restores the intended semantics for both shapes."
  (let ((by-support (make-hash-table :test #'equal))
        (survivors '()))
    (dolist (fact (candidates-facts organism))
      (let ((support (answer-set fact)))
        (setf (gethash support by-support)
              (append (contributing-rules fact) (gethash support by-support)))))
    (maphash (lambda (support rules)
               (declare (ignore support))
               (setf survivors
                     (append (surviving-rules (remove-duplicates rules)) survivors)))
             by-support)
    ;; Redundant-evidence filtering runs LAST and across the whole organism, not within
    ;; a support group: rules resting on one source may assert different distributions
    ;; and therefore land on different facts, which is exactly why subsumption -- scoped
    ;; by support -- cannot see them.
    (drop-redundant-evidence survivors)))

(defun answer-mass-of (fact &optional survivors-in-scope)
  "The mass function one CANDIDATES fact contributes.

   Each SURVIVING firing behind the fact is one independent assertion of the answer,
   and they are combined by Dempster's rule. Recomputing from the surviving rules
   rather than reading the fact's own belief is what implements SPECIFICITY: the engine
   combined every contributor when it collapsed the duplicate assertions, and had no
   way to know one of them was subsumed.

   Each firing's answer is then DISCOUNTED by how strongly that firing's premises were
   believed. Two quantities are in play and they are not the same: a rule's :belief is
   how strongly the answer follows FROM its premises, and the discount is how strongly
   those premises were believed in the first place. The rule belief alone is right only
   when the evidence was asserted outright, which is every scenario but a hedged one --
   and reading the fact's own belief instead is not an option, because it is the
   COMBINED result of every contributor and cannot be decomposed per rule.

   Before this, evidence strength reached the fact and stopped there: culture-2's
   0.8/0.2 Gram hedge produced facts at 0.56/0.14/0.72 and a differential computed from
   0.7/0.7/0.9, identical whether the clinician called the stain 80% negative, 50/50, or
   80% POSITIVE. /assert-fact accepted a `confidence', echoed it back, and it changed
   nothing.

   For a FLAT answer at full evidence strength this is exactly the old arithmetic.
   Combining two simple support functions on the same set with beliefs a and b puts
   a + b - ab on it, which is the probabilistic sum this function used to compute
   directly. Nothing moves unless a premise was hedged.

   For a GRADED answer the distribution is stated on the FACT rather than carried as a
   rule's single :belief, so each surviving firing asserts the same mass function,
   discounted by its own evidence, and they combine the same way."
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
       ;; No derivation (a fact asserted as evidence rather than concluded):
       ;; take what it carries.
       (let ((b (belief:belief-factor fact)))
         (candidates:answer value (if (realp b) b 1.0)))))))

(defun answer-of (fact)
  "(SET . BELIEF) for one CANDIDATES fact.

   BELIEF is the mass the answer COMMITS -- everything it does not leave on Theta. For
   a flat answer that is the reinforced rule belief, unchanged. For a graded answer it
   is the total of its focal masses, which is the closest single number to `how much
   this evidence claims at all' and is what a summary line should quote."
  (let* ((organism (lisa:get-slot-value fact 'lisa-user::of))
         (mass (answer-mass-of fact (surviving-rules-for organism))))
    (cons (answer-set fact)
          (- 1.0 (candidates:ignorance mass)))))

(defun answer-grading (fact)
  "((MASS . SET) ...) for a graded answer, strongest first -- NIL when FACT is flat.

   The extra information a graded answer carries: not which organisms survive, but how
   the evidence distributes its confidence among them."
  (let ((value (answer-value fact)))
    (when (candidates:graded-answer-p value)
      (sort (mapcar (lambda (pair)
                      (cons (float (car pair) 1.0) (candidates:canonical (cdr pair))))
                    value)
            #'> :key #'car))))

(defun answers-for (organism)
  "((SET . BELIEF) ...) -- every answer any rule gave about ORGANISM."
  (mapcar #'answer-of (candidates-facts organism)))

(defun answer-masses-for (organism)
  "The mass function each answer about ORGANISM contributes.

   A fact whose every contributing rule is subsumed contributes NOTHING and is
   dropped, rather than falling back to the fact's own belief -- it is not independent
   evidence, it is the same evidence stated less specifically."
  (let ((survivors (surviving-rules-for organism)))
    (mapcar (lambda (fact) (answer-mass-of fact survivors))
            (contributing-facts organism))))

(defun consensus (organism)
  "Combine every answer about ORGANISM.

   Returns (values MASS CONFLICT ANSWERS): the combined mass function, the conflict
   read BEFORE normalization -- both normalizations resolve it away, so it cannot be
   recovered afterwards -- and the answers it was built from, for explanation."
  (multiple-value-bind (mass conflict)
      (candidates:combine-masses (answer-masses-for organism))
    (values mass conflict (answers-for organism))))

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

(defun answer-detail (fact)
  "(SET BELIEF RULES GRADING) for one CANDIDATES fact -- an answer WITH its attribution.

   GRADING is NIL for a flat answer, so callers that only ever read the first three
   elements are unaffected.

   ANSWER-OF gives the numbers; this gives the numbers and who said them, which is
   what an explanation needs and what /why is built from."
  (let* ((a (answer-of fact))
         (organism (lisa:get-slot-value fact 'lisa-user::of))
         (scope (surviving-rules-for organism)))
    (list (car a) (cdr a)
          (remove-if-not (lambda (r) (member r scope)) (contributing-rules fact))
          (answer-grading fact))))

(defun contributing-facts (organism)
  "ORGANISM's CANDIDATES facts, minus any whose every contributing rule was SUBSUMED.

   A subsumed rule is not independent evidence -- it is the same evidence stated less
   specifically -- so the fact it produced contributes no mass. It must not appear in an
   explanation either. Before this filter, /why on culture-1a listed two answers at
   belief 0.60 and 0.70 with EMPTY `rules' arrays: attribution-free claims carrying
   numbers that no surviving rule stood behind, which is exactly what the WHY facility
   exists to make impossible. Found by re-measuring docs/clinician-scenarios.md, not by
   the suite -- the /why tests run on culture-1 and culture-4, where nothing is subsumed."
  (let ((survivors (surviving-rules-for organism)))
    (remove-if (lambda (fact)
                 (let ((contributors (contributing-rules fact)))
                   (and contributors
                        (notany (lambda (r) (member r survivors)) contributors))))
               (candidates-facts organism))))

(defun answer-details (organism)
  "((SET BELIEF RULES GRADING) ...) -- every answer about ORGANISM, attributed."
  (mapcar #'answer-detail (contributing-facts organism)))

(defun entity-naming (hypothesis)
  "The first entity in working memory some rule's answer admits HYPOTHESIS for.

   A caller asking `why klebsiella' names a HYPOTHESIS, not an entity; in a
   polymicrobial culture the entity it belongs to is a fact about working memory
   rather than something the caller should have to know."
  (find-if (lambda (organism)
             (some (lambda (fact) (member hypothesis (answer-set fact)))
                   (candidates-facts organism)))
           (organisms-with-answers)))

(defun catalogue-rules ()
  "Every knowledge-bearing rule in the loaded corpus -- the reporting and driver
   rules that carry no belief are not part of the corpus a client asks about."
  (remove-if-not #'lisa:knowledge-rule-p (lisa:get-rule-list (lisa:inference-engine))))

(defun rule-answer (rule)
  "The set of organisms RULE's evidence narrows to, or NIL if it asserts no answer.

   The RHS asserts a quoted list, so what the introspection API hands back is
   (QUOTE (...)); the quote is reader syntax on the way in and has no business
   reaching a caller."
  (let ((value (rule-asserted-answer rule)))
    (when value (candidates:answer-support value))))

(defun rule-asserted-answer (rule)
  "The raw value RULE asserts -- a flat set, or a graded ((MASS . SET) ...)."
  (loop for (class . value) in (lisa:rule-asserted-facts rule)
        when (eq class 'lisa-user::candidates)
          return (if (and (consp value) (eq (car value) 'quote))
                     (second value)
                     value)))

(defun rule-grading (rule)
  "((MASS . SET) ...) if RULE asserts a graded answer, strongest first; else NIL."
  (let ((value (rule-asserted-answer rule)))
    (when (candidates:graded-answer-p value)
      (sort (mapcar (lambda (pair)
                      (cons (float (car pair) 1.0) (candidates:canonical (cdr pair))))
                    value)
            #'> :key #'car))))

(defun rules-behind (organism hypothesis)
  "The rules whose answers admit HYPOTHESIS -- what an explanation quotes.

   Deliberately the rules that ADMITTED it, not those that excluded others: under this
   shape nothing argues against anything, so the honest account of why a hypothesis
   survives is which evidence kept admitting it."
  (loop for fact in (candidates-facts organism)
        when (member hypothesis (answer-set fact))
          append (mapcar #'lisa:rule-short-name (surviving-rules (contributing-rules fact)))
            into names
        finally (return (remove-duplicates names))))