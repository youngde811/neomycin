;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: Guards on the LLM system prompt (src/llm/claude/system-prompt.md)
;; against the compiled rulebase.
;;
;; WHY THIS FILE EXISTS. The prompt used to carry a hand-transcribed catalogue of
;; all 50 rules -- names, beliefs, premises, rationale -- which is a second source
;; of truth for something the Lisp side already guards. Retire a species or
;; re-weight a rule and the markdown silently disagreed with the engine, with
;; nothing to catch it; the corpus had a staleness guard (property-tests.lisp) and
;; the prompt had none. /rules retired the catalogue, so what is left to protect
;; is small but not nothing: the prompt still quotes rule names in its worked
;; examples, and it still states the corpus counts.
;;
;; These are deliberately the only two claims about the rulebase the prompt is
;; allowed to make from its own text. Everything else it must ask for.

(in-package "LISA-TEST")

(defun system-prompt-text ()
  "The LLM system prompt, as text."
  (with-open-file (in (asdf:system-relative-pathname
                       "neomycin" "src/llm/claude/system-prompt.md")
                      :external-format :utf-8)
    (let ((text (make-string (file-length in))))
      (subseq text 0 (read-sequence text in)))))

(defun backticked-tokens (text)
  "Every `backtick-delimited` span in TEXT."
  (let ((acc '())
        (start 0))
    (loop
      (let* ((open (position #\` text :start start))
             (close (and open (position #\` text :start (1+ open)))))
        (unless close (return (nreverse acc)))
        (push (subseq text (1+ open) close) acc)
        (setf start (1+ close))))))

(defun rule-reference-p (token)
  "True when TOKEN is written like a rule name. The corpus names every rule for
   what it does -- X-narrows-to-Y -- which is what lets this guard tell a quoted
   RULE from a quoted fact type or tool name without a list to maintain. A rule
   named outside that convention is simply not guarded here.

   THIS PREDICATE WENT BLIND ONCE. It matched the pre-v0.11 conventions
   (-suggests-, -argues-against-), and when the corpus was renamed wholesale to
   -narrows-to- every token stopped matching, so guard 1 passed by checking
   nothing for the whole of v0.11. A guard whose subject can be renamed out from
   under it needs its own guard, which is RULE-NAMING-CONVENTION-STILL-HOLDS below."
  (search "-narrows-to-" token))

(deftest rule-naming-convention-still-holds ()
  ;; The meta-guard. RULE-REFERENCE-P recognizes rule names by convention rather
  ;; than by list, which is what keeps it maintenance-free -- and also what let it
  ;; silently match nothing after the v0.11 rename. Assert the convention itself,
  ;; so the next rename fails HERE, loudly, instead of quietly disarming guard 1.
  (let ((rules (domain-rules)))
    (is (plusp (length rules)) "there are domain rules to check")
    (dolist (rule rules)
      (let ((name (string-downcase (symbol-name (lisa:rule-short-name rule)))))
        (is (rule-reference-p name)
            (format nil "rule `~A` does not follow the naming convention ~
                         RULE-REFERENCE-P recognizes -- either rename the rule or ~
                         update the predicate, but do not leave guard 1 blind" name))))))

(defun integers-in (text)
  "Every non-negative integer appearing in TEXT, in order."
  (let ((acc '())
        (i 0)
        (end (length text)))
    (loop while (< i end)
          do (if (digit-char-p (char text i))
                 (multiple-value-bind (value next) (parse-integer text :start i :junk-allowed t)
                   (push value acc)
                   (setf i next))
                 (incf i)))
    (nreverse acc)))

(defun sentence-after (text anchor)
  "The sentence beginning at ANCHOR in TEXT, up to the next period."
  (let ((start (search anchor text)))
    (when start
      (let ((stop (position #\. text :start start)))
        (subseq text start (or stop (length text)))))))

;;; ------------------------------------------------------------------
;;; Guard 1 -- every rule the prompt names still exists.
;;; ------------------------------------------------------------------

(deftest prompt-names-only-real-rules ()
  ;; The worked examples quote rule names verbatim, which is the behaviour we want
  ;; from the LLM too -- but a quoted name that no longer exists teaches it to
  ;; invent one. Renaming a rule must either update the example or drop it.
  (let ((rules (mapcar (lambda (r) (string-downcase (symbol-name (lisa:rule-short-name r))))
                       (domain-rules))))
    (dolist (token (remove-if-not #'rule-reference-p
                                  (backticked-tokens (system-prompt-text))))
      (is (member token rules :test #'string=)
          (format nil "system-prompt.md quotes rule `~A`, which is not in the ~
                       compiled rulebase (renamed, retired, or a typo)" token)))))

;;; ------------------------------------------------------------------
;;; Guard 2 -- the corpus counts the prompt states are the real ones.
;;; ------------------------------------------------------------------

(deftest prompt-states-the-real-corpus-counts ()
  ;; The prompt opens its rulebase section with "The engine holds N diagnostic
  ;; rules -- C confirming and D ruling-out." Those three numbers are the only
  ;; quantitative claim it makes without asking the engine, and they are exactly
  ;; the kind of thing that goes stale the next time a cluster lands.
  (let* ((sentence (sentence-after (system-prompt-text) "The engine holds"))
         (stated (and sentence (integers-in sentence)))
         (rules (domain-rules))
         (actual (list (length rules)
                       (count-if #'lisa:confirming-rule-p rules)
                       (count-if #'lisa:disconfirming-rule-p rules))))
    (is sentence "system-prompt.md no longer states the corpus counts -- expected a ~
                  sentence beginning \"The engine holds\"")
    (when sentence
      (is (equal stated actual)
          (format nil "system-prompt.md says (total confirming disconfirming) = ~S, ~
                       the compiled rulebase has ~S" stated actual)))))
;;; ------------------------------------------------------------------
;;; The prompt must not restate what the shared frame made false.
;;;
;;; These are NEGATIVE guards, which is unusual but earned: both claims below were
;;; true of the per-hypothesis system and were stated in the prompt for a year. They
;;; are the two most natural things for a future edit to reintroduce, and either one
;;; would have the LLM narrating an arithmetic the engine does not perform.
;;; ------------------------------------------------------------------

(defun collapse-whitespace (s)
  "S with every run of whitespace reduced to a single space.

   The prompt is hard-wrapped, so a multi-word phrase can be split across a newline
   and a literal SEARCH for it fails -- silently turning a guard off. That is exactly
   how RULE-REFERENCE-P went blind, one layer down: a check that matches nothing
   passes. Normalising both sides makes these guards insensitive to re-wrapping, which
   also strengthens the negative ones -- a banned phrase cannot be smuggled back in by
   letting it fall across a line break."
  (let ((out (make-string-output-stream))
        (in-space nil))
    (loop for ch across s
          do (if (member ch '(#\Space #\Tab #\Newline #\Return))
                 (unless in-space (write-char #\Space out) (setf in-space t))
                 (progn (write-char ch out) (setf in-space nil))))
    (get-output-stream-string out)))

(defun prompt-contains-p (needle)
  (search (collapse-whitespace needle)
          (collapse-whitespace (system-prompt-text))
          :test #'char-equal))

(deftest prompt-does-not-claim-a-mechanism-the-engine-lacks ()
  ;; Every phrase here was TRUE of an earlier representation and is now false. They
  ;; are the most natural things for a future edit to reintroduce, which is why they
  ;; are guarded negatively rather than merely corrected once.
  (dolist (claim '("class belief × rule belief"      ; composition law -- nothing chains
                   "class belief * rule belief"
                   "composes through its class"
                   "below 1.0 means a ruling-out rule fired"  ; nothing rules out
                   "negative belief"                          ; no rule carries a sign
                   ;; The affirmative "X argues *against* Y" -- emphasised, which is
                   ;; what distinguishes it from the DENIALS the prompt makes
                   ;; correctly ("no rule argues against an organism"). This one
                   ;; described catalase and outlived the v0.11 rewrite by hiding in
                   ;; the fact-ontology section, where these guards were not looking.
                   "argues *against*"))
    (is (not (prompt-contains-p claim))
        (format nil "system-prompt.md still describes ~S, which the engine no longer does"
                claim))))

(deftest prompt-explains-answers-and-intersection ()
  ;; The positive counterpart: the LLM has to know that a rule states a SET, that
  ;; exclusion is what remains after intersecting, and that a genus IS a set -- none
  ;; of which it can infer from a payload it was not told to read.
  (dolist (topic '("answer" "set_valued" "intersect" "conflict"))
    (is (prompt-contains-p topic)
        (format nil "system-prompt.md does not explain ~A" topic))))

(defun tools-json-text ()
  (with-open-file (in (asdf:system-relative-pathname
                       "neomycin" "src/llm/claude/tools.json")
                      :external-format :utf-8)
    (let ((text (make-string (file-length in))))
      (subseq text 0 (read-sequence text in)))))

(defun tools-contains-p (needle)
  (search needle (tools-json-text) :test #'char-equal))

(deftest tools-describe-the-differential-payload ()
  ;; The schemas are a SECOND thing the LLM reads, and they drifted once already while
  ;; the suite stayed green. If a schema does not mention a field, the model has no
  ;; reason to look at it and the most informative half of the payload is dead weight.
  (dolist (topic '("set_valued" "conflict" "hypotheses"))
    (is (tools-contains-p topic)
        (format nil "tools.json does not mention ~A" topic)))
  ;; The catch-all element is gone with the open frame -- an unmentioned organism is
  ;; not a listed hypothesis, it is residual ignorance. The schema has to say so, or
  ;; the model will read absence from the differential as exclusion.
  (is (tools-contains-p "residual ignorance")
      "tools.json does not explain what an unmentioned organism's plausibility means")
  (is (tools-contains-p "does not model every organism")
      "tools.json does not warn that the corpus is not exhaustive"))

(deftest tools-describe-answers-not-exclusions ()
  (is (tools-contains-p "answer") "tools.json describes a rule's answer")
  (is (not (tools-contains-p "confirming | disconfirming)"))
      "and does not offer a rule KIND the corpus no longer has"))

;;; ------------------------------------------------------------------
;;; Guard 3 -- the prompt advertises exactly the vocabulary the corpus can hear.
;;;
;;; The defect this exists for: the prompt's fact tables listed 11 values across 9
;;; parameters that NO rule premises on -- urease=negative, hemolysis=gamma,
;;; catalase=positive, culture-age at any value, and six more. Asserting one
;;; succeeds. The bridge interns the value, files the fact, returns 200, and no
;;; rule matches it. Nothing anywhere reports that the observation was inert.
;;;
;;; That is worse than an unknown fact TYPE, which at least 500s. It cost a real
;;; consultation: the model was told a negative urease, asserted it, and then --
;;; reasoning from clinical plausibility rather than from the corpus -- recommended
;;; an oxidase test and a pyocyanin reading to resolve the case. Neither exists
;;; here. A clinician following that advice orders lab work whose result can never
;;; be entered.
;;;
;;; So the tables are allowed to list an inert value -- a clinician may report one
;;; and the model should record it -- but they must MARK it, and the marking is
;;; checked against the compiled rules rather than trusted. A dagger that should
;;; not be there fails just as loudly as one that is missing: the prompt must not
;;; under-claim the corpus either, or the model will stop asking for a test that
;;; works.
;;; ------------------------------------------------------------------

(defparameter +inert-marker+ (code-char 8224)
  "DAGGER. Written by code point so this file stays ASCII and no source-encoding
   setting can quietly change what the guard compares against.")

(defun corpus-vocabulary ()
  "The corpus's input vocabulary as lowercase strings: ((param value ...) ...)."
  (mapcar (lambda (entry)
            (cons (string-downcase (symbol-name (car entry)))
                  (mapcar (lambda (v) (string-downcase (princ-to-string v)))
                          (cdr entry))))
          (lisa:corpus-premise-vocabulary (domain-rules))))

(defun trim-cell (s)
  (string-trim '(#\Space #\Tab) s))

(defun split-on (char s)
  (let ((acc '()) (start 0))
    (loop for pos = (position char s :start start)
          do (push (subseq s start (or pos (length s))) acc)
             (if pos (setf start (1+ pos)) (return (nreverse acc))))))

(defun backticked-cell (cell)
  "CELL's content when it is a single `backticked` token, else NIL."
  (let ((trimmed (trim-cell cell)))
    (when (and (> (length trimmed) 2)
               (char= (char trimmed 0) #\`)
               (char= (char trimmed (1- (length trimmed))) #\`)
               (not (find #\` trimmed :start 1 :end (1- (length trimmed)))))
      (subseq trimmed 1 (1- (length trimmed))))))

(defun prompt-vocabulary-rows ()
  "((param value inert-marked-p) ...) parsed from the prompt's fact tables.

   A table row qualifies when its first cell is a single backticked token -- which
   is how the three fact-ontology tables are written and the contraindication table
   (whose first cell is quoted clinician speech) is not."
  (let ((acc '()))
    (dolist (line (split-on #\Newline (system-prompt-text)) (nreverse acc))
      (let ((cells (split-on #\| line)))
        (when (>= (length cells) 4)
          (let ((param (backticked-cell (second cells))))
            (when param
              (dolist (raw (split-on #\, (third cells)))
                (let* ((value (trim-cell raw))
                       (inert (and (plusp (length value))
                                   (char= (char value (1- (length value)))
                                          +inert-marker+))))
                  (when (plusp (length value))
                    (push (list param
                                (if inert (subseq value 0 (1- (length value))) value)
                                inert)
                          acc)))))))))))

(deftest prompt-marks-exactly-the-inert-values ()
  (let ((vocab (corpus-vocabulary))
        (rows (prompt-vocabulary-rows)))
    (is (plusp (length rows))
        "system-prompt.md still has parseable fact-ontology tables")
    (dolist (row rows)
      (destructuring-bind (param value marked-inert) row
        (let ((consumable (and (member value (cdr (assoc param vocab :test #'string=))
                                       :test #'string-equal)
                               t)))
          (if marked-inert
              (is (not consumable)
                  (format nil "system-prompt.md marks ~A=~A inert, but a rule ~
                               premises on it -- drop the dagger, or the model will ~
                               stop asking for a test that works" param value))
              (is consumable
                  (format nil "system-prompt.md advertises ~A=~A with no marking, ~
                               but no rule premises on it. Asserting it succeeds and ~
                               changes nothing, silently. Mark it inert (~A) or add a ~
                               rule that reads it" param value +inert-marker+))))))))

(deftest every-inert-value-the-prompt-marks-has-a-reason ()
  ;; The second half of property-tests' invariant 13, and it lives here because the
  ;; prompt's tables are the only enumeration of what a client may assert -- the
  ;; bridge interns whatever value it is handed, so the corpus cannot supply the list.
  ;;
  ;; Marking a value inert says "this is silent"; *deliberately-inert* says WHY, and
  ;; without the second the first is just a dagger nobody has to justify. Eleven
  ;; values were silent before any of this existed and not one was a decision.
  (dolist (row (prompt-vocabulary-rows))
    (destructuring-bind (param value marked-inert) row
      (when marked-inert
        (let ((entry (find-if
                      (lambda (e)
                        (and (string-equal (symbol-name (first e)) param)
                             (or (null (second e))
                                 (string-equal (symbol-name (second e)) value))))
                      *deliberately-inert*)))
          (is entry
              (format nil "system-prompt.md marks ~A=~A inert, but *deliberately-inert* ~
                           gives no reason for it. Either author a rule that reads it, ~
                           or record why the marker cannot discriminate here"
                      param value))
          (when entry
            (is (plusp (length (third entry)))
                (format nil "~A=~A is documented as inert with an empty rationale"
                        param value))))))))

(deftest prompt-states-the-inert-value-policy ()
  ;; The marking is only half the fix; the model also has to be told what to DO
  ;; about it. Both halves of the policy are load-bearing and both were absent.
  (dolist (claim '("Never recommend a test whose result this corpus cannot act on"
                   "summary.parameters"
                   "oxidase"))                 ; named because it is what was suggested
    (is (prompt-contains-p claim)
        (format nil "system-prompt.md no longer states ~S -- the inert-value policy ~
                     is incomplete without it" claim))))

(deftest tools-json-marks-the-same-inert-values ()
  ;; tools.json is the THIRD copy of the vocabulary (prompt table, enum, value
  ;; description) and drifted once already while the suite stayed green. Guard it
  ;; against the same computed truth, in both directions.
  (let* ((text (tools-json-text))
         (start (search "INERT VALUES" text))
         ;; Bounded by the enclosing JSON string, not by a character count: the
         ;; descriptions that follow enumerate every fact type, so an over-long
         ;; window finds each parameter "mentioned" and the guard reports nothing.
         (blurb (and start (subseq text start (or (position #\" text :start start)
                                                  (length text)))))
         (rows (prompt-vocabulary-rows))
         (params (remove-duplicates (mapcar #'first rows) :test #'string=)))
    (is blurb "tools.json names its inert values -- expected an \"INERT VALUES\" note")
    (when blurb
      (dolist (param params)
        (let ((any-inert (some (lambda (r) (and (string= (first r) param) (third r)))
                               rows))
              (mentioned (and (search param blurb :test #'char-equal) t)))
          (if any-inert
              (is mentioned
                  (format nil "tools.json's INERT note does not mention ~A, which has ~
                               a value no rule reads" param))
              (is (not mentioned)
                  (format nil "tools.json's INERT note mentions ~A, but every value ~
                               it advertises is consumable" param))))))))

(deftest prompt-does-not-transcribe-a-policy-dial ()
  ;; The prompt said the coverage threshold was "0.2" and stayed saying it through
  ;; the v0.11 recalibration to 0.1 -- so the model quoted a stale number to a
  ;; clinician as the reason an organism went untreated. The fix is not to correct
  ;; the digits, which would go stale again on the next tuning; it is to stop
  ;; carrying them. The response echoes coverage_threshold, and the prompt must
  ;; point at it rather than restate it.
  (let ((text (system-prompt-text)))
    (is (prompt-contains-p "coverage_threshold")
        "system-prompt.md must tell the model to read the gate off the payload")
    ;; Any literal that happens to equal the current value is still a transcription,
    ;; so this looks for the SHAPE of one rather than for a wrong number.
    (dolist (form (list (format nil "coverage threshold (default ~,1F)"
                                therapy:*coverage-threshold*)
                        "coverage threshold (default 0.2)"
                        "coverage threshold (default 0.1)"))
      (is (not (search form text :test #'char-equal))
          (format nil "system-prompt.md transcribes the coverage threshold as ~S; ~
                       cite the echoed coverage_threshold field instead" form)))))

(deftest prompt-reads-conflict-with-the-margin ()
  ;; The retired rule -- "high K means the evidence disagrees, treat the figures as
  ;; unstable" -- is false in this algebra, and following it the model warned a
  ;; clinician three times in one consultation while the identification was in fact
  ;; sharpening. The claims that replace it are pinned in candidates-tests; this
  ;; guards the prompt against drifting back.
  (dolist (topic '("margin" "margin_against" "leading_answer"))
    (is (prompt-contains-p topic)
        (format nil "system-prompt.md does not explain ~A, so K is left uninterpretable"
                topic)))
  (dolist (claim '("High `K` (above ~0.5) means the evidence **disagrees with itself**"
                   "treat these figures as unstable and get a discriminating test"))
    (is (not (prompt-contains-p claim))
        (format nil "system-prompt.md has reintroduced ~S, which the measured ~
                     behaviour of K contradicts" claim))))

(deftest prompt-reads-a-margin-with-no-rival ()
  ;; Both halves of a real misreading, from the clinician session of 2026-08-24. The
  ;; payload carried a SEVEN-ORGANISM `leading_answer' and `margin_against' null --
  ;; nothing contradicted it -- and the narration was "margin 0.23 (E. coli leading
  ;; over the runner-up group)". It invented a rival the engine had explicitly
  ;; declined to name, and handed the margin to one member of the leading set.
  ;;
  ;; The model did not invent that reading; the prompt taught it. Two sentences were
  ;; wrong: `margin' was described as the leading ORGANISM's belief above the
  ;; RUNNER-UP's, and -- flatly false -- a set-valued leader was said to score margin
  ;; 0 and K 0. LISA::MARGIN's own docstring says the opposite, and the corpus
  ;; produces the counterexample. This pins the corrections.
  (dolist (topic '("`margin_against` is `null`"
                   "the set is the headline"
                   "Set SIZE reports the resolution"))
    (is (prompt-contains-p topic)
        (format nil "system-prompt.md no longer explains ~S, which is how the ~
                     margin came to be narrated as a contest that did not exist"
                topic)))
  (dolist (claim '("It is 0 whenever no single organism leads"
                   "That case has margin 0 **and** K 0"
                   "how far the leading organism's belief sits above the runner-up's"))
    (is (not (prompt-contains-p claim))
        (format nil "system-prompt.md has reintroduced ~S -- a set-valued leading ~
                     answer does NOT imply margin 0, and the leader is an ANSWER ~
                     rather than an organism" claim))))

(deftest prompt-and-tools-carry-the-inert-flag ()
  ;; /assert-fact used to answer identically for a value the corpus premises on and
  ;; one it cannot hear, so `age-group: elderly' was recorded for an 82-year-old,
  ;; fired nothing, and was never mentioned again. The bridge now returns `inert'
  ;; on every assertion. The prompt has to tell the model to READ it -- the flag is
  ;; worth nothing if the narration still passes over it in silence.
  (dolist (topic '("`inert`" "`inert_note`"))
    (is (prompt-contains-p topic)
        (format nil "system-prompt.md does not mention ~A, so the model has no ~
                     instruction to disclose an inert assertion" topic)))
  (is (tools-contains-p "inert_note")
      "tools.json does not document the inert flag on assert_fact's response"))

(deftest tools-read-conflict-with-the-margin ()
  (dolist (topic '("margin" "margin_against"))
    (is (tools-contains-p topic)
        (format nil "tools.json does not mention ~A" topic)))
  (is (not (tools-contains-p "so a high K means the rules that fired DISAGREE and the figures are unstable"))
      "tools.json still tells the model to read K as a reliability score"))

(deftest prompt-explains-support-versus-share ()
  ;; The single most trust-destroying thing the engine does: a clinician reports a
  ;; finding that supports an organism and the organism's number goes DOWN. The
  ;; arithmetic is right (Bel is a share of one unit of mass, and the same fact
  ;; strengthened a rival more), so the fix is narration -- but narration nothing
  ;; guards is narration that drifts. The behaviour itself is pinned by
  ;; SUPPORT-CAN-RISE-WHILE-SHARE-FALLS in candidates-tests.lisp.
  (dolist (claim '("Support and share are different quantities"
                   "can make its belief go down"))
    (is (prompt-contains-p claim)
        (format nil "system-prompt.md no longer explains ~S" claim)))
  ;; The two failure modes the guidance exists to prevent, either of which would be a
  ;; false statement about a correct computation. Asserted POSITIVELY -- that the
  ;; prohibitions are still there -- because a negative guard on this text matches the
  ;; prohibition itself ("Never say the finding was unhelpful" contains the phrase) and
  ;; would fail on the very wording it is meant to protect.
  (dolist (prohibition '("Never say the finding was unhelpful"
                         "never suggest the engine made a mistake"))
    (is (prompt-contains-p prohibition)
        (format nil "system-prompt.md no longer prohibits ~S" prohibition))))

(deftest prompt-describes-set-obligations ()
  ;; Stage D put a coverage requirement in the payload that names no organism. If the
  ;; prompt does not explain it, the model will either ignore it or -- worse -- narrate
  ;; it as treating a species, which is the one thing a set answer does not claim.
  (dolist (topic '("set_obligations"))
    (is (prompt-contains-p topic)
        (format nil "system-prompt.md does not explain ~A" topic)))
  ;; The family backstop is gone; the prompt described it for two releases after the
  ;; taxonomy stopped being reified, and it would now be a mechanism the solver lacks.
  (dolist (claim '("enterobacteriaceae family" "as a *backstop*"))
    (is (not (prompt-contains-p claim))
        (format nil "system-prompt.md still describes ~S, which the solver no longer does"
                claim))))

(deftest tools-describe-the-gate-and-what-it-dropped ()
  (dolist (topic '("set_obligations" "below_threshold" "covered_by" "coverage_threshold"))
    (is (tools-contains-p topic)
        (format nil "tools.json does not mention ~A -- the model has no reason to ~
                     read it, and will report a covered organism as untreated" topic))))

(deftest tools-json-is-well-formed-and-covers-the-endpoints ()
  ;; Cheap structural check: every tool the prompt tells the model to call must exist.
  (let ((text (tools-json-text)))
    (dolist (tool '("assert_fact" "run_inference" "get_conclusions" "explain_conclusion"
                    "describe_rules" "get_partial_matches" "recommend_therapy"
                    "reset_session"))
      (is (search tool text) (format nil "tools.json defines ~A" tool)))))

;;; ------------------------------------------------------------------
;;; Inert assertions are no longer silent
;;; ------------------------------------------------------------------
;;;
;;; /assert-fact answered identically for a value the corpus premises on and one no
;;; rule can ever match. In the clinician session of 2026-08-24 that meant
;;; `age-group' = `elderly', asserted for an 82-year-old against a corpus that hears
;;; `neonate' and nothing else: recorded, inert, never mentioned again, and invisible
;;; to every layer -- the bridge returned the same 200, and the release check
;;; validates parameter NAMES without ever looking at values.
;;;
;;; LISA-BRIDGE::INERT-NOTE is the answer, and it is tested here rather than over HTTP
;;; because the decision is the interesting part; hunchentoot is not.

(deftest inert-note-is-silent-for-a-value-the-corpus-hears ()
  (dolist (case '((lisa-user::age-group . lisa-user::neonate)
                  (lisa-user::gram       . lisa-user::neg)
                  (lisa-user::hemolysis  . lisa-user::beta)))
    (is (null (lisa-bridge::inert-note (string-downcase (symbol-name (car case)))
                                       (car case) (cdr case)))
        (format nil "~(~a~) = ~(~a~) is premised on by a real rule, so it must not ~
                     be reported inert" (car case) (cdr case)))))

(deftest inert-note-names-what-the-parameter-can-hear ()
  ;; The exact defect. `elderly' must be flagged, and the note has to say what WOULD
  ;; have worked -- "that did nothing" is half an answer to a caller who now has to
  ;; pick something else.
  (let ((note (lisa-bridge::inert-note "age-group"
                                       'lisa-user::age-group 'lisa-user::elderly)))
    (is (stringp note)
        "age-group = elderly matches no premise in the corpus and must be reported inert")
    (when (stringp note)
      (is (search "INERT" note) "the note says so in a word a client can match on")
      (is (search "age-group" note) "the note names the parameter")
      (is (search "elderly" note) "the note names the value that did nothing")
      (is (search "neonate" note)
          "the note names what age-group IS read for, which is the actionable half"))))

(deftest inert-note-covers-a-parameter-no-rule-reads-at-all ()
  ;; A declared fact class nothing premises on. The vocabulary is derived from
  ;; PREMISES precisely so this case is visible; the note must not fall through to a
  ;; nil that reads as "fine".
  (let ((note (lisa-bridge::inert-note "culture-age"
                                       'lisa-user::culture-age 'lisa-user::|3|)))
    (is (stringp note)
        "culture-age is assertable and no rule premises on it -- that is inert")))
