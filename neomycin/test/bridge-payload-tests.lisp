;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: Tests for the payloads /why, /rules and /conclusions serve -- the
;; whole Lisp path each handler runs, minus HTTP.
;;
;; WHY THIS FILE EXISTS. The v0.11 promotion retired organism-identity, and /why went
;; on looking for it: it returned 404 for every organism in the corpus, and did so
;; through a green 892-assertion suite and a "passing" bin/test-why.sh. Nothing was
;; wrong with either -- the suite tested the engine and never called the handler, and
;; the smoke script piped a 404 body through json.tool and exited 0. The defect was
;; found by a clinician-driver session, which is a slow and expensive way to discover
;; that an endpoint has been dead since the refactor.
;;
;; The lesson is narrow and worth stating: a payload builder is code, and code that no
;; test calls will be broken by the next refactor without anyone hearing about it.
;; These tests call them.

(in-package "LISA-TEST")

;;; ------------------------------------------------------------------
;;; /why
;;; ------------------------------------------------------------------

(defun why-for (organism)
  "The /why payload for ORGANISM, built exactly as the handler builds it."
  (let ((entity (neomycin:entity-naming organism)))
    (and entity (neomycin::why-payload organism entity))))

(deftest why-explains-a-named-organism ()
  ;; The regression itself: every organism the corpus can conclude must be
  ;; explicable. This is the assertion whose absence let /why 404 for two commits.
  (run-scenario 'lisa-user::culture-1 :candidates)
  (dolist (organism '(:pseudomonas :klebsiella))
    (let ((payload (why-for organism)))
      (is (hash-table-p payload)
          (format nil "/why returns a payload for ~(~a~)" organism))
      (is (string= (gethash "organism" payload) (string-downcase (symbol-name organism)))
          "the payload echoes the organism asked about")
      (is (plusp (length (gethash "argument" payload)))
          "the argument is not empty"))))

(deftest why-reports-answers-that-exclude-as-well-as-admit ()
  ;; The load-bearing property. Nothing argues against anything here, so an
  ;; explanation that showed only the admitting answers could never account for why
  ;; a hypothesis is held DOWN -- and a reader would be left to assume some rule
  ;; objected. Both kinds must be present, flagged.
  ;;
  ;; RE-POINTED FROM culture-1 BY CATEGORY B, and the reason is the finding. In
  ;; culture-1 every answer now ADMITS klebsiella: the epidemiological rules grade
  ;; their answers instead of asserting singletons, so none of them says klebsiella is
  ;; impossible any more, and the test had nothing left to find. That is the corpus
  ;; being more honest, not the property lapsing.
  ;;
  ;; Exclusion is now what BENCH findings do, which is where it belonged. In culture-4
  ;; the beta-hemolysis answer {pyogenes, agalactiae} genuinely excludes pneumococcus.
  (run-scenario 'lisa-user::culture-4 :candidates)
  (let* ((payload (why-for :streptococcus-pneumoniae))
         (argument (coerce (gethash "argument" payload) 'list))
         (admitting (remove-if-not (lambda (a) (gethash "admits" a)) argument))
         (excluding (remove-if (lambda (a) (gethash "admits" a)) argument)))
    (is (plusp (length admitting)) "some answer admits pneumococcus")
    (is (plusp (length excluding))
        "the beta-hemolytic answers are reported too, flagged admits=false")
    (is (every (lambda (a) (plusp (length (gethash "rules" a)))) argument)
        "every answer names the rules that gave it")))

(deftest why-reports-the-grading-of-a-graded-answer ()
  ;; A graded answer that reported only NARROWS_TO would read as though the evidence
  ;; had no view on which member is likelier -- the exact opposite of what grading
  ;; exists to say. The distribution has to reach the explanation, or a narrator will
  ;; describe an epidemiological rule as indifferent between six organisms.
  (run-scenario 'lisa-user::culture-1 :candidates)
  (let* ((payload (why-for :pseudomonas))
         (argument (coerce (gethash "argument" payload) 'list))
         (graded (remove-if-not (lambda (a) (gethash "grading" a)) argument)))
    (is (plusp (length graded)) "culture-1's context answers report their grading")
    (is (every (lambda (a) (plusp (length (gethash "grading" a)))) graded)
        "and each grading is non-empty")
    (is (some (lambda (a) (plusp (gethash "mass_for_organism" a))) graded)
        "the mass this evidence puts on pseudomonas specifically is reported")
    (is (every (lambda (a)
                 (let ((masses (map 'list (lambda (g) (gethash "mass" g))
                                    (gethash "grading" a))))
                   (equal masses (sort (copy-list masses) #'>))))
               graded)
        "strongest focal set first, so a narrator reading in order leads correctly")))

(deftest why-intersection-is-what-the-admitting-answers-leave ()
  ;; RE-POINTED with the test above, and for the same reason. In culture-1 the
  ;; admitting answers now intersect to all six opportunist rods rather than to
  ;; klebsiella alone -- correct, because nothing in that consultation is a bench
  ;; finding and epidemiology does not narrow to one organism.
  (run-scenario 'lisa-user::culture-4 :candidates)
  (let ((payload (why-for :streptococcus-pyogenes)))
    (is (equalp (gethash "intersection" payload) #("streptococcus-pyogenes"))
        "the bench answers admitting pyogenes intersect to it alone")))

(deftest why-intersection-does-not-over-narrow-on-epidemiology ()
  ;; The companion property, and the one Category B is about: when every answer is
  ;; epidemiological the intersection must stay WIDE. If this ever collapses to a
  ;; single organism again, some rule has gone back to asserting a singleton it cannot
  ;; support, and a clinician will be told the answer is settled when it is not.
  (run-scenario 'lisa-user::culture-1 :candidates)
  (let ((payload (why-for :pseudomonas)))
    (is (> (length (gethash "intersection" payload)) 1)
        "burn + immunocompromised does not identify an organism, and must not say it does")))

(deftest why-carries-provenance-for-every-rule-it-cites ()
  ;; The citation path. A rule appearing in an explanation without its provenance
  ;; invites the narrator to supply one from memory, which is the failure mode the
  ;; whole WHY facility exists to prevent.
  (run-scenario 'lisa-user::culture-1 :candidates)
  (let* ((payload (why-for :pseudomonas))
         (rules (loop for answer across (gethash "argument" payload)
                      append (coerce (gethash "rules" answer) 'list))))
    (is (plusp (length rules)) "rules are cited")
    (is (every (lambda (r) (gethash "provenance" r)) rules)
        "every cited rule carries its provenance")
    (is (every (lambda (r) (plusp (length (gethash "evidence" (gethash "provenance" r)))))
               rules)
        "every provenance carries at least one verified citation")))

(deftest why-belief-interval-brackets-correctly ()
  (run-scenario 'lisa-user::culture-1 :candidates)
  (let ((payload (why-for :klebsiella)))
    (is (<= 0.0 (gethash "bel" payload) (gethash "pl" payload) 1.0)
        "0 <= bel <= pl <= 1")))

(deftest why-answers-always-name-a-rule-even-under-subsumption ()
  ;; THE GAP THAT LET AN ATTRIBUTION-FREE ANSWER SHIP. Every /why test above runs on
  ;; culture-1 or culture-4, where nothing is subsumed -- so "every answer names the
  ;; rules that gave it" was only ever checked where it could not fail.
  ;;
  ;; culture-1a is the case with subsumption: three context rules fire and the most
  ;; specific one drops the other two. Their FACTS remain in working memory, and
  ;; ANSWER-DETAILS used to report them with a belief and an EMPTY rules array -- a
  ;; number in the explanation that no surviving rule stood behind, which is precisely
  ;; what the WHY facility exists to make impossible. Found by re-measuring
  ;; docs/clinician-scenarios.md against the engine, not by this suite.
  (run-scenario 'lisa-user::culture-1a :candidates)
  (dolist (organism '(:pseudomonas :klebsiella :e-coli))
    (let* ((payload (why-for organism))
           (argument (coerce (gethash "argument" payload) 'list)))
      (is (plusp (length argument))
          (format nil "~(~a~) has an argument at all" organism))
      (is (every (lambda (a) (plusp (length (gethash "rules" a)))) argument)
          (format nil "every answer in ~(~a~)'s argument names at least one rule"
                  organism))))
  ;; And the subsumed rules must not be cited anywhere either -- they were dropped for
  ;; conditioning on nothing extra, so quoting them would overstate the evidence.
  (let* ((payload (why-for :e-coli))
         (cited (loop for a across (gethash "argument" payload)
                      append (map 'list (lambda (r) (gethash "rule" r)) (gethash "rules" a)))))
    (is (not (member "compromised-aerobic-gram-neg-rod-narrows-to-opportunist-rods"
                     cited :test #'string=))
        "the subsumed compromised-host rule is not cited")
    (is (member "hospital-acquired-compromised-aerobic-gram-neg-rod-narrows-to-opportunist-rods"
                cited :test #'string=)
        "the specific rule that subsumed it is")))

(deftest why-declines-an-organism-no-rule-named ()
  ;; A 404 here is correct and must stay reachable: the honest answer for an
  ;; unmodelled organism is that nothing has spoken to it, not a fabricated zero.
  (run-scenario 'lisa-user::culture-1 :candidates)
  (is (null (neomycin:entity-naming :nocardia))
      "an organism no rule named resolves to no entity, and /why 404s"))

;;; ------------------------------------------------------------------
;;; /rules
;;; ------------------------------------------------------------------

(deftest rules-summary-describes-the-real-corpus ()
  ;; The other half of the same regression: the summary went on reporting
  ;; organism-class and organism-identity, and every list came back EMPTY while the
  ;; endpoint returned 200. An empty list is not a visible failure, so it needs a
  ;; test that says what non-empty means.
  (let* ((rules (neomycin:catalogue-rules))
         (summary (neomycin::rules-summary rules))
         (organisms (gethash "organisms" summary)))
    (is (= (length rules) (gethash "total" summary)) "total counts the corpus")
    (is (plusp (length organisms)) "the organism list is not empty")
    (is (find "pseudomonas" organisms :test #'string=) "and names real organisms")
    (is (= (length rules)
           (loop for count being the hash-values of (gethash "resolutions" summary)
                 sum count))
        "every rule is counted in exactly one resolution bucket")))

(deftest every-rule-states-an-answer ()
  ;; RULE-ANSWER strips the quote the RHS carries. If that ever stops working the
  ;; catalogue renders Lisp reader syntax at a JSON client -- which it did, as
  ;; "'(staphylococcus-aureus ...)", for as long as nothing checked.
  (dolist (rule (neomycin:catalogue-rules))
    (let ((answer (neomycin:rule-answer rule)))
      (is (and (consp answer) (every #'keywordp answer))
          (format nil "~(~a~) answers with a set of keywords"
                  (lisa:rule-short-name rule))))))

(deftest rules-json-renders-a-usable-entry ()
  (let* ((rule (find-if (lambda (r)
                          (string-equal (symbol-name (lisa:rule-short-name r))
                                        "burn-blood-aerobic-gram-neg-rod-narrows-to-opportunist-rods"))
                        (neomycin:catalogue-rules)))
         (json (and rule (neomycin::rule->json rule))))
    (is (hash-table-p json) "the rule is in the catalogue")
    ;; RE-POINTED BY CATEGORY B. This rule used to answer {pseudomonas} at resolution 1
    ;; -- a claim that a burn patient's gram-negative bacteraemia could be nothing else.
    ;; It now GRADES the six organisms burn-unit surveillance actually reports.
    (is (equalp (gethash "narrows_to" json)
                #("e-coli" "enterobacter" "klebsiella" "proteus" "pseudomonas" "serratia"))
        "its answer renders as names")
    (is (= 6 (gethash "resolution" json)) "resolution is the answer's size")
    (is (plusp (length (gethash "premises" json))) "its premises are reported")
    (is (gethash "provenance" json) "its provenance is carried")
    ;; The grading is the point: narrows_to alone would say the six are
    ;; indistinguishable, and burn-unit data say they are not.
    (let ((grading (gethash "grading" json)))
      (is (and grading (plusp (length grading))) "a graded rule reports its grading")
      (when (and grading (plusp (length grading)))
        (is (equalp (gethash "organisms" (aref grading 0)) #("pseudomonas"))
            "strongest first, and in a burn that is pseudomonas")))))

;;; ------------------------------------------------------------------
;;; /conclusions
;;; ------------------------------------------------------------------

(deftest conclusions-reports-the-grading-of-a-graded-answer ()
  ;; /conclusions is the payload a client reads FIRST, and it was the last one to learn
  ;; about grading. Before this, culture-1's two context answers rendered as a bare 0.40
  ;; and 0.60 over the same six organisms -- indistinguishable, when one leans
  ;; Pseudomonas and the other leans E. coli, which is the entire reason the
  ;; differential lands where it does. /why and /rules both reported it; this did not.
  (run-scenario 'lisa-user::culture-1 :candidates)
  (let* ((payload (neomycin:conclusions-payload))
         (answers (coerce (gethash "answers" (aref (gethash "organisms" payload) 0)) 'list))
         (graded (remove-if-not (lambda (a) (gethash "grading" a)) answers)))
    (is (= 2 (length graded)) "culture-1's two context answers report their grading")
    (is (every (lambda (a) (plusp (length (gethash "grading" a)))) graded)
        "and neither grading is empty")
    ;; The two must lean OPPOSITE ways -- that is the case's whole character, and a
    ;; payload that flattened it would hide the disagreement K is measuring.
    (let ((leaders (mapcar (lambda (a) (aref (gethash "organisms" (aref (gethash "grading" a) 0)) 0))
                           graded)))
      (is (member "pseudomonas" leaders :test #'string=) "one answer leads with pseudomonas")
      (is (member "e-coli" leaders :test #'string=) "the other leads with e-coli"))
    ;; A flat bench answer must NOT sprout a grading field.
    (is (notevery (lambda (a) (gethash "grading" a)) answers)
        "the stain answers stay flat -- grading is emitted only where it exists")))

(deftest conclusions-payload-is-well-formed ()
  (run-scenario 'lisa-user::culture-1 :candidates)
  (let* ((payload (neomycin:conclusions-payload))
         (organisms (gethash "organisms" payload)))
    (is (plusp (length organisms)) "at least one entity is reported")
    (let ((differential (aref organisms 0)))
      (is (gethash "hypotheses" differential) "the differential names hypotheses")
      (is (numberp (gethash "conflict" differential)) "K is reported")
      (is (numberp (gethash "theta_mass" differential))
          "m(Theta) for the consultation is reported, under its own name"))
    (is (plusp (length (gethash "conclusions" payload)))
        "the flat leading-calls list is populated")))
;;; ------------------------------------------------------------------
;;; /rules ?premises= answers by PARAMETER as well as by value.
;;;
;;; Found by the release-check consultation, not by this suite. The filter compared
;;; values only, so `?premises=urease' returned zero rules -- and the model, having
;;; asked exactly that, told a clinician there was no rule reading a negative urease
;;; and that it could not rule out Proteus. Both false.
;;;
;;; The failure mode is the one this project keeps meeting: a query that returns
;;; NOTHING is indistinguishable from a corpus that CONTAINS nothing.
;;; ------------------------------------------------------------------

(deftest rules-premises-filter-matches-parameter-names ()
  (let ((by-name (neomycin::matching-rules :premises "urease")))
    (is (plusp (length by-name))
        "?premises=urease finds the rules that read urease -- naming the parameter is
         a sensible question and used to return silence")
    ;; Both polarities, which is the point of asking by parameter: a clinician wants
    ;; to know what the TEST is worth, not what one of its readings is worth.
    (dolist (expected '(lisa-user::urease-positive-narrows-to-urease-producers
                        lisa-user::urease-negative-narrows-to-non-proteus-rods))
      (is (find expected by-name :key #'lisa:rule-short-name)
          (format nil "~(~a~) is among them" expected)))))

(deftest rules-premises-filter-still-matches-values ()
  ;; The original behaviour, unchanged: naming a reading narrows to that reading.
  (let ((by-value (neomycin::matching-rules :premises "non-motile")))
    (is (plusp (length by-value)) "?premises=non-motile finds the rule reading it")
    (is (every (lambda (r) (member 'lisa-user::non-motile
                                   (lisa:rule-premise-values r 'lisa-user::motility)))
               by-value)
        "and only rules that actually read that value")))

(deftest rules-premises-filter-is-honestly-empty ()
  ;; An empty result must still be possible, or the filter would be useless. `oxidase'
  ;; is not a parameter this corpus has at all.
  (is (zerop (length (neomycin::matching-rules :premises "oxidase")))
      "a finding the corpus does not model returns nothing"))

;;; ------------------------------------------------------------------
;;; `no rival' on the wire
;;; ------------------------------------------------------------------
;;;
;;; MARGIN_AGAINST names the nearest answer that CONTRADICTS the leader, and there
;;; often is none -- the leading answer stands unopposed. That absence was emitted as
;;; the keyword :NULL, which jzon stringifies to the JSON STRING "NULL": truthy in
;;; every client language there is. A Python consumer writing `if margin_against:'
;;; read "there IS a rival" in precisely the case where there was none.
;;;
;;; It cost a real misreading. In the clinician session of 2026-08-24 a payload with
;;; no rival and a seven-organism leading answer was narrated as "E. coli leading over
;;; the runner-up group" -- a contest the engine had explicitly declined to describe.
;;;
;;; These assert the SERIALIZED form, not the Lisp value, because the Lisp value was
;;; never the bug: :NULL is a perfectly good sentinel until jzon renders it.

(defun payload-json (payload)
  (com.inuoe.jzon:stringify payload))

(deftest conclusions-emits-real-json-null-for-no-rival ()
  (run-scenario 'lisa-user::culture-1 :candidates)
  (let* ((json (payload-json (neomycin:conclusions-payload))))
    (is (search "\"margin_against\":null" json)
        "culture-1 leaves the leading answer unopposed, so /conclusions must emit a
         real JSON null for margin_against")
    (is (not (search "\"margin_against\":\"NULL\"" json))
        "margin_against is serialized as the STRING \"NULL\", which is truthy in
         every client language -- the trap this test exists to hold shut")))

(deftest why-emits-real-json-null-for-no-rival ()
  (run-scenario 'lisa-user::culture-1 :candidates)
  (let ((json (payload-json (why-for :e-coli))))
    (is (search "\"margin_against\":null" json)
        "/why must report `no contradicting answer' the same way /conclusions does")
    (is (not (search "\"margin_against\":\"NULL\"" json))
        "/why is serializing the string \"NULL\" again")))

(deftest a-named-rival-still-serializes-as-a-list ()
  ;; The other half: fixing the null must not turn a REAL rival into one. culture-4
  ;; is the case where two answers genuinely contradict.
  (run-scenario 'lisa-user::culture-4 :candidates)
  (let ((json (payload-json (why-for :streptococcus-pneumoniae))))
    (is (not (search "\"margin_against\":null" json))
        "culture-4 has a contradicting answer, so margin_against must name it")))

;;; ------------------------------------------------------------------
;;; Two ignorances, two names
;;; ------------------------------------------------------------------
;;;
;;; m(Theta) for the consultation and pl-bel for a hypothesis are different
;;; quantities, and both were emitted as "ignorance" in the same payload. An organism
;;; at bel 0.91 / pl 1.00 was duly narrated as having "essentially no residual
;;; ignorance (0.002)" -- the entity's m(Theta) -- when its own was 0.09. The entity
;;; figure is THETA_MASS now; the per-hypothesis one keeps the name, which is also
;;; what the therapy payload's susceptibilities use.

(deftest entity-ignorance-is-named-theta-mass ()
  (run-scenario 'lisa-user::culture-1 :candidates)
  (let* ((payload (neomycin:conclusions-payload))
         (organism (aref (gethash "organisms" payload) 0)))
    (is (nth-value 1 (gethash "theta_mass" organism))
        "the entity-level m(Theta) is reported as theta_mass")
    (is (not (nth-value 1 (gethash "ignorance" organism)))
        "no key called `ignorance' survives at entity level -- that name now belongs
         to the per-hypothesis quantity alone")))

(deftest hypothesis-ignorance-is-still-pl-minus-bel ()
  ;; The other half of the rename: per hypothesis the name is unchanged AND the
  ;; arithmetic holds, which is what the release check asserts against prose.
  (run-scenario 'lisa-user::culture-1 :candidates)
  (let* ((payload (neomycin:conclusions-payload))
         (organism (aref (gethash "organisms" payload) 0)))
    (loop for h across (gethash "hypotheses" organism)
          for bel = (gethash "bel" h)
          for pl = (gethash "pl" h)
          for ign = (gethash "ignorance" h)
          do (is (< (abs (- ign (- pl bel))) 1d-9)
                 (format nil "~A: ignorance must be pl - bel"
                         (gethash "value" h))))))
