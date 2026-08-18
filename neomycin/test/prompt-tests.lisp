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
   what it does -- X-suggests-Y or X-argues-against-Y -- which is what lets this
   guard tell a quoted RULE from a quoted fact type or tool name without a list to
   maintain. A rule named outside that convention is simply not guarded here."
  (or (search "-suggests-" token)
      (search "-argues-against-" token)))

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
         ;; The prompt describes the corpus it narrates, which during the v0.11
         ;; transition is still the legacy shape. It is rewritten when candidates
         ;; becomes the default.
         (rules (legacy-rules))
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

(defun prompt-contains-p (needle)
  (search needle (system-prompt-text) :test #'char-equal))

(deftest prompt-does-not-claim-the-composition-law ()
  ;; Under the frame a chained rule contributes unconditional support that the class
  ;; premise GATES; class and species evidence then COMBINE, so the class corroborates
  ;; the species rather than discounting it (decision D1). "class belief x rule belief"
  ;; describes a multiplication the engine no longer performs.
  (dolist (claim '("class belief × rule belief" "class belief * rule belief"
                   "composes through its class" "0.64 = 0.8 × 0.8"))
    (is (not (prompt-contains-p claim))
        (format nil "system-prompt.md still claims the composition law: ~S" claim))))

(deftest prompt-does-not-equate-low-plausibility-with-ruling-out ()
  ;; The inference "pl < 1.0 therefore a ruling-out rule fired" was valid only while
  ;; each hypothesis had its own frame. Now most squeezing comes from RIVAL hypotheses
  ;; taking up belief, with no rule arguing against anything.
  (is (not (prompt-contains-p "below 1.0 means a ruling-out rule fired"))
      "system-prompt.md still equates a lowered plausibility with a ruling-out rule"))

(deftest prompt-explains-the-frame-payload ()
  ;; The positive counterpart: the frame block carries answers the per-organism list
  ;; cannot give, and the prompt has to say so or the LLM will not look.
  (dolist (topic '("set_valued" "other-organism" "conflict"))
    (is (prompt-contains-p topic)
        (format nil "system-prompt.md does not mention the frame payload's ~A" topic))))

(deftest prompt-does-not-describe-negative-beliefs ()
  ;; The corpus has none left: every claim carries a positive mass and direction is
  ;; the verb (:supports / :excludes). A prompt telling the LLM to look for a negative
  ;; belief would send it hunting for something that no longer exists in any payload.
  (dolist (claim '("negative belief" "negative :belief" "carry a negative"))
    (is (not (prompt-contains-p claim))
        (format nil "system-prompt.md still describes ~S" claim))))

(deftest prompt-explains-claims ()
  ;; The replacement has to be present, not merely the old text absent.
  (dolist (topic '("claims" "excludes" "supports"))
    (is (prompt-contains-p topic)
        (format nil "system-prompt.md does not mention ~A" topic))))

;;; ------------------------------------------------------------------
;;; The TOOL SCHEMAS are a second thing the LLM reads, and they drifted.
;;;
;;; system-prompt.md has been guarded for a while; tools.json never was. When the
;;; payloads changed shape, three tool descriptions silently went on describing the
;;; old ones -- promising a `belief` that is now absent, a `kind` that had gained a
;;; value, and a composition string stating a multiplication the engine no longer
;;; performs. The suite was green throughout. These guards close that gap.
;;; ------------------------------------------------------------------

(defun tools-json-text ()
  (with-open-file (in (asdf:system-relative-pathname
                       "neomycin" "src/llm/claude/tools.json")
                      :external-format :utf-8)
    (let ((text (make-string (file-length in))))
      (subseq text 0 (read-sequence text in)))))

(defun tools-contains-p (needle)
  (search needle (tools-json-text) :test #'char-equal))

(deftest tools-describe-the-frame-payload ()
  ;; get_conclusions returns the frame block; if the schema does not say so, the model
  ;; has no reason to look at it, and the most informative half of the payload is dead
  ;; weight.
  (dolist (topic '("set_valued" "other-organism" "conflict" "hypotheses"))
    (is (tools-contains-p topic)
        (format nil "tools.json does not mention the frame payload's ~A" topic))))

(deftest tools-describe-claims-not-negative-beliefs ()
  ;; A rule's strength is a list of positively-massed claims. A schema promising a
  ;; single `belief` would have the model quote NIL for all 16 converted rules.
  (is (tools-contains-p "claims") "tools.json describes a rule's claims")
  (is (tools-contains-p "both")
      "and the third `kind` value, for a rule that supports and excludes at once")
  (is (tools-contains-p "POSITIVE")
      "and says masses are positive, direction being the verb"))

(deftest tools-do-not-state-the-old-composition ()
  ;; The stalest thing in the file: an example of arithmetic the engine stopped doing.
  (dolist (claim '("composed with the 0.500 rule"
                   "confirming | disconfirming)"))
    (is (not (tools-contains-p claim))
        (format nil "tools.json still states ~S" claim))))

(deftest tools-json-is-well-formed-and-covers-the-endpoints ()
  ;; Cheap structural check: every tool the prompt tells the model to call must exist.
  (let ((text (tools-json-text)))
    (dolist (tool '("assert_fact" "run_inference" "get_conclusions" "explain_conclusion"
                    "describe_rules" "get_partial_matches" "recommend_therapy"
                    "reset_session"))
      (is (search tool text) (format nil "tools.json defines ~A" tool)))))
