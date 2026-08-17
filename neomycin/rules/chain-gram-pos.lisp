;; This file is part of Lisa, the Lisp-based Intelligent Software Agents platform.

;; MIT License

;; Copyright (c) 2000 David Young

;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to deal
;; in the Software without restriction, including without limitation the rights
;; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;; copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:

;; The above copyright notice and this permission notice shall be included in all
;; copies or substantial portions of the Software.

;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.

;; Description: The gram-POSITIVE coccus clusters -- three more chained genus classes
;; built on the enterobacteriaceae template (docs/gram-positive-cluster-design.md).
;; Staphylococcus, Streptococcus and Enterococcus were each a leaf organism-identity
;; before this increment despite being genera; they are now organism-CLASSes refined
;; to leaf species by coagulase / hemolysis / disc tests / sugars.
;;
;; Cross-disconfirmation among these siblings lives in disconfirming.lisp; the
;; patient-level rules that shift belief on them live in host-factors.lisp.

(in-package :lisa-user)

;; NOTE: the one-hop `gram-pos-cocci-in-clumps-suggests-staphylococcus` leaf identity
;; rule was RETIRED in slice A of the gram-positive cluster. Staphylococcus is a
;; GENUS, not a species -- exactly the defect C2 fixed for enterobacteriaceae. It is
;; now concluded as an ORGANISM-CLASS (see the tier-1 class rules below), never as an
;; ORGANISM-IDENTITY; the identity layer names only leaf SPECIES (S. aureus,
;; S. epidermidis, S. saprophyticus). Keeping the leaf alongside the chain would have
;; double-counted the same clumps evidence (a leaf identity AND a class, then again
;; through the species).

;; NOTE: the one-hop `gram-pos-cocci-in-chains-suggests-streptococcus` leaf identity
;; rule was RETIRED in slice A, for the same reason as the staphylococcus leaf above:
;; Streptococcus is a GENUS. It is now an ORGANISM-CLASS, refined to leaf SPECIES
;; (S. pyogenes, S. agalactiae, S. pneumoniae, viridans) by hemolysis + optochin /
;; bacitracin.

;;; ------------------------------------------------------------------
;;; Tier 1 for the GRAM-POSITIVE COCCI (docs/gram-positive-cluster-design.md §3.1).
;;;
;;; Three more belief-valued intermediates, built on the enterobacteriaceae template.
;;; The staphylococcus and streptococcus rules take the premises AND the 0.7 belief of
;;; the leaf rules they replace, exactly as the enterobacteriaceae class rule carried
;;; 0.8 over from its retired leaf -- so the class conclusion is not a new claim, just
;;; the old one aimed at the right level of the taxonomy.
;;;
;;; CATALASE is deliberately NOT a premise here even though it is the textbook
;;; staph-vs-strep discriminator: making it mandatory would silently stop every
;;; existing scenario (none of which assert it) from reaching a gram-positive
;;; conclusion at all. It earns its keep as a DISCONFIRMING rule instead, which is
;;; where it does real DS work.
;;; ------------------------------------------------------------------
(defrule gram-pos-cocci-in-clumps-suggests-staphylococcus-class
    (:belief 0.7
     ;; SLICE D / D6. The three staphylococci are what the corpus models; gram +
     ;; morphology + clumping is coarse enough that an unmodelled cluster-forming
     ;; gram-positive coccus is a live possibility, so :other-organism is included.
     :supports (:staphylococcus :other-organism)
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.12 (Staphylococcus), NBK8448"
                             "NCBI Bookshelf / StatPearls, Gram-Positive Bacteria, NBK470553")
                  :belief-basis :illustrative
                  :note "Gram-positive cocci in grape-like clusters (clumps) are morphologically characteristic of the genus Staphylococcus, which is catalase-positive and subdivides into coagulase-positive (S. aureus) and coagulase-negative (S. epidermidis, S. saprophyticus) species. The genus/species chaining structure follows MYCIN (Buchanan & Shortliffe 1984); this rule is a neomycin reconstruction. 0.7 carried over from the retired one-hop staphylococcus leaf."))
  (organism (id ?o))
  (gram (value pos) (of ?o))
  (morphology (value coccus) (of ?o))
  (growth-conformation (value clumps) (of ?o))
  =>
  (assert (organism-class (value :staphylococcus) (of ?o))))

