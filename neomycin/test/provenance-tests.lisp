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
        ;; The honesty flag: the belief VALUE is illustrative, never sourced from :evidence.
        (is (eq (getf prov :belief-basis) :illustrative)
            (format nil "~A: :belief-basis must be :illustrative" short))
        (is (stringp (getf prov :note))
            (format nil "~A: :note must be a string" short))))))

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