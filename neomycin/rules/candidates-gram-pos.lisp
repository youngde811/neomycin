;;; -*- Mode: Lisp -*-
;;;
;;; Part of neomycin's canonical rulebase.
;;;
;;; THE FULL GRAM-POSITIVE CLUSTER as narrows-to rules, per
;;; docs/narrows-to-gram-pos-sketch.md. 27 rules in the pre-v0.11 corpus (15 cluster +
;;; 4 host-factor + 8 ruling-out) become 23 here, after four merges.
;;;
;;;   * CONFIRMING RULES ONLY. Nothing is excluded by being named. All 8 ruling-out
;;;     rules became confirming rules that say what their evidence establishes.
;;;   * EVERY RULE HAS A VISIBLE RHS asserting a CANDIDATES fact -- the set its
;;;     evidence narrows the answer to.
;;;   * BELIEF ON THE ASSERTED FACT, via the ordinary :belief keyword.
;;;   * NO ORGANISM-CLASS. A class IS a candidates set: :staphylococcus is
;;;     {aureus, epidermidis, saprophyticus}. Nothing chains, nothing composes, and
;;;     the three carried-over class beliefs simply cease to exist.
;;;   * NO FRAME DECLARED. Nothing enumerates the pathogens.
;;;
;;; Species rules gate on their own EVIDENCE rather than on a class fact -- coagulase
;;; is a staphylococcal test, hemolysis is streptococcal. The two that are not
;;; group-specific (the enterococcal sugars, and the pure-context respiratory rule)
;;; gate on the evidence that would have derived the class.

(in-package :lisa-user)

;;; ==================================================================
;;; 1. Narrowing by stain, morphology and group-level bench tests
;;; ==================================================================

;;; Gram-positive cocci in CLUMPS are the staphylococci. This is the rule whose
;;; belief used to be the carried-over 0.7 on a reified :staphylococcus class; here it
;;; answers a real question -- how reliably does clumping mean one of these three?
(defrule clumps-narrows-to-staphylococci
    (:belief 0.7)
  (organism (id ?o))
  (gram (value pos) (of ?o))
  (morphology (value coccus) (of ?o))
  (growth-conformation (value clumps) (of ?o))
  =>
  (assert (candidates (value '(:staphylococcus-aureus :staphylococcus-epidermidis
                               :staphylococcus-saprophyticus))
                      (of ?o))))

;;; Cocci in CHAINS are the streptococci AND the enterococci -- the finding does not
;;; separate them, and slice D already had to widen the shipped rule to admit it.
(defrule chains-narrows-to-chain-formers
    (:belief 0.7)
  (organism (id ?o))
  (gram (value pos) (of ?o))
  (morphology (value coccus) (of ?o))
  (growth-conformation (value chains) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-pneumoniae :streptococcus-pyogenes
                               :streptococcus-agalactiae :streptococcus-viridans
                               :enterococcus-faecalis :enterococcus-faecium))
                      (of ?o))))

;;; WAS catalase-neg-argues-against-staphylococci. It could only say "not a
;;; staphylococcus"; as a narrows-to rule it says what a catalase-negative
;;; gram-positive coccus actually IS. Same observation, more information.
(defrule catalase-negative-narrows-to-chain-formers
    (:belief 0.7)
  (organism (id ?o))
  (gram (value pos) (of ?o))
  (morphology (value coccus) (of ?o))
  (catalase (value negative) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-pneumoniae :streptococcus-pyogenes
                               :streptococcus-agalactiae :streptococcus-viridans
                               :enterococcus-faecalis :enterococcus-faecium))
                      (of ?o))))

;;; Bile-esculin hydrolysis PLUS growth in 6.5% NaCl is the enterococcal pair; the
;;; salt tolerance is what separates them from the non-enterococcal group D strep.
(defrule bile-esculin-salt-tolerant-narrows-to-enterococci
    (:belief 0.8)
  (organism (id ?o))
  (gram (value pos) (of ?o))
  (morphology (value coccus) (of ?o))
  (growth-conformation (value chains) (of ?o))
  (bile-esculin (value positive) (of ?o))
  (salt-tolerance (value tolerant) (of ?o))
  =>
  (assert (candidates (value '(:enterococcus-faecalis :enterococcus-faecium))
                      (of ?o))))

;;; WAS bile-esculin-neg-argues-against-enterococci. A bile-esculin-negative chain
;;; former is a streptococcus.
(defrule bile-esculin-negative-narrows-to-streptococci
    (:belief 0.6)
  (organism (id ?o))
  (gram (value pos) (of ?o))
  (morphology (value coccus) (of ?o))
  (growth-conformation (value chains) (of ?o))
  (bile-esculin (value negative) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-pneumoniae :streptococcus-pyogenes
                               :streptococcus-agalactiae :streptococcus-viridans))
                      (of ?o))))

