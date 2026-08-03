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

(defun composition-string (rec)
  "A plain-language, algebra-neutral statement of this firing's arithmetic, built
   from the actual recorded numbers (reduced to scalars). The structured belief
   fields keep the full interval; this is the narratable summary."
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
