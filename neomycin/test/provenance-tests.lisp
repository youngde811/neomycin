;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: Tests for the WHY/HOW explanation & provenance facility
;; (docs/why-how-provenance-design.md). Slice A added the ENGINE CAPABILITY (a
;; machine-readable :provenance rule property in Lisa core). Slice B POPULATED it
;; across all 23 rules with a TWO-AXIS record: :origin (artifact lineage) +
;; :evidence (real, adversarially-verified authoritative clinical sources) +
;; :belief-basis :illustrative (the CF/DS value is schematic, NOT sourced from the
;; evidence) + :note. Later slices (C derivation capture, D /why) add tests here.

(in-package "LISA-TEST")

(defun rule-provenance-of (name)
  "The :provenance plist declared on rule NAME (a LISA-USER symbol), or NIL."
  (let ((rule (lisa:find-rule (lisa:inference-engine) name)))
    (and rule (lisa:rule-provenance rule))))

(defparameter *provenance-origins* '(:genuine-mycin :paip-subset :neomycin-extrapolation)
  "The allowed artifact-lineage tags (corpus-expansion-sketch.md §4).")

;;; ------------------------------------------------------------------
;;; Slice A -- the engine carries the property (declared vs undeclared).
;;; ------------------------------------------------------------------

(deftest rule-provenance-property-is-carried ()
  ;; A rule declaring :provenance exposes it via LISA:RULE-PROVENANCE; the
  ;; `conclusion` reporting rule declares none and reads NIL -- proving the property
  ;; is additive and pure metadata (it never affects inference).
  (let ((paip (rule-provenance-of 'lisa-user::gram-neg-rod-in-burn-patient-suggests-pseudomonas))
        (neo  (rule-provenance-of 'lisa-user::aerobic-gram-neg-rod-suggests-enterobacteriaceae-class))
        (none (rule-provenance-of 'lisa-user::conclusion)))
    (is (eq (getf paip :origin) :paip-subset)
        "an inherited base rule is tagged :paip-subset")
    (is (eq (getf neo :origin) :neomycin-extrapolation)
        "a neomycin-added rule is tagged :neomycin-extrapolation")
    (is (null none)
        "the `conclusion` reporting rule declares no :provenance (reads NIL)")))

;;; ------------------------------------------------------------------
;;; Slice B -- every DOMAIN rule carries a well-formed two-axis record.
;;; ------------------------------------------------------------------

(deftest every-knowledge-rule-carries-well-formed-provenance ()
  ;; Invariant over the whole rulebase: every rule EXCEPT the `conclusion` reporting
  ;; rule must carry (:origin <valid> :evidence (<non-empty strings>) :belief-basis
  ;; :illustrative :note <string>). Adding a rule without provenance fails this.
  (dolist (rule (lisa::get-rule-list (lisa:inference-engine)))
    (let ((short (lisa:rule-short-name rule))
          (prov (lisa:rule-provenance rule)))
      (unless (eq short 'lisa-user::conclusion)
        (is (member (getf prov :origin) *provenance-origins*)
            (format nil "~A: :origin must be one of ~S, got ~S"
                    short *provenance-origins* (getf prov :origin)))
        (is (and (consp (getf prov :evidence))
                 (every #'stringp (getf prov :evidence)))
            (format nil "~A: :evidence must be a non-empty list of source strings" short))
        ;; The honesty flag: the belief VALUE is either an illustrative teaching figure
        ;; (never sourced from :evidence) OR :frequency-derived -- read off stratified
        ;; observation counts (docs/ds-grounded-beliefs-design.md). A :frequency-derived
        ;; rule must carry a well-formed :grounding plist recording those counts.
        (let ((basis (getf prov :belief-basis)))
          (is (member basis '(:illustrative :frequency-derived))
              (format nil "~A: :belief-basis must be :illustrative or :frequency-derived, got ~S"
                      short basis))
          (when (eq basis :frequency-derived)
            (let* ((g (getf prov :grounding))
                   (s (getf g :susceptible))
                   (n (getf g :tested)))
              (is (and (consp g)
                       (integerp s) (integerp n) (<= 0 s n)
                       (stringp (getf g :source)))
                  (format nil "~A: :frequency-derived requires a well-formed :grounding ~
                               (:susceptible s :tested n (0<=s<=n) :source <string>), got ~S"
                          short g)))))
        (is (stringp (getf prov :note))
            (format nil "~A: :note must be a string" short))))))

;;; ------------------------------------------------------------------
;;; Frequency-grounded rule beliefs (LIGHT) -- docs/ds-grounded-beliefs-design.md.
;;; The belief on a grounded rule is read off stratified counts via GROUNDED (the IDM
;;; lower expectation s/(n+σ)), not hand-picked, and its provenance says so.
;;; ------------------------------------------------------------------

(defun rule-belief-of (name)
  "The scalar :belief declared on rule NAME (a LISA-USER symbol), or NIL."
  (let ((rule (lisa:find-rule (lisa:inference-engine) name)))
    (and rule (belief:belief-factor rule))))

(deftest grounded-helper-is-idm-lower-expectation ()
  ;; GROUNDED computes the IDM lower expectation s/(n+σ), σ=2 -- the LIGHT point belief
  ;; and the bel bound of the antibiogram's counts->interval (so LIGHT->FULL is additive).
  (is (approx= (lisa-user::grounded 47 50) (/ 47.0 52.0))
      "grounded(47,50) should be 47/(50+2) = 47/52")
  (is (approx= (lisa-user::grounded 0 0) 0.0)
      "grounded(0,0) is vacuous -> 0.0")
  (is (approx= (lisa-user::grounded 10 10) (/ 10.0 12.0))
      "grounded(10,10) = 10/12: even all-positive counts stay below 1.0 (finite-sample humility)"))

(deftest red-pigment-serratia-belief-is-frequency-grounded ()
  ;; The first grounded rule: :belief-basis :frequency-derived (not :illustrative), the
  ;; stratified counts recorded in :grounding, and the rule's actual baked-in belief
  ;; equals grounded(counts) -- provenance and belief are a single source of truth.
  (let* ((prov (rule-provenance-of 'lisa-user::enterobacteriaceae-red-pigment-suggests-serratia))
         (g (getf prov :grounding)))
    (is (eq (getf prov :belief-basis) :frequency-derived)
        "red-pigment->Serratia must be :frequency-derived")
    (is (and (= (getf g :susceptible) 47) (= (getf g :tested) 50))
        "its :grounding must record the 47/50 stratified counts")
    (is (approx= (rule-belief-of 'lisa-user::enterobacteriaceae-red-pigment-suggests-serratia)
                 (lisa-user::grounded (getf g :susceptible) (getf g :tested)))
        "the rule's baked-in belief must equal grounded(susceptible, tested)")))

;;; ------------------------------------------------------------------
;;; Slice C -- belief DERIVATION capture (the rete derivation-table).
;;; The engine now records, per rule-concluded fact, the ordered firings that built
;;; its belief -- authoritative "how did this belief get this value," not recomputed.
;;; ------------------------------------------------------------------

(defun find-concluded-fact (name value)
  "The first NAME fact whose VALUE slot equals VALUE (both LISA-USER symbols), or NIL."
  (dolist (f (lisa:get-fact-list (lisa:inference-engine)))
    (when (and (eq (lisa:fact-name f) name)
               (eql (lisa:get-slot-value f 'lisa-user::value) value))
      (return f))))

(defun derivation-of (name value)
  "The derivation record list for the NAME/VALUE fact in working memory, or NIL."
  (let ((f (find-concluded-fact name value)))
    (and f (lisa:fact-derivation (lisa:inference-engine) f))))

(deftest derivation-records-a-combination-of-firings ()
  ;; culture-1: two pseudomonas rules fire on one hypothesis. The derivation is the
  ;; ORDERED list of both firings, belief-before/after bracketing each, so the
  ;; combination (0.4, then combine 0.6 -> 0.76) is authoritative, not recomputed.
  (run-scenario 'lisa-user::culture-1 :certainty-factors)
  (let ((d (derivation-of 'lisa-user::organism-identity :pseudomonas)))
    (is (= 2 (length d)) "pseudomonas belief was built by two firings")
    (is (approx= (lisa:derivation-record-rule-belief (first d)) 0.4)
        "first firing is the 0.4 burn rule")
    (is (null (lisa:derivation-record-belief-before (first d)))
        "first firing starts from no prior belief")
    (is (approx= (lisa:derivation-record-belief-after (first d)) 0.4)
        "after the first firing, belief is 0.4")
    (is (approx= (lisa:derivation-record-rule-belief (second d)) 0.6)
        "second firing is the 0.6 compromised-host rule")
    (is (approx= (lisa:derivation-record-belief-before (second d)) 0.4)
        "second firing composes onto the running 0.4")
    (is (approx= (lisa:derivation-record-belief-after (second d)) 0.76)
        "combined belief is 0.76")))

(deftest derivation-exposes-the-chained-class-premise ()
  ;; klebsiella is refined from the derived organism-class. Its single derivation
  ;; record must carry the organism-class premise WITH its 0.8 belief, so
  ;; 0.40 = 0.8 (class) x 0.5 (rule) is reconstructable -- and the premise fact object
  ;; recurses into the class's own derivation (the multi-hop chain the /why endpoint
  ;; walks).
  (run-scenario 'lisa-user::culture-1 :certainty-factors)
  (let* ((d (derivation-of 'lisa-user::organism-identity :klebsiella))
         (rec (first d))
         (class-premise (and rec
                             (find-if (lambda (pr)
                                        (eq (lisa:fact-name (car pr)) 'lisa-user::organism-class))
                                      (lisa:derivation-record-premises rec)))))
    (is (= 1 (length d)) "klebsiella was concluded by a single tier-2 firing")
    (is (approx= (lisa:derivation-record-rule-belief rec) 0.5) "the klebsiella rule's own belief is 0.5")
    (is class-premise "the derivation carries the organism-class premise")
    (is (approx= (cdr class-premise) 0.8) "the class premise's belief snapshot is 0.8")
    (is (approx= (lisa:derivation-record-belief-after rec) 0.40) "composed belief is 0.8 x 0.5 = 0.40")
    (is (lisa:fact-derivation (lisa:inference-engine) (car class-premise))
        "the class premise fact has its OWN derivation -- the chain recurses")))

(deftest raw-evidence-has-no-derivation ()
  ;; Only rule-concluded facts are explained; a fact asserted as raw evidence has no
  ;; derivation record (FACT-DERIVATION returns NIL).
  (run-scenario 'lisa-user::culture-1 :certainty-factors)
  (is (null (derivation-of 'lisa-user::gram 'lisa-user::neg))
      "the raw gram=neg evidence fact has no derivation"))

(deftest reset-clears-the-derivation-table ()
  ;; Derivations are per-consultation -- a reset wipes them along with the facts.
  (run-scenario 'lisa-user::culture-1 :certainty-factors)
  (is (plusp (hash-table-count (lisa:rete-derivation-table (lisa:inference-engine))))
      "a run populates the derivation table")
  (lisa:reset)
  (is (zerop (hash-table-count (lisa:rete-derivation-table (lisa:inference-engine))))
      "reset empties the derivation table"))

;;; ------------------------------------------------------------------
;;; Slice D -- the /why serializer (the whole Lisp path the /why handler runs,
;;; minus HTTP; the curl smoke test bin/test-why.sh covers the wire).
;;; ------------------------------------------------------------------

(deftest why-serializer-renders-the-chained-derivation ()
  ;; klebsiella's rendered derivation must carry the composition arithmetic, the
  ;; rule's provenance (authoritative origin + verified evidence), and the recursive
  ;; organism-class premise (its own nested derivation + belief) -- the multi-hop
  ;; explanation the LLM narrates instead of reconstructing.
  (run-scenario 'lisa-user::culture-1 :certainty-factors)
  (let* ((fact (lisa-bridge::find-organism-identity-fact :klebsiella))
         (derivs (lisa:fact-derivation (lisa:inference-engine) fact))
         (json (lisa-bridge::derivation-record->json (first derivs))))
    (is (string= (gethash "rule" json)
                 "enterobacteriaceae-in-compromised-host-suggests-klebsiella")
        "the record names the short (descriptive) rule name")
    (is (search "= 0.400" (gethash "composition" json))
        "the composition states the composed 0.40 result")
    (let ((prov (gethash "provenance" json)))
      (is (and prov (string= (gethash "origin" prov) "paip-subset"))
          "the klebsiella rule's origin surfaces as paip-subset")
      (is (and prov (plusp (length (gethash "evidence" prov))))
          "verified evidence is present and non-empty"))
    (let* ((premises (gethash "premises" json))
           (class-premise (find-if (lambda (p) (search "organism-class" (gethash "fact" p)))
                                   premises)))
      (is class-premise "the organism-class premise is rendered")
      (is (and class-premise (gethash "belief" class-premise))
          "the class premise carries its belief snapshot")
      (is (and class-premise (gethash "derivation" class-premise))
          "the class premise carries its OWN nested derivation (chain recurses)"))))