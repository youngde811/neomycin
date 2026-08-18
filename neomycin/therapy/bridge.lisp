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

(defun collect-identity-conclusions ()
  "Alist ((organism-keyword . belief) ...): everything to treat in this consultation.

   Read from the CONSENSUS over answers rather than from per-organism facts, because
   under the v0.11 shape a rule asserts the SET its evidence narrows to and no rule
   concludes a species on its own. NEOMYCIN:DIFFERENTIAL combines those answers and
   projects each named organism's Bel -- the belief committed to that organism
   specifically, as opposed to a group it belongs to -- which is the conservative
   floor the coverage gate wants.

   Unions across EVERY organism in the consultation, since a polymicrobial culture is
   modelled as several organisms and all of them need covering. Where two organisms
   could be the same species the stronger belief governs, because coverage is a
   question about the patient rather than about one isolate.

   Organisms at Bel 0 are dropped: nothing supports them, and treating them would be
   treating the absence of evidence."
  (let ((acc '()))
    (dolist (organism (neomycin:organisms-with-answers) (nreverse acc))
      (dolist (row (neomycin:differential organism))
        (when (plusp (second row))
          (let ((seen (assoc (first row) acc)))
            (if seen
                (setf (cdr seen) (max (cdr seen) (second row)))
                (push (cons (first row) (second row)) acc))))))))

(defun collect-set-valued-conclusions ()
  "((set . mass) ...): belief committed to a SET of organisms without naming a member
   -- 'one of this family, the evidence does not say which' -- across every organism
   in the consultation.

   This is what FAMILY-BACKSTOPS used to construct by hand from organism-class facts.
   It now falls out of the arithmetic, so the taxonomy no longer has to be reified in
   order for the solver to see it."
  (loop for organism in (neomycin:organisms-with-answers)
        append (candidates:set-valued (neomycin:consensus organism))))

(defun backstop-items (kb members)
  "The KB items that between them cover MEMBERS: each distinct family among them, plus
   any member that belongs to no family and so must be named directly.

   A set-valued answer need not correspond to a single family. 'An aerobic
   gram-negative rod' spans the Enterobacteriaceae AND Pseudomonas, and covering it
   empirically means covering both -- which is what a clinician does. The pre-v0.11
   corpus could not express that, because it reified one organism-class per rule and
   the answer was whatever class had been asserted."
  (let ((items '()))
    (dolist (organism members (nreverse items))
      (let ((family (kb-family-of kb organism)))
        (pushnew (or family organism) items)))))

(defun family-backstops (species set-valued kb)
  "Items to treat empirically for answers that never resolved to an organism.

   A set-valued answer is carried in ONLY when identification could not pin down a
   member firmly enough: it is included IFF no organism in it clears the coverage gate
   (*coverage-threshold*, reduced by SCALAR-OF -- the same gate the solver's Phase A
   applies). When a member DOES clear it, that member carries the coverage need and
   the set is suppressed, so a family and its own member are never both treated.

   Each surviving set contributes the items that cover it (see BACKSTOP-ITEMS), at the
   set's own mass. Where two sets contribute the same item the stronger mass governs."
  (let ((acc '()))
    (dolist (entry set-valued (nreverse acc))
      (destructuring-bind (members . mass) entry
        (unless (some (lambda (pair)
                        (and (member (car pair) members)
                             (>= (scalar-of (cdr pair)) *coverage-threshold*)))
                      species)
          (dolist (item (backstop-items kb members))
            (let ((seen (assoc item acc)))
              (if seen
                  (setf (cdr seen) (max (cdr seen) mass))
                  (push (cons item mass) acc)))))))))

(defun conclusions-for-solver (&optional (kb (therapy-kb)))
  "Return ((organism-keyword . belief) ...) for the solver: every organism-identity
   (leaf species) in working memory, PLUS a family backstop entry for any
   organism-class whose member species all fall below the coverage gate (see
   FAMILY-BACKSTOPS). KB supplies the family taxonomy; it defaults to the canonical
   therapy KB, matching what the handler recommends over."
  (let ((species (collect-identity-conclusions)))
    (append species (family-backstops species (collect-set-valued-conclusions) kb))))

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

(defun alternative-regimen->json (alt)
  "An ALTERNATIVE-REGIMEN renders as {drugs: [...]} -- each drug in the same shape
   as a REGIMEN entry, so a reader compares like with like."
  (let ((ht (make-hash-table :test #'equal)))
    (setf (gethash "drugs" ht)
          (coerce (mapcar #'regimen-item->json (alternative-regimen-drugs alt)) 'vector))
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
    ;; The two "what else was possible" fields. Always emitted, even when empty:
    ;; an absent key reads as "not applicable", an empty array reads as "asked and
    ;; answered -- nothing". Only the second is true, and it is the distinction
    ;; whose absence produced the false answer in exact-solver-design.md 1.1.
    (setf (gethash "alternative_agents" ht)
          (coerce (mapcar #'regimen-item->json
                          (recommendation-alternative-agents rec))
                  'vector))
    (setf (gethash "alternative_regimens" ht)
          (coerce (mapcar #'alternative-regimen->json
                          (recommendation-alternative-regimens rec))
                  'vector))
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
  "The requested solver keyword, defaulting to :exact when unset.

   The default was :greedy until the exact solver's equivalence with it was
   established by test across every scenario and patient combination
   (exact-solver-design.md 5). Exact never loses to greedy -- where the two differ,
   greedy's approximation was the one that lost -- and only the exhaustive search
   can report ALTERNATIVE-REGIMENS. :greedy remains selectable, and is what the
   equivalence property is asserted against."
  (if (and raw (stringp raw) (plusp (length raw)))
      (intern (string-upcase raw) :keyword)
      :exact))

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

(defun parse-objective (raw)
  "The requested objective keyword, defaulting to :lexicographic when unset.
   Accepts lexicographic | spectrum-sparing; anything else signals an error the
   handler surfaces, rather than silently falling back to the default and returning
   a regimen the caller did not ask for.

   Defaults to :lexicographic deliberately: turning the objective dial CHANGES the
   recommendation, so it stays opt-in (exact-solver-design.md 3.5)."
  (if (and raw (stringp raw) (plusp (length raw)))
      (ecase (intern (string-upcase raw) :keyword)
        (:lexicographic :lexicographic)
        (:spectrum-sparing :spectrum-sparing))
      :lexicographic))

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
             (objective (parse-objective (and body (gethash "objective" body))))
             (conclusions (conclusions-for-solver)))
        (use-solver solver-name)
        ;; Dynamically bind the two policy dials for this request only, so a
        ;; per-request `gate` or `objective` never leaks into later sessions.
        (let* ((*susceptibility-gate* gate)
               (*objective* objective)
               (result (recommendation->json
                        (recommend conclusions (therapy-kb) patient))))
          ;; Echo the operative context so the response is self-describing.
          (setf (gethash "belief_system" result)
                (belief:belief-system-name belief:*belief-system*))
          (setf (gethash "solver" result) (key->name solver-name))
          (setf (gethash "gate" result) (key->name gate))
          (setf (gethash "objective" result) (key->name objective))
          (lisa-bridge:json-response result)))
    (error (e)
      (lisa-bridge:error-response
       (format nil "Therapy recommendation failed: ~A" e) :status 500))))