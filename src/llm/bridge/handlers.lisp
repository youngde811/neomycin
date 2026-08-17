;; This file is part of Lisa, the Lisp-based Intelligent Software Agents platform.

;; MIT License

;; Copyright (c) 2000 David Young

;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to deal
;; in the Software without restriction, including without limitation the rights
;; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;; copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:

;; The above copyright notice and this permission notice shall be included in all
;; copies or substantial portions of the Software.

;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.

(in-package :lisa-bridge)

(defun json-response (data &key (status 200))
  "Set response content type to JSON and return DATA serialized as a JSON string."
  (setf (hunchentoot:content-type*) "application/json")
  (setf (hunchentoot:return-code*) status)
  (com.inuoe.jzon:stringify data))

(defun error-response (message &key (status 400))
  (let ((ht (make-hash-table :test #'equal)))
    (setf (gethash "error" ht) message)
    (json-response ht :status status)))

(defun read-json-body ()
  "Read and parse the JSON request body."
  (let ((body (hunchentoot:raw-post-data :force-text t)))
    (when (and body (> (length body) 0))
      (com.inuoe.jzon:parse body))))

(hunchentoot:define-easy-handler (health-check :uri "/health") ()
  (json-response
   (let ((ht (make-hash-table :test #'equal)))
     (setf (gethash "status" ht) "ok")
     ht)))

(hunchentoot:define-easy-handler (assert-fact-handler :uri "/assert-fact"
                                                      :default-request-type :post) ()
  (let ((body (read-json-body)))
    (unless body
      (return-from assert-fact-handler
        (error-response "Request body must be valid JSON.")))
    (let ((fact-type (gethash "fact_type" body))
          (entity-name (gethash "entity" body))
          (value (gethash "value" body))
          (confidence (gethash "confidence" body)))
      (unless (and fact-type value)
        (return-from assert-fact-handler
          (error-response "fact_type and value are required.")))
      (handler-case
          ;; Scope the fact to its context in the patient -> culture -> organism
          ;; lineage; the bridge creates any missing context facts (see
          ;; session.lisp). ENTITY-NAME, when given, selects the organism for
          ;; organism-level facts; patient/culture facts are auto-scoped.
          (let* ((class-sym (find-symbol (string-upcase fact-type) :lisa-user))
                 (value-sym (intern (string-upcase value) :lisa-user))
                 (of-id (context-id-for fact-type entity-name))
                 (instance (make-instance class-sym :value value-sym :of of-id)))
            (lisa:assert-instance instance :belief confidence)
            (let ((result (make-hash-table :test #'equal)))
              (setf (gethash "status" result) "asserted")
              (setf (gethash "fact_type" result) fact-type)
              (setf (gethash "value" result) value)
              (setf (gethash "scoped_to" result)
                    (string-downcase (symbol-name of-id)))
              (when entity-name
                (setf (gethash "entity" result) entity-name))
              (when confidence
                (setf (gethash "confidence" result) confidence))
              (json-response result)))
        (error (e)
          (error-response (format nil "Assertion failed: ~A" e) :status 500))))))

(defvar *last-rule-trace* ""
  "Captured trace output from the most recent inference run.")

(hunchentoot:define-easy-handler (run-inference-handler :uri "/run-inference"
                                                        :default-request-type :post) ()
  (handler-case
      (progn
        (lisa:watch :rules)
        (let* ((*trace-output* (make-string-output-stream))
               (count (lisa:run)))
          (lisa:unwatch :rules)
          (setf *last-rule-trace* (get-output-stream-string *trace-output*))
          (let ((result (make-hash-table :test #'equal)))
            (setf (gethash "status" result) "completed")
            (setf (gethash "rules_fired" result) count)
            (json-response result))))
    (error (e)
      (lisa:unwatch :rules)
      (error-response (format nil "Inference failed: ~A" e) :status 500))))

(hunchentoot:define-easy-handler (rule-trace-handler :uri "/rule-trace"
                                                     :default-request-type :get) ()
  (let ((result (make-hash-table :test #'equal)))
    (setf (gethash "trace" result) *last-rule-trace*)
    (json-response result)))

(defun belief->json-value (belief)
  "Serialize a belief through the active belief system, converting alist
   payloads (as produced by the Dempster-Shafer implementation) into
   hash-tables so jzon renders them as JSON objects rather than arrays."
  (let ((rendered (belief:belief->json belief:*belief-system* belief)))
    (cond
      ((null rendered) nil)
      ((and (consp rendered) (consp (car rendered)))
       (let ((ht (make-hash-table :test #'equal)))
         (dolist (pair rendered)
           (setf (gethash (car pair) ht) (cdr pair)))
         ht))
      (t rendered))))

;;; ------------------------------------------------------------------
;;; Shared-frame projection (only emitted when a frame-based system is active).
;;;
;;; The per-hypothesis payload above reports one interval per organism-identity FACT.
;;; Under a shared frame that is a lossy view of what the engine knows: it cannot show
;;; an organism that no rule concluded but that the evidence has squeezed, it cannot
;;; show mass sitting on a SET ("one of this family, unsaid which"), and it cannot show
;;; how much conflict was renormalized away. This adds all three, alongside -- never
;;; instead of -- the existing payload, so nothing that reads /conclusions today
;;; changes shape.
;;; ------------------------------------------------------------------

(defun frame-based-run-p ()
  (and belief:*frame* (belief:frame-based-p belief:*belief-system*)))

(defun element-name (element)
  (string-downcase (symbol-name element)))

(defun mask->names (mask)
  (coerce (mapcar #'element-name (belief:mask->elements belief:*frame* mask)) 'vector))

(defun hypothesis->json (mass element)
  "One frame element's interval, whether or not a rule ever concluded it."
  (let ((ht (make-hash-table :test #'equal))
        (bel (belief:mass-belief mass element))
        (pl (belief:mass-plausibility mass element)))
    (setf (gethash "value" ht) (element-name element))
    (setf (gethash "bel" ht) bel)
    (setf (gethash "pl" ht) pl)
    (setf (gethash "ignorance" ht) (- pl bel))
    ht))

(defun set-valued->json (mass)
  "Focal sets that are neither a single hypothesis nor total ignorance -- genuine
   set-valued conclusions, e.g. mass on a whole family with no member singled out."
  (coerce
   (mapcar (lambda (entry)
             (let ((ht (make-hash-table :test #'equal)))
               (setf (gethash "members" ht) (mask->names (car entry)))
               (setf (gethash "mass" ht) (cdr entry))
               ht))
           (belief:mass-set-valued mass))
   'vector))

(defun entity-projection->json (entity pool)
  (let ((ht (make-hash-table :test #'equal))
        (mass (belief:pool-mass pool)))
    (setf (gethash "entity" ht) (string-downcase (princ-to-string entity)))
    (setf (gethash "operator" ht) (string-downcase (symbol-name belief:*frame-operator*)))
    (setf (gethash "normalization" ht)
          (string-downcase (symbol-name belief:*frame-normalization*)))
    ;; K, read UNNORMALIZED from the pool: both normalizations resolve conflict away,
    ;; so the projected mass function always reports zero. A consultation that
    ;; renormalized away a third of its mass should be able to say so.
    (setf (gethash "conflict" ht) (belief:pool-conflict pool))
    (setf (gethash "ignorance" ht)
          (belief:mass-ref mass (belief:frame-theta belief:*frame*)))
    (setf (gethash "hypotheses" ht)
          (coerce (map 'list (lambda (e) (hypothesis->json mass e))
                       (belief:frame-elements belief:*frame*))
                  'vector))
    (setf (gethash "set_valued" ht) (set-valued->json mass))
    ht))

(defun frame-projection->json ()
  "The frame and one projection per entity, or NIL under a per-hypothesis system."
  (when (frame-based-run-p)
    (let ((ht (make-hash-table :test #'equal))
          (entities '()))
      (setf (gethash "elements" ht)
            (coerce (map 'list #'element-name (belief:frame-elements belief:*frame*))
                    'vector))
      (setf (gethash "subsets" ht)
            (coerce (mapcar #'element-name
                            (belief:frame-subset-names belief:*frame*))
                    'vector))
      (maphash (lambda (entity pool)
                 (push (entity-projection->json entity pool) entities))
               (lisa::rete-evidence-pools (lisa:inference-engine)))
      (setf (gethash "entities" ht) (coerce (nreverse entities) 'vector))
      ht)))

(hunchentoot:define-easy-handler (conclusions-handler :uri "/conclusions"
                                                      :default-request-type :get) ()
  (handler-case
      (let ((facts (lisa:get-fact-list (lisa:inference-engine)))
            (conclusions '()))
        (dolist (fact facts)
          (when (eq (lisa:fact-name fact) 'lisa-user::organism-identity)
            (let ((entry (make-hash-table :test #'equal))
                  (val (lisa:get-slot-value fact (intern "VALUE" :lisa-user))))
              (setf (gethash "value" entry)
                    (string-downcase (symbol-name val)))
              (let ((belief (belief:belief-factor fact)))
                (when belief
                  (setf (gethash "belief" entry)
                        (belief->json-value belief))))
              (push entry conclusions))))
        (let ((result (make-hash-table :test #'equal)))
          (setf (gethash "conclusions" result) (coerce (nreverse conclusions) 'vector))
          (setf (gethash "belief_system" result)
                (belief:belief-system-name belief:*belief-system*))
          (let ((frame (frame-projection->json)))
            (when frame (setf (gethash "frame" result) frame)))
          (json-response result)))
    (error (e)
      (error-response (format nil "Failed to retrieve conclusions: ~A" e) :status 500))))

(hunchentoot:define-easy-handler (reset-handler :uri "/reset"
                                                :default-request-type :post) ()
  (handler-case
      (let* ((body (read-json-body))
             (requested (when body (gethash "belief_system" body)))
             (choice (parse-belief-system-name requested)))
        (when choice
          (belief:use-system choice))
        (reset-session)
        (let ((result (make-hash-table :test #'equal)))
          (setf (gethash "status" result) "reset")
          (setf (gethash "belief_system" result)
                (belief:belief-system-name belief:*belief-system*))
          (json-response result)))
    (error (e)
      (error-response (format nil "Reset failed: ~A" e) :status 500))))

(defun fact-matches-pattern-p (fact pattern)
  "Return T if FACT has the same class as PATTERN and every simple (constant)
slot in the pattern equals the corresponding slot on the fact.  Variable-bound
and constrained slots are ignored — they can bind to anything within a single
pattern.  Cross-pattern variable consistency is not checked here."
  (and (eq (lisa:fact-name fact) (lisa::parsed-pattern-class pattern))
       (every (lambda (slot)
                (or (not (lisa::simple-slot-p slot))
                    (equal (lisa:get-slot-value fact (lisa::pattern-slot-name slot))
                           (lisa::pattern-slot-value slot))))
              (lisa::parsed-pattern-slots pattern))))

(defun pattern-satisfied-by-wm-p (pattern facts)
  "Return T if any fact in FACTS satisfies PATTERN per FACT-MATCHES-PATTERN-P."
  (some (lambda (fact) (fact-matches-pattern-p fact pattern)) facts))

(defun pattern-description (pattern)
  "Return a human-readable string describing what a pattern requires."
  (let* ((class-name (lisa::parsed-pattern-class pattern))
         (slots (lisa::parsed-pattern-slots pattern))
         (slot-strs
           (loop for slot in slots
                 when (lisa::simple-slot-p slot)
                   collect (format nil "~A=~A"
                                   (string-downcase (symbol-name (lisa::pattern-slot-name slot)))
                                   (string-downcase (princ-to-string (lisa::pattern-slot-value slot)))))))
    (if slot-strs
        (format nil "~A (~{~A~^, ~})"
                (string-downcase (symbol-name class-name))
                slot-strs)
        (string-downcase (symbol-name class-name)))))

(hunchentoot:define-easy-handler (partial-matches-handler :uri "/partial-matches"
                                                          :default-request-type :get) ()
  (handler-case
      (let* ((rules (lisa::get-rule-list (lisa:inference-engine)))
             (facts (lisa:get-fact-list (lisa:inference-engine)))
             (results '()))
        (dolist (rule rules)
          (let ((matched '())
                (missing '())
                (total 0))
            (dolist (pattern (lisa::rule-patterns rule))
              ;; Only consider generic patterns.  Test / negated / OR patterns
              ;; are out of scope for this diagnostic endpoint.
              (when (lisa::generic-pattern-p pattern)
                (incf total)
                (if (pattern-satisfied-by-wm-p pattern facts)
                    (push (pattern-description pattern) matched)
                    (push (pattern-description pattern) missing))))
            (when (and (> total 0) missing matched)
              (let ((entry (make-hash-table :test #'equal)))
                (setf (gethash "rule" entry)
                      (string-downcase (symbol-name (lisa:rule-short-name rule))))
                (setf (gethash "belief" entry)
                      (belief->json-value (lisa::belief-factor rule)))
                (setf (gethash "matched" entry)
                      (coerce (nreverse matched) 'vector))
                (setf (gethash "missing" entry)
                      (coerce (nreverse missing) 'vector))
                (setf (gethash "matched_count" entry) (- total (length missing)))
                (setf (gethash "total_conditions" entry) total)
                (push entry results)))))
        (let ((response (make-hash-table :test #'equal)))
          (setf (gethash "partial_matches" response)
                (coerce (nreverse results) 'vector))
          (json-response response)))
    (error (e)
      (error-response (format nil "Partial match query failed: ~A" e) :status 500))))

;;; ------------------------------------------------------------------
;;; /why -- authoritative belief explanation (WHY/HOW facility).
;;;
;;; Returns, for a concluded organism identity, the ENGINE-RECORDED derivation of
;;; its belief (LISA:FACT-DERIVATION, captured at fire time) rather than an
;;; LLM-reconstructed one: every contributing firing with its rule, that rule's own
;;; belief, the premises it matched (each with its belief snapshot), the
;;; before/after belief bracketing the firing, a plain-language composition, and the
;;; rule's machine-readable :provenance (origin + verified citations). A premise that
;;; is itself a derived fact (e.g. the organism-class) carries its OWN derivation, so
;;; the multi-hop chain is walked recursively. The LLM narrates from this; it no
;;; longer recomputes the arithmetic or recalls the citations.
;;; ------------------------------------------------------------------

(defun find-organism-identity-fact (value-keyword)
  "The organism-identity fact whose VALUE slot is VALUE-KEYWORD, or NIL."
  (dolist (fact (lisa:get-fact-list (lisa:inference-engine)))
    (when (and (eq (lisa:fact-name fact) 'lisa-user::organism-identity)
               (eq (lisa:get-slot-value fact (intern "VALUE" :lisa-user)) value-keyword))
      (return fact))))

(defun belief-scalar (belief)
  "Reduce BELIEF to a scalar for the composition string, through the active belief
   system. NIL -> NIL; a raw number is itself; a structured belief reduces via
   BELIEF:BELIEF->NUMBER. Used only for the human-readable arithmetic; the full
   interval is preserved in the structured `belief` fields."
  (cond ((null belief) nil)
        ((realp belief) belief)
        (t (ignore-errors (belief:belief->number belief:*belief-system* belief)))))

(defun fact-short-desc (fact)
  "A compact label like \"organism-class enterobacteriaceae\" or \"gram neg\"."
  (let ((val (ignore-errors (lisa:get-slot-value fact (intern "VALUE" :lisa-user)))))
    (if val
        (format nil "~A ~A"
                (string-downcase (symbol-name (lisa:fact-name fact)))
                (string-downcase (princ-to-string val)))
        (string-downcase (symbol-name (lisa:fact-name fact))))))

(defun provenance->json (prov)
  "Render a rule's :provenance plist as a JSON object (origin, evidence, belief_basis,
   note); NIL if the rule declares none."
  (when prov
    (let ((ht (make-hash-table :test #'equal)))
      (when (getf prov :origin)
        (setf (gethash "origin" ht) (string-downcase (symbol-name (getf prov :origin)))))
      (when (getf prov :evidence)
        (setf (gethash "evidence" ht) (coerce (getf prov :evidence) 'vector)))
      (when (getf prov :belief-basis)
        (setf (gethash "belief_basis" ht) (string-downcase (symbol-name (getf prov :belief-basis)))))
      (when (getf prov :note)
        (setf (gethash "note" ht) (getf prov :note)))
      ht)))

(defun frame-composition-string (rec)
  "The narratable summary of a firing under a shared frame.

   Deliberately NOT phrased as arithmetic on one hypothesis. Under a frame a firing
   commits mass to a SET, and what happens to any individual member is a consequence
   of combining that with everything else in the pool -- not of a multiplication this
   firing performed. Saying 'X went from 0.4 to 0.76' would be a fiction here; saying
   what was committed to which set, and how much conflict resulted, is what actually
   occurred."
  (let ((k (lisa:derivation-record-conflict rec)))
    (format nil "~{~A~^, and ~}~@[; pool conflict after this firing ~,3F~]"
            (mapcar (lambda (c) (claim-phrase (car c) (cdr c)))
                    (lisa:derivation-record-claims rec))
            k)))

(defun claim-phrase (mask mass)
  "One claim, in words. A rule may state several -- red pigment means Serratia, and
   means none of these five -- so each is phrased separately and they are joined."
  (let* ((members (belief:mask->elements belief:*frame* mask))
         (n (length members))
         (frame-size (belief:frame-size belief:*frame*))
         ;; A claim naming most of the frame is an EXCLUSION; saying which few are out
         ;; is far more legible than listing the fourteen that are in.
         (excluded (belief:mask->elements
                    belief:*frame* (belief:mask-complement belief:*frame* mask))))
    (cond
      ((and (> n (/ frame-size 2)) excluded)
       (format nil "committed ~,3F against {~{~A~^, ~}}"
               mass (mapcar #'element-name excluded)))
      ((<= n 4)
       (format nil "committed ~,3F to {~{~A~^, ~}}" mass (mapcar #'element-name members)))
      (t
       (format nil "committed ~,3F to a set of ~D {~{~A~^, ~}, ...}"
               mass n (mapcar #'element-name (subseq members 0 3)))))))

(defun composition-string (rec)
  "A plain-language, algebra-neutral statement of this firing's arithmetic, built
   from the actual recorded numbers (reduced to scalars). The structured belief
   fields keep the full interval; this is the narratable summary."
  (when (and (lisa:derivation-record-claims rec) belief:*frame*)
    (return-from composition-string (frame-composition-string rec)))
  (let* ((rule-belief (lisa:derivation-record-rule-belief rec))
         (before (lisa:derivation-record-belief-before rec))
         (after (belief-scalar (lisa:derivation-record-belief-after rec)))
         ;; premises that actually carry belief (a derived intermediate like the
         ;; organism-class); raw nil-belief evidence only gates firing.
         (carried (remove nil (lisa:derivation-record-premises rec) :key #'cdr)))
    (cond
      ((and (null before) carried)
       (let ((p (first carried)))
         (format nil "~,3F (~A) composed with the ~,3F rule = ~,3F"
                 (belief-scalar (cdr p)) (fact-short-desc (car p)) rule-belief (or after 0))))
      ((null before)
       (format nil "rule belief ~,3F = ~,3F" rule-belief (or after 0)))
      (t
       (format nil "prior ~,3F combined with the ~,3F rule = ~,3F"
               (belief-scalar before) rule-belief (or after 0))))))

;; Mutually recursive: a derivation record renders its premises, and a derived
;; premise renders its own derivation records.
(declaim (ftype (function (t) t) derivation-record->json premise->json))

(defun premise->json (premise)
  "PREMISE is (fact . belief-snapshot). Render {fact, [belief], [derivation]}; the
   nested `derivation` appears only when the premise is itself a rule-concluded fact
   (walking the multi-hop chain)."
  (let ((fact (car premise))
        (belief (cdr premise))
        (ht (make-hash-table :test #'equal)))
    (setf (gethash "fact" ht) (fact-short-desc fact))
    (when belief
      (setf (gethash "belief" ht) (belief->json-value belief)))
    (let ((sub (lisa:fact-derivation (lisa:inference-engine) fact)))
      (when sub
        (setf (gethash "derivation" ht)
              (coerce (mapcar #'derivation-record->json sub) 'vector))))
    ht))

(defun derivation-record->json (rec)
  "Render one firing: rule (short name), rule_belief, belief_before/after,
   composition, premises, and the rule's provenance."
  (let* ((rule-name (lisa:derivation-record-rule rec))
         (rule (lisa:find-rule (lisa:inference-engine) rule-name))
         (ht (make-hash-table :test #'equal)))
    (setf (gethash "rule" ht)
          (string-downcase (symbol-name (if rule (lisa:rule-short-name rule) rule-name))))
    (setf (gethash "rule_belief" ht) (lisa:derivation-record-rule-belief rec))
    (let ((before (lisa:derivation-record-belief-before rec)))
      (when before
        (setf (gethash "belief_before" ht) (belief->json-value before))))
    (setf (gethash "belief_after" ht)
          (belief->json-value (lisa:derivation-record-belief-after rec)))
    (setf (gethash "composition" ht) (composition-string rec))
    ;; Under a shared frame a firing commits mass to a SET, and the scalar
    ;; before/after pair cannot say which set. These three fields carry what the
    ;; narration otherwise could not state: what was supported, how strongly, and how
    ;; much the pool disagreed with itself afterwards.
    (let ((claims (lisa:derivation-record-claims rec)))
      (when (and claims belief:*frame*)
        ;; A rule may state several claims at different granularities, so this is a
        ;; list even when it has one entry -- a reader should never have to branch on
        ;; how many an author happened to write.
        (setf (gethash "claims" ht)
              (coerce (mapcar (lambda (c)
                                (let ((h (make-hash-table :test #'equal)))
                                  (setf (gethash "supports" h) (mask->names (car c)))
                                  (setf (gethash "mass" h) (cdr c))
                                  h))
                              claims)
                      'vector))
        (let ((k (lisa:derivation-record-conflict rec)))
          (when k (setf (gethash "conflict_after" ht) k)))))
    (setf (gethash "premises" ht)
          (coerce (mapcar #'premise->json (lisa:derivation-record-premises rec)) 'vector))
    (let ((prov (and rule (provenance->json (lisa:rule-provenance rule)))))
      (when prov
        (setf (gethash "provenance" ht) prov)))
    ht))

(hunchentoot:define-easy-handler (why-handler :uri "/why") ()
  (handler-case
      (let* ((body (ignore-errors (read-json-body)))
             (organism (or (and body (gethash "organism" body))
                           (hunchentoot:get-parameter "organism"))))
        (unless (and organism (stringp organism) (plusp (length organism)))
          (return-from why-handler
            (error-response "An `organism` value is required (JSON body field or ?organism= query param).")))
        (let* ((value-kw (intern (string-upcase organism) :keyword))
               (fact (find-organism-identity-fact value-kw)))
          (unless fact
            (return-from why-handler
              (error-response
               (format nil "No organism-identity `~A` in working memory -- run inference first."
                       (string-downcase organism))
               :status 404)))
          (let ((result (make-hash-table :test #'equal)))
            (setf (gethash "organism" result) (string-downcase organism))
            (let ((belief (belief:belief-factor fact)))
              (when belief
                (setf (gethash "belief" result) (belief->json-value belief))))
            (setf (gethash "derivation" result)
                  (coerce (mapcar #'derivation-record->json
                                  (lisa:fact-derivation (lisa:inference-engine) fact))
                          'vector))
            (setf (gethash "belief_system" result)
                  (belief:belief-system-name belief:*belief-system*))
            (json-response result))))
    (error (e)
      (error-response (format nil "Explanation failed: ~A" e) :status 500))))

;;; ------------------------------------------------------------------
;;; /rules -- the corpus catalogue.
;;;
;;; The companion query to /why. /why explains a conclusion the engine actually
;;; reached; /rules answers what the corpus CONTAINS, whether or not anything has
;;; fired -- what a rule concludes, what it needs, what it believes, and on what
;;; authority. That is the question a client otherwise answers from a second,
;;; hand-maintained copy of the rulebase, which drifts the moment a rule is
;;; retired or re-parented.
;;;
;;; The walkers underneath are domain-neutral (LISA:RULE-ASSERTED-FACTS and
;;; friends). The domain vocabulary appears HERE, in the serializer, exactly as it
;;; already does in /conclusions and /why: organism-class is the chaining
;;; intermediate, organism-identity the leaf.
;;; ------------------------------------------------------------------

(defun value-name (value)
  "VALUE's bare name, downcased -- :STAPHYLOCOCCUS renders as \"staphylococcus\".
   The corpus spells these consistently as keywords; the normalization is here so
   that Lisp reader syntax never reaches a JSON client, not to reconcile a
   disagreement in the rulebase."
  (string-downcase (princ-to-string value)))

(defun value-matches-p (value query)
  "True when VALUE is what QUERY (a client-supplied string) names. Compared by
   name so no client input is ever interned."
  (and query (string-equal (value-name value) query)))

(defun catalogue-rules ()
  "Every knowledge-bearing rule in the loaded rulebase -- the reporting and
   driver rules that carry no belief are not part of the corpus a client is
   asking about."
  (remove-if-not #'lisa:knowledge-rule-p
                 (lisa:get-rule-list (lisa:inference-engine))))

(defun rule-kind (rule)
  "What a rule does to belief: supports hypotheses, excludes some, or BOTH.

   `both` is not a fudge -- it is what a discriminating test actually does, and what
   the corpus could not express until a rule could state several claims. The older
   single-belief form can only be one or the other, because a scalar has one sign."
  (let ((confirming (lisa:confirming-rule-p rule))
        (disconfirming (lisa:disconfirming-rule-p rule)))
    (cond ((and confirming disconfirming) "both")
          (disconfirming "disconfirming")
          (t "confirming"))))

(defun rule-chained-from (rule)
  "The organism-class RULE refines from, or NIL if it reads raw evidence. This is
   what makes a rule tier-2, and why its effective belief composes through the
   class rather than standing alone."
  (first (lisa:rule-premise-values rule 'lisa-user::organism-class)))

(defun ordered-premise-classes (rule)
  "RULE's premise classes, de-duplicated, in pattern order."
  (remove-duplicates (lisa:rule-premise-classes rule) :from-end t))

(defun rule-premises->json (rule)
  "[{class, values}] for each premise class RULE constrains to a literal. Classes
   matched only through variables (the organism/culture context wiring) carry no
   value and are omitted -- they gate the join, they are not evidence."
  (let ((acc '()))
    (dolist (class (ordered-premise-classes rule) (coerce (nreverse acc) 'vector))
      (let ((values (lisa:rule-premise-values rule class)))
        (when values
          (let ((ht (make-hash-table :test #'equal)))
            (setf (gethash "class" ht) (string-downcase (symbol-name class)))
            (setf (gethash "values" ht)
                  (coerce (mapcar #'value-name values) 'vector))
            (push ht acc)))))))

(defun rule-concludes->json (rule)
  "[{class, value}] for each fact RULE asserts."
  (coerce (mapcar (lambda (pair)
                    (let ((ht (make-hash-table :test #'equal)))
                      (setf (gethash "class" ht)
                            (string-downcase (symbol-name (car pair))))
                      (setf (gethash "value" ht) (value-name (cdr pair)))
                      ht))
                  (lisa:rule-asserted-facts rule))
          'vector))

(defun rule->json (rule)
  "One catalogue entry: what the rule concludes, needs, believes, and cites."
  (let ((ht (make-hash-table :test #'equal)))
    (setf (gethash "rule" ht) (string-downcase (symbol-name (lisa:rule-short-name rule))))
    (setf (gethash "belief" ht) (lisa:rule-belief rule))
    (setf (gethash "kind" ht) (rule-kind rule))
    (setf (gethash "concludes" ht) (rule-concludes->json rule))
    (setf (gethash "premises" ht) (rule-premises->json rule))
    (let ((from (rule-chained-from rule)))
      (when from
        (setf (gethash "chained_from" ht) (value-name from))))
    ;; A ruling-out rule names its targets in a (test (member ...)) rather than in
    ;; a premise slot, so they would otherwise be invisible in this payload.
    (let ((targets (lisa:rule-member-test-values rule)))
      (when targets
        (setf (gethash "targets" ht)
              (coerce (mapcar #'value-name targets) 'vector))))
    ;; Every rule's CLAIMS: what its evidence commits belief to, and how strongly.
    ;; A list even for a single-claim rule, so a reader never branches on how many the
    ;; author happened to write. `source` separates a DECLARED claim from one inferred
    ;; by fallback -- the distinction slice D's focal-width audit turns on, which the
    ;; LLM should not have to guess. Reported only when a frame is declared, because
    ;; only then does the engine act on it.
    (when belief:*frame*
      (let ((claims (ignore-errors (lisa:rule-claims rule belief:*frame*))))
        (when claims
          (setf (gethash "claims" ht)
                (coerce
                 (mapcar (lambda (c)
                           (let ((h (make-hash-table :test #'equal)))
                             (setf (gethash "supports" h) (mask->names (lisa:claim-mask c)))
                             (setf (gethash "size" h) (belief:mask-size (lisa:claim-mask c)))
                             (setf (gethash "mass" h) (lisa:claim-mass c))
                             (setf (gethash "source" h)
                                   (string-downcase (symbol-name (lisa:claim-kind c))))
                             h))
                         claims)
                 'vector)))))
    (let ((prov (provenance->json (lisa:rule-provenance rule))))
      (when prov
        (setf (gethash "provenance" ht) prov)))
    ht))

;;; Filters. Each is a predicate over a rule; the handler ANDs the ones the
;;; client supplied.

(defun rule-concludes-value-p (rule query)
  (some (lambda (pair) (value-matches-p (cdr pair) query))
        (lisa:rule-asserted-facts rule)))

(defun rule-premises-value-p (rule query)
  (some (lambda (class)
          (some (lambda (v) (value-matches-p v query))
                (lisa:rule-premise-values rule class)))
        (ordered-premise-classes rule)))

(defun rule-targets-value-p (rule query)
  "True when RULE names QUERY in a (test (member ...)) -- how a ruling-out rule
   selects the hypotheses it argues against."
  (some (lambda (v) (value-matches-p v query))
        (lisa:rule-member-test-values rule)))

(defun cluster-identity-names (query)
  "The identities refined FROM the class QUERY: what every rule premising on that
   class concludes. Computed once per request, not per rule."
  (let ((acc '()))
    (dolist (rule (catalogue-rules) (nreverse acc))
      (when (and (lisa:confirming-rule-p rule)
                 (rule-premises-value-p rule query))
        (dolist (pair (lisa:rule-asserted-facts rule))
          (when (eq (car pair) 'lisa-user::organism-identity)
            (pushnew (value-name (cdr pair)) acc :test #'string=)))))))

(defun rule-in-cluster-p (rule query cluster-identities)
  "A cluster is a derived class, everything refined from it, and everything that
   argues about those refinements: the rule CONCLUDING the class, every rule
   PREMISING on it, and every rule concluding or targeting one of its species.
   The third arm is what reaches the ruling-out rules -- they key off the identity
   and never mention the class, so a client asking `what separates the
   staphylococci?' would otherwise be shown only the rules that argue FOR each
   species and none of the discriminators that argue against."
  (or (rule-concludes-value-p rule query)
      (rule-premises-value-p rule query)
      (some (lambda (id)
              (or (rule-concludes-value-p rule id)
                  (rule-targets-value-p rule id)))
            cluster-identities)))

(defun matching-rules (&key name kind concludes premises cluster)
  (let ((rules (catalogue-rules))
        (cluster-identities (and cluster (cluster-identity-names cluster))))
    (when name
      (setf rules (remove-if-not
                   (lambda (r) (string-equal (symbol-name (lisa:rule-short-name r)) name))
                   rules)))
    (when kind
      (setf rules (remove-if-not (lambda (r) (string-equal (rule-kind r) kind)) rules)))
    (when concludes
      (setf rules (remove-if-not (lambda (r) (rule-concludes-value-p r concludes)) rules)))
    (when premises
      (setf rules (remove-if-not (lambda (r) (rule-premises-value-p r premises)) rules)))
    (when cluster
      (setf rules (remove-if-not
                   (lambda (r) (rule-in-cluster-p r cluster cluster-identities))
                   rules)))
    rules))

(defun concluded-value-names (rules class)
  "The distinct values RULES conclude for CLASS, as names, confirming rules only.
   An excluding rule concludes nothing, and one written in the older form re-asserted
   the hypothesis it argued against -- either way it must not look like a way to
   reach one."
  (let ((acc '()))
    (dolist (rule rules (coerce (nreverse acc) 'vector))
      (when (lisa:confirming-rule-p rule)
        (dolist (pair (lisa:rule-asserted-facts rule))
          (when (eq (car pair) class)
            (pushnew (value-name (cdr pair)) acc :test #'string=)))))))

(defun clusters->json (class-names)
  "{class: [identities refined from it]} -- the chaining map. This is the one
   piece of corpus shape a client cannot reconstruct from the flat lists: which
   species hang off which derived class, and therefore whose belief composes
   through what."
  (let ((ht (make-hash-table :test #'equal)))
    (loop for class across class-names
          do (setf (gethash class ht)
                   (coerce (cluster-identity-names class) 'vector)))
    ht))

(defun rules-summary (rules)
  "The corpus SHAPE: counts, the derived classes and what each refines to, and
   the leaf identities. A client can hold this in its head and query the detail
   on demand -- which is the entire point of the endpoint."
  (let ((ht (make-hash-table :test #'equal))
        (classes (concluded-value-names rules 'lisa-user::organism-class)))
    (setf (gethash "total" ht) (length rules))
    ;; A rule may state both supporting and excluding claims, so these need not sum
    ;; to the corpus size -- `both` counts the overlap explicitly rather than leaving
    ;; a reader to infer it from a discrepancy.
    (setf (gethash "confirming" ht) (count-if #'lisa:confirming-rule-p rules))
    (setf (gethash "disconfirming" ht) (count-if #'lisa:disconfirming-rule-p rules))
    (setf (gethash "both" ht)
          (count-if (lambda (r) (and (lisa:confirming-rule-p r)
                                     (lisa:disconfirming-rule-p r)))
                    rules))
    (setf (gethash "organism_classes" ht) classes)
    (setf (gethash "clusters" ht) (clusters->json classes))
    (setf (gethash "identities" ht)
          (concluded-value-names rules 'lisa-user::organism-identity))
    ht))

(hunchentoot:define-easy-handler (rules-handler :uri "/rules") ()
  (handler-case
      (let* ((rules (matching-rules
                     :name (hunchentoot:get-parameter "name")
                     :kind (hunchentoot:get-parameter "kind")
                     :concludes (hunchentoot:get-parameter "concludes")
                     :premises (hunchentoot:get-parameter "premises")
                     :cluster (hunchentoot:get-parameter "cluster")))
             (result (make-hash-table :test #'equal)))
        ;; The summary always describes the WHOLE corpus, not the filtered slice:
        ;; it is orientation, and a filtered count would misreport the shape.
        (setf (gethash "summary" result) (rules-summary (catalogue-rules)))
        (setf (gethash "matched" result) (length rules))
        (setf (gethash "rules" result)
              (coerce (mapcar #'rule->json rules) 'vector))
        (json-response result))
    (error (e)
      (error-response (format nil "Rule query failed: ~A" e) :status 500))))
