;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: neomycin's own HTTP surface -- /conclusions, /why, /rules.
;;
;; It lives here rather than in src/llm/bridge/ for the same reason the therapy
;; endpoint does: reporting a differential over organisms is domain knowledge. The
;; substrate bridge has no business knowing what an organism is, and could not
;; reference this package in any case, since it loads first.
;;
;; Registered by hunchentoot's DEFINE-EASY-HANDLER, so a running acceptor picks it up
;; when this system is loaded.

(in-package :neomycin)

(defun organism-name (x)
  (and x (string-downcase (princ-to-string x))))

(defun answers->json (details)
  "The answers behind a differential, from ANSWER-DETAILS.

   Takes DETAILS rather than bare (SET . BELIEF) pairs so a GRADED answer can report
   its distribution here too. Without it /conclusions showed culture-1's two context
   answers as a bare 0.40 and 0.60 over the same six organisms -- identical-looking,
   when in fact one leans Pseudomonas and the other leans E. coli, which is the entire
   reason the differential comes out the way it does. /why and /rules both reported
   grading; this one did not, and it is the payload a client reads FIRST."
  (coerce (mapcar (lambda (d)
                    (destructuring-bind (set belief rules &optional grading) d
                      (declare (ignore rules))
                      (let ((h (make-hash-table :test #'equal)))
                        ;; What the rule SAID, before anything was combined: the set its
                        ;; evidence narrowed to, and how strongly.
                        (setf (gethash "narrows_to" h)
                              (coerce (mapcar #'organism-name set) 'vector))
                        (setf (gethash "belief" h) belief)
                        (when grading
                          (setf (gethash "grading" h) (grading->json grading)))
                        h)))
                  details)
          'vector))

(defun hypotheses->json (organism)
  (coerce (mapcar (lambda (row)
                    (let ((h (make-hash-table :test #'equal)))
                      (setf (gethash "value" h) (organism-name (first row)))
                      (setf (gethash "bel" h) (second row))
                      (setf (gethash "pl" h) (third row))
                      (setf (gethash "ignorance" h) (- (third row) (second row)))
                      h))
                  (differential organism))
          'vector))

(defun set-valued->json (mass)
  (coerce (mapcar (lambda (e)
                    (let ((h (make-hash-table :test #'equal)))
                      (setf (gethash "members" h)
                            (coerce (mapcar #'organism-name (car e)) 'vector))
                      (setf (gethash "mass" h) (cdr e))
                      h))
                  (candidates:set-valued mass))
          'vector))

(defun differential->json (organism)
  "The differential for ORGANISM.

   Reports what a per-organism list cannot: the ANSWERS the rules actually gave, the
   set-valued belief that names no member, the conflict, and the residual ignorance --
   which is also the plausibility of any organism the corpus does not model."
  (let ((ht (make-hash-table :test #'equal)))
    (multiple-value-bind (mass conflict) (consensus organism)
      (setf (gethash "organism" ht) (organism-name organism))
      ;; K, read BEFORE normalization: both normalizations resolve it away, so it
      ;; cannot be recovered from the result.
      ;;
      ;; K counts mass committed to combinations that cannot all be true. It does
      ;; NOT measure how unreliable the surviving answer is, and it was read that
      ;; way -- two answers naming different organisms conflict TOTALLY here, so K
      ;; grows as the winning side strengthens against a fixed rival. MARGIN is
      ;; emitted beside it because the pair is interpretable and neither half is.
      (setf (gethash "conflict" ht) conflict)
      (multiple-value-bind (margin leader rival) (candidates:margin mass)
        (setf (gethash "margin" ht) margin)
        ;; The leader and its nearest CONTRADICTING answer, named. Without them a
        ;; narrow margin is a bare number and the reader has to guess what it lost
        ;; ground to -- and in the case that matters most, the rival is a SET whose
        ;; members each have Bel 0, so guessing from `hypotheses' finds nothing.
        (setf (gethash "leading_answer" ht)
              (coerce (mapcar #'organism-name leader) 'vector))
        ;; REAL JSON null, not the keyword :NULL -- jzon stringifies that to the
        ;; STRING "NULL", which is truthy in every client language there is. A
        ;; Python consumer writing `if payload["margin_against"]:' therefore read
        ;; "there is a rival" in exactly the case where there is none, and a model
        ;; reading the payload saw a string where the meaning was absence. Under
        ;; jzon the mapping is 'CL:NULL -> null, T -> true, NIL -> false; NIL is
        ;; false and NOT null, so it cannot be used here either.
        (setf (gethash "margin_against" ht)
              (if rival (coerce (mapcar #'organism-name rival) 'vector) 'cl:null)))
      (setf (gethash "ignorance" ht) (candidates:ignorance mass))
      (setf (gethash "answers" ht) (answers->json (answer-details organism)))
      (setf (gethash "hypotheses" ht) (hypotheses->json organism))
      (setf (gethash "set_valued" ht) (set-valued->json mass)))
    ht))

(defun conclusions-payload ()
  (let ((result (make-hash-table :test #'equal))
        (organisms (organisms-with-answers)))
    ;; One differential per organism -- a polymicrobial culture is modelled as several
    ;; organisms, and each is a separate question.
    (setf (gethash "organisms" result)
          (coerce (mapcar #'differential->json organisms) 'vector))
    (setf (gethash "belief_system" result)
          (belief:belief-system-name belief:*belief-system*))
    ;; A flat leading-calls list, for clients that want only the differential's head.
    (setf (gethash "conclusions" result)
          (coerce (sort (loop for organism in organisms
                              append (loop for row in (differential organism)
                                           when (plusp (second row))
                                             collect (let ((h (make-hash-table :test #'equal)))
                                                       (setf (gethash "value" h)
                                                             (organism-name (first row)))
                                                       (setf (gethash "belief" h) (second row))
                                                       h)))
                        #'> :key (lambda (h) (gethash "belief" h)))
                  'vector))
    result))

(hunchentoot:define-easy-handler (conclusions-handler :uri "/conclusions"
                                                      :default-request-type :get) ()
  (handler-case (lisa-bridge:json-response (conclusions-payload))
    (error (e)
      (lisa-bridge:error-response
       (format nil "Failed to retrieve conclusions: ~A" e) :status 500))))

;;; ------------------------------------------------------------------
;;; /why -- why this organism, and why not the others.
;;;
;;; The explanation a rule corpus of this shape can give is BETTER than the one it
;;; replaced, and different in kind. There is no composition chain to walk any more --
;;; nothing chains -- so what /why narrates is the ARGUMENT: each answer the evidence
;;; gave, the set it narrowed to, whether that set still admits the hypothesis, and
;;; what survives intersecting them.
;;;
;;;   lactose fermentation said one of {e-coli, klebsiella, enterobacter, serratia}
;;;   at 0.70; indole production said one of {e-coli, proteus} at 0.60; only e-coli
;;;   is in both.
;;;
;;; That last clause is the whole point: nothing ARGUED AGAINST klebsiella. It fell
;;; out because an answer that did not name it was combined in. Exclusion is a
;;; consequence of the arithmetic, and the payload has to show it as one -- which is
;;; why answers that do NOT admit the hypothesis are reported alongside those that
;;; do, rather than filtered out as irrelevant.
;;; ------------------------------------------------------------------

(defun rule-citation->json (rule)
  "One rule as it appears inside an explanation: what it is, what it staked, and on
   whose authority."
  (let ((ht (make-hash-table :test #'equal)))
    (setf (gethash "rule" ht) (organism-name (lisa:rule-short-name rule)))
    (setf (gethash "belief" ht) (abs (lisa:rule-belief rule)))
    (let ((prov (lisa-bridge:provenance->json (lisa:rule-provenance rule))))
      (when prov (setf (gethash "provenance" ht) prov)))
    ht))

(defun grading->json (grading)
  "A graded answer's focal masses, strongest first."
  (coerce (mapcar (lambda (pair)
                    (let ((ht (make-hash-table :test #'equal)))
                      (setf (gethash "mass" ht) (car pair))
                      (setf (gethash "organisms" ht)
                            (coerce (mapcar #'organism-name (cdr pair)) 'vector))
                      ht))
                  grading)
          'vector))

(defun answer-argument->json (detail hypothesis)
  "One answer's role in the argument for HYPOTHESIS."
  (destructuring-bind (set belief rules &optional grading) detail
    (let ((ht (make-hash-table :test #'equal)))
      (setf (gethash "narrows_to" ht)
            (coerce (mapcar #'organism-name set) 'vector))
      (setf (gethash "belief" ht) belief)
      ;; The load-bearing field. An answer that does not admit the hypothesis is not
      ;; evidence against it -- it is evidence for something else, which costs the
      ;; hypothesis plausibility as a side effect of combination.
      (setf (gethash "admits" ht) (and (member hypothesis set) t))
      ;; A GRADED answer distributes its mass INSIDE narrows_to rather than spreading
      ;; it evenly. Emitted only when present, so a bench answer's payload is
      ;; unchanged. Without this an epidemiological answer reads as though it had no
      ;; opinion about which member is likelier, which is the opposite of the truth.
      (when grading
        (setf (gethash "grading" ht) (grading->json grading))
        (setf (gethash "mass_for_organism" ht)
              (let ((hit (find-if (lambda (pair) (member hypothesis (cdr pair))) grading)))
                (if hit (car hit) 0.0))))
      (setf (gethash "rules" ht)
            (coerce (mapcar #'rule-citation->json rules) 'vector))
      ht)))

(defun grading-clause (grading)
  "How a graded answer leans, in words -- or NIL when it is flat.

   Without this the narrative reads an epidemiological answer as indifferent among its
   members, which is the reading grading exists to prevent: a burn rule that says
   `one of six at 0.40' sounds like it has no view, when in fact half its mass is on
   Pseudomonas. The narrative is quotable directly by the model, so the lean has to be
   IN it and not merely somewhere in the payload."
  (when grading
    (let ((leader (first grading)))
      (format nil ", leaning ~{~A~^/~} (~,2F of it)"
              (mapcar #'organism-name (cdr leader))
              (car leader)))))

(defun answer-clause (detail)
  "One answer as a clause: who said it, what it narrowed to, how strongly, which way."
  (format nil "~{~A~^ and ~} said one of {~{~A~^, ~}} at ~,2F~A"
          (mapcar (lambda (r) (organism-name (lisa:rule-short-name r))) (third detail))
          (mapcar #'organism-name (first detail))
          (second detail)
          (or (grading-clause (fourth detail)) "")))

(defun narrative (hypothesis admitting excluding intersection)
  "The argument in plain language.

   The closing sentence is the one that matters, and it is deliberately blunt: no rule
   argues against anything here, so a hypothesis losing plausibility has to be
   explained by what the OTHER answers named, not by an objection nobody raised."
  (let ((name (organism-name hypothesis)))
    (format nil "~{~A~^; ~}. ~A"
            (mapcar #'answer-clause (append admitting excluding))
            (cond
              ((null admitting)
               (format nil "No answer admits ~A, so nothing supports it here." name))
              ((null excluding)
               (format nil "Every answer admits ~A." name))
              (t
               (format nil "~A answer~P admit~A ~A, and together they narrow to {~{~A~^, ~}}. ~
                            ~A other~P name~A organisms ~A is not among, which is what costs ~
                            it plausibility -- no rule argues against ~A."
                       (string-capitalize (format nil "~R" (length admitting)) :end 1)
                       (length admitting)
                       (if (= 1 (length admitting)) "s" "")
                       name
                       (mapcar #'organism-name intersection)
                       (string-capitalize (format nil "~R" (length excluding)) :end 1)
                       (length excluding)
                       (if (= 1 (length excluding)) "s" "")
                       name name))))))

(defun why-payload (hypothesis entity)
  (let ((details (answer-details entity)))
    (multiple-value-bind (mass conflict) (consensus entity)
      (let ((ht (make-hash-table :test #'equal))
            (admitting (remove-if-not (lambda (d) (member hypothesis (first d))) details))
            (excluding (remove-if (lambda (d) (member hypothesis (first d))) details)))
        (setf (gethash "organism" ht) (organism-name hypothesis))
        (setf (gethash "entity" ht) (organism-name entity))
        (setf (gethash "bel" ht) (candidates:bel mass hypothesis))
        (setf (gethash "pl" ht) (candidates:pl mass hypothesis))
        (setf (gethash "conflict" ht) conflict)
        ;; Same pairing as /conclusions: an explanation that quotes K without the
        ;; margin invites the reading the numbers do not support.
        (multiple-value-bind (margin leader rival) (candidates:margin mass)
          (setf (gethash "margin" ht) margin)
          (setf (gethash "leading_answer" ht)
                (coerce (mapcar #'organism-name leader) 'vector))
          ;; Real JSON null, same reasoning as /conclusions above.
          (setf (gethash "margin_against" ht)
                (if rival (coerce (mapcar #'organism-name rival) 'vector) 'cl:null)))
        (setf (gethash "ignorance" ht) (candidates:ignorance mass))
        (setf (gethash "argument" ht)
              (coerce (mapcar (lambda (d) (answer-argument->json d hypothesis))
                              (append admitting excluding))
                      'vector))
        ;; What the admitting answers, taken together, leave standing. When the
        ;; hypothesis is the only member this IS the derivation -- there is nothing
        ;; further to explain.
        (let ((intersection (let ((sets (mapcar #'first admitting)))
                              (if sets (reduce #'candidates:set-intersect sets) '()))))
          (setf (gethash "intersection" ht)
                (coerce (mapcar #'organism-name intersection) 'vector))
          (setf (gethash "narrative" ht)
                (narrative hypothesis admitting excluding intersection)))
        (setf (gethash "belief_system" ht)
              (belief:belief-system-name belief:*belief-system*))
        ht))))

(hunchentoot:define-easy-handler (why-handler :uri "/why") ()
  (handler-case
      (let* ((body (ignore-errors (lisa-bridge:read-json-body)))
             (organism (or (and body (gethash "organism" body))
                           (hunchentoot:get-parameter "organism"))))
        (unless (and organism (stringp organism) (plusp (length organism)))
          (return-from why-handler
            (lisa-bridge:error-response
             "An `organism` value is required (JSON body field or ?organism= query param).")))
        (let* ((hypothesis (intern (string-upcase organism) :keyword))
               (entity (entity-naming hypothesis)))
          (unless entity
            (return-from why-handler
              (lisa-bridge:error-response
               (format nil "No rule has named `~A` in this consultation -- run inference ~
                            first, or ask about an organism the corpus models. Its ~
                            plausibility is whatever ignorance remains."
                       (string-downcase organism))
               :status 404)))
          (lisa-bridge:json-response (why-payload hypothesis entity))))
    (error (e)
      (lisa-bridge:error-response (format nil "Explanation failed: ~A" e) :status 500))))

;;; ------------------------------------------------------------------
;;; /rules -- the corpus catalogue.
;;;
;;; The companion query to /why: that explains a conclusion the engine reached, this
;;; answers what the corpus CONTAINS whether or not anything has fired. It exists so
;;; a client need not keep a second, hand-maintained copy of the rulebase.
;;;
;;; The walkers underneath are domain-neutral and stay in the substrate. The
;;; vocabulary is here, because `candidates' is domain knowledge -- and because the
;;; shape a catalogue reports is now flat. There are no derived classes to map and no
;;; leaf identities to distinguish from them: every rule answers the same question at
;;; whatever resolution its evidence supports.
;;; ------------------------------------------------------------------

(defun rule-premises->json (rule)
  "[{class, values}] for each premise class RULE constrains to a literal. Classes
   matched only through variables (the context wiring) gate the join rather than
   carrying evidence, and are omitted."
  (let ((acc '()))
    (dolist (class (remove-duplicates (lisa:rule-premise-classes rule) :from-end t)
                   (coerce (nreverse acc) 'vector))
      (let ((values (lisa:rule-premise-values rule class)))
        (when values
          (let ((ht (make-hash-table :test #'equal)))
            (setf (gethash "class" ht) (organism-name class))
            (setf (gethash "values" ht) (coerce (mapcar #'organism-name values) 'vector))
            (push ht acc)))))))

(defun rule->json (rule)
  "One catalogue entry: what the rule answers, what it needs, and on what authority."
  (let ((ht (make-hash-table :test #'equal))
        (answer (rule-answer rule)))
    (setf (gethash "rule" ht) (organism-name (lisa:rule-short-name rule)))
    (setf (gethash "belief" ht) (abs (lisa:rule-belief rule)))
    (setf (gethash "narrows_to" ht) (coerce (mapcar #'organism-name answer) 'vector))
    (setf (gethash "resolution" ht) (length answer))
    ;; A GRADED rule distributes its belief across focal sets INSIDE narrows_to. Without
    ;; this the catalogue would show an epidemiological rule as though it had no view on
    ;; which member is likelier -- the exact claim grading exists to make. Emitted only
    ;; when present, so every bench entry is byte-identical to before.
    (let ((grading (rule-grading rule)))
      (when grading (setf (gethash "grading" ht) (grading->json grading))))
    (setf (gethash "premises" ht) (rule-premises->json rule))
    (let ((prov (lisa-bridge:provenance->json (lisa:rule-provenance rule))))
      (when prov (setf (gethash "provenance" ht) prov)))
    ht))

(defun rule-names-p (rule query)
  (some (lambda (o) (string-equal (organism-name o) query)) (rule-answer rule)))

(defun rule-premises-value-p (rule query)
  "True when RULE reads QUERY -- matched against premise VALUES *and* against
   parameter NAMES.

   MATCHING NAMES TOO IS THE FIX FOR A FALSE NEGATIVE THAT REACHED A CLINICIAN. The
   filter used to compare values only, so `?premises=urease' returned zero rules: a
   perfectly sensible question -- \"what does this corpus do with urease?\" -- answered
   with silence indistinguishable from \"nothing reads it\". In a release-check
   consultation the model asked exactly that, got nothing back, and told the clinician
   there was no rule reading a negative urease and that it could not rule out Proteus.
   Both false: UREASE-NEGATIVE-NARROWS-TO-NON-PROTEUS-RODS exists and excludes
   precisely Proteus.

   The tool schema made it worse by offering `lactose' as an example value, which is a
   parameter name -- so the documented query was one of the ones that returned nothing.

   A caller asking which rules read a finding should get them whether they name the
   parameter or the reading. Both forms are now answerable, and neither can be
   mistaken for an empty corpus."
  (let ((classes (remove-duplicates (lisa:rule-premise-classes rule))))
    (or (some (lambda (class) (string-equal (organism-name class) query)) classes)
        (some (lambda (class)
                (some (lambda (v) (string-equal (organism-name v) query))
                      (lisa:rule-premise-values rule class)))
              classes))))

(defun matching-rules (&key name names premises)
  (let ((rules (catalogue-rules)))
    (when name
      (setf rules (remove-if-not
                   (lambda (r) (string-equal (symbol-name (lisa:rule-short-name r)) name))
                   rules)))
    (when names
      (setf rules (remove-if-not (lambda (r) (rule-names-p r names)) rules)))
    (when premises
      (setf rules (remove-if-not (lambda (r) (rule-premises-value-p r premises)) rules)))
    rules))

(defun parameters->json (rules)
  "The corpus's INPUT vocabulary: every observation RULES can act on, by parameter.

   The counterpart to ORGANISMS. That says what the corpus can conclude; this says
   what it can be told -- and the two failure modes are not symmetric. An organism
   the corpus cannot name is visible the moment you look for it in the differential.
   A finding the corpus cannot HEAR is invisible: the bridge accepts the assertion,
   returns 200, fires nothing, and the consultation proceeds as though the test had
   never been run.

   A value absent here is therefore not merely unmodelled, it is INERT, and a client
   must not solicit it. See lisa:corpus-premise-vocabulary."
  (coerce (mapcar (lambda (entry)
                    (let ((ht (make-hash-table :test #'equal)))
                      (setf (gethash "parameter" ht) (organism-name (car entry)))
                      (setf (gethash "values" ht)
                            (coerce (mapcar #'organism-name (cdr entry)) 'vector))
                      ht))
                  (lisa:corpus-premise-vocabulary rules))
          'vector))

(defun rules-summary (rules)
  "The corpus SHAPE: how many rules, which organisms they can speak about, what
   observations they can act on, and at what resolutions they answer.

   RESOLUTIONS is the distribution of answer sizes -- {1: 19, 2: 6, 4: 3} reads as
   nineteen rules that name a single organism, six that narrow to a pair, three to a
   group of four. It replaces the old class/identity split, which assumed a two-tier
   corpus. There are no tiers now: a rule answers at whatever resolution its evidence
   supports, and a coarse answer is a conclusion rather than a way-station."
  (let ((ht (make-hash-table :test #'equal))
        (organisms '())
        (resolutions (make-hash-table :test #'equal)))
    (dolist (rule rules)
      (let ((answer (rule-answer rule)))
        (dolist (o answer) (pushnew (organism-name o) organisms :test #'string=))
        (incf (gethash (princ-to-string (length answer)) resolutions 0))))
    (setf (gethash "total" ht) (length rules))
    (setf (gethash "organisms" ht) (coerce (sort organisms #'string<) 'vector))
    (setf (gethash "parameters" ht) (parameters->json rules))
    (setf (gethash "resolutions" ht) resolutions)
    ht))

(hunchentoot:define-easy-handler (rules-handler :uri "/rules") ()
  (handler-case
      (let* ((rules (matching-rules :name (hunchentoot:get-parameter "name")
                                    :names (hunchentoot:get-parameter "names")
                                    :premises (hunchentoot:get-parameter "premises")))
             (result (make-hash-table :test #'equal)))
        ;; The summary always describes the WHOLE corpus, not the filtered slice: it is
        ;; orientation, and a filtered count would misreport the shape.
        (setf (gethash "summary" result) (rules-summary (catalogue-rules)))
        (setf (gethash "matched" result) (length rules))
        (setf (gethash "rules" result) (coerce (mapcar #'rule->json rules) 'vector))
        (lisa-bridge:json-response result))
    (error (e)
      (lisa-bridge:error-response (format nil "Rule query failed: ~A" e) :status 500))))
