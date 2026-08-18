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
    (:belief 0.7
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.12 (Staphylococcus), NBK8448"
                             "NCBI Bookshelf / StatPearls, Gram-Positive Bacteria, NBK470553")
                  :belief-basis :illustrative
                  :note "Staphylococci are gram-positive cocci dividing in irregular clusters. Narrows to the three the corpus models; the finding does not separate them, and this rule does not pretend it does. Replaces the reified :staphylococcus organism-class, whose 0.7 was carried over from a retired rule and answered no conditional -- as a narrows-to belief it answers one: how reliably does clumping mean one of these three?"))
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
    (:belief 0.7
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.13 (Streptococcus, Patterson), NBK7611"
                             "NCBI Bookshelf / StatPearls, Gram-Positive Bacteria, NBK470553")
                  :belief-basis :illustrative
                  :note "Gram-positive cocci in chains are the streptococci AND the enterococci -- morphology does not separate them. The pre-v0.11 rule named only the four streptococci and needed a separate ruling-out rule for the enterococci; naming the set both licenses removes it."))
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
    (:belief 0.7
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf / StatPearls, Gram-Positive Bacteria, NBK470553"
                             "NCBI Bookshelf, Medical Microbiology 4th ed. ch.12 (Staphylococcus), NBK8448")
                  :belief-basis :illustrative
                  :note "Staphylococci are catalase-positive; streptococci and enterococci are catalase-negative. Stated as what a catalase-negative gram-positive coccus IS rather than what it is not, which is strictly more information than the ruling-out rule it replaces."))
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
    (:belief 0.8
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("J Clin Microbiol, Presumptive Identification of Group D Streptococci: the Bile-Esculin Test, PMC376909"
                             "J Clin Microbiol, Comparison of Several Laboratory Media for Presumptive Identification of Enterococci and Group D Streptococci, PMC379740"
                             "NCBI Bookshelf, Enterococci: From Commensals to Leading Causes of Drug Resistant Infection (Diversity, Origins in Nature, and Gut Colonization), NBK190427")
                  :belief-basis :illustrative
                  :note "Enterococci hydrolyze esculin in 40% bile AND grow in 6.5% NaCl; the salt tolerance is what distinguishes them from the non-enterococcal group D streptococci, which are also bile-esculin positive."))
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
    (:belief 0.6
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("J Clin Microbiol, Presumptive Identification of Group D Streptococci: the Bile-Esculin Test, PMC376909"
                             "J Clin Microbiol, Comparison of Several Laboratory Media for Presumptive Identification of Enterococci and Group D Streptococci, PMC379740")
                  :belief-basis :illustrative
                  :note "A bile-esculin-negative chain-former is a streptococcus. The pre-v0.11 rule held itself to -0.6 because the test is shared with the non-enterococcal group D streptococci, making it a stronger ruling-IN than ruling-out marker -- which as a narrows-to claim is exactly the right reading, and the belief is unchanged."))
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
    (:belief 0.7
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf / StatPearls, Vancomycin-Resistant Enterococci, NBK513233"
                             "Frontiers in Microbiology 2016 (Gilmore et al.), Global Emergence of Enterococci as Nosocomial Pathogens, PMC4880559")
                  :belief-basis :illustrative
                  :note "Enterococci are a leading cause of bacteraemia in the compromised host. A PRIOR rather than a deduction: it narrows to a pair with modest belief, which is what an epidemiological claim should look like."))
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
    (:belief 0.85
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.12 (Staphylococcus), NBK8448"
                             "NCBI Bookshelf / StatPearls, Staphylococcus aureus Infection, NBK441868"
                             "NCBI Bookshelf / StatPearls, Staphylococcus epidermidis Infection, NBK563240"
                             "NCBI Bookshelf / StatPearls, Staphylococcus saprophyticus Infection, NBK482367")
                  :belief-basis :illustrative
                  :note "Coagulase production separates S. aureus from the coagulase-negative staphylococci. MERGED from a confirming/excluding pair that already agreed at 0.85, so the merge changes nothing but the count."))
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
    (:belief 0.85
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf / StatPearls, Staphylococcus epidermidis Infection, NBK563240"
                             "NCBI Bookshelf / StatPearls, Gram-Positive Bacteria, NBK470553"
                             "NCBI Bookshelf, Medical Microbiology 4th ed. ch.12 (Staphylococcus), NBK8448"
                             "NCBI Bookshelf / StatPearls, Staphylococcus aureus Infection, NBK441868")
                  :belief-basis :illustrative
                  :note "Coagulase-negativity identifies the GROUP, not a species. MERGED from a pair that disagreed: the confirming rule was discounted to 0.55 precisely BECAUSE it identified the group rather than S. epidermidis, while the excluding rule used 0.85. Naming the group makes 0.85 the right number and the discount unnecessary -- the merge fixes an error rather than averaging it."))
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
    (:belief 0.8
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf / StatPearls, Staphylococcus saprophyticus Infection, NBK482367"
                             "J Clin Microbiol, Use of Mueller-Hinton agar to determine novobiocin susceptibility of coagulase-negative staphylococci, PMC272557")
                  :belief-basis :illustrative
                  :note "S. saprophyticus is differentiated from the other coagulase-negative staphylococci by RESISTANCE to novobiocin; the 5-ug disc has a reported 93% positive predictive accuracy, which is what 0.8 reflects."))
  (organism (id ?o))
  (coagulase (value negative) (of ?o))
  (novobiocin (value resistant) (of ?o))
  =>
  (assert (candidates (value '(:staphylococcus-saprophyticus)) (of ?o))))

;;; WAS beta-hemolysis-argues-against-non-beta-streptococci. Beta hemolysis means one
;;; of the beta-hemolytic streptococci; pneumococcus and viridans are excluded by
;;; arithmetic, not by being named.
(defrule beta-hemolysis-narrows-to-beta-hemolytic-strep
    (:belief 0.75
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.13 (Streptococcus, Patterson), NBK7611"
                             "NCBI Bookshelf / StatPearls, Streptococcus pneumoniae, NBK470537")
                  :belief-basis :illustrative
                  :note "Beta (complete) hemolysis is characteristic of groups A and B; S. pneumoniae and the viridans group are alpha-hemolytic. Stated as what beta hemolysis establishes rather than what it denies -- pneumococcus and viridans are excluded by intersection, not by being named."))
  (organism (id ?o))
  (hemolysis (value beta) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-pyogenes :streptococcus-agalactiae))
                      (of ?o))))