(defrule gram-pos-cocci-in-chains-suggests-streptococcus-class
    (:belief 0.7
     ;; SLICE D, and structurally the same defect as the enterobacteriaceae class
     ;; rule: ENTEROCOCCI are also gram-positive cocci in chains, so gram + morphology
     ;; + conformation cannot separate them from the streptococci. Claiming only the
     ;; four streptococci put this rule in conflict with the enterococcus rule reading
     ;; the same three findings; widening it drops culture-3's conflict from 0.647 to
     ;; 0.525 because the two rules now agree instead of fighting.
     :supports (:gram-pos-cocci-in-chains :other-organism)
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.13 (Streptococcus, Patterson), NBK7611"
                             "NCBI Bookshelf / StatPearls, Gram-Positive Bacteria, NBK470553")
                  :belief-basis :illustrative
                  :note "Gram-positive cocci in chains are morphologically characteristic of the genus Streptococcus, which is catalase-negative and subdivides by hemolysis (beta/alpha/gamma) and disc tests. The genus/species chaining structure follows MYCIN (Buchanan & Shortliffe 1984); this rule is a neomycin reconstruction. 0.7 carried over from the retired one-hop streptococcus leaf."))
  (organism (id ?o))
  (gram (value pos) (of ?o))
  (morphology (value coccus) (of ?o))
  (growth-conformation (value chains) (of ?o))
  =>
  (assert (organism-class (value :streptococcus) (of ?o))))

;; Enterococcus gets its OWN tier-1 class rather than sitting under streptococcus.
;; Bile-esculin positivity alone does not separate enterococci from the
;; non-enterococcal group D streptococci -- growth in 6.5% NaCl is what does -- so
;; the rule requires BOTH. 0.8: the pair is highly characteristic.
(defrule bile-esculin-pos-salt-tolerant-chains-suggests-enterococcus-class
    (:belief 0.8
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("J Clin Microbiol, Presumptive Identification of Group D Streptococci: the Bile-Esculin Test, PMC376909"
                             "J Clin Microbiol, Comparison of Several Laboratory Media for Presumptive Identification of Enterococci and Group D Streptococci, PMC379740"
                             "NCBI Bookshelf, Enterococci: From Commensals to Leading Causes of Drug Resistant Infection (Diversity, Origins in Nature, and Gut Colonization), NBK190427")
                  :belief-basis :illustrative
                  :note "Enterococci hydrolyze esculin in the presence of 40% bile AND grow in 6.5% NaCl; the salt tolerance is what distinguishes them from the non-enterococcal group D streptococci, which are also bile-esculin positive. Enterococcus was classified as Group D Streptococcus in the MYCIN era and split into its own genus in 1984; modeled here as a genus peer of Staphylococcus and Streptococcus."))
  (organism (id ?o))
  (gram (value pos) (of ?o))
  (morphology (value coccus) (of ?o))
  (growth-conformation (value chains) (of ?o))
  (bile-esculin (value positive) (of ?o))
  (salt-tolerance (value tolerant) (of ?o))
  =>
  (assert (organism-class (value :enterococcus) (of ?o))))

;; RE-POINTED in slice A: this rule used to conclude an :enterococcus leaf IDENTITY.
;; Enterococcus is a GENUS, so it now concludes the ORGANISM-CLASS instead, giving the
;; enterococcus class a second, CLINICAL evidence path alongside the biochemical one
;; below -- the same two-paths-to-one-conclusion shape klebsiella and salmonella
;; already have. Keeping this path matters because it reaches the class in scenarios
;; that never run a bile-esculin or salt-tolerance test.
(defrule gram-pos-cocci-in-chains-in-blood-compromised-suggests-enterococcus
    (:belief 0.7
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf / StatPearls, Vancomycin-Resistant Enterococci, NBK513233"
                             "Frontiers in Microbiology 2016 (Gilmore et al.), Global Emergence of Enterococci as Nosocomial Pathogens, PMC4880559")
                  :belief-basis :illustrative
                  :note "Gram-positive cocci in chains/pairs from blood in hospitalized/compromised patients suggest Enterococcus."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (culture-site (value blood) (of ?c))
  (gram (value pos) (of ?o))
  (morphology (value coccus) (of ?o))
  (growth-conformation (value chains) (of ?o))
  (compromised-host (value t) (of ?p))
  =>
  (assert (organism-class (value :enterococcus) (of ?o))))

