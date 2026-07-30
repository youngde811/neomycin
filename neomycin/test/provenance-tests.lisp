;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: Tests for the WHY/HOW explanation & provenance facility
;; (docs/why-how-provenance-design.md). Slice A covers the ENGINE CAPABILITY: a
;; machine-readable :provenance rule property, added additively to Lisa core
;; (src/core/rule.lisp + parser). Later slices populate provenance across the
;; rulebase (B), capture derivations (C), and serve /why (D) -- their tests land
;; here too. These are neomycin-only: the :provenance property is exercised by
;; neomycin's rulebase, never by Lisa's examples/mycin.lisp.

(in-package "LISA-TEST")

(defun rule-provenance-of (name)
  "The :provenance plist declared on rule NAME (a LISA-USER symbol), or NIL."
  (let ((rule (lisa:find-rule (lisa:inference-engine) name)))
    (and rule (lisa:rule-provenance rule))))

;;; ------------------------------------------------------------------
;;; Slice A -- the :provenance rule property is carried by the engine.
;;; ------------------------------------------------------------------

(deftest rule-provenance-property-is-carried ()
  ;; A rule declaring :provenance exposes it as a plist via LISA:RULE-PROVENANCE;
  ;; a rule that declares none reads NIL. The property is pure metadata -- it does
  ;; not affect inference (the golden + rule suites are unchanged by its presence).
  (let ((class-prov (rule-provenance-of
                     'lisa-user::aerobic-gram-neg-rod-suggests-enterobacteriaceae-class))
        (ecoli-prov (rule-provenance-of
                     'lisa-user::enterobacteriaceae-lactose-pos-indole-pos-suggests-e-coli))
        (plain-prov (rule-provenance-of
                     'lisa-user::gram-neg-rod-in-burn-patient-suggests-pseudomonas)))
    ;; Declared: a well-formed (:origin ... :citation ...) plist.
    (is (eq (getf class-prov :origin) :neomycin-extrapolation)
        "the class rule carries :origin :neomycin-extrapolation")
    (is (stringp (getf class-prov :citation))
        "the class rule carries a scalar (string) citation")
    (is (eq (getf ecoli-prov :origin) :neomycin-extrapolation)
        "the e-coli rule carries :origin :neomycin-extrapolation")
    (is (and (consp (getf ecoli-prov :citation))
             (every #'stringp (getf ecoli-prov :citation)))
        "the e-coli rule carries a list-of-strings citation")
    ;; Undeclared: NIL -- proves the property is additive and disturbs nothing.
    (is (null plain-prov)
        "a rule with no :provenance declaration reads NIL (additive default)")))