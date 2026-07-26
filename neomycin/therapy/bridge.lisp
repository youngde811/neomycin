;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.

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

;; Description: The therapy phase's HTTP surface (design doc step (c)). This file
;; lives in the NEOMYCIN system -- not lisa-bridge -- because it depends on both
;; the therapy solver and the bridge, and lisa-bridge must stay ignorant of
;; neomycin (it is a dependency of neomycin, not the reverse). The handler is a
;; hunchentoot define-easy-handler, so the running easy-acceptor picks it up
;; globally with no change to the bridge's startup.
;;
;; Split into three small, independently-testable pieces: the GLUE that reads
;; identification conclusions off the Rete working memory, the SERIALIZER that
;; renders a RECOMMENDATION as JSON-ready hash-tables, and the HANDLER that ties
;; them to the solver. The LLM narrates the result; it never chooses a drug.

(in-package :neomycin-therapy)

;;; ------------------------------------------------------------------
;;; Glue: engine working memory -> solver conclusions
;;; ------------------------------------------------------------------

(defun conclusions-for-solver ()
  "Return ((organism-keyword . belief) ...): one entry per organism-identity fact
   in the engine's working memory, each belief taken from the active belief
   system. The value slot is already a keyword (the vocabulary migration), so it
   drops straight into the keyword-keyed therapy KB with no conversion."
  (loop for fact in (lisa:get-fact-list (lisa:inference-engine))
        when (eq (lisa:fact-name fact) 'lisa-user::organism-identity)
          collect (cons (lisa:get-slot-value fact 'lisa-user::value)
                        (belief:belief-factor fact))))

;;; ------------------------------------------------------------------
;;; Serializer: RECOMMENDATION -> JSON-ready hash-tables
;;; ------------------------------------------------------------------

(defun key->name (keyword)
  "Downcased string name of a keyword id, for JSON (NIL -> NIL)."
  (and keyword (string-downcase (symbol-name keyword))))

(defun susceptibility-bounds (susceptibility)
  "Return (values bel pl ignorance) for a susceptibility, NATIVELY -- independent
   of the active identification belief system. A susceptibility's uncertainty is a
   fact about the antibiogram, not the diagnostic algebra, so its serialized shape
   must be identical under CF and DS (susceptibility-belief-design.md decision C).
   A ds-belief yields its bounds; a bare scalar is a degenerate zero-ignorance
   interval; anything else degrades to a zero interval.

   NB: we deliberately do NOT route this through lisa-bridge:belief->json-value.
   That helper serializes via the ACTIVE belief system, which would render a
   ds-belief susceptibility as {bel, pl, ignorance} under DS but drop ignorance
   under CF -- reintroducing the very ID-algebra coupling decision C removed."
  (cond
    ((belief:ds-belief-p susceptibility)
     (values (belief:ds-belief-bel susceptibility)
             (belief:ds-belief-pl susceptibility)
             (belief:ds-ignorance susceptibility)))
    ((realp susceptibility)
     (values susceptibility susceptibility 0.0))
    (t (values 0.0 0.0 0.0))))

(defun susceptibility-entry->json (item)
  "ITEM is a SUSCEPTIBILITY-ITEM. Render as {organism, bel, pl, ignorance, source,
   [n_tested]} -- the interval surfaced so a wide (sparse-data) susceptibility is
   narratable as provisional (S2), plus antibiogram PROVENANCE (design doc 6) so
   Claude can cite the local sample size and distinguish local from reference.
   `source` is \"local-antibiogram\" when a local count contributed, else
   \"reference\"; `n_tested` is present only in the former case -- its absence means
   reference-only, the pre-overlay behavior."
  (let ((s (make-hash-table :test #'equal)))
    (setf (gethash "organism" s) (key->name (susceptibility-item-organism item)))
    (multiple-value-bind (bel pl ignorance)
        (susceptibility-bounds (susceptibility-item-value item))
      (setf (gethash "bel" s) bel)
      (setf (gethash "pl" s) pl)
      (setf (gethash "ignorance" s) ignorance))
    (setf (gethash "source" s) (key->name (susceptibility-item-source item)))
    (when (susceptibility-item-n-tested item)
      (setf (gethash "n_tested" s) (susceptibility-item-n-tested item)))
    s))

(defun regimen-item->json (item)
  (let ((ht (make-hash-table :test #'equal)))
    (setf (gethash "drug" ht) (key->name (regimen-item-drug item)))
    (setf (gethash "dose" ht) (regimen-item-dose item))
    (setf (gethash "covers" ht)
          (coerce (mapcar #'key->name (regimen-item-covers item)) 'vector))
    (setf (gethash "susceptibility" ht)
          (coerce (mapcar #'susceptibility-entry->json
                          (regimen-item-susceptibility item))
                  'vector))
    ht))

(defun treat-item->json (item)
  (let ((ht (make-hash-table :test #'equal)))
    (setf (gethash "organism" ht) (key->name (treat-item-organism item)))
    ;; BELIEF is the raw belief object -> render through the active belief system.
    (setf (gethash "belief" ht) (lisa-bridge:belief->json-value (treat-item-belief item)))
    ht))

(defun exclusion->json (exclusion)
  (let ((ht (make-hash-table :test #'equal)))
    (setf (gethash "drug" ht) (key->name (exclusion-drug exclusion)))
    (setf (gethash "reason" ht) (key->name (exclusion-reason exclusion)))
    ht))

(defun recommendation->json (rec)
  "Render a RECOMMENDATION as a hash-table jzon serializes to a JSON object.
   Lists become vectors so they render as JSON arrays, not nested objects."
  (let ((ht (make-hash-table :test #'equal)))
    (setf (gethash "regimen" ht)
          (coerce (mapcar #'regimen-item->json (recommendation-regimen rec)) 'vector))
    (setf (gethash "items_to_treat" ht)
          (coerce (mapcar #'treat-item->json (recommendation-items-to-treat rec)) 'vector))
    (setf (gethash "excluded" ht)
          (coerce (mapcar #'exclusion->json (recommendation-excluded rec)) 'vector))
    (setf (gethash "uncovered" ht)
          (coerce (mapcar #'key->name (recommendation-uncovered rec)) 'vector))
    ht))

;;; ------------------------------------------------------------------
;;; Request parsing
;;; ------------------------------------------------------------------

(defun parse-patient-state (raw)
  "RAW is the parsed JSON `patient` value (a vector of state-token strings) or
   NIL. Returns a list of patient-state keyword tokens the solver matches against
   contraindication triggers, e.g. \"allergy-cephalosporin\" -> :allergy-cephalosporin."
  (when raw
    (loop for token across raw
          collect (intern (string-upcase token) :keyword))))

(defun parse-solver-name (raw)
  "The requested solver keyword, defaulting to :greedy when unset."
  (if (and raw (stringp raw) (plusp (length raw)))
      (intern (string-upcase raw) :keyword)
      :greedy))

(defun parse-gate (raw)
  "The requested coverage-gate keyword, defaulting to :belief (conservative) when
   unset. Accepts belief | plausibility | midpoint; anything else signals an error
   the handler surfaces, rather than silently mis-gating."
  (if (and raw (stringp raw) (plusp (length raw)))
      (ecase (intern (string-upcase raw) :keyword)
        (:belief :belief)
        (:plausibility :plausibility)
        (:midpoint :midpoint))
      :belief))

;;; ------------------------------------------------------------------
;;; Handler: POST /recommend-therapy
;;; ------------------------------------------------------------------

(hunchentoot:define-easy-handler (recommend-therapy-handler :uri "/recommend-therapy"
                                                            :default-request-type :post) ()
  (handler-case
      (let* ((body (lisa-bridge:read-json-body))
             (patient (parse-patient-state (and body (gethash "patient" body))))
             (solver-name (parse-solver-name (and body (gethash "solver" body))))
             (gate (parse-gate (and body (gethash "gate" body))))
             (conclusions (conclusions-for-solver)))
        (use-solver solver-name)
        ;; Dynamically bind the coverage-gate dial for this request only, so a
        ;; per-request `gate` never leaks into later sessions.
        (let* ((*susceptibility-gate* gate)
               (result (recommendation->json
                        (recommend conclusions (therapy-kb) patient))))
          ;; Echo the operative context so the response is self-describing.
          (setf (gethash "belief_system" result)
                (belief:belief-system-name belief:*belief-system*))
          (setf (gethash "solver" result) (key->name solver-name))
          (setf (gethash "gate" result) (key->name gate))
          (lisa-bridge:json-response result)))
    (error (e)
      (lisa-bridge:error-response
       (format nil "Therapy recommendation failed: ~A" e) :status 500))))