;;; WAS alpha-hemolysis-argues-against-beta-hemolytic-streptococci, and it gains
;;; information: the shipped corpus had no confirming rule at this granularity.
(defrule alpha-hemolysis-narrows-to-alpha-hemolytic-strep
    (:belief 0.75
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.13 (Streptococcus, Patterson), NBK7611"
                             "NCBI Bookshelf / StatPearls, Group B Streptococcus and Pregnancy, NBK482443")
                  :belief-basis :illustrative
                  :note "Alpha (partial, green) hemolysis is characteristic of S. pneumoniae and the viridans group. The pre-v0.11 corpus had no confirming rule at this granularity at all, so stating it gains information rather than merely relocating it."))
  (organism (id ?o))
  (hemolysis (value alpha) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-pneumoniae :streptococcus-viridans))
                      (of ?o))))

;;; Bacitracin separates group A from group B among the beta-hemolytics.
(defrule bacitracin-sensitive-narrows-to-pyogenes
    (:belief 0.85
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.13 (Streptococcus, Patterson), NBK7611"
                             "NCBI Bookshelf, Streptococcus pyogenes: Basic Biology to Clinical Manifestations (Laboratory Diagnosis of group A streptococci), NBK587110")
                  :belief-basis :illustrative
                  :note "Bacitracin susceptibility is the classic presumptive test separating group A (S. pyogenes) from group B among the beta-hemolytic streptococci."))
  (organism (id ?o))
  (hemolysis (value beta) (of ?o))
  (bacitracin (value sensitive) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-pyogenes)) (of ?o))))

(defrule bacitracin-resistant-narrows-to-agalactiae
    (:belief 0.7
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.13 (Streptococcus, Patterson), NBK7611"
                             "NCBI Bookshelf / StatPearls, Group B Streptococcus and Pregnancy, NBK482443")
                  :belief-basis :illustrative
                  :note "Group B (S. agalactiae) is characteristically bacitracin-resistant. 0.7 rather than higher because groups C and G are also bacitracin-resistant."))
  (organism (id ?o))
  (hemolysis (value beta) (of ?o))
  (bacitracin (value resistant) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-agalactiae)) (of ?o))))

;;; MERGE 3: strep-alpha-hemolytic-optochin-sensitive-suggests-strep-pneumoniae (0.85)
;;; + optochin-sensitive-argues-against-viridans (0.70). Merged at 0.85.
(defrule optochin-sensitive-narrows-to-pneumoniae
    (:belief 0.85
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.13 (Streptococcus, Patterson), NBK7611"
                             "NCBI Bookshelf / StatPearls, Streptococcus pneumoniae, NBK470537")
                  :belief-basis :illustrative
                  :note "Optochin susceptibility is the standard presumptive test separating S. pneumoniae from the other alpha-hemolytic streptococci. MERGED from a pair that disagreed (0.85 confirming, 0.70 excluding); the higher survives, since naming what the test establishes needs no discount."))
  (organism (id ?o))
  (hemolysis (value alpha) (of ?o))
  (optochin (value sensitive) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-pneumoniae)) (of ?o))))

;;; Viridans is defined largely by exclusion from S. pneumoniae, hence the weaker 0.65.
(defrule optochin-resistant-narrows-to-viridans
    (:belief 0.65
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.13 (Streptococcus, Patterson), NBK7611")
                  :belief-basis :illustrative
                  :note "The viridans group is defined largely by exclusion from S. pneumoniae among the alpha-hemolytic streptococci, hence the weaker 0.65."))
  (organism (id ?o))
  (hemolysis (value alpha) (of ?o))
  (optochin (value resistant) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-viridans)) (of ?o))))

