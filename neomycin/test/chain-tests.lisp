;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: Chained-cluster tests (corpus sketch §3B/§5.1). A cluster is a
;; multi-hop reconstruction: evidence -> derived ORGANISM-CLASS (tier 1) -> competing
;; sibling species (tier 2) -> cross-disconfirmation among those siblings. There are
;; now FOUR classes across three clusters: enterobacteriaceae (the original), and the
;; gram-positive staphylococcus / streptococcus / enterococcus genera added by
;; docs/gram-positive-cluster-design.md.
;;
;; This file covers all three layers: each class rule in isolation; the composition
;; law (species belief = class belief * rule belief) stated once per cluster over
;; every isolatable tier-2 rule; and each cross-disconfirming rule fired against a
;; single live sibling. These tests are neomycin-only (organism-class exists only in
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

;;; Tier-1 for the GRAM-POSITIVE cocci (docs/gram-positive-cluster-design.md §3.1).
;;; Same shape as the enterobacteriaceae class rule above: a genus abstraction
;;; concluded from morphology, carrying the belief of the leaf rule it replaced.

(deftest chain-tier1-gram-pos-cocci-clumps-staphylococcus-class () ; 0.7
  ;; Replaces the retired one-hop clumps -> staphylococcus IDENTITY rule: same
  ;; premises, same 0.7, but the conclusion is the genus CLASS that slice B refines
  ;; into S. aureus / S. epidermidis / S. saprophyticus by coagulase and novobiocin.
  (check-class-rule (lambda (o p) (declare (ignore p))
                      (af "gram" "pos" o) (af "morphology" "coccus" o)
                      (af "growth-conformation" "clumps" o))
                    "staphylococcus" 0.7))

(deftest chain-tier1-gram-pos-cocci-chains-streptococcus-class () ; 0.7
  ;; Replaces the retired one-hop chains -> streptococcus IDENTITY rule.
  (check-class-rule (lambda (o p) (declare (ignore p))
                      (af "gram" "pos" o) (af "morphology" "coccus" o)
                      (af "growth-conformation" "chains" o))
                    "streptococcus" 0.7))

(deftest chain-tier1-bile-esculin-salt-tolerant-enterococcus-class () ; 0.8
  ;; Enterococcus as a genus peer, not a streptococcal subtype: bile-esculin
  ;; positivity ALONE would not separate it from the non-enterococcal group D
  ;; streptococci, so the rule also requires 6.5% NaCl tolerance. Note the chains
  ;; premises also fire the streptococcus class rule -- both classes legitimately
  ;; hold, which is why this checks the enterococcus one specifically.
  (check-class-rule (lambda (o p) (declare (ignore p))
                      (af "gram" "pos" o) (af "morphology" "coccus" o)
                      (af "growth-conformation" "chains" o)
                      (af "bile-esculin" "positive" o)
                      (af "salt-tolerance" "tolerant" o))
                    "enterococcus" 0.8))

(deftest chain-tier1-chains-blood-compromised-enterococcus-class () ; 0.7
  ;; The CLINICAL second path to the enterococcus class (re-pointed from a leaf
  ;; identity in slice A). It reaches the class without any biochemical test, which
  ;; is what keeps the class available in scenarios that never run one.
  (check-class-rule (lambda (o p)
                      (af "culture-site" "blood" *ctx-culture*)
                      (af "gram" "pos" o) (af "morphology" "coccus" o)
                      (af "growth-conformation" "chains" o)
                      (af "compromised-host" "t" p))
                    "enterococcus" 0.7))

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
  ;; Multi-organism companion to multi-organism-identities-stay-scoped (scenarios.lisp).
  ;; After slice A BOTH organisms stop at a genus/family class: o1 (aerobic gram-neg
  ;; rod) derives enterobacteriaceae, o2 (gram-pos coccus in clumps) derives
  ;; staphylococcus. Each must land on its own organism and neither may leak onto the
  ;; other -- the two-sided scoping assertion, now that the identity layer is empty
  ;; here until slice B adds a coagulase to the driver.
  (belief:use-system :dempster-shafer)
  (let ((*standard-output* (make-broadcast-stream)))
    (funcall 'lisa-user::culture-multi))
  (let ((classes (collect-classes-scoped))
        (o1 (lu "o1")) (o2 (lu "o2")))
    (is (equal (sort (copy-list classes) #'string< :key #'car)
               (list (cons "enterobacteriaceae" o1)
                     (cons "staphylococcus" o2)))
        "exactly two organism-classes, each scoped to its own organism")
    (is (equal (cdr (assoc "enterobacteriaceae" classes :test #'string=)) o1)
        "the enterobacteriaceae class must sit on o1, not leak onto o2")
    (is (equal (cdr (assoc "staphylococcus" classes :test #'string=)) o2)
        "the staphylococcus class must sit on o2, not leak onto o1")))

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

(defparameter *staph-class-belief* 0.7
  "Tier-1 staphylococcus genus-class belief (slice A; carried from the retired leaf).")

(defparameter *strep-class-belief* 0.7
  "Tier-1 streptococcus genus-class belief (slice A; carried from the retired leaf).")

(defparameter *enterococcus-class-belief* 0.8
  "Tier-1 enterococcus genus-class belief via the bile-esculin + salt-tolerance rule.")

(defun check-composition-cases (class-belief lineage cases)
  "Assert the composition law for each of CASES against a shared LINEAGE builder.
   Each case is (species-string rule-belief discriminator-builder) and must fire
   exactly ONE tier-2 rule, whose composed belief is CLASS-BELIEF * RULE-BELIEF --
   CF exactly, DS as [product, 1.0] since nothing argues against it yet."
  (dolist (case cases)
    (destructuring-bind (species rule-belief discriminators) case
      (let ((expected (* class-belief rule-belief))
            (builder (lambda (o p)
                       (funcall lineage o p)
                       (funcall discriminators o p))))
        (check-cf (run-facts :certainty-factors builder) species expected)
        (check-ds (run-facts :dempster-shafer builder) species expected 1.0)))))

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

;;; The same law over the three GRAM-POSITIVE clusters (slice B). Between them these
;;; cases fire all 9 new tier-2 species rules AND both re-parented ones in isolation,
;;; so they supply the per-rule isolation coverage the corpus standard asks for as
;;; well as the invariant -- the generalization sketch §8 wants, arriving early because
;;; three clusters now instance the same law with different class beliefs.

(deftest chain-belief-composes-staphylococcus-species ()
  (check-composition-cases
   *staph-class-belief*
   (lambda (o p) (declare (ignore p))
     (af "gram" "pos" o) (af "morphology" "coccus" o) (af "growth-conformation" "clumps" o))
   (list
    (list "staphylococcus-aureus"         0.85 (lambda (o p) (declare (ignore p))
                                                 (af "coagulase" "positive" o)))
    (list "staphylococcus-epidermidis"    0.55 (lambda (o p) (declare (ignore p))
                                                 (af "coagulase" "negative" o)))
    ;; Novobiocin resistance also leaves the weaker epidermidis default standing; the
    ;; saprophyticus value is unaffected by that, and slice C is where the two siblings
    ;; start arguing with each other.
    (list "staphylococcus-saprophyticus"  0.8  (lambda (o p) (declare (ignore p))
                                                 (af "coagulase" "negative" o)
                                                 (af "novobiocin" "resistant" o)))
    ;; The re-parented clinical path to S. aureus -- no coagulase asserted, so only
    ;; the hospital-acquired rule fires.
    (list "staphylococcus-aureus"         0.8  (lambda (o p) (declare (ignore o))
                                                 (af "hospital-acquired" "t" p))))))

(deftest chain-belief-composes-streptococcus-species ()
  (check-composition-cases
   *strep-class-belief*
   (lambda (o p) (declare (ignore p))
     (af "gram" "pos" o) (af "morphology" "coccus" o) (af "growth-conformation" "chains" o))
   (list
    (list "streptococcus-pyogenes"    0.85 (lambda (o p) (declare (ignore p))
                                             (af "hemolysis" "beta" o)
                                             (af "bacitracin" "sensitive" o)))
    (list "streptococcus-agalactiae"  0.7  (lambda (o p) (declare (ignore p))
                                             (af "hemolysis" "beta" o)
                                             (af "bacitracin" "resistant" o)))
    (list "streptococcus-pneumoniae"  0.85 (lambda (o p) (declare (ignore p))
                                             (af "hemolysis" "alpha" o)
                                             (af "optochin" "sensitive" o)))
    (list "streptococcus-viridans"    0.65 (lambda (o p) (declare (ignore p))
                                             (af "hemolysis" "alpha" o)
                                             (af "optochin" "resistant" o)))
    ;; The re-parented clinical (site-based) path to S. pneumoniae.
    (list "streptococcus-pneumoniae"  0.75 (lambda (o p) (declare (ignore o))
                                             (af "infection-site" "respiratory" p))))))

(deftest chain-belief-composes-enterococcus-species ()
  ;; The chains lineage also derives the streptococcus class, but no strep species rule
  ;; fires without a hemolysis reading, so each case still fires exactly one tier-2 rule.
  (check-composition-cases
   *enterococcus-class-belief*
   (lambda (o p) (declare (ignore p))
     (af "gram" "pos" o) (af "morphology" "coccus" o) (af "growth-conformation" "chains" o)
     (af "bile-esculin" "positive" o) (af "salt-tolerance" "tolerant" o))
   (list
    (list "enterococcus-faecalis" 0.7 (lambda (o p) (declare (ignore p))
                                        (af "sorbitol" "fermenter" o)
                                        (af "arabinose" "non-fermenter" o)))
    (list "enterococcus-faecium"  0.7 (lambda (o p) (declare (ignore p))
                                        (af "arabinose" "fermenter" o)
                                        (af "sorbitol" "non-fermenter" o))))))

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
;;; ------------------------------------------------------------------
;;; CROSS-DISCONFIRMATION among the GRAM-POSITIVE siblings, in isolation (slice C).
;;;
;;; Same method as the enterobacteriaceae section above: establish ONE sibling by an
;;; independent path, then assert the contradicting marker and verify the identity
;;; survives with a lowered belief and DS plausibility below 1.0.
;;;
;;; Where a discriminator is the sibling's ONLY confirming route (coagulase for the
;;; CoNS species, hemolysis for S. pyogenes, optochin for viridans, arabinose for
;;; E. faecalis), the test asserts BOTH readings of that marker -- the ambiguous-result
;;; pattern culture-2 established for the Gram stain. That is the honest way to load a
;;; contradiction onto a hypothesis whose only support is the marker now being
;;; contradicted.
;;; ------------------------------------------------------------------

(deftest rule-coagulase-neg-argues-against-staph-aureus ()
  ;; S. aureus established by the CLINICAL hospital-acquired path (0.7*0.8 = 0.56),
  ;; so the coagulase reading is genuinely independent evidence; a negative then
  ;; argues against it (-0.85).
  (check-disconfirms (lambda (o p)
                       (af "gram" "pos" o) (af "morphology" "coccus" o)
                       (af "growth-conformation" "clumps" o)
                       (af "hospital-acquired" "t" p)
                       (af "coagulase" "negative" o))
                     "staphylococcus-aureus" 0.56))

(deftest rule-coagulase-pos-argues-against-coagulase-negative-staph ()
  ;; S. epidermidis established by coagulase-negative (0.7*0.55 = 0.385); an
  ;; ambiguous/contradictory positive coagulase then argues against it (-0.85).
  (check-disconfirms (lambda (o p) (declare (ignore p))
                       (af "gram" "pos" o) (af "morphology" "coccus" o)
                       (af "growth-conformation" "clumps" o)
                       (af "coagulase" "negative" o)
                       (af "coagulase" "positive" o))
                     "staphylococcus-epidermidis" 0.385))

(deftest rule-catalase-neg-argues-against-staphylococci ()
  ;; S. aureus established clinically (0.56); a catalase-negative reading argues
  ;; against the whole genus (-0.7). This is the tier-1 discriminator doing its work
  ;; from the disconfirming side, which is why it is not a class premise.
  (check-disconfirms (lambda (o p)
                       (af "gram" "pos" o) (af "morphology" "coccus" o)
                       (af "growth-conformation" "clumps" o)
                       (af "hospital-acquired" "t" p)
                       (af "catalase" "negative" o))
                     "staphylococcus-aureus" 0.56))

(deftest rule-beta-hemolysis-argues-against-non-beta-streptococci ()
  ;; S. pneumoniae established by the respiratory site (0.7*0.75 = 0.525); a BETA
  ;; hemolysis reading argues against the alpha-hemolytic pneumococcus (-0.75).
  ;; This is culture-4's mechanism, isolated.
  (check-disconfirms (lambda (o p)
                       (af "gram" "pos" o) (af "morphology" "coccus" o)
                       (af "growth-conformation" "chains" o)
                       (af "infection-site" "respiratory" p)
                       (af "hemolysis" "beta" o))
                     "streptococcus-pneumoniae" 0.525))

(deftest rule-alpha-hemolysis-argues-against-beta-hemolytic-streptococci ()
  ;; S. pyogenes established by beta + bacitracin-sensitive (0.7*0.85 = 0.595); a
  ;; contradictory alpha reading then argues against it (-0.75).
  (check-disconfirms (lambda (o p) (declare (ignore p))
                       (af "gram" "pos" o) (af "morphology" "coccus" o)
                       (af "growth-conformation" "chains" o)
                       (af "hemolysis" "beta" o) (af "bacitracin" "sensitive" o)
                       (af "hemolysis" "alpha" o))
                     "streptococcus-pyogenes" 0.595))

(deftest rule-optochin-sensitive-argues-against-viridans ()
  ;; Viridans established by alpha + optochin-resistant (0.7*0.65 = 0.455); a
  ;; contradictory optochin-sensitive reading argues against it (-0.7).
  (check-disconfirms (lambda (o p) (declare (ignore p))
                       (af "gram" "pos" o) (af "morphology" "coccus" o)
                       (af "growth-conformation" "chains" o)
                       (af "hemolysis" "alpha" o) (af "optochin" "resistant" o)
                       (af "optochin" "sensitive" o))
                     "streptococcus-viridans" 0.455))

(deftest rule-bile-esculin-neg-argues-against-enterococci ()
  ;; E. faecalis established through the enterococcus class (0.8*0.7 = 0.56); a
  ;; contradictory bile-esculin-negative reading argues against it (-0.6), the
  ;; mildest of the gram-positive disconfirmers.
  (check-disconfirms (lambda (o p) (declare (ignore p))
                       (af "gram" "pos" o) (af "morphology" "coccus" o)
                       (af "growth-conformation" "chains" o)
                       (af "bile-esculin" "positive" o) (af "salt-tolerance" "tolerant" o)
                       (af "sorbitol" "fermenter" o) (af "arabinose" "non-fermenter" o)
                       (af "bile-esculin" "negative" o))
                     "enterococcus-faecalis" 0.56))

(deftest rule-arabinose-pos-argues-against-e-faecalis ()
  ;; E. faecalis established by the sorbitol+/arabinose- pair (0.56); a contradictory
  ;; arabinose-fermenter reading argues against it (-0.7). Sorbitol stays positive, so
  ;; the E. faecium rule does not fire and only the rule under test can disconfirm.
  (check-disconfirms (lambda (o p) (declare (ignore p))
                       (af "gram" "pos" o) (af "morphology" "coccus" o)
                       (af "growth-conformation" "chains" o)
                       (af "bile-esculin" "positive" o) (af "salt-tolerance" "tolerant" o)
                       (af "sorbitol" "fermenter" o) (af "arabinose" "non-fermenter" o)
                       (af "arabinose" "fermenter" o))
                     "enterococcus-faecalis" 0.56))

;;; ------------------------------------------------------------------
;;; HOST-FACTOR modifiers over the gram-positive classes (slice D; sketch §5.5).
;;;
;;; These compose through a genus class exactly like the biochemical species rules,
;;; so the same class-belief * rule-belief law applies. What differs is their role:
;;; they add an independent mass to a hypothesis the morphology already raises,
;;; rather than discriminating between siblings. (The one-hop neutropenia ->
;;; Pseudomonas modifier lives in rules.lisp, since Pseudomonas is not an
;;; enterobacteriaceae and so cannot chain from the class its premises derive.)
;;; ------------------------------------------------------------------

(deftest chain-host-factor-iv-drug-use-staph-aureus () ; 0.7*0.55 = 0.385
  ;; No coagulase asserted, so the biochemical S. aureus rule stays silent and this
  ;; clinical prior fires alone -- deliberately usable before the biochemistry is back.
  (check-rule (lambda (o p)
                (af "gram" "pos" o) (af "morphology" "coccus" o)
                (af "growth-conformation" "clumps" o)
                (af "iv-drug-use" "t" p))
              "staphylococcus-aureus" 0.385))

(deftest chain-host-factor-neonate-strep-agalactiae () ; 0.7*0.7 = 0.49
  ;; Beta hemolysis with NO bacitracin reading: neither group A nor group B
  ;; biochemical rule can fire, so the host factor is isolated.
  (check-rule (lambda (o p)
                (af "gram" "pos" o) (af "morphology" "coccus" o)
                (af "growth-conformation" "chains" o)
                (af "hemolysis" "beta" o)
                (af "age-group" "neonate" p))
              "streptococcus-agalactiae" 0.49))

(deftest chain-host-factor-urinary-staph-saprophyticus () ; 0.7*0.65 = 0.455
  ;; Coagulase-negative also raises the S. epidermidis default, but that is a
  ;; DIFFERENT identity; no novobiocin is asserted, so S. saprophyticus is reached
  ;; by this host-factor rule alone.
  (check-rule (lambda (o p)
                (af "gram" "pos" o) (af "morphology" "coccus" o)
                (af "growth-conformation" "clumps" o)
                (af "coagulase" "negative" o)
                (af "infection-site" "urinary" p))
              "staphylococcus-saprophyticus" 0.455))

(deftest chain-host-factor-prosthetic-epidermidis-combines () ; 0.385 combine 0.42 = 0.6433
  ;; NOT an isolation, and cannot be one: this rule's premises are a superset of the
  ;; plain coagulase-negative rule's, so both necessarily fire off the shared class --
  ;; the biochemical default (0.7*0.55 = 0.385) and the device host factor
  ;; (0.7*0.6 = 0.42) -- and their masses combine to 0.6433. Same situation as
  ;; rule-hospital-compromised-klebsiella-combines on the gram-negative side, and a
  ;; direct demonstration that a host factor ADDS evidence rather than replacing it.
  (check-rule (lambda (o p)
                (af "gram" "pos" o) (af "morphology" "coccus" o)
                (af "growth-conformation" "clumps" o)
                (af "coagulase" "negative" o)
                (af "prosthetic-material" "t" p))
              "staphylococcus-epidermidis" 0.6433))
