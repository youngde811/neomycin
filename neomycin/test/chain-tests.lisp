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
;;; Biochemical CROSS-DISCONFIRMATION among the siblings, in isolation.
;;; Each of the four cross-disconfirming rules is fired against a SINGLE live
;;; sibling identity established by an independent (non-contradicting) path, then a
;;; contradicting biochemical marker is asserted; CHECK-DISCONFIRMS verifies the
;;; identity is still present but its belief fell below the confirming value and its
;;; DS plausibility dropped below 1.0 (the ruling-out rule fired). No competing
;;; sibling is present, so only the rule under test can disconfirm. (Companion to
;;; the gram/aerobic disconfirming isolation tests in rules.lisp.)
;;; ------------------------------------------------------------------

(deftest rule-red-pigment-argues-against-non-serratia ()
  ;; Proteus established by urease+/swarming (0.8*0.8 = 0.64); red pigment (essentially
  ;; Serratia-specific) then argues against it (-0.8).
  (check-disconfirms (lambda (o p) (declare (ignore p))
                       (af "gram" "neg" o) (af "morphology" "rod" o) (af "aerobicity" "aerobic" o)
                       (af "urease" "positive" o) (af "motility" "swarming" o)
                       (af "pigment" "red" o))
                     "proteus" 0.64))

(deftest rule-indole-pos-argues-against-indole-negative-species ()
  ;; Serratia established by red pigment (0.8*0.75 = 0.60); a positive indole then
  ;; argues against the characteristically indole-negative Serratia (-0.6).
  (check-disconfirms (lambda (o p) (declare (ignore p))
                       (af "gram" "neg" o) (af "morphology" "rod" o) (af "aerobicity" "aerobic" o)
                       (af "pigment" "red" o)
                       (af "indole" "positive" o))
                     "serratia" 0.60))

(deftest rule-lactose-fermenter-argues-against-non-fermenters ()
  ;; Proteus established by urease+/swarming (0.64); lactose fermentation then argues
  ;; against the non-fermenter Proteus (-0.7).
  (check-disconfirms (lambda (o p) (declare (ignore p))
                       (af "gram" "neg" o) (af "morphology" "rod" o) (af "aerobicity" "aerobic" o)
                       (af "urease" "positive" o) (af "motility" "swarming" o)
                       (af "lactose" "fermenter" o))
                     "proteus" 0.64))

(deftest rule-lactose-non-fermenter-argues-against-fermenters ()
  ;; Klebsiella established by compromised-host (0.8*0.5 = 0.40) -- a context path, not
  ;; biochemistry, so it can coexist with a lactose reading; a non-fermenting lactose
  ;; reading then argues against the strong fermenter Klebsiella (-0.6).
  (check-disconfirms (lambda (o p)
                       (af "gram" "neg" o) (af "morphology" "rod" o) (af "aerobicity" "aerobic" o)
                       (af "compromised-host" "t" p)
                       (af "lactose" "non-fermenter" o))
                     "klebsiella" 0.40))

;;; ------------------------------------------------------------------
;;; Two near-tied siblings + a discriminating biochemical -> DS CONFLICT.
;;;
;;; This is the sibling-cluster analogue of culture-2's ambiguous-stain conflict. Construct
;;; an organism the biochemistry pulls two ways: lactose+/indole+ refines E. coli
;;; (0.8*0.8 = 0.64), while urease+/swarming refines Proteus (0.8*0.8 = 0.64) -- two
;;; siblings TIED at 0.64 out of the shared class. The reading is internally contradictory
;;; for BOTH: E. coli is urease-NEGATIVE, so urease+ fires
;;; `urease-pos-argues-against-urease-negative-organism` (-0.7) against it; Proteus is a
;;; lactose NON-fermenter, so the same lactose+ that confirmed E. coli fires
;;; `lactose-fermenter-argues-against-non-fermenters` (-0.7) against Proteus. Each sibling
;;; is disconfirmed by exactly the marker that confirmed the OTHER.
;;;
;;; Under DS this is genuine conflict on both (K = 0.64*0.7 = 0.448 each): both masses
;;; renormalize to bel 0.348 and -- the fingerprint -- PLAUSIBILITY drops to 0.543, below
;;; 1.0. DS shows HOW the biochemistry fails to fit either cleanly (a lowered ceiling on
;;; each), not just that a number fell; the symmetric contradiction leaves neither as a
;;; false winner. CF collapses each conflict to the same single scalar, -0.167 (a negative
;;; CF, "evidence against"), losing the bel/pl structure DS preserves. (Biologically an
;;; isolate is not both E. coli and Proteus; like culture-2 this case exists to exercise
;;; the belief algebra on the cluster, not to model a real organism.)
;;; ------------------------------------------------------------------