;;; A CONTEXT rule at group level: enterococci are a leading cause of bacteraemia in
;;; the compromised host. Narrows to a pair with modest belief -- exactly what a
;;; prior claim should look like.
(defrule blood-compromised-chains-narrows-to-enterococci
    (:belief 0.7)
  (organism (id ?o))
  (culture (id ?c))
  (patient (id ?p))
  (culture-site (value blood) (of ?c))
  (gram (value pos) (of ?o))
  (morphology (value coccus) (of ?o))
  (growth-conformation (value chains) (of ?o))
  (compromised-host (value t) (of ?p))
  =>
  (assert (candidates (value '(:enterococcus-faecalis :enterococcus-faecium))
                      (of ?o))))

;;; ==================================================================
;;; 2. Narrowing by discriminating bench test
;;; ==================================================================

;;; MERGE 1: staph-coagulase-pos-suggests-staph-aureus (0.85) +
;;;          coagulase-pos-argues-against-coagulase-negative-staph (0.85).
;;; Both numbers agreed, so the merge is clean.
(defrule coagulase-positive-narrows-to-aureus
    (:belief 0.85)
  (organism (id ?o))
  (gram (value pos) (of ?o))
  (morphology (value coccus) (of ?o))
  (growth-conformation (value clumps) (of ?o))
  (coagulase (value positive) (of ?o))
  =>
  (assert (candidates (value '(:staphylococcus-aureus)) (of ?o))))

;;; MERGE 2, and the instructive one: staph-coagulase-neg-suggests-staph-epidermidis
;;; was 0.55, coagulase-neg-argues-against-staph-aureus was 0.85. The 0.55 was
;;; discounted in its own note precisely BECAUSE "coagulase-negativity identifies the
;;; GROUP, not this species" -- which is why it was wrong as a species claim and
;;; right as a set claim. Merged at 0.85, which fixes the error rather than averaging
;;; it away. (David's call, 2026-08-17: the higher of each pair survives.)
(defrule coagulase-negative-narrows-to-coagulase-negative-staph
    (:belief 0.85)
  (organism (id ?o))
  (gram (value pos) (of ?o))
  (morphology (value coccus) (of ?o))
  (growth-conformation (value clumps) (of ?o))
  (coagulase (value negative) (of ?o))
  =>
  (assert (candidates (value '(:staphylococcus-epidermidis
                               :staphylococcus-saprophyticus))
                      (of ?o))))

;;; Novobiocin RESISTANCE separates S. saprophyticus from the other coagulase-negative
;;; staphylococci; the 5-ug disc has ~93% positive predictive accuracy.
(defrule novobiocin-resistant-narrows-to-saprophyticus
    (:belief 0.8)
  (organism (id ?o))
  (coagulase (value negative) (of ?o))
  (novobiocin (value resistant) (of ?o))
  =>
  (assert (candidates (value '(:staphylococcus-saprophyticus)) (of ?o))))

;;; WAS beta-hemolysis-argues-against-non-beta-streptococci. Beta hemolysis means one
;;; of the beta-hemolytic streptococci; pneumococcus and viridans are excluded by
;;; arithmetic, not by being named.
(defrule beta-hemolysis-narrows-to-beta-hemolytic-strep
    (:belief 0.75)
  (organism (id ?o))
  (hemolysis (value beta) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-pyogenes :streptococcus-agalactiae))
                      (of ?o))))

;;; WAS alpha-hemolysis-argues-against-beta-hemolytic-streptococci, and it gains
;;; information: the shipped corpus had no confirming rule at this granularity.
(defrule alpha-hemolysis-narrows-to-alpha-hemolytic-strep
    (:belief 0.75)
  (organism (id ?o))
  (hemolysis (value alpha) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-pneumoniae :streptococcus-viridans))
                      (of ?o))))

;;; Bacitracin separates group A from group B among the beta-hemolytics.
(defrule bacitracin-sensitive-narrows-to-pyogenes
    (:belief 0.85)
  (organism (id ?o))
  (hemolysis (value beta) (of ?o))
  (bacitracin (value sensitive) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-pyogenes)) (of ?o))))

(defrule bacitracin-resistant-narrows-to-agalactiae
    (:belief 0.7)
  (organism (id ?o))
  (hemolysis (value beta) (of ?o))
  (bacitracin (value resistant) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-agalactiae)) (of ?o))))