;;; ------------------------------------------------------------------
;;; Tier 2 for the GRAM-POSITIVE COCCI: genus class -> competing SPECIES
;;; (docs/gram-positive-cluster-design.md §3.2).
;;;
;;; Same shape as the enterobacteriaceae species tier: each rule reads the derived
;;; organism-class as a premise, so species belief = class belief * this rule's
;;; belief. The discriminators (coagulase, hemolysis, optochin, bacitracin,
;;; novobiocin, arabinose, sorbitol) carry nil belief and only gate firing.
;;;
;;; Unlike the enterobacteriaceae biochemicals, these discriminators partition
;;; cleanly -- hemolysis three ways, coagulase two -- which is what lets the slice-C
;;; cross-disconfirming rules carry stronger negative beliefs and drive plausibility
;;; further below 1.0 on the losing sibling.
;;; ------------------------------------------------------------------
;; S. aureus: the coagulase-positive staphylococcus. 0.85 -- coagulase is the
;; defining genus-internal split, though not quite absolute in practice.
;; Composes to 0.7*0.85 = 0.595.
(defrule staph-coagulase-pos-suggests-staph-aureus
    (:belief 0.85
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.12 (Staphylococcus), NBK8448"
                             "NCBI Bookshelf / StatPearls, Staphylococcus aureus Infection, NBK441868")
                  :belief-basis :illustrative
                  :note "Staphylococcus aureus is the coagulase-POSITIVE staphylococcus; a Gram stain plus catalase and coagulase allows it to be identified quickly and separates it from the coagulase-negative species."))
  (organism (id ?o))
  (organism-class (value :staphylococcus) (of ?o))
  (coagulase (value positive) (of ?o))
  =>
  (assert (organism-identity (value :staphylococcus-aureus) (of ?o))))

;; S. epidermidis: the DEFAULT coagulase-negative staphylococcus. 0.55 is
;; deliberately the weakest belief in the corpus -- CoNS is a group, and this rule
;; names its commonest member rather than making a positive identification. The
;; near-tie against S. saprophyticus below is the point. Composes to 0.7*0.55 = 0.385.
;; (Modeling CoNS as a group identity instead is the honest alternative; deferred,
;; see design §8.1 -- the significance/contaminant increment will want it.)
(defrule staph-coagulase-neg-suggests-staph-epidermidis
    (:belief 0.55
     ;; SLICE D. The rule's own :note already said this -- "coagulase-negativity
     ;; identifies the GROUP, not this species" -- and the set it described in prose
     ;; is now the set it declares. Coagulase-negativity separates S. epidermidis and
     ;; S. saprophyticus from S. aureus; it does not separate them from each other.
     ;; NO :other-organism (D6): the premises are specific enough -- already inside the
     ;; staphylococcus class -- that the modelled species are a near-complete
     ;; enumeration, and this is a species-level rather than a stain-level rule.
     :supports (:staphylococcus-epidermidis :staphylococcus-saprophyticus)
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf / StatPearls, Staphylococcus epidermidis Infection, NBK563240"
                             "NCBI Bookshelf / StatPearls, Gram-Positive Bacteria, NBK470553")
                  :belief-basis :illustrative
                  :note "S. epidermidis is a coagulase-negative, catalase-positive gram-positive coccus in clusters, and the commonest coagulase-negative staphylococcus in clinical specimens. Weak (0.55) because coagulase-negativity identifies the GROUP, not this species."))
  (organism (id ?o))
  (organism-class (value :staphylococcus) (of ?o))
  (coagulase (value negative) (of ?o))
  =>
  (assert (organism-identity (value :staphylococcus-epidermidis) (of ?o))))

;; S. saprophyticus: coagulase-negative AND novobiocin-RESISTANT -- the standard
;; discriminator within CoNS. 0.8, calibrated to the reported 93% positive
;; predictive accuracy of the novobiocin disc. Composes to 0.7*0.8 = 0.56.
(defrule staph-coagulase-neg-novobiocin-resistant-suggests-staph-saprophyticus
    (:belief 0.8
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf / StatPearls, Staphylococcus saprophyticus Infection, NBK482367"
                             "J Clin Microbiol, Use of Mueller-Hinton agar to determine novobiocin susceptibility of coagulase-negative staphylococci, PMC272557")
                  :belief-basis :illustrative
                  :note "S. saprophyticus is differentiated from the other coagulase-negative staphylococci by RESISTANCE to novobiocin; the 5-ug disc has a reported 93% positive predictive accuracy as a presumptive test, which is what 0.8 reflects."))
  (organism (id ?o))
  (organism-class (value :staphylococcus) (of ?o))
  (coagulase (value negative) (of ?o))
  (novobiocin (value resistant) (of ?o))
  =>
  (assert (organism-identity (value :staphylococcus-saprophyticus) (of ?o))))

