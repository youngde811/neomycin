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



;;; ------------------------------------------------------------------
;;; Invariant 12 -- a marker that is VARIABLE for an organism may not exclude it.
;;;
;;; This is the enforceable half of the authoring policy stated at the top of
;;; candidates-gram-neg.lisp. Under this representation absence from an answer IS
;;; exclusion, so leaving an organism out of a rule's answer asserts that the finding
;;; rules it out. Where the literature says a marker is variable for an organism, that
;;; assertion is false and the organism must stay in -- a wider answer is a weaker
;;; claim, and the algebra is built to carry it.
;;;
;;; The corpus got this wrong three times in one week, and always the same way: the
;;; author was reasoning inside one family and silently excluded everything outside it.
;;; Pseudomonas fell out of the non-lactose-fermenters (it IS the textbook
;;; non-fermenter), Pseudomonas fell out of the urease producers (72% are positive),
;;; and Bacteroides fell out of the indole producers (the B. fragilis group splits down
;;; the middle). None was caught by a test, because no test reached those rules and the
;;; disconfirming form they were converted from never had to state the complement.
;;;
;;; Each entry below is a claim about the literature and carries its citation. Adding
;;; one is a research act; deleting one to make this pass is not.
;;; ------------------------------------------------------------------

(defparameter *variable-markers*
  '((lisa-user::lactose lisa-user::non-fermenter (:pseudomonas)
     "P. aeruginosa is the textbook non-lactose-fermenter, the standard contrast to
      the Enterobacteriaceae. NBK8035.")
    (lisa-user::urease lisa-user::positive (:pseudomonas)
     "72% of P. aeruginosa strains are urease-positive -- the paper exists because
      they gave false-positive rapid urease tests during H. pylori identification.
      J Clin Microbiol, PMC86256.")
    (lisa-user::indole lisa-user::positive (:proteus :bacteroides)
     "P. mirabilis is indole-negative, P. vulgaris positive. The B. fragilis group
      likewise splits: B. ovatus, B. thetaiotaomicron and B. uniformis are positive;
      B. fragilis, B. distasonis and B. vulgatus are negative. Antimicrob Agents
      Chemother, PMC183804.")
    (lisa-user::lactose lisa-user::fermenter (:serratia)
     "Serratia is a slow and variable lactose reactor, so the marker is not clean for
      it in either direction. NBK8035.")
    ;; The reciprocal readings, added with the rules that first read them. A marker
    ;; that cannot exclude an organism cannot do so in EITHER direction, so every
    ;; entry above implies one here -- which is why the negative polarities were the
    ;; place to look once the reciprocals were authored.
    (lisa-user::urease lisa-user::negative (:klebsiella :enterobacter :serratia
                                            :pseudomonas)
     "The variable urease producers. Klebsiella, Enterobacter and Serratia are
      variable (NBK8035) and 72% of P. aeruginosa is positive (PMC86256), so the
      other 28% reads negative -- none of them can be excluded by a negative urease.
      Only Proteus can, being rapid and strong. NBK442017.")
    (lisa-user::motility lisa-user::non-motile (:e-coli)
     "E. coli is flagellated and described as motile, but motility is variably
      EXPRESSED and a substantial minority of clinical isolates read non-motile on a
      standard tube test -- so a non-motile result cannot exclude it. Klebsiella,
      characteristically non-motile, is what the marker is actually for. NBK8035,
      NBK564298."))
  "(MARKER VALUE ORGANISMS-IT-CANNOT-EXCLUDE RATIONALE).

   Read as: any rule resting on MARKER = VALUE ALONE must leave every listed organism
   standing in its answer, because the literature says that marker does not discriminate
   for it. Rules that add a second bench marker are exempt -- see
   RULES-READING-ONLY-MARKER for why.")

(defparameter *bench-markers*
  '(lisa-user::lactose lisa-user::indole lisa-user::urease lisa-user::pigment
    lisa-user::motility lisa-user::hemolysis lisa-user::optochin lisa-user::bacitracin
    lisa-user::catalase lisa-user::coagulase lisa-user::novobiocin
    lisa-user::bile-esculin lisa-user::salt-tolerance lisa-user::sorbitol
    lisa-user::arabinose)
  "The bench tests. Host and site parameters are not among them: they gate WHERE a
   rule applies, they are not themselves discriminators between organisms.")

(defun rule-bench-markers (rule)
  (remove-if-not (lambda (m) (lisa:rule-premise-values rule m)) *bench-markers*))

(defun rules-reading-only-marker (marker value)
  "Every knowledge rule requiring MARKER = VALUE and NO OTHER bench marker.

   The restriction is the whole subtlety. A single marker cannot exclude an organism it
   does not discriminate -- but a CONJUNCTION can, because the second test may do what
   the first could not. Urease-positive alone cannot rule out Pseudomonas (72% are
   positive); urease-positive AND swarming can, because swarming motility is Proteus.
   Likewise lactose+ alone cannot exclude Serratia, but lactose+ with indole+ names
   E. coli. So this invariant governs the rules that rest on ONE bench finding, and
   leaves conjunctions to the judgement recorded in their provenance notes."
  (remove-if-not
   (lambda (rule)
     (and (member value (lisa:rule-premise-values rule marker) :test #'eq)
          (equal (list marker) (rule-bench-markers rule))))
   (neomycin:catalogue-rules)))

;;; ------------------------------------------------------------------
;;; Invariant 13 -- no UNDOCUMENTED silence.
;;;
;;; A parameter value the knowledge base declares but no rule premises on is INERT:
;;; the bridge accepts the assertion, returns success, and nothing happens. There is
;;; no error, and the consultation looks exactly as it would if the test had come
;;; back uninformative.
;;;
;;; That is sometimes the right answer -- some markers genuinely cannot discriminate
;;; among the organisms this corpus models, and the honest thing is to say so. What
;;; is never right is for it to be an ACCIDENT. Eleven values were inert before this
;;; invariant existed and not one of them was a decision: they were the polarities
;;; nobody wrote, left over from a corpus of ruling-out rules where a marker had only
;;; one direction to state.
;;;
;;; So each surviving one carries a reason here, checked in both directions. This file
;;; owns the first: a documented value that a rule now READS is a stale note. The
;;; second -- an advertised value that is inert and has NO entry -- is checked in
;;; prompt-tests.lisp (EVERY-INERT-VALUE-THE-PROMPT-MARKS-HAS-A-REASON), because the
;;; set of values a client may assert is enumerated by the prompt's fact tables and
;;; nowhere in the corpus: the bridge interns whatever value it is handed.
;;; ------------------------------------------------------------------

(defparameter *deliberately-inert*
  '((lisa-user::pigment lisa-user::none
     "Many clinical Serratia isolates are non-pigmented, so the ABSENCE of red
      pigment excludes nothing -- an answer naming every organism would be the
      honest one, and a rule that narrows to everything is not worth firing. The
      positive reading is the whole of this marker's value.")
    (lisa-user::hemolysis lisa-user::gamma
     "Non-hemolysis is characteristic of the enterococci but is also shown by group D
      and some viridans streptococci, and both enterococci here are already reached
      by bile-esculin plus salt tolerance on stronger evidence. Authoring it would
      add a wide answer that duplicates a narrow one.")
    (lisa-user::salt-tolerance lisa-user::intolerant
     "A bile-esculin-positive, salt-INTOLERANT chain former is a non-enterococcal
      group D streptococcus -- S. gallolyticus/bovis -- which this corpus does not
      model. The answer lies entirely outside the named organisms, so there is no set
      to assert. Under the open frame that hypothesis keeps its plausibility as
      residual ignorance, which is the correct outcome and needs no rule.")
    (lisa-user::age-group lisa-user::infant
     "Only NEONATE carries a rule (group B streptococcal disease of the newborn).
      The other bands have no epidemiological discriminator in this corpus, and
      inventing one would be belief without evidence.")
    (lisa-user::age-group lisa-user::adult
     "As INFANT: recorded for the chart, read by no rule.")
    (lisa-user::age-group lisa-user::elderly
     "As INFANT: recorded for the chart, read by no rule.")
    (lisa-user::culture-age nil
     "MYCIN used culture age for contamination reasoning -- an old culture growing a
      skin organism suggests a contaminant. That inference is not reconstructed here,
      so the parameter is accepted and unread at EVERY value."))
  "(PARAMETER VALUE RATIONALE), VALUE NIL meaning the parameter is unread at every
   value. Each entry is a decision that a marker cannot usefully discriminate among
   the organisms this corpus models -- not a gap left open.")

(deftest property-every-inert-value-is-a-decision ()
  ;; Direction 1: nothing documented as inert may have quietly acquired a rule.
  (let ((vocab (lisa:corpus-premise-vocabulary (neomycin:catalogue-rules))))
    (dolist (entry *deliberately-inert*)
      (destructuring-bind (param value rationale) entry
        (declare (ignore rationale))
        (let ((known (cdr (assoc param vocab))))
          (if (null value)
              (is (null known)
                  (format nil "~(~a~) is documented as unread at every value, but a ~
                               rule now premises on it -- update *deliberately-inert*"
                          param))
              (is (not (member value known :test #'eq))
                  (format nil "~(~a~)=~(~a~) is documented as inert, but a rule now ~
                               reads it -- the note is stale"
                          param value))))))))

(deftest property-variable-marker-cannot-exclude-an-organism ()
  (dolist (entry *variable-markers*)
    (destructuring-bind (marker value organisms rationale) entry
      (declare (ignore rationale))
      (dolist (rule (rules-reading-only-marker marker value))
        (let ((answer (neomycin:rule-answer rule)))
          (dolist (organism organisms)
            (is (member organism answer)
                (format nil "~(~a~) reads ~(~a~)=~(~a~), so it must not exclude ~(~a~)"
                        (lisa:rule-short-name rule) marker value organism))))))))

(deftest property-variable-marker-table-is-live ()
  ;; A table entry naming a marker no rule reads is dead weight that will quietly stop
  ;; guarding anything -- exactly how the corpus lost track of these in the first place.
  (dolist (entry *variable-markers*)
    (destructuring-bind (marker value organisms rationale) entry
      (declare (ignore organisms rationale))
      (is (rules-reading-only-marker marker value)
          (format nil "some single-marker rule still reads ~(~a~)=~(~a~)" marker value)))))
