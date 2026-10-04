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
  (coerce (mapcar (lambda (d)
                    (destructuring-bind (set belief rules &optional grading) d
                      (declare (ignore rules))
                      (let ((h (make-hash-table :test #'equal)))
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
  (let ((ht (make-hash-table :test #'equal)))
    (multiple-value-bind (mass conflict) (consensus organism)
      (setf (gethash "organism" ht) (organism-name organism))
      (setf (gethash "conflict" ht) conflict)
      (multiple-value-bind (margin leader rival) (candidates:margin mass)
        (setf (gethash "margin" ht) margin)
        (setf (gethash "leading_answer" ht)
              (coerce (mapcar #'organism-name leader) 'vector))
        (setf (gethash "margin_against" ht)
              (if rival (coerce (mapcar #'organism-name rival) 'vector)
                'cl:null)))
        (setf (gethash "theta_mass" ht) (candidates:ignorance mass))
      (setf (gethash "answers" ht) (answers->json (answer-details organism)))
      (setf (gethash "hypotheses" ht) (hypotheses->json organism))
      (setf (gethash "set_valued" ht) (set-valued->json mass)))
    ht))

(defun conclusions-payload ()
  (let ((result (make-hash-table :test #'equal))
        (organisms (organisms-with-answers)))
    (setf (gethash "organisms" result)
          (coerce (mapcar #'differential->json organisms) 'vector))
    (setf (gethash "belief_system" result)
          (belief:belief-system-name belief:*belief-system*))
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

(defun rule-citation->json (rule)
  "One rule as it appears inside an explanation: what it is, what it staked, and on
   whose authority."
  (let ((ht (make-hash-table :test #'equal)))
    (setf (gethash "rule" ht) (organism-name (lisa:rule-short-name rule)))
    (setf (gethash "belief" ht) (abs (lisa:rule-belief rule)))
    (let ((prov (lisa-bridge:provenance->json (lisa:rule-provenance rule))))
      (when prov
        (setf (gethash "provenance" ht) prov)))
    ht))

(defun grading->json (grading)
  (coerce (mapcar (lambda (pair)
                    (let ((ht (make-hash-table :test #'equal)))
                      (setf (gethash "mass" ht) (car pair))
                      (setf (gethash "organisms" ht)
                            (coerce (mapcar #'organism-name (cdr pair)) 'vector))
                      ht))
                  grading)
          'vector))

(defun answer-argument->json (detail hypothesis)
  (destructuring-bind (set belief rules &optional grading) detail
    (let ((ht (make-hash-table :test #'equal)))
      (setf (gethash "narrows_to" ht)
            (coerce (mapcar #'organism-name set) 'vector))
      (setf (gethash "belief" ht) belief)
      (setf (gethash "admits" ht) (and (member hypothesis set) t))
      (when grading
        (setf (gethash "grading" ht) (grading->json grading))
        (setf (gethash "mass_for_organism" ht)
              (let ((hit (find-if (lambda (pair)
                                    (member hypothesis (cdr pair)))
                                  grading)))
                (if hit (car hit)
                  0.0))))
      (setf (gethash "rules" ht)
            (coerce (mapcar #'rule-citation->json rules) 'vector))
      ht)))

(defun grading-clause (grading)
  (when grading
    (let ((leader (first grading)))
      (format nil ", leaning ~{~A~^/~} (~,2F of it)"
              (mapcar #'organism-name (cdr leader))
              (car leader)))))

(defun answer-clause (detail)
  (format nil "~{~A~^ and ~} said one of {~{~A~^, ~}} at ~,2F~A"
          (mapcar (lambda (r) (organism-name (lisa:rule-short-name r))) (third detail))
          (mapcar #'organism-name (first detail))
          (second detail)
          (or (grading-clause (fourth detail))
              "")))

(defun narrative (hypothesis admitting excluding intersection)
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
                       (if (= 1 (length admitting))
                         "s" "")
                       name
                       (mapcar #'organism-name intersection)
                       (string-capitalize (format nil "~R" (length excluding)) :end 1)
                       (length excluding)
                       (if (= 1 (length excluding))
                         "s" "")
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
        (multiple-value-bind (margin leader rival) (candidates:margin mass)
          (setf (gethash "margin" ht) margin)
          (setf (gethash "leading_answer" ht)
                (coerce (mapcar #'organism-name leader) 'vector))
          (setf (gethash "margin_against" ht)
                (if rival (coerce (mapcar #'organism-name rival) 'vector)
                  'cl:null)))
        (setf (gethash "theta_mass" ht) (candidates:ignorance mass))
        (setf (gethash "argument" ht)
              (coerce (mapcar (lambda (d)
                                (answer-argument->json d hypothesis))
                              (append admitting excluding))
                      'vector))
        (let ((intersection (let ((sets (mapcar #'first admitting)))
                              (if sets
                                  (reduce #'candidates:set-intersect sets)
                                '()))))
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
        (unless (and organism
                     (stringp organism)
                     (plusp (length organism)))
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

(defun rule-premises->json (rule)
  (let ((acc nil))
    (dolist (class (remove-duplicates (lisa:rule-premise-classes rule) :from-end t)
                   (coerce (nreverse acc) 'vector))
      (let ((values (lisa:rule-premise-values rule class)))
        (when values
          (let ((ht (make-hash-table :test #'equal)))
            (setf (gethash "class" ht) (organism-name class))
            (setf (gethash "values" ht) (coerce (mapcar #'organism-name values) 'vector))
            (push ht acc)))))))

(defun rule->json (rule)
  (let ((ht (make-hash-table :test #'equal))
        (answer (rule-answer rule)))
    (setf (gethash "rule" ht) (organism-name (lisa:rule-short-name rule)))
    (setf (gethash "belief" ht) (abs (lisa:rule-belief rule)))
    (setf (gethash "narrows_to" ht) (coerce (mapcar #'organism-name answer) 'vector))
    (setf (gethash "resolution" ht) (length answer))
    (let ((grading (rule-grading rule)))
      (when grading
        (setf (gethash "grading" ht) (grading->json grading))))
    (setf (gethash "premises" ht) (rule-premises->json rule))
    (let ((prov (lisa-bridge:provenance->json (lisa:rule-provenance rule))))
      (when prov
        (setf (gethash "provenance" ht) prov)))
    ht))

(defun rule-names-p (rule query)
  (some (lambda (o)
          (string-equal (organism-name o) query))
        (rule-answer rule)))

(defun rule-premises-value-p (rule query)
  (let ((classes (remove-duplicates (lisa:rule-premise-classes rule))))
    (or (some (lambda (class)
                (string-equal (organism-name class) query))
              classes)
        (some (lambda (class)
                (some (lambda (v) (string-equal (organism-name v) query))
                      (lisa:rule-premise-values rule class)))
              classes))))

(defun matching-rules (&key name names premises)
  (let ((rules (catalogue-rules)))
    (when name
      (setf rules (remove-if-not
                   (lambda (r)
                     (string-equal (symbol-name (lisa:rule-short-name r)) name))
                   rules)))
    (when names
      (setf rules (remove-if-not (lambda (r)
                                   (rule-names-p r names))
                                 rules)))
    (when premises
      (setf rules (remove-if-not (lambda (r)
                                   (rule-premises-value-p r premises))
                                 rules)))
    rules))

(defun parameters->json (rules)
  (coerce (mapcar (lambda (entry)
                    (let ((ht (make-hash-table :test #'equal)))
                      (setf (gethash "parameter" ht) (organism-name (car entry)))
                      (setf (gethash "values" ht)
                            (coerce (mapcar #'organism-name (cdr entry)) 'vector))
                      ht))
                  (lisa:corpus-premise-vocabulary rules))
          'vector))

(defun rules-summary (rules)
  (let ((ht (make-hash-table :test #'equal))
        (organisms nil)
        (resolutions (make-hash-table :test #'equal)))
    (dolist (rule rules)
      (let ((answer (rule-answer rule)))
        (dolist (o answer)
          (pushnew (organism-name o) organisms :test #'string=))
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
        (setf (gethash "summary" result) (rules-summary (catalogue-rules)))
        (setf (gethash "matched" result) (length rules))
        (setf (gethash "rules" result) (coerce (mapcar #'rule->json rules) 'vector))
        (lisa-bridge:json-response result))
    (error (e)
      (lisa-bridge:error-response (format nil "Rule query failed: ~A" e) :status 500))))