;; Tier-2 (chained, re-parented in slice B): the raw gram-pos/coccus/clumps premises
;; are replaced by organism-class :staphylococcus, which already encodes them, so
;; belief composes 0.7*0.8 = 0.56 through the intermediate. A CLINICAL second path to
;; S. aureus alongside the biochemical coagulase rule -- the same two-paths-to-one-
;; species shape klebsiella and salmonella already have.
(defrule hospital-acquired-gram-pos-cocci-in-clumps-suggests-staph-aureus
    (:belief 0.8
     :provenance (:origin :paip-subset
                  :evidence ("CDC Emerging Infectious Diseases 2007 (Klein et al.), MRSA hospitalizations & deaths, US 1999-2005 -- wwwnc.cdc.gov/eid/article/13/12/07-0629_article"
                             "NCBI Bookshelf / StatPearls, Staphylococcus aureus Infection, NBK441868")
                  :belief-basis :illustrative
                  :note "Staphylococcus aureus is a leading cause of hospital-acquired infection, including nosocomial bacteremia."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (organism-class (value :staphylococcus) (of ?o))
  (hospital-acquired (value t) (of ?p))
  =>
  (assert (organism-identity (value :staphylococcus-aureus) (of ?o))))

;; S. pyogenes (Group A): beta-hemolytic AND bacitracin-SENSITIVE. 0.85 rather than
;; higher because the marker is presumptive, not definitive: up to 10% of S. pyogenes
;; are bacitracin-resistant and 3-5% of group C/G are susceptible.
;; Composes to 0.7*0.85 = 0.595.
(defrule strep-beta-hemolytic-bacitracin-sensitive-suggests-strep-pyogenes
    (:belief 0.85
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.13 (Streptococcus, Patterson), NBK7611"
                             "NCBI Bookshelf, Streptococcus pyogenes: Basic Biology to Clinical Manifestations (Laboratory Diagnosis of group A streptococci), NBK587110")
                  :belief-basis :illustrative
                  :note "Bacitracin susceptibility is the widely used screening method for presumptive identification of beta-hemolytic group A Streptococcus (S. pyogenes), differentiating it from groups B, C and G. Presumptive only: up to 10% of S. pyogenes are bacitracin-resistant and 3-5% of group C/G are susceptible -- hence 0.85."))
  (organism (id ?o))
  (organism-class (value :streptococcus) (of ?o))
  (hemolysis (value beta) (of ?o))
  (bacitracin (value sensitive) (of ?o))
  =>
  (assert (organism-identity (value :streptococcus-pyogenes) (of ?o))))

;; S. agalactiae (Group B): beta-hemolytic AND bacitracin-RESISTANT. 0.7 -- weaker
;; than its group A sibling because bacitracin resistance is shared with groups C
;; and G, so it narrows rather than names. Composes to 0.7*0.7 = 0.49.
(defrule strep-beta-hemolytic-bacitracin-resistant-suggests-strep-agalactiae
    (:belief 0.7
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.13 (Streptococcus, Patterson), NBK7611"
                             "NCBI Bookshelf / StatPearls, Group B Streptococcus and Pregnancy, NBK482443")
                  :belief-basis :illustrative
                  :note "Bacitracin RESISTANCE in a beta-hemolytic streptococcus argues for a non-group-A group, of which group B (S. agalactiae) is the principal clinical one. Only 0.7 because groups C and G are also bacitracin-resistant, so this narrows the field rather than naming the species."))
  (organism (id ?o))
  (organism-class (value :streptococcus) (of ?o))
  (hemolysis (value beta) (of ?o))
  (bacitracin (value resistant) (of ?o))
  =>
  (assert (organism-identity (value :streptococcus-agalactiae) (of ?o))))

;; S. pneumoniae: alpha-hemolytic AND optochin-SENSITIVE -- the classic separation
;; from the rest of the viridans-type alpha-hemolytic streptococci. 0.85.
;; Composes to 0.7*0.85 = 0.595.
(defrule strep-alpha-hemolytic-optochin-sensitive-suggests-strep-pneumoniae
    (:belief 0.85
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.13 (Streptococcus, Patterson), NBK7611"
                             "NCBI Bookshelf / StatPearls, Streptococcus pneumoniae, NBK470537")
                  :belief-basis :illustrative
                  :note "S. pneumoniae is separated from the other alpha-hemolytic streptococci by sensitivity to surfactants -- bile or optochin -- which activate its autolytic enzymes."))
  (organism (id ?o))
  (organism-class (value :streptococcus) (of ?o))
  (hemolysis (value alpha) (of ?o))
  (optochin (value sensitive) (of ?o))
  =>
  (assert (organism-identity (value :streptococcus-pneumoniae) (of ?o))))

