;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: neomycin test-suite setup. Runs (at load time) BEFORE any test,
;; pointing the shared LISA-TEST harness at neomycin's canonical rulebase.
;;
;; neomycin/rulebase.lisp is the definitive rulebase and is already loaded by the
;; NEOMYCIN ASDF system (a dependency of neomycin/test). Lisa's examples/mycin.lisp
;; is part of Lisa-proper and is NEVER used by neomycin -- so we repoint
;; *rulebase-source* at neomycin's rulebase and mark it loaded, which stops
;; ENSURE-RULEBASE from loading Lisa's example over neomycin's (keyword) rulebase.
;; Without this, the harness's example would shadow neomycin/rulebase.lisp and the
;; golden + therapy tests would silently validate the wrong rulebase.

(in-package "LISA-TEST")

(setf *rulebase-source*
      (asdf:system-relative-pathname "neomycin" "neomycin/rulebase.lisp"))

;; The NEOMYCIN system already loaded the rulebase; don't reload Lisa's example.
(setf *rulebase-loaded* t)