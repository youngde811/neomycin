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

(deftest chain-tier1-class-scoped-in-multi-organism ()
  ;; Multi-organism companion to multi-organism-identities-stay-scoped (scenarios.lisp):
  ;; the enterobacteriaceae CLASS must land on o1 (the aerobic gram-neg rod) and NOT
  ;; on o2 (the gram-pos coccus). After C2 the class is the only conclusion o1
  ;; carries, so this is the positive scoping assertion the identity-side test can no
  ;; longer make.
  (belief:use-system :dempster-shafer)
  (let ((*standard-output* (make-broadcast-stream)))
    (funcall 'lisa-user::culture-multi))
  (let ((classes (collect-classes-scoped))
        (o1 (lu "o1")) (o2 (lu "o2")))
    (is (equal classes (list (cons "enterobacteriaceae" o1)))
        "exactly one organism-class, enterobacteriaceae, scoped to o1")
    (is (not (find o2 classes :key #'cdr))
        "the enterobacteriaceae class must NOT leak onto o2")))

;;; ------------------------------------------------------------------
;;; Chained cluster, tier 2 (§3B) -- a species refined FROM the intermediate, with
;;; belief composing THROUGH it, and its therapy susceptibility rolling UP to the
;;; family (the species carries no KB entry of its own).
;;; ------------------------------------------------------------------

(deftest chain-tier2-e-coli-composes-through-class () ; 0.8*0.8 = 0.64
  ;; Aerobic gram-neg rod fires organism-class :enterobacteriaceae (0.8); class +
  ;; lactose-fermenter + indole-positive refines to E. coli (rule 0.8). The
  ;; discriminators carry nil belief, so the composed species belief is 0.8*0.8 = 0.64
  ;; -- belief flowing through the belief-valued intermediate, the §3B path.
  (check-rule (lambda (o p) (declare (ignore p))
                (af "gram" "neg" o) (af "morphology" "rod" o)
                (af "aerobicity" "aerobic" o)
                (af "lactose" "fermenter" o) (af "indole" "positive" o))
              "e-coli" 0.64))

(deftest chain-e-coli-inherits-family-susceptibility ()
  ;; In the CANONICAL KB, :e-coli carries no sensitivities of its own; via the
  ;; deffamily roll-up it inherits :enterobacteriaceae's. Meropenem probes it -- the
  ;; species figure must equal the family figure exactly.
  (let ((eco (therapy:kb-susceptibility therapy:*therapy-kb* :meropenem :e-coli))
        (fam (therapy:kb-susceptibility therapy:*therapy-kb* :meropenem :enterobacteriaceae)))
    (is (and eco fam) "both e-coli and enterobacteriaceae resolve a meropenem susceptibility")
    (is (and (belief:ds-belief-p eco) (belief:ds-belief-p fam)
             (= (belief:ds-belief-bel eco) (belief:ds-belief-bel fam))
             (= (belief:ds-belief-pl eco) (belief:ds-belief-pl fam)))
        "e-coli's meropenem susceptibility equals the enterobacteriaceae family figure (roll-up)")))

(deftest chain-tier2-enterobacter-composes-through-class () ; 0.8*0.6 = 0.48
  ;; lactose+ / indole- / MOTILE -> Enterobacter (motility separates it from
  ;; non-motile Klebsiella). Composed 0.8*0.6 = 0.48.
  (check-rule (lambda (o p) (declare (ignore p))
                (af "gram" "neg" o) (af "morphology" "rod" o) (af "aerobicity" "aerobic" o)
                (af "lactose" "fermenter" o) (af "indole" "negative" o)
                (af "motility" "motile" o))
              "enterobacter" 0.48))

(deftest chain-tier2-serratia-composes-through-class () ; 0.8*0.75 = 0.60
  ;; Red pigment (prodigiosin) -> Serratia. Composed 0.8*0.75 = 0.60.
  (check-rule (lambda (o p) (declare (ignore p))
                (af "gram" "neg" o) (af "morphology" "rod" o) (af "aerobicity" "aerobic" o)
                (af "pigment" "red" o))
              "serratia" 0.60))

(deftest chain-tier2-proteus-composes-through-class () ; 0.8*0.8 = 0.64
  ;; Urease+ and swarming -> Proteus. Composed 0.8*0.8 = 0.64.
  (check-rule (lambda (o p) (declare (ignore p))
                (af "gram" "neg" o) (af "morphology" "rod" o) (af "aerobicity" "aerobic" o)
                (af "urease" "positive" o) (af "motility" "swarming" o))
              "proteus" 0.64))

;;; ------------------------------------------------------------------
;;; The composition INVARIANT, stated once over every isolatable tier-2 rule.
;;;
;;; The individual chain-tier2-* / rule-* tests above pin specific goldens; this one
;;; asserts the *law* they all instance: a chained species' belief is exactly the
;;; enterobacteriaceae class belief (0.8) times the species rule's own belief, because
;;; belief composes through the derived organism-class (docs/chaining-belief-spike.md
;;; §7). Under CF that product is the belief; under DS it is [product, 1.0] --
;;; confirmatory, no conflict. Each case fires a SINGLE tier-2 rule on a minimal
;;; aerobic-gram-neg-rod lineage plus that rule's discriminators. (The hospital-acquired
;;; klebsiella rule, 0.6, is deliberately omitted: its premises are a superset of the
;;; compromised rule's, so it cannot fire alone -- both key off the shared class and
;;; their masses combine to 0.688, covered by rule-hospital-compromised-klebsiella-combines.)
;;; ------------------------------------------------------------------

(defparameter *entero-class-belief* 0.8
  "The tier-1 enterobacteriaceae organism-class belief every tier-2 species composes
   through. Change here iff the class rule's belief changes.")

(deftest chain-belief-composes-as-class-times-rule ()
  (dolist (case (list
                 ;; (species-string rule-belief discriminator-builder)
                 (list "e-coli"      0.8  (lambda (o p) (declare (ignore p))
                                            (af "lactose" "fermenter" o) (af "indole" "positive" o)))
                 (list "enterobacter" 0.6 (lambda (o p) (declare (ignore p))
                                            (af "lactose" "fermenter" o) (af "indole" "negative" o)
                                            (af "motility" "motile" o)))
                 (list "serratia"    0.75 (lambda (o p) (declare (ignore p))
                                            (af "pigment" "red" o)))
                 (list "proteus"     0.8  (lambda (o p) (declare (ignore p))
                                            (af "urease" "positive" o) (af "motility" "swarming" o)))
                 (list "klebsiella"  0.5  (lambda (o p) (declare (ignore o))
                                            (af "compromised-host" "t" p)))
                 (list "salmonella"  0.65 (lambda (o p) (declare (ignore o))
                                            (af "recent-travel" "tropical" p)))
                 (list "salmonella"  0.55 (lambda (o p) (declare (ignore o))
                                            (af "culture-site" "blood" *ctx-culture*)
                                            (af "white-blood-count" "low" p)))))
    (destructuring-bind (species rule-belief discriminators) case
      (let ((expected (* *entero-class-belief* rule-belief))
            (builder (lambda (o p)
                       (af "gram" "neg" o) (af "morphology" "rod" o) (af "aerobicity" "aerobic" o)
                       (funcall discriminators o p))))
        ;; CF: exactly the product. DS: [product, 1.0] -- confirmatory regime.
        (check-cf (run-facts :certainty-factors builder) species expected)
        (check-ds (run-facts :dempster-shafer builder) species expected 1.0)))))

;;; ------------------------------------------------------------------
;;; Two near-tied siblings + a discriminating biochemical -> DS CONFLICT.
;;;
;;; This is the sibling-cluster analogue of culture-2's ambiguous-stain conflict, and
;;; the reason the urease disconfirming rule was added in C1. Construct an organism the
;;; biochemistry pulls two ways: lactose+/indole+ refines E. coli (0.8*0.8 = 0.64), while
;;; urease+/swarming refines Proteus (0.8*0.8 = 0.64) -- two siblings TIED at 0.64 out of
;;; the shared class. But E. coli is a urease-NEGATIVE species, so the same urease+ reading
;;; fires `urease-pos-argues-against-urease-negative-organism` (-0.7) against E. coli only.
;;;
;;; Under DS this is genuine conflict (K = 0.64*0.7 = 0.448): E. coli's mass renormalizes to
;;; bel 0.348 and -- the fingerprint -- its PLAUSIBILITY drops to 0.543, below 1.0. Proteus,
;;; untouched by any disconfirming rule, stays [0.64, 1.0]. The tie is broken by the
;;; discriminator, and DS shows HOW (a lowered ceiling), not just that a number fell.
;;; CF collapses the same conflict to a single scalar: E. coli to -0.167 (a negative CF,
;;; "evidence against"), losing the bel/pl structure DS preserves. (Biologically an isolate
;;; is not both E. coli and Proteus; like culture-2 this case exists to exercise the belief
;;; algebra on the cluster, not to model a real organism.)
;;; ------------------------------------------------------------------

(defun run-sibling-conflict (system)
  "Aerobic gram-neg rod that reads lactose+/indole+ (E. coli) AND urease+/swarming
   (Proteus): the urease+ additionally disconfirms the urease-negative E. coli."
  (run-facts system
             (lambda (o p) (declare (ignore p))
               (af "gram" "neg" o) (af "morphology" "rod" o) (af "aerobicity" "aerobic" o)
               (af "lactose" "fermenter" o) (af "indole" "positive" o)
               (af "urease" "positive" o) (af "motility" "swarming" o))))

(deftest chain-sibling-urease-conflict-cf ()
  ;; CF collapses the conflict: E. coli's 0.64 confirming CF combines with the -0.7
  ;; disconfirming CF to a single negative number; Proteus is untouched at 0.64.
  (let ((c (run-sibling-conflict :certainty-factors)))
    (check-cf c "proteus" 0.64)
    (check-cf c "e-coli" -0.16667)))

(deftest chain-sibling-urease-conflict-ds ()
  ;; DS keeps the conflict legible: Proteus clean at [0.64, 1.0]; E. coli renormalized
  ;; to bel 0.348 with plausibility 0.543 -- a ceiling below 1.0 is the conflict's
  ;; fingerprint (K = 0.448).
  (let ((c (run-sibling-conflict :dempster-shafer)))
    (check-ds c "proteus" 0.64 1.0)
    (check-ds c "e-coli" 0.34783 0.54348)))

(deftest chain-sibling-conflict-drops-only-the-disconfirmed-plausibility ()
  ;; The behavioral property behind the goldens: the discriminating urease+ pulls the
  ;; urease-negative sibling's plausibility below 1.0 while leaving the other sibling's
  ;; at 1.0 -- DS localizes the conflict to the hypothesis the evidence argues against.
  (let ((c (run-sibling-conflict :dempster-shafer)))
    (is (< (belief:ds-belief-pl (belief-of c "e-coli")) 1.0)
        "urease+ should drop E. coli's plausibility below 1.0 (it is urease-negative)")
    (is (approx= (belief:ds-belief-pl (belief-of c "proteus")) 1.0)
        "Proteus plausibility stays 1.0 -- no rule argues against it")
    (is (> (belief:ds-belief-bel (belief-of c "proteus"))
           (belief:ds-belief-bel (belief-of c "e-coli")))
        "the tie breaks in Proteus's favor once E. coli absorbs the urease conflict")))