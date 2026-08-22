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

(defun set-obligation-entries (set-valued)
  "((MEMBERS . MASS) ...) for every set-valued answer, carried through to the solver
   as a coverage obligation. MEMBERS is a LIST, which is how phase A tells a set entry
   from an organism entry -- an organism id is a symbol and never a list.

   NO SUPPRESSION, and that is the change. This was FAMILY-BACKSTOPS, which dropped a
   set the moment any one of its members cleared the gate, reasoning that the member
   'carries the coverage need'. It does not: mass on {A..G} is committed to no member
   in particular, so covering A and B leaves it undischarged. Culture-1 puts 0.155 on
   the seven aerobic gram-negative rods; the narrow regimens missed Salmonella and
   reported nothing uncovered. Measured across the scenario x patient x objective
   matrix, four configurations of sixty were silently under-covering this way.

   Nor does a set collapse to its KB FAMILY any more. That was the other half of the
   illusion: ceftazidime covers :enterobacteriaceae at bel 0.66 and :salmonella at
   0.46, so against a 0.5 threshold the family proxy read as covered while the member
   was not. The family roll-up keeps its real job -- a species with no entry of its
   own inherits its family's figure in KB-SUSCEPTIBILITY -- but it is no longer
   allowed to stand in for the set. An obligation is discharged member by member.

   Sets BELOW the gate are dropped here rather than in phase A, so that what the
   solver receives is exactly what it must act on."
  (loop for (members . mass) in set-valued
        when (>= (scalar-of mass) *coverage-threshold*)
          collect (cons members mass)))

(defun conclusions-for-solver (&optional (kb (therapy-kb)))
  "What the solver must cover: every organism the consultation named with belief of
   its own, PLUS every set-valued answer carrying enough mass to clear the gate.

   Two kinds of entry share one alist. (ORGANISM . BELIEF) is a hypothesis with
   belief committed to it specifically; ((MEMBER ...) . MASS) is an answer that
   committed mass to a group without naming a member, and phase A tells them apart by
   whether the car is a list. Both must be covered and they are not interchangeable --
   which is the whole lesson of the suppression rule that used to conflate them.

   KB is accepted for interface stability and is no longer consulted: the taxonomy was
   only ever used to collapse a set onto a family, which SET-OBLIGATION-ENTRIES
   explains is unsound."
  (declare (ignore kb))
  (append (collect-identity-conclusions)
          (set-obligation-entries (collect-set-valued-conclusions))))

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

(defun incidental-cover->json (cover)
  (let ((ht (make-hash-table :test #'equal)))
    (setf (gethash "drug" ht) (key->name (incidental-cover-drug cover)))
    (setf (gethash "susceptibility" ht)
          (susceptibility-entry->json (incidental-cover-susceptibility cover)))
    ht))

(defun set-obligation->json (obligation)
  "One set-valued conclusion the regimen had to cover: {members, mass, uncovered}.

   UNCOVERED is emitted even when empty, and empty is the answer to a real question --
   'does this regimen cover the group you could not resolve?' A non-empty list is a
   member the evidence says could be the organism and the regimen does not treat,
   which is the failure this field was added to stop hiding."
  (let ((ht (make-hash-table :test #'equal)))
    (setf (gethash "members" ht)
          (coerce (mapcar #'key->name (set-obligation-members obligation)) 'vector))
    (setf (gethash "mass" ht) (set-obligation-mass obligation))
    (setf (gethash "uncovered" ht)
          (coerce (mapcar #'key->name (set-obligation-uncovered obligation)) 'vector))
    ht))

(defun below-threshold->json (item)
  "One organism the coverage gate dropped: {organism, belief, covered_by}.

   COVERED_BY is the load-bearing field, and it is emitted even when empty. The
   regimen's own `covers' lists only the organisms the solver was TARGETING, so
   without this a drug that happens to cover the runner-up looks as though it does
   not -- which is how a meropenem regimen covering Klebsiella at [0.88, 0.99] was
   narrated as leaving Klebsiella untreated."
  (let ((ht (make-hash-table :test #'equal)))
    (setf (gethash "organism" ht) (key->name (below-threshold-item-organism item)))
    (setf (gethash "belief" ht)
          (lisa-bridge:belief->json-value (below-threshold-item-belief item)))
    (setf (gethash "covered_by" ht)
          (coerce (mapcar #'incidental-cover->json
                          (below-threshold-item-covered-by item))
                  'vector))
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
    ;; The gate's other side: organisms deliberately NOT treated, and what the
    ;; regimen covers there anyway. Always emitted, for the reason given below.
    (setf (gethash "below_threshold" ht)
          (coerce (mapcar #'below-threshold->json
                          (recommendation-below-threshold rec))
                  'vector))
    ;; Set-valued answers the regimen was obliged to cover. Distinct from
    ;; items_to_treat: these name no organism in particular, so reporting them as
    ;; treated organisms would claim an individual belief none of them has.
    (setf (gethash "set_obligations" ht)
          (coerce (mapcar #'set-obligation->json
                          (recommendation-set-obligations rec))
                  'vector))
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
          ;; The gate's NUMBER, not just its kind. It was transcribed into the
          ;; system prompt as "default 0.2", stayed there through the v0.11
          ;; recalibration to 0.1, and was quoted to a clinician as the reason an
          ;; organism went untreated. A dial a client has to narrate is a dial the
          ;; response has to carry.
          (setf (gethash "coverage_threshold" result) *coverage-threshold*)
          (setf (gethash "susceptibility_threshold" result) *susceptibility-threshold*)
          (lisa-bridge:json-response result)))
    (error (e)
      (lisa-bridge:error-response
       (format nil "Therapy recommendation failed: ~A" e) :status 500))))