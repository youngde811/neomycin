;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: neomycin test-suite setup. Runs (at load time) BEFORE any test,
;; pointing the shared LISA-TEST harness at neomycin's canonical rulebase.
;;
;; neomycin/rules/ is the definitive rulebase and is already loaded by the NEOMYCIN
;; ASDF system (a dependency of neomycin/test). Lisa's examples/mycin.lisp is part of
;; Lisa-proper and is NEVER used by neomycin -- so we repoint *rulebase-source* at
;; neomycin's rulebase and mark it loaded, which stops ENSURE-RULEBASE from loading
;; Lisa's example over neomycin's (keyword) rulebase. Without this, the harness's
;; example would shadow neomycin's rules and the golden + therapy tests would silently
;; validate the wrong rulebase.
;;
;; NOTE on the source pathname: the rulebase is no longer a single file (it was split
;; into neomycin/rules/ by cluster), so *rulebase-source* now names the load-first
;; class-definition file rather than the whole corpus. Nothing ever LOADs it --
;; ENSURE-RULEBASE only reads *rulebase-source* when *rulebase-loaded* is NIL, and we
;; set that to T immediately below -- so this is documentation of provenance, not a
;; load path. If that ever changes, this must become a list of the ASDF components.

(in-package "LISA-TEST")

(setf *rulebase-source*
      (asdf:system-relative-pathname "neomycin" "neomycin/rules/context.lisp"))

;; The NEOMYCIN system already loaded the rulebase; don't reload Lisa's example.
(setf *rulebase-loaded* t)