;; Viridans group: alpha-hemolytic AND optochin-RESISTANT. 0.65 -- "viridans" is a
;; heterogeneous GROUP defined largely by exclusion (alpha-hemolytic and NOT
;; pneumococcus), so the conclusion is genuinely coarser than its siblings.
;; Composes to 0.7*0.65 = 0.455.
(defrule strep-alpha-hemolytic-optochin-resistant-suggests-viridans
    (:belief 0.65
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.13 (Streptococcus, Patterson), NBK7611")
                  :belief-basis :illustrative
                  :note "Alpha-hemolytic streptococci that are optochin-RESISTANT are the viridans group. 0.65 because viridans is a heterogeneous group defined largely by exclusion from S. pneumoniae, not a species-level call."))
  (organism (id ?o))
  (organism-class (value :streptococcus) (of ?o))
  (hemolysis (value alpha) (of ?o))
  (optochin (value resistant) (of ?o))
  =>
  (assert (organism-identity (value :streptococcus-viridans) (of ?o))))

;; Tier-2 (chained, re-parented in slice B): premises replaced by organism-class
;; :streptococcus, so belief composes 0.7*0.75 = 0.525. The clinical (site-based)
;; path to S. pneumoniae, alongside the biochemical optochin rule.
(defrule respiratory-gram-pos-cocci-in-chains-suggests-strep-pneumoniae
    (:belief 0.75
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf / StatPearls, Streptococcus pneumoniae, NBK470537"
                             "NCBI Bookshelf / StatPearls, Community-Acquired Pneumonia, NBK430749")
                  :belief-basis :illustrative
                  :note "Streptococcus pneumoniae is a leading cause of community-acquired pneumonia and lower respiratory tract infection."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (organism-class (value :streptococcus) (of ?o))
  (infection-site (value respiratory) (of ?p))
  =>
  (assert (organism-identity (value :streptococcus-pneumoniae) (of ?o))))

;; E. faecalis vs E. faecium: a reciprocal sugar pair, NOT arabinose alone.
;; Verification found the single-marker teaching contested -- PMC5476817 reports
;; faecalis sorbitol+/arabinose- and faecium the reverse, while the biochemical key
;; in PMC91588 does not treat arabinose as discriminating between the two. Requiring
;; BOTH sugars is the honest reading of a divided source base, and the belief is held
;; at 0.7 rather than the 0.8 a clean single marker would earn. Deliberate exact tie
;; between the siblings: 0.8*0.7 = 0.56 each.
(defrule enterococcus-sorbitol-pos-arabinose-neg-suggests-e-faecalis
    (:belief 0.7
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("Carriage of multidrug resistant Enterococcus faecium and Enterococcus faecalis among apparently healthy humans, PMC5476817"
                             "NCBI Bookshelf, Enterococci: From Commensals to Leading Causes of Drug Resistant Infection, NBK190427")
                  :belief-basis :illustrative
                  :note "PMC5476817: 'All the Enterococcus faecalis isolates fermented sorbitol, mannitol, glucose and lactose but not arabinose while E. faecium was able to ferment arabinose, mannitol, glucose and lactose but not sorbitol.' CONTESTED: the biochemical key in PMC91588 does not treat arabinose as discriminating between these two species, so this rule requires the reciprocal PAIR and is held to 0.7 rather than 0.8."))
  (organism (id ?o))
  (organism-class (value :enterococcus) (of ?o))
  (sorbitol (value fermenter) (of ?o))
  (arabinose (value non-fermenter) (of ?o))
  =>
  (assert (organism-identity (value :enterococcus-faecalis) (of ?o))))

(defrule enterococcus-arabinose-pos-sorbitol-neg-suggests-e-faecium
    (:belief 0.7
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("Carriage of multidrug resistant Enterococcus faecium and Enterococcus faecalis among apparently healthy humans, PMC5476817"
                             "NCBI Bookshelf, Enterococci: From Commensals to Leading Causes of Drug Resistant Infection, NBK190427")
                  :belief-basis :illustrative
                  :note "The reciprocal of the E. faecalis rule: E. faecium ferments arabinose but not sorbitol. Same contested-source caveat and same 0.7. Clinically this is the most therapy-consequential split on the gram-positive side, since E. faecium does not behave like the genus average on ampicillin or vancomycin -- a species-level KB entry is the correct follow-up (design §8.3)."))
  (organism (id ?o))
  (organism-class (value :enterococcus) (of ?o))
  (arabinose (value fermenter) (of ?o))
  (sorbitol (value non-fermenter) (of ?o))
  =>
  (assert (organism-identity (value :enterococcus-faecium) (of ?o))))
