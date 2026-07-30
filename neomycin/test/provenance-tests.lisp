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