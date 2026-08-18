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
  (let ((paip (rule-provenance-of 'lisa-user::burn-blood-gram-neg-rod-narrows-to-pseudomonas))
        (neo  (rule-provenance-of 'lisa-user::red-pigment-narrows-to-serratia))
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

(defun answer-fact-containing (organism)
  "The first CANDIDATES fact whose set contains ORGANISM."
  (find-if (lambda (f) (member organism (lisa:get-slot-value f 'lisa-user::value)))
           (neomycin:candidates-facts 'lisa-user::o1)))

(deftest derivation-records-the-rules-behind-an-answer ()
  ;; The v0.11 equivalent of the chained-derivation tests this replaces. There is no
  ;; chain any more -- nothing composes THROUGH an organism-class -- so what a
  ;; derivation records is which rules produced an ANSWER, and that is what an
  ;; explanation quotes.
  (run-scenario 'lisa-user::culture-1 :candidates)
  (let* ((fact (answer-fact-containing :pseudomonas))
         (rules (and fact (neomycin:contributing-rules fact))))
    (is fact "culture-1 produced an answer naming pseudomonas")
    (when fact
      (is (plusp (length rules)) "and the engine recorded which rules produced it")
      (is (every (lambda (r) (realp (lisa:rule-belief r))) rules)
          "each carrying its own belief"))))

(deftest derivation-supports-explaining-a-hypothesis ()
  ;; Under this shape nothing argues against anything, so the honest account of why a
  ;; hypothesis survives is which evidence kept ADMITTING it -- which RULES-BEHIND
  ;; reads straight out of working memory rather than reconstructing.
  (run-scenario 'lisa-user::culture-1 :candidates)
  (let ((rules (neomycin:rules-behind 'lisa-user::o1 :pseudomonas)))
    (is (plusp (length rules)) "pseudomonas has rules behind it")
    (is (member 'lisa-user::burn-blood-gram-neg-rod-narrows-to-pseudomonas rules)
        "including the burn rule, which narrowed to it")
    (is (member 'lisa-user::compromised-gram-neg-rod-narrows-to-pseudomonas rules)
        "and the compromised-host rule -- distinct evidence, both admitting it")))

(deftest raw-evidence-has-no-derivation ()
  ;; Only rule-concluded facts are explained; a fact asserted as raw evidence has no
  ;; derivation record (FACT-DERIVATION returns NIL).
  (run-scenario 'lisa-user::culture-1 :candidates)
  (is (null (derivation-of 'lisa-user::gram 'lisa-user::neg))
      "the raw gram=neg evidence fact has no derivation"))

(deftest reset-clears-the-derivation-table ()
  ;; Derivations are per-consultation -- a reset wipes them along with the facts.
  (run-scenario 'lisa-user::culture-1 :candidates)
  (is (plusp (hash-table-count (lisa:rete-derivation-table (lisa:inference-engine))))
      "a run populates the derivation table")
  (lisa:reset)
  (is (zerop (hash-table-count (lisa:rete-derivation-table (lisa:inference-engine))))
      "reset empties the derivation table"))

;;; ------------------------------------------------------------------
;;; Slice D -- the /why serializer (the whole Lisp path the /why handler runs,
;;; minus HTTP; the curl smoke test bin/test-why.sh covers the wire).
;;; ------------------------------------------------------------------

