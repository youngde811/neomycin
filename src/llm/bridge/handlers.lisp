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

;;; ------------------------------------------------------------------
;;; Inert observations.
;;;
;;; A fact CLASS the knowledge base does not declare is rejected below, loudly. A
;;; VALUE no rule premises on is a different failure and, until now, a SILENT one:
;;; the assertion succeeds, the response is byte-for-byte indistinguishable from a
;;; live one, and the consultation proceeds as though the finding had been recorded.
;;;
;;; Measured in a clinician session on 2026-08-24. The clinician opened with "82 year
;;; old male"; the client asserted `age-group' = `elderly'; the corpus hears `neonate'
;;; and nothing else. It fired nothing, it was never mentioned again, and no layer of
;;; the stack said a word -- not the bridge, which returned the same 200 it returns
;;; for a live value, and not the release check, which validates parameter NAMES
;;; against the catalogue and never looks at values.
;;;
;;; See LISA:CORPUS-PREMISE-VOCABULARY, whose own header names this hazard exactly:
;;; a client that cannot tell inert from live will eventually ask its user for an
;;; observation the rulebase can never act on -- and when the client is an LLM and the
;;; user is a clinician, that is a real lab test ordered for an answer that cannot be
;;; entered.
;;;
;;; DOMAIN-NEUTRAL. The vocabulary is computed from the COMPILED rulebase, so this
;;; knows no more about organisms than the rest of :LISA-BRIDGE does. It is the same
;;; derivation NEOMYCIN::CATALOGUE-RULES uses, and deliberately not a call into it:
;;; that would invert the load order.
;;; ------------------------------------------------------------------

(defun active-knowledge-rules ()
  "Every knowledge rule currently compiled into the engine."
  (remove-if-not #'lisa:knowledge-rule-p
                 (lisa:get-rule-list (lisa:inference-engine))))

(defun inert-note (fact-type class-sym value-sym)
  "Why asserting CLASS-SYM = VALUE-SYM can change nothing, or NIL if it can.

   NIL is the answer for a value some rule premises on -- the ordinary case. A
   string is returned only when the assertion is inert, and it names what the
   corpus WOULD hear for this parameter, because `that value does nothing' is
   half an answer to a caller who has to pick another."
  (let ((rules (active-knowledge-rules)))
    (unless (lisa:corpus-premises-value-p rules class-sym value-sym)
      (let ((heard (cdr (assoc class-sym (lisa:corpus-premise-vocabulary rules)))))
        (if heard
            (format nil "INERT: no rule premises on `~(~A~)' = `~(~A~)'. The fact was ~
                         recorded and can never match, so it will not change any ~
                         conclusion. This parameter is read only for: ~{`~(~A~)'~^, ~}."
                    fact-type (symbol-name value-sym)
                    (mapcar #'symbol-name heard))
            (format nil "INERT: no rule premises on `~(~A~)' at any value. The fact ~
                         was recorded and can never match, so it will not change any ~
                         conclusion."
                    fact-type))))))

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
      ;; Reject an unknown fact TYPE by name, before MAKE-INSTANCE is handed the NIL
      ;; that FIND-SYMBOL returns for one. The failure was already caught below, but
      ;; it surfaced as "There is no class named COMMON-LISP:NIL" -- an internal
      ;; detail that tells a client nothing about what it did wrong or what to do
      ;; instead. A caller choosing which observation to gather needs to hear "that
      ;; is not a fact type here", which is a different thing from a 500.
      (let ((class-sym (find-symbol (string-upcase fact-type) :lisa-user)))
        (unless (and class-sym (find-class class-sym nil))
          (return-from assert-fact-handler
            (error-response
             (format nil "Unknown fact_type `~A'. This knowledge base has no such ~
                          parameter, so the observation cannot be recorded and no ~
                          rule could read it. Query the rule catalogue for the ~
                          parameters it does define."
                     fact-type)
             :status 400))))
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
              ;; Say so when the fact can never match. ALWAYS emitted, true or
              ;; false: a key that is present only on failure is one a client can
              ;; forget to look for, which is the silence this exists to end.
              (let ((note (inert-note fact-type class-sym value-sym)))
                (setf (gethash "inert" result) (and note t))
                (when note
                  (setf (gethash "inert_note" result) note)))
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

;;; NOTE: /conclusions lives in neomycin/bridge.lisp, not here. It reports a
;;; DIFFERENTIAL read from candidate-set answers, which is domain knowledge -- the
;;; substrate bridge has no business knowing what an organism is, and cannot reference
;;; the application package anyway, since it loads first.

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

(defun provenance->json (prov)
  "Render a rule's :provenance plist as a JSON object (origin, evidence_group,
   evidence, belief_basis, note); NIL if the rule declares none.

   EVIDENCE_GROUP names a set of rules resting on the same underlying evidence. They are
   not independent observations, so only one of them contributes to a differential --
   the others are dropped before combination and will be absent from the argument
   entirely. Emitted so a reader can see WHY a rule they expected is missing."
  (when prov
    (let ((ht (make-hash-table :test #'equal)))
      (when (getf prov :origin)
        (setf (gethash "origin" ht) (string-downcase (symbol-name (getf prov :origin)))))
      (when (getf prov :evidence)
        (setf (gethash "evidence" ht) (coerce (getf prov :evidence) 'vector)))
      (when (getf prov :evidence-group)
        (setf (gethash "evidence_group" ht)
              (string-downcase (symbol-name (getf prov :evidence-group)))))
      (when (getf prov :belief-basis)
        (setf (gethash "belief_basis" ht) (string-downcase (symbol-name (getf prov :belief-basis)))))
      (when (getf prov :note)
        (setf (gethash "note" ht) (getf prov :note)))
      ht)))
