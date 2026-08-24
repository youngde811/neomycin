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
                                 'lisa-user::compromised-aerobic-gram-neg-rod-narrows-to-opportunist-rods))
        (specific (lisa:find-rule (lisa:inference-engine)
                                  'lisa-user::hospital-acquired-compromised-aerobic-gram-neg-rod-narrows-to-opportunist-rods)))
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
                              'lisa-user::burn-blood-aerobic-gram-neg-rod-narrows-to-opportunist-rods))
        (compromised (lisa:find-rule (lisa:inference-engine)
                                     'lisa-user::compromised-aerobic-gram-neg-rod-narrows-to-opportunist-rods)))
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
    (lisa-user::white-blood-count lisa-user::low
     "INERT SINCE CATEGORY B. Its only rule --
      blood-low-wbc-aerobic-gram-neg-rod-narrows-to-salmonella -- was RETIRED as the
      wrong conditional docs/belief-conditional-audit.md 3.3 predicted: it fired ON a
      low white count, so it owed P(Salmonella | low WBC), while the 15-25% figure it
      cited is P(low WBC | typhoid), a sensitivity. Correcting the conditional does not
      rescue it, because leukopenia in gram-negative bacteraemia marks SEVERITY rather
      than species -- it occurs across E. coli, Klebsiella and Pseudomonas sepsis
      alike, so the honest answer is the whole aerobic set and adds nothing the Gram
      stain already said. Still assertable, because a clinician reporting a low count
      should have it recorded; it just no longer moves anything.")
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

;;; ------------------------------------------------------------------
;;; Invariant 14 -- a GRADED rule asserts exactly what its :belief declares.
;;;
;;; A flat rule's belief is applied by the engine, so the declaration and the
;;; assertion cannot disagree. A graded rule states its masses on the RHS, where
;;; nothing forces them to add up to the :belief in the header -- and the two are read
;;; by different callers. /rules and the conflict machinery quote the header; the
;;; consensus quotes the RHS. Left unchecked they would drift, and the drift would be
;;; invisible: every number involved is plausible on its own.
;;;
;;; This is the guard that keeps "a rule contributes exactly its :belief" true for the
;;; graded shape as well, which is what CHECK-RULE already enforces for the flat one.
;;; ------------------------------------------------------------------

(defun graded-rules ()
  (remove-if-not #'neomycin:rule-grading (candidates-rules)))

(deftest property-graded-rules-exist ()
  ;; If this ever fails, either the corpus lost its graded rules or RULE-GRADING
  ;; stopped recognising them -- and every invariant below would pass vacuously.
  (is (plusp (length (graded-rules)))
      "the corpus has graded rules for the invariants below to check"))

(deftest property-graded-masses-are-well-formed ()
  (dolist (rule (graded-rules))
    (let* ((grading (neomycin:rule-grading rule))
           (total (reduce #'+ (mapcar #'car grading))))
      (is (every (lambda (pair) (plusp (car pair))) grading)
          (format nil "~(~a~): every focal mass is positive"
                  (lisa:rule-short-name rule)))
      (is (every (lambda (pair) (and (consp (cdr pair)) (every #'keywordp (cdr pair))))
                 grading)
          (format nil "~(~a~): every focal set is a non-empty set of keywords"
                  (lisa:rule-short-name rule)))
      (is (<= total 1.0)
          (format nil "~(~a~): masses sum to ~,4F, which must not exceed 1"
                  (lisa:rule-short-name rule) total))
      ;; The residue is Theta, and it must be a real residue. A graded rule committing
      ;; everything claims the answer is settled, which is exactly the overclaim the
      ;; graded shape exists to avoid for epidemiological evidence.
      (is (< total 1.0)
          (format nil "~(~a~): leaves ~,4F on Theta -- epidemiology never settles it"
                  (lisa:rule-short-name rule) (- 1.0 total))))))

(deftest property-graded-total-equals-declared-belief ()
  ;; THE DRIFT GUARD. The header says how much the rule commits; the RHS says where it
  ;; goes. They must agree, or /rules and /conclusions quote different numbers for the
  ;; same rule and neither is wrong on its own terms.
  (dolist (rule (graded-rules))
    (let ((declared (abs (lisa:rule-belief rule)))
          (asserted (reduce #'+ (mapcar #'car (neomycin:rule-grading rule)))))
      (is (approx= declared asserted)
          (format nil "~(~a~): declares :belief ~,4F but asserts ~,4F"
                  (lisa:rule-short-name rule) declared asserted)))))

(deftest property-graded-focal-sets-are-distinct ()
  ;; Two focal sets that are EQUAL would be one focal set whose mass was written twice.
  ;; GRADED-ANSWER sums them silently -- correct arithmetic, but it hides an authoring
  ;; slip, and the declared-total guard above would then fail somewhere confusing.
  (dolist (rule (graded-rules))
    (let ((sets (mapcar #'cdr (neomycin:rule-grading rule))))
      (is (= (length sets) (length (remove-duplicates sets :test #'equal)))
          (format nil "~(~a~): no focal set is written twice"
                  (lisa:rule-short-name rule))))))

;;; ------------------------------------------------------------------
;;; Invariant 15 -- a CONTEXT rule gates on the findings its answer presupposes.
;;;
;;; A rule premising on the patient or the culture -- a burn, a compromised host, an
;;; infection site, an age band -- is saying "given this organism, that context makes
;;; these members likelier". It is NOT saying "this context implies this kind of
;;; organism". So it has to establish the kind first, by premising on the stain,
;;; morphology and aerobicity its answer takes for granted. Otherwise it fires on an
;;; organism its answer cannot possibly be.
;;;
;;; THIS IS NOT HYPOTHETICAL. Category B found three of them, and one was live in a
;;; shipped scenario: culture-2 asserts an ANAEROBIC gram-negative rod, and both
;;; pseudomonas context rules fired on it -- neither had ever gated on aerobicity --
;;; asserting {pseudomonas}, an obligate aerobe, against {bacteroides}. The corpus was
;;; contradicting itself, and the golden test credited the resulting conflict to the
;;; ambiguous Gram stain. The worst of the three never fired in any test at all:
;;; NEONATE-BETA-HEMOLYTIC premised on beta hemolysis and NOTHING else, so it fired on
;;; a beta-hemolytic E. COLI and answered S. agalactiae.
;;;
;;; The gates were missing for years and every layer stayed green, because a rule
;;; firing where it should not is invisible unless something asks what its answer
;;; presupposes. This asks.
;;; ------------------------------------------------------------------

(defparameter *context-parameters*
  '(lisa-user::burn lisa-user::compromised-host lisa-user::hospital-acquired
    lisa-user::recent-travel lisa-user::white-blood-count lisa-user::infection-site
    lisa-user::neutropenia lisa-user::prosthetic-material lisa-user::iv-drug-use
    lisa-user::age-group)
  "Patient-level facts. CULTURE-SITE is deliberately absent: it scopes a rule to a
   specimen without implying anything about the organism's morphology.")

(defparameter *answer-presuppositions*
  ;; (pool-name members required-gates), where a gate is (parameter . value).
  `(("the aerobic gram-negative rods"
     (:e-coli :klebsiella :salmonella :enterobacter :serratia :proteus :pseudomonas)
     ((lisa-user::gram . lisa-user::neg)
      (lisa-user::morphology . lisa-user::rod)
      (lisa-user::aerobicity . lisa-user::aerobic)))
    ("the anaerobic gram-negative rods"
     (:bacteroides)
     ((lisa-user::gram . lisa-user::neg)
      (lisa-user::morphology . lisa-user::rod)
      (lisa-user::aerobicity . lisa-user::anaerobic)))
    ("the gram-positive cocci"
     (:staphylococcus-aureus :staphylococcus-epidermidis :staphylococcus-saprophyticus
      :streptococcus-pneumoniae :streptococcus-pyogenes :streptococcus-agalactiae
      :streptococcus-viridans :enterococcus-faecalis :enterococcus-faecium)
     ((lisa-user::gram . lisa-user::pos)
      (lisa-user::morphology . lisa-user::coccus))))
  "What an answer confined to a pool takes for granted about the organism.")

(defun context-rules ()
  (remove-if-not (lambda (rule)
                   (some (lambda (p) (lisa:rule-premise-values rule p))
                         *context-parameters*))
                 (candidates-rules)))

(defun pool-for-answer (answer)
  "The entry of *ANSWER-PRESUPPOSITIONS* whose members contain every organism in
   ANSWER, or NIL when the answer straddles pools and so presupposes nothing."
  (find-if (lambda (entry)
             (every (lambda (o) (member o (second entry))) answer))
           *answer-presuppositions*))

(deftest property-context-rules-gate-on-what-their-answer-presupposes ()
  (dolist (rule (context-rules))
    (let* ((answer (neomycin:rule-answer rule))
           (pool (and answer (pool-for-answer answer))))
      (when pool
        (destructuring-bind (pool-name members gates) pool
          (declare (ignore members))
          (dolist (gate gates)
            (is (member (cdr gate) (lisa:rule-premise-values rule (car gate)) :test #'eq)
                (format nil "~(~a~) answers within ~A, so it must premise on ~
                             ~(~a~)=~(~a~) -- without it the rule fires on an organism ~
                             its answer cannot be"
                        (lisa:rule-short-name rule) pool-name
                        (car gate) (cdr gate)))))))))

(deftest property-context-gate-invariant-is-live ()
  ;; The table only guards what it can reach. If no context rule's answer falls inside
  ;; a pool, the invariant above passes without checking anything.
  (let ((covered (remove-if-not (lambda (r)
                                  (let ((a (neomycin:rule-answer r)))
                                    (and a (pool-for-answer a))))
                                (context-rules))))
    (is (plusp (length covered))
        "some context rule's answer sits inside a pool, so invariant 15 has work to do")))

;;; ------------------------------------------------------------------
;;; Invariant 16 -- a rule must not commit LESS than a same-support rule it subsumes.
;;;
;;; Scoped deliberately to pairs whose answers have the same SUPPORT, because that is
;;; the only place the specificity policy swaps one rule for another. Elsewhere a
;;; narrow rule committing more than a wide one is perfectly fine: they are independent
;;; evidence combined by Dempster's rule, not competing estimates of one probability,
;;; and the algebra already guarantees Bel(subset) <= Bel(superset) downstream. A
;;; broader version of this check reports 13 "violations" across the corpus and every
;;; one of them is a false alarm.
;;;
;;; Where it DOES bite, the consequence is real: the general rule is DROPPED, so if it
;;; committed more, the corpus loses mass by learning a fact. Measured before the fix:
;;; hospital-acquired-compromised committed 0.60 while the hospital-acquired rule it
;;; subsumes committed 0.70, so a patient who was both got LESS commitment than one who
;;; was merely hospital-acquired.
;;; ------------------------------------------------------------------

(deftest property-subsuming-rule-commits-at-least-as-much ()
  (let ((rules (candidates-rules))
        (pairs 0))
    (dolist (specific rules)
      (dolist (general rules)
        (when (and (not (eq specific general))
                   (lisa:rule-subsumes-p specific general)
                   (equal (neomycin:rule-answer specific) (neomycin:rule-answer general)))
          (incf pairs)
          (is (>= (abs (lisa:rule-belief specific)) (abs (lisa:rule-belief general)))
              (format nil "~(~a~) (~,2F) subsumes ~(~a~) (~,2F) and must not commit less ~
                           -- the general rule is DROPPED when both fire, so the corpus ~
                           would lose mass by learning a fact"
                      (lisa:rule-short-name specific) (abs (lisa:rule-belief specific))
                      (lisa:rule-short-name general) (abs (lisa:rule-belief general)))))))
    (is (plusp pairs)
        "some same-support subsumption pair exists, so this invariant has work to do")))

;;; ------------------------------------------------------------------
;;; Invariant 17 -- reciprocal readings of one marker carry EQUAL belief unless the
;;; rule's note states an asymmetry.
;;;
;;; A belief is the mass a piece of evidence commits to its answer -- how sure we are
;;; the true organism is in there. It is NOT a measure of how much the answer narrows.
;;; So two readings of the same test carry the same belief when the test is equally
;;; reliable both ways, REGARDLESS of how many organisms each reading admits. The
;;; corpus's own precedent is catalase: 0.70 for a three-member answer and 0.70 for a
;;; six-member one, with a note saying explicitly that the test is no more reliable in
;;; one direction than the other.
;;;
;;; Two pairs had drifted off that precedent with no justification -- lactose 0.70/0.60
;;; and urease 0.70/0.60 -- and the urease note argued for its lower number from
;;; INFORMATIVENESS ("one organism removed from eight"), which implies the opposite of
;;; what it concluded. Three pairs are asymmetric and stay that way, because each names
;;; a real asymmetry in the test; they are listed here so an unexplained one cannot hide
;;; among them.
;;; ------------------------------------------------------------------

(defparameter *asymmetric-markers*
  '((lisa-user::novobiocin
     "Resistance is close to S. saprophyticus-specific; sensitivity is the common case
      among coagulase-negative staphylococci and most of the organisms it admits are
      ones this corpus does not model.")
    (lisa-user::bacitracin
     "Susceptibility is the classic presumptive test for group A; RESISTANCE is shared
      with groups C and G, so it establishes less.")
    (lisa-user::optochin
     "Susceptibility separates S. pneumoniae cleanly; the viridans group is defined
      largely BY EXCLUSION from pneumococcus, which is a weaker basis."))
  "Markers whose two readings are legitimately unequal, each with the reason. Anything
   not listed here must be symmetric.")

(defun bench-rule-p (rule)
  "True when RULE reads only bench findings -- no patient or culture context.

   Context rules are excluded deliberately. NEONATE-BETA-HEMOLYTIC reads hemolysis, but
   it is not a second READING of the hemolysis test: it is an epidemiological rule that
   happens to gate on one. Comparing its belief against
   BETA-HEMOLYSIS-NARROWS-TO-BETA-HEMOLYTIC-STREP would be comparing two different kinds
   of claim."
  (notany (lambda (p) (lisa:rule-premise-values rule p)) *context-parameters*))

(defun marker-set-of (rule)
  (sort (copy-list (rule-bench-markers rule)) #'string< :key #'symbol-name))

(defun reciprocal-pairs-on (marker)
  "((RULE-A RULE-B) ...) -- bench rules reading MARKER that require exactly the same set
   of bench markers and differ ONLY in the value they demand for MARKER.

   Requiring the same marker SET is what makes these genuine reciprocals. Both novobiocin
   rules read coagulase AND novobiocin, so they pair; a rule reading novobiocin alongside
   something else entirely would not."
  (let ((rules (remove-if-not (lambda (r)
                                (and (bench-rule-p r)
                                     (lisa:rule-premise-values r marker)))
                              (candidates-rules)))
        (acc '()))
    (loop for (a . rest) on rules
          do (dolist (b rest)
               (when (and (equal (marker-set-of a) (marker-set-of b))
                          (not (equal (lisa:rule-premise-values a marker)
                                      (lisa:rule-premise-values b marker)))
                          (every (lambda (m)
                                   (or (eq m marker)
                                       (equal (lisa:rule-premise-values a m)
                                              (lisa:rule-premise-values b m))))
                                 (rule-bench-markers a)))
                 (push (list a b) acc))))
    acc))

(deftest property-reciprocal-readings-are-symmetric ()
  (dolist (marker *bench-markers*)
    (unless (assoc marker *asymmetric-markers*)
      (dolist (pair (reciprocal-pairs-on marker))
        (destructuring-bind (a b) pair
          (is (= (abs (lisa:rule-belief a)) (abs (lisa:rule-belief b)))
              (format nil "~(~a~) is read two ways at ~,2F and ~,2F (~(~a~) / ~(~a~)) -- a ~
                           marker with no declared asymmetry must weight its readings ~
                           equally, because a belief measures RELIABILITY and not how much ~
                           the answer narrows. Fix the belief, or list it in ~
                           *asymmetric-markers* with the reason"
                      marker
                      (abs (lisa:rule-belief a)) (abs (lisa:rule-belief b))
                      (lisa:rule-short-name a) (lisa:rule-short-name b))))))))

(deftest property-asymmetric-marker-table-is-live ()
  ;; An entry naming a marker whose readings are in fact equal, or which no longer has a
  ;; reciprocal pair at all, is dead weight that will quietly stop guarding anything.
  (dolist (entry *asymmetric-markers*)
    (destructuring-bind (marker rationale) entry
      (is (and (stringp rationale) (plusp (length rationale)))
          (format nil "~(~a~) is documented as asymmetric with a reason" marker))
      (let ((pairs (reciprocal-pairs-on marker)))
        (is pairs
            (format nil "~(~a~) still has a reciprocal pair to be asymmetric ABOUT" marker))
        (is (some (lambda (p) (/= (abs (lisa:rule-belief (first p)))
                                  (abs (lisa:rule-belief (second p)))))
                  pairs)
            (format nil "~(~a~) is listed as asymmetric but its readings now carry the ~
                         same belief -- drop it from *asymmetric-markers*" marker))))))

;;; ------------------------------------------------------------------
;;; Invariant 18 -- every parameter the corpus can HEAR is explicitly scoped by the
;;; bridge.
;;;
;;; The bridge files each asserted fact against a context -- patient, culture or
;;; organism -- from a lookup table, and that lookup DEFAULTED to :organism for
;;; anything it did not know. The default was silent and total.
;;;
;;; `neutropenia', `prosthetic-material', `iv-drug-use' and `age-group' were missing.
;;; Each was therefore filed against the ORGANISM while the rules that read them join
;;; through the PATIENT, so four rules -- one of them the only rule reading each of
;;; those parameters -- were UNFIRABLE through the HTTP bridge. They fired perfectly
;;; from the Lisp drivers, which assert `(of p1)' directly, which is exactly why the
;;; suite never noticed: every scenario test goes through the drivers and the bridge
;;; is a different layer.
;;;
;;; Found by a model-in-the-loop release check, when the model reported that it had
;;; asserted neutropenia, could not find the rule in the trace, and declined to invent
;;; a reason. The clinician-facing cost was total: a neutropenic patient's neutropenia
;;; contributed nothing and nothing said so.
;;; ------------------------------------------------------------------

(deftest property-every-heard-parameter-is-explicitly-scoped ()
  (let ((vocab (lisa:corpus-premise-vocabulary (neomycin:catalogue-rules))))
    (is (plusp (length vocab)) "the corpus has a premise vocabulary to check")
    (dolist (entry vocab)
      (let* ((param (first entry))
             (name (string-downcase (symbol-name param))))
        (is (assoc name lisa-bridge::*param-level* :test #'string=)
            (format nil "~(~a~) is read by some rule, so lisa-bridge::*param-level* ~
                         must scope it EXPLICITLY -- the :organism default silently ~
                         misfiles patient-level facts and makes their rules unfirable ~
                         through the bridge"
                    param))))))

(deftest property-patient-parameters-scope-to-the-patient ()
  ;; The half that catches a WRONG entry rather than a missing one. Every parameter a
  ;; rule reads alongside a `patient' premise is patient-level by construction.
  (let ((patient-params '()))
    ;; Derived from *context-parameters*, which invariant 15 already maintains.
    (dolist (param *context-parameters*)
      (when (some (lambda (r) (lisa:rule-premise-values r param)) (candidates-rules))
        (push param patient-params)))
    (is (plusp (length patient-params)) "some context parameter is read by a rule")
    (dolist (param patient-params)
      (let ((name (string-downcase (symbol-name param))))
        (is (eq :patient (lisa-bridge::param-level name))
            (format nil "~(~a~) is a patient-level context parameter and must scope to ~
                         :patient, not ~(~a~)"
                    param (lisa-bridge::param-level name)))))))

;;; ------------------------------------------------------------------
;;; Invariant 19 -- an evidence group is exactly the set of rules that share a shape.
;;;
;;; A rule may declare `:evidence-group' in its provenance, meaning THESE RULES REST ON
;;; THE SAME UNDERLYING EVIDENCE. Only one member of a group contributes to a
;;; differential; the rest are dropped before combination, because Dempster's rule
;;; assumes independence they do not have.
;;;
;;; That declaration is load-bearing and unverifiable by inspection, so it is checked
;;; from both sides:
;;;
;;;   * every member of a group must actually SHARE A SHAPE with the others -- grouping
;;;     rules that genuinely disagree would silently discard real evidence; and
;;;   * any two graded rules that DO share a shape must be in the same group -- which is
;;;     the mechanical test docs/base-rate-investigation.md section 6 called for, and
;;;     which would have caught the original defect when the four rules were authored one
;;;     after another from overlapping literature.
;;;
;;; "Shape" is each focal mass as a fraction of the rule's own commitment. The tolerance
;;; is deliberately loose: it exists to catch an OMISSION, not to define the semantics.
;;; ------------------------------------------------------------------

(defparameter +shape-tolerance+ 0.08
  "How far two normalised focal masses may differ before the rules count as
   differently-shaped. Loose on purpose: this detects a missing declaration, it does not
   decide one.")

(defun rule-shape (rule)
  "((SET . FRACTION) ...) -- RULE's grading normalised by its own commitment, or NIL."
  (let ((g (neomycin:rule-grading rule)))
    (when g
      (let ((total (reduce #'+ (mapcar #'car g))))
        (when (plusp total)
          (sort (mapcar (lambda (pair) (cons (cdr pair) (/ (car pair) total))) g)
                #'string< :key (lambda (x) (format nil "~{~a~^,~}" (car x)))))))))

(defun shapes-match-p (a b)
  "True when two rules' normalised gradings agree on every focal set within tolerance."
  (let ((sa (rule-shape a)) (sb (rule-shape b)))
    (and sa sb
         (equal (mapcar #'car sa) (mapcar #'car sb))
         (every (lambda (x y) (< (abs (- (cdr x) (cdr y))) +shape-tolerance+)) sa sb))))

(defun graded-rules-with-groups ()
  (remove-if-not #'neomycin:rule-grading (candidates-rules)))

(deftest property-evidence-group-members-share-a-shape ()
  (let ((groups (make-hash-table :test #'eq)))
    (dolist (rule (graded-rules-with-groups))
      (let ((g (neomycin:rule-evidence-group rule)))
        (when g (push rule (gethash g groups)))))
    (is (plusp (hash-table-count groups))
        "the corpus declares at least one evidence group")
    (maphash
     (lambda (group members)
       (is (> (length members) 1)
           (format nil "evidence group ~(~a~) has ~D member(s) -- a group of one ~
                        suppresses nothing and should be dropped"
                   group (length members)))
       (loop for (a . rest) on members
             do (dolist (b rest)
                  (is (shapes-match-p a b)
                      (format nil "~(~a~) and ~(~a~) are in evidence group ~(~a~) but ~
                                   their shapes differ -- grouping rules that disagree ~
                                   discards real evidence"
                              (lisa:rule-short-name a) (lisa:rule-short-name b) group)))))
     groups)))

(deftest property-same-shaped-rules-are-grouped ()
  ;; The omission half. This is the check that was missing when the four opportunist
  ;; rules were authored in v0.13, one after another, from overlapping literature.
  (let ((rules (graded-rules-with-groups)))
    (loop for (a . rest) on rules
          do (dolist (b rest)
               (when (shapes-match-p a b)
                 (is (and (neomycin:rule-evidence-group a)
                          (eq (neomycin:rule-evidence-group a)
                              (neomycin:rule-evidence-group b)))
                     (format nil "~(~a~) and ~(~a~) assert the SAME SHAPE but are not in ~
                                  one evidence group -- they will be combined as ~
                                  independent evidence and count the same fact twice"
                             (lisa:rule-short-name a) (lisa:rule-short-name b))))))))

;;; ------------------------------------------------------------------
;;; Invariant 20 -- every rule's :provenance is a well-formed property list.
;;;
;;; This looks like belt-and-braces and is not. A `:note' containing an UNESCAPED
;;; double quote silently ends the string early, turns the following words into symbols,
;;; and leaves the plist an ODD number of elements. The rule still compiles. The corpus
;;; still loads. The suite still passes -- because GETF only errors when it walks the
;;; whole list without finding its key, so every LOOKUP THAT SUCCEEDS hides the damage.
;;;
;;; That is exactly how it shipped in v0.14.0: `lactose-non-fermenter' carried a
;;; malformed provenance through a green suite and a green release check, and surfaced
;;; only when a later change asked for a key that rule did not have -- at which point
;;; GET /rules returned an error for the WHOLE CORPUS, not just that rule.
;;;
;;; The lesson is the shape, not the typo: a check that passes because it never asks
;;; the failing question is not a check.
;;; ------------------------------------------------------------------

(deftest property-provenance-is-a-well-formed-plist ()
  (dolist (rule (neomycin:catalogue-rules))
    (let ((prov (lisa:rule-provenance rule)))
      (when prov
        (is (evenp (length prov))
            (format nil "~(~a~): :provenance has ~D elements -- an odd length means a ~
                         string ended early, almost always an unescaped double quote in ~
                         the :note"
                    (lisa:rule-short-name rule) (length prov)))
        (is (loop for (k nil) on prov by #'cddr always (keywordp k))
            (format nil "~(~a~): every :provenance key must be a keyword; got ~{~S ~}"
                    (lisa:rule-short-name rule)
                    (loop for (k nil) on prov by #'cddr unless (keywordp k) collect k)))
        ;; The operative half: a lookup for an ABSENT key must not blow up. This is the
        ;; call that failed in production while every present-key lookup succeeded.
        (is (ignore-errors (getf prov :a-key-no-rule-declares) t)
            (format nil "~(~a~): looking up an absent :provenance key errors -- the ~
                         plist is malformed in a way present-key lookups hide"
                    (lisa:rule-short-name rule)))))))