(defun run-sibling-conflict (system)
  "Aerobic gram-neg rod that reads lactose+/indole+ (E. coli) AND urease+/swarming
   (Proteus): urease+ disconfirms the urease-negative E. coli, and lactose+ disconfirms
   the non-fermenter Proteus -- a symmetric double-conflict."
  (run-facts system
             (lambda (o p) (declare (ignore p))
               (af "gram" "neg" o) (af "morphology" "rod" o) (af "aerobicity" "aerobic" o)
               (af "lactose" "fermenter" o) (af "indole" "positive" o)
               (af "urease" "positive" o) (af "motility" "swarming" o))))

(deftest chain-sibling-urease-conflict-cf ()
  ;; CF collapses the conflict: each sibling's 0.64 confirming CF combines with a -0.7
  ;; disconfirming CF (E. coli by urease+, Proteus by lactose+) to the same single
  ;; negative number -- the contradiction implicates both equally.
  (let ((c (run-sibling-conflict :certainty-factors)))
    (check-cf c "proteus" -0.16667)
    (check-cf c "e-coli" -0.16667)))

(deftest chain-sibling-urease-conflict-ds ()
  ;; DS keeps the conflict legible: BOTH siblings renormalize to bel 0.348 with
  ;; plausibility 0.543 -- a ceiling below 1.0 is the conflict's fingerprint
  ;; (K = 0.448 each). E. coli is disconfirmed by urease+ (it is urease-negative) and
  ;; Proteus by lactose+ (it is a non-fermenter): a symmetric double-conflict.
  (let ((c (run-sibling-conflict :dempster-shafer)))
    (check-ds c "proteus" 0.34783 0.54348)
    (check-ds c "e-coli" 0.34783 0.54348)))

(deftest chain-sibling-conflict-pulls-both-contradicted-siblings-below-1 ()
  ;; The behavioral property behind the goldens: this reading is biochemically
  ;; contradictory for BOTH candidates (E. coli should not be urease+, Proteus should
  ;; not be a lactose fermenter), so each discriminating marker pulls the sibling it
  ;; argues against below plausibility 1.0. DS localizes the conflict to exactly the
  ;; contradicted hypotheses -- here both -- and, the contradiction being symmetric,
  ;; leaves them at equal (lowered) intervals rather than crowning a false winner.
  (let ((c (run-sibling-conflict :dempster-shafer)))
    (is (< (belief:ds-belief-pl (belief-of c "e-coli")) 1.0)
        "urease+ should drop E. coli's plausibility below 1.0 (it is urease-negative)")
    (is (< (belief:ds-belief-pl (belief-of c "proteus")) 1.0)
        "lactose+ should drop Proteus's plausibility below 1.0 (it is a non-fermenter)")
    (is (approx= (belief:ds-belief-bel (belief-of c "proteus"))
                 (belief:ds-belief-bel (belief-of c "e-coli")))
        "the contradiction is symmetric -- neither sibling wins the tie")))

;;; ------------------------------------------------------------------
;;; The OBSERVED session gap, now closed: lactose+/indole+ AND red pigment.
;;;
;;; This is the exact reading from the 2026-07-30 clinician session (corpus-sketch
;;; §5 cand. 4): an aerobic gram-neg rod read lactose+/indole+ (E. coli, 0.64) and
;;; red pigment (Serratia, 0.60), and BOTH sat at plausibility 1.0 -- the engine
;;; could not express that one organism cannot be both. With the cross-disconfirming
;;; rules the red pigment (Serratia-specific) fires -0.8 against E. coli, and the
;;; indole+ fires -0.6 against the indole-negative Serratia. Each sibling is
;;; disconfirmed by the marker that confirmed the OTHER, so BOTH plausibilities now
;;; fall below 1.0 -- the honest "the biochemistry doesn't cleanly fit either" the
;;; flat pl 1.0 could not give. The magnitudes differ (-0.8 vs -0.6), so unlike the
;;; urease case this conflict is ASYMMETRIC: E. coli is pulled down harder.
;;; ------------------------------------------------------------------

(defun run-red-pigment-conflict (system)
  "Aerobic gram-neg rod reading lactose+/indole+ (E. coli, 0.64) AND red pigment
   (Serratia, 0.60): red pigment disconfirms E. coli (-0.8), indole+ disconfirms
   Serratia (-0.6). The reconstruction of the observed session gap."
  (run-facts system
             (lambda (o p) (declare (ignore p))
               (af "gram" "neg" o) (af "morphology" "rod" o) (af "aerobicity" "aerobic" o)
               (af "lactose" "fermenter" o) (af "indole" "positive" o)
               (af "pigment" "red" o))))

(deftest chain-sibling-red-pigment-conflict-cf ()
  ;; CF collapses each conflict to a scalar. E. coli 0.64 (+) with -0.8: -0.4444.
  ;; Serratia 0.60 (+) with -0.6: exact cancellation to 0.0.
  (let ((c (run-red-pigment-conflict :certainty-factors)))
    (check-cf c "e-coli" -0.44444)
    (check-cf c "serratia" 0.0)))

