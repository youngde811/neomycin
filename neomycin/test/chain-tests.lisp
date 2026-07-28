;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: Chained-cluster tests (corpus sketch §3B/§5.1). The enterobacteriaceae
;; family is reconstructed as a multi-hop cluster: evidence -> derived ORGANISM-CLASS
;; (tier 1) -> competing sibling species (tier 2, a later increment). This file
;; covers TIER 1 in isolation -- the first corpus inference that concludes a
;; belief-valued INTERMEDIATE abstraction, the DS composition path nothing else
;; exercises yet. These tests are neomycin-only (organism-class exists only in
;; neomycin/rulebase.lisp, never in Lisa's examples/mycin.lisp), so they live in
;; the neomycin/test system rather than the shared lisa/test rule suite.

(in-package "LISA-TEST")

;;; ------------------------------------------------------------------
;;; Reading the derived intermediate out of working memory.
;;; COLLECT-CONCLUSIONS (harness.lisp) is the organism-identity-specific
;;; specialization of COLLECT-PARAM-BELIEFS; the chain adds a second
;;; belief-valued conclusion type (organism-class), read the same way.
;;; ------------------------------------------------------------------

(defun collect-param-beliefs (fact-name)
  "Alist (value-string . belief) for every FACT-NAME fact in working memory."
  (let ((acc '()))
    (dolist (fact (lisa:get-fact-list (lisa:inference-engine)))
      (when (eq (lisa:fact-name fact) fact-name)
        (push (cons (string-downcase
                     (symbol-name (lisa:get-slot-value fact 'lisa-user::value)))
                    (belief:belief-factor fact))
              acc)))
    acc))

(defun collect-classes-scoped ()
  "(value-string . of) for every organism-class fact -- lineage-aware, mirroring
   COLLECT-IDENTITIES for the derived intermediate."
  (let ((acc '()))
    (dolist (fact (lisa:get-fact-list (lisa:inference-engine)))
      (when (eq (lisa:fact-name fact) 'lisa-user::organism-class)
        (push (cons (string-downcase
                     (symbol-name (lisa:get-slot-value fact 'lisa-user::value)))
                    (lisa:get-slot-value fact 'lisa-user::of))
              acc)))
    acc))

(defun run-facts-classes (system builder)
  "Drive BUILDER's minimal lineage under SYSTEM (via RUN-FACTS), then return the
   organism-CLASS conclusions. RUN-FACTS leaves working memory standing after it
   returns, so we re-read it for the intermediate fact type."
  (run-facts system builder)
  (collect-param-beliefs 'lisa-user::organism-class))

(defun check-class-rule (builder class belief)
  "A tier-1 class rule fired in isolation must contribute exactly its :belief --
   CF = BELIEF, DS = [BELIEF, 1.0] -- on the derived organism-class, mirroring
   CHECK-RULE for leaf organism-identity."
  (check-cf (run-facts-classes :certainty-factors builder) class belief)
  (check-ds (run-facts-classes :dempster-shafer builder) class belief 1.0))

;;; ------------------------------------------------------------------
;;; Chained cluster, tier 1 (§3B) -- the derived organism-class intermediate,
;;; tested in isolation BEFORE any species-refinement (tier 2) exists.
;;; ------------------------------------------------------------------

(deftest chain-tier1-aerobic-gram-neg-rod-enterobacteriaceae-class () ; 0.8
  ;; Aerobic gram-neg rod -> organism-class :enterobacteriaceae. Same premises and
  ;; belief as the leaf enterobacteriaceae rule, but the conclusion is the derived
  ;; FAMILY class -- the belief-valued intermediate the chain will compose through.
  ;; Confirmatory only (no disconfirming rule touches organism-class yet), so DS
  ;; plausibility stays at 1.0 and DS-bel equals the CF number: the un-conflicted
  ;; regime, exactly as for a leaf confirming rule.
  (check-class-rule (lambda (o p) (declare (ignore p))
                      (af "gram" "neg" o) (af "morphology" "rod" o)
                      (af "aerobicity" "aerobic" o))
                    "enterobacteriaceae" 0.8))

(deftest chain-tier1-class-scoped-to-organism ()
  ;; The derived class must land on the organism it was inferred from (its OF slot)
  ;; and nowhere else -- the lineage invariant tier-2 species refinement will read
  ;; the intermediate through. Exactly one class fact, scoped to the lone organism.
  (run-facts :dempster-shafer
             (lambda (o p) (declare (ignore p))
               (af "gram" "neg" o) (af "morphology" "rod" o)
               (af "aerobicity" "aerobic" o)))
  (is (equal (collect-classes-scoped)
             (list (cons "enterobacteriaceae" *ctx-organism*)))
      "organism-class enterobacteriaceae should be scoped to the single organism"))