;;; The enterococcal sugars. Sorbitol and arabinose are used across many genera, so
;;; unlike coagulase or hemolysis these are NOT group-specific -- they gate on the
;;; enterococcal discriminators that would have derived the class.
(defrule sorbitol-pos-arabinose-neg-narrows-to-faecalis
    (:belief 0.7
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("Carriage of multidrug resistant Enterococcus faecium and Enterococcus faecalis among apparently healthy humans, PMC5476817"
                             "NCBI Bookshelf, Enterococci: From Commensals to Leading Causes of Drug Resistant Infection, NBK190427")
                  :belief-basis :illustrative
                  :note "E. faecalis characteristically ferments sorbitol and not arabinose; E. faecium is the reciprocal. Gated on the enterococcal discriminators rather than on a class fact, because sugar fermentations are used across many genera and are not group-specific on their own."))
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
    (:belief 0.7
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("Carriage of multidrug resistant Enterococcus faecium and Enterococcus faecalis among apparently healthy humans, PMC5476817"
                             "NCBI Bookshelf, Enterococci: From Commensals to Leading Causes of Drug Resistant Infection, NBK190427")
                  :belief-basis :illustrative
                  :note "E. faecium characteristically ferments arabinose and not sorbitol. MERGED from a confirming/excluding pair that already agreed at 0.7."))
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
    (:belief 0.8
     :provenance (:origin :paip-subset
                  :evidence ("CDC Emerging Infectious Diseases 2007 (Klein et al.), MRSA hospitalizations & deaths, US 1999-2005 -- wwwnc.cdc.gov/eid/article/13/12/07-0629_article"
                             "NCBI Bookshelf / StatPearls, Staphylococcus aureus Infection, NBK441868")
                  :belief-basis :illustrative
                  :note "S. aureus is a leading nosocomial pathogen, notably in bacteraemia and surgical-site infection."))
  (organism (id ?o))
  (patient (id ?p))
  (gram (value pos) (of ?o))
  (morphology (value coccus) (of ?o))
  (growth-conformation (value clumps) (of ?o))
  (hospital-acquired (value t) (of ?p))
  =>
  (assert (candidates (value '(:staphylococcus-aureus)) (of ?o))))

(defrule iv-drug-use-clumps-narrows-to-aureus
    (:belief 0.55
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("Microbial Epidemiology of Infectious Endocarditis in the Intravenous Drug Abuse Population, PMC6374230"
                             "NCBI Bookshelf / StatPearls, Tricuspid Valve Endocarditis, NBK538423")
                  :belief-basis :illustrative
                  :note "S. aureus causes 60-70% of infective endocarditis in people who inject drugs, against under a third in non-users."))
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
    (:belief 0.75
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf / StatPearls, Streptococcus pneumoniae, NBK470537"
                             "NCBI Bookshelf / StatPearls, Community-Acquired Pneumonia, NBK430749")
                  :belief-basis :illustrative
                  :note "S. pneumoniae is the commonest bacterial cause of community-acquired pneumonia. Pure context, so it gates on the stain and morphology that would have derived the streptococcus class."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (infection-site (value respiratory) (of ?p))
  (gram (value pos) (of ?o))
  (morphology (value coccus) (of ?o))
  (growth-conformation (value chains) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-pneumoniae)) (of ?o))))

(defrule neonate-beta-hemolytic-narrows-to-agalactiae
    (:belief 0.7
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("CDC MMWR RR-59-10, Prevention of Perinatal Group B Streptococcal Disease"
                             "NCBI Bookshelf / StatPearls, Group B Streptococcus and Pregnancy, NBK482443"
                             "CDC Active Bacterial Core surveillance, Early-Onset Neonatal Sepsis Surveillance and Trends")
                  :belief-basis :illustrative
                  :note "S. agalactiae (group B) is the leading cause of early-onset neonatal sepsis and meningitis."))
  (organism (id ?o))
  (patient (id ?p))
  (age-group (value neonate) (of ?p))
  (hemolysis (value beta) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-agalactiae)) (of ?o))))

(defrule prosthetic-material-coag-neg-narrows-to-epidermidis
    (:belief 0.6
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf / StatPearls, Staphylococcus epidermidis Infection, NBK563240")
                  :belief-basis :illustrative
                  :note "S. epidermidis is the classic biofilm-forming pathogen of prosthetic joints, valves and indwelling devices."))
  (organism (id ?o))
  (patient (id ?p))
  (coagulase (value negative) (of ?o))
  (prosthetic-material (value t) (of ?p))
  =>
  (assert (candidates (value '(:staphylococcus-epidermidis)) (of ?o))))

(defrule urinary-coag-neg-narrows-to-saprophyticus
    (:belief 0.65
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf / StatPearls, Staphylococcus saprophyticus Infection, NBK482367")
                  :belief-basis :illustrative
                  :note "S. saprophyticus is a leading cause of uncomplicated cystitis in young women, second only to E. coli."))
  (organism (id ?o))
  (patient (id ?p))
  (coagulase (value negative) (of ?o))
  (infection-site (value urinary) (of ?p))
  =>
  (assert (candidates (value '(:staphylococcus-saprophyticus)) (of ?o))))