(deftest chain-sibling-red-pigment-conflict-ds ()
  ;; DS keeps both conflicts legible with the asymmetry visible in the intervals:
  ;; E. coli renormalizes to [0.2623, 0.4098] (K = 0.64*0.8 = 0.512), Serratia to
  ;; [0.375, 0.625] (K = 0.60*0.6 = 0.36) -- the more-specific red pigment bites harder.
  (let ((c (run-red-pigment-conflict :dempster-shafer)))
    (check-ds c "e-coli"   0.26230 0.40984)
    (check-ds c "serratia" 0.375   0.625)))

(deftest chain-sibling-red-pigment-drops-both-plausibilities ()
  ;; The behavioral property the session gap demanded: a contradictory pair of
  ;; biochemical readings pulls BOTH siblings' plausibility below 1.0 (neither stays
  ;; co-plausible at 1.0), and -- the magnitudes differing -- E. coli (hit by the
  ;; Serratia-specific pigment, -0.8) ends up below Serratia (hit by indole, -0.6).
  (let ((c (run-red-pigment-conflict :dempster-shafer)))
    (is (< (belief:ds-belief-pl (belief-of c "e-coli")) 1.0)
        "red pigment should drop E. coli's plausibility below 1.0")
    (is (< (belief:ds-belief-pl (belief-of c "serratia")) 1.0)
        "indole+ should drop Serratia's plausibility below 1.0")
    (is (< (belief:ds-belief-bel (belief-of c "e-coli"))
           (belief:ds-belief-bel (belief-of c "serratia")))
        "the -0.8 pigment bites harder than the -0.6 indole: E. coli falls further")))

;;; ------------------------------------------------------------------
;;; A CONTEXT-chained sibling meets a contradicting biochemical (open-Q3).
;;;
;;; Salmonella and Klebsiella are chained off host/travel context, not biochemistry,
;;; so they rarely co-fire WITH a biochemical species -- but when a context call meets
;;; a contradicting biochemical reading the cross-disconfirmation still applies. Here
;;; tropical travel suggests Salmonella (0.8*0.65 = 0.52), then a lactose-fermenter
;;; reading -- Salmonella is a classic non-fermenter -- fires
;;; `lactose-fermenter-argues-against-non-fermenters` (-0.7) against it.
;;; ------------------------------------------------------------------

(defun run-salmonella-lactose-conflict (system)
  "Tropical-travel Salmonella (0.52) meeting a contradicting lactose-fermenter reading
   (-0.7): a context-chained call disconfirmed by biochemistry."
  (run-facts system
             (lambda (o p)
               (af "gram" "neg" o) (af "morphology" "rod" o) (af "aerobicity" "aerobic" o)
               (af "recent-travel" "tropical" p)
               (af "lactose" "fermenter" o))))

(deftest chain-context-salmonella-lactose-conflict-cf ()
  ;; Salmonella 0.52 (+) combined with the -0.7 non-fermenter disconfirmation: -0.375.
  (let ((c (run-salmonella-lactose-conflict :certainty-factors)))
    (check-cf c "salmonella" -0.375)))

(deftest chain-context-salmonella-lactose-conflict-ds ()
  ;; DS: Salmonella renormalizes to [0.2453, 0.4717] (K = 0.52*0.7 = 0.364) -- a
  ;; context-suggested call whose plausibility the biochemistry pulls below 1.0.
  (let ((c (run-salmonella-lactose-conflict :dempster-shafer)))
    (check-ds c "salmonella" 0.24528 0.47170)))

(deftest chain-biochemistry-adjudicates-context-vs-biochemical-sibling ()
  ;; Restores the asymmetric-localization demonstration: travel suggests Salmonella
  ;; (0.52) while lactose+/indole+ confirm E. coli (0.64). The lactose+ (and indole+)
  ;; argue against the non-fermenter Salmonella, but NOTHING argues against E. coli, so
  ;; DS localizes the conflict to Salmonella alone -- E. coli stays clean at [0.64, 1.0]
  ;; while Salmonella's plausibility falls below 1.0. The biochemistry adjudicates
  ;; between the context call and the biochemical call.
  (let ((c (run-facts :dempster-shafer
                      (lambda (o p)
                        (af "gram" "neg" o) (af "morphology" "rod" o) (af "aerobicity" "aerobic" o)
                        (af "recent-travel" "tropical" p)
                        (af "lactose" "fermenter" o) (af "indole" "positive" o)))))
    (is (approx= (belief:ds-belief-pl (belief-of c "e-coli")) 1.0)
        "E. coli stays clean at plausibility 1.0 -- no rule argues against it")
    (is (approx= (belief:ds-belief-bel (belief-of c "e-coli")) 0.64)
        "E. coli belief stays at its confirmed 0.64")
    (is (< (belief:ds-belief-pl (belief-of c "salmonella")) 1.0)
        "the lactose+ reading drops the non-fermenter Salmonella's plausibility below 1.0")
    (is (> (belief:ds-belief-bel (belief-of c "e-coli"))
           (belief:ds-belief-bel (belief-of c "salmonella")))
        "the biochemistry favors the biochemical E. coli over the context-suggested Salmonella")))