;;; MERGE 3: strep-alpha-hemolytic-optochin-sensitive-suggests-strep-pneumoniae (0.85)
;;; + optochin-sensitive-argues-against-viridans (0.70). Merged at 0.85.
(defrule optochin-sensitive-narrows-to-pneumoniae
    (:belief 0.85)
  (organism (id ?o))
  (hemolysis (value alpha) (of ?o))
  (optochin (value sensitive) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-pneumoniae)) (of ?o))))

;;; Viridans is defined largely by exclusion from S. pneumoniae, hence the weaker 0.65.
(defrule optochin-resistant-narrows-to-viridans
    (:belief 0.65)
  (organism (id ?o))
  (hemolysis (value alpha) (of ?o))
  (optochin (value resistant) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-viridans)) (of ?o))))

;;; The enterococcal sugars. Sorbitol and arabinose are used across many genera, so
;;; unlike coagulase or hemolysis these are NOT group-specific -- they gate on the
;;; enterococcal discriminators that would have derived the class.
(defrule sorbitol-pos-arabinose-neg-narrows-to-faecalis
    (:belief 0.7)
  (organism (id ?o))
  (bile-esculin (value positive) (of ?o))
  (salt-tolerance (value tolerant) (of ?o))
  (sorbitol (value fermenter) (of ?o))
  (arabinose (value non-fermenter) (of ?o))
  =>
  (assert (candidates (value '(:enterococcus-faecalis)) (of ?o))))

;;; MERGE 4: enterococcus-arabinose-pos-sorbitol-neg-suggests-e-faecium (0.7) +
;;; arabinose-pos-argues-against-e-faecalis (0.7). Both agreed at 0.7.
(defrule arabinose-pos-sorbitol-neg-narrows-to-faecium
    (:belief 0.7)
  (organism (id ?o))
  (bile-esculin (value positive) (of ?o))
  (salt-tolerance (value tolerant) (of ?o))
  (arabinose (value fermenter) (of ?o))
  (sorbitol (value non-fermenter) (of ?o))
  =>
  (assert (candidates (value '(:enterococcus-faecium)) (of ?o))))

;;; ==================================================================
;;; 3. Narrowing by patient and culture context
;;; ==================================================================
;;; These narrow to a small set with modest belief -- m({aureus}) = 0.55 and
;;; m(Theta) = 0.45 is exactly what "IV drug use makes S. aureus likely" means. They
;;; do not resist the shape; what they produce is honest conflict against a bench
;;; finding pointing elsewhere.

(defrule hospital-acquired-clumps-narrows-to-aureus
    (:belief 0.8)
  (organism (id ?o))
  (patient (id ?p))
  (gram (value pos) (of ?o))
  (morphology (value coccus) (of ?o))
  (growth-conformation (value clumps) (of ?o))
  (hospital-acquired (value t) (of ?p))
  =>
  (assert (candidates (value '(:staphylococcus-aureus)) (of ?o))))

(defrule iv-drug-use-clumps-narrows-to-aureus
    (:belief 0.55)
  (organism (id ?o))
  (patient (id ?p))
  (gram (value pos) (of ?o))
  (morphology (value coccus) (of ?o))
  (growth-conformation (value clumps) (of ?o))
  (iv-drug-use (value t) (of ?p))
  =>
  (assert (candidates (value '(:staphylococcus-aureus)) (of ?o))))

;;; Pure context -- no bench finding of its own, so it gates on the stain that would
;;; have derived the streptococcus class.
(defrule respiratory-chains-narrows-to-pneumoniae
    (:belief 0.75)
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (infection-site (value respiratory) (of ?p))
  (gram (value pos) (of ?o))
  (morphology (value coccus) (of ?o))
  (growth-conformation (value chains) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-pneumoniae)) (of ?o))))

(defrule neonate-beta-hemolytic-narrows-to-agalactiae
    (:belief 0.7)
  (organism (id ?o))
  (patient (id ?p))
  (age-group (value neonate) (of ?p))
  (hemolysis (value beta) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-agalactiae)) (of ?o))))

(defrule prosthetic-material-coag-neg-narrows-to-epidermidis
    (:belief 0.6)
  (organism (id ?o))
  (patient (id ?p))
  (coagulase (value negative) (of ?o))
  (prosthetic-material (value t) (of ?p))
  =>
  (assert (candidates (value '(:staphylococcus-epidermidis)) (of ?o))))

(defrule urinary-coag-neg-narrows-to-saprophyticus
    (:belief 0.65)
  (organism (id ?o))
  (patient (id ?p))
  (coagulase (value negative) (of ?o))
  (infection-site (value urinary) (of ?p))
  =>
  (assert (candidates (value '(:staphylococcus-saprophyticus)) (of ?o))))