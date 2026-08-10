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

;; Description: Every ruling-out rule in the corpus, across all clusters. These are
;; what keep Dempster-Shafer honest: without disconfirming evidence nothing produces
;; conflict, plausibility never falls below 1.0, and DS collapses toward CF.

(in-package :lisa-user)

;;; --- Ruling-out (disconfirming) rules ---
;;;
;;; These inject *negative* evidence: a contradictory Gram stain or oxygen
;;; requirement argues AGAINST a live organism-identity hypothesis. They key off
;;; the hypothesis and its contradicting parameter on the SAME organism (?o) and
;;; re-assert it with a negative rule belief, which the active belief system
;;; folds in as disconfirming evidence.
;;;
;;; Under Dempster-Shafer a negative :belief becomes mass on not-H, so meeting
;;; confirmatory evidence produces real conflict (K > 0): Bel falls AND
;;; plausibility drops below 1.0 -- an ambiguous stain becomes a widened, lowered
;;; interval. Under certainty factors it simply combines as a negative CF.
(defrule gram-pos-stain-argues-against-gram-neg-organism
    (:belief -0.7
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf / StatPearls, Gram Staining, NBK562156"
                             "NCBI Bookshelf / StatPearls, Gram-Positive Bacteria, NBK470553")
                  :belief-basis :illustrative
                  :note "A gram-positive stain (thick peptidoglycan wall) is evidence against a gram-negative organism; the two Gram classes are mutually exclusive by cell-wall structure."))
  (organism (id ?o))
  (gram (value pos) (of ?o))
  (organism-identity (value ?value) (of ?o))
  ;; :enterobacteriaceae dropped from this list in C2 -- it is a family CLASS now,
  ;; never an organism-identity, so it can never match here.
  (test (member ?value '(:pseudomonas :klebsiella :salmonella
                         :e-coli :enterobacter :serratia :proteus :bacteroides)))
  =>
  (assert (organism-identity (value ?value) (of ?o))))

(defrule gram-neg-stain-argues-against-gram-pos-organism
    (:belief -0.7
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf / StatPearls, Gram Staining, NBK562156"
                             "NCBI Bookshelf / StatPearls, Gram-Positive Bacteria, NBK470553")
                  :belief-basis :illustrative
                  :note "A gram-negative stain result is evidence against a gram-positive organism; the Gram stain partitions bacteria into two mutually exclusive cell-wall categories."))
  (organism (id ?o))
  (gram (value neg) (of ?o))
  (organism-identity (value ?value) (of ?o))
  ;; :staphylococcus, :streptococcus and :enterococcus dropped in slice A -- all three
  ;; are organism-CLASSes now, never organism-identities, so they can never match here
  ;; (the same bookkeeping C2 did for :enterobacteriaceae). Their leaf SPECIES, added
  ;; in slice B, take their place.
  (test (member ?value '(:staphylococcus-aureus :staphylococcus-epidermidis
                         :staphylococcus-saprophyticus
                         :streptococcus-pneumoniae :streptococcus-pyogenes
                         :streptococcus-agalactiae :streptococcus-viridans
                         :enterococcus-faecalis :enterococcus-faecium)))
  =>
  (assert (organism-identity (value ?value) (of ?o))))

(defrule aerobic-growth-argues-against-anaerobe
    (:belief -0.8
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.20 (Anaerobes: General Characteristics), NBK7638"
                             "NCBI Bookshelf, Medical Microbiology 4th ed. ch.20 (Anaerobic Gram-Negative Bacilli, Finegold), NBK8438")
                  :belief-basis :illustrative
                  :note "Documented aerobic growth argues against an obligate anaerobe such as Bacteroides, which cannot grow in the presence of oxygen."))
  (organism (id ?o))
  (aerobicity (value aerobic) (of ?o))
  (organism-identity (value ?value) (of ?o))
  (test (member ?value '(:bacteroides)))
  =>
  (assert (organism-identity (value ?value) (of ?o))))

;; Biochemical disconfirmation among the enterobacteriaceae siblings: a positive
;; urease argues AGAINST the urease-negative species (E. coli, Salmonella). This is
;; what lets a contradictory biochemical finding pull a species' plausibility below
;; 1.0 -- the DS-conflict material for near-tied siblings. (Authoritative sources in
;; the rule's :provenance :evidence.)
(defrule urease-pos-argues-against-urease-negative-organism
    (:belief -0.7
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Enterobacteriaceae), NBK8035"
                             "NCBI Bookshelf / StatPearls, Proteus mirabilis Infections, NBK442017")
                  :belief-basis :illustrative
                  :note "Proteus is rapidly urease-positive while E. coli and Salmonella are characteristically urease-negative, so a positive urease argues against E. coli/Salmonella and toward Proteus (rare urease-positive Salmonella exist, hence -0.7 not absolute)."))
  (organism (id ?o))
  (urease (value positive) (of ?o))
  (organism-identity (value ?value) (of ?o))
  (test (member ?value '(:e-coli :salmonella)))
  =>
  (assert (organism-identity (value ?value) (of ?o))))

;; Red pigment (prodigiosin) is essentially Serratia-specific, so it argues AGAINST
;; every OTHER sibling: seeing it makes a non-Serratia call unlikely. -0.8 -- the most
;; exclusive of the biochemical markers (prodigiosin has no counterpart in the other
;; genera). Closes half the observed session gap (red pigment now pulls E. coli down).
(defrule red-pigment-argues-against-non-serratia
    (:belief -0.8
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Enterobacteriaceae), NBK8035"
                             "Scientific Reports 2024, Serratia marcescens prodigiosin red pigment, PMC11291754 (doi:10.1038/s41598-024-68747-3)")
                  :belief-basis :illustrative
                  :note "The red pigment prodigiosin is essentially specific to Serratia marcescens among the Enterobacteriaceae, so its presence argues against E. coli, Klebsiella, Salmonella, Enterobacter, and Proteus."))
  (organism (id ?o))
  (pigment (value red) (of ?o))
  (organism-identity (value ?value) (of ?o))
  (test (member ?value '(:e-coli :klebsiella :salmonella :enterobacter :proteus)))
  =>
  (assert (organism-identity (value ?value) (of ?o))))

;; A positive indole argues AGAINST the characteristically indole-negative siblings
;; (Klebsiella, Enterobacter, Salmonella, Serratia). Proteus is deliberately EXCLUDED:
;; P. mirabilis is indole- but P. vulgaris is indole+, so the marker is ambiguous for
;; the genus (honest scoping). -0.6 -- clean but not absolute. Closes the other half of
;; the observed session gap (indole+ now pulls Serratia down).
(defrule indole-pos-argues-against-indole-negative-species
    (:belief -0.6
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Enterobacteriaceae), NBK8035"
                             "J Clin Microbiol (indole-positive vs indole-negative Klebsiella identification), PMC1594763")
                  :belief-basis :illustrative
                  :note "Klebsiella, Enterobacter, Salmonella, and Serratia are characteristically indole-negative, so a positive indole argues against them. Proteus is excluded because P. mirabilis is indole-negative while P. vulgaris is indole-positive (ambiguous for the genus)."))
  (organism (id ?o))
  (indole (value positive) (of ?o))
  (organism-identity (value ?value) (of ?o))
  (test (member ?value '(:klebsiella :enterobacter :salmonella :serratia)))
  =>
  (assert (organism-identity (value ?value) (of ?o))))

;; Lactose fermentation argues AGAINST the classic non-fermenters, Salmonella and
;; Proteus -- the standard teaching discriminator (MacConkey lactose reaction). -0.7.
(defrule lactose-fermenter-argues-against-non-fermenters
    (:belief -0.7
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Enterobacteriaceae), NBK8035"
                             "NCBI Bookshelf / StatPearls, Proteus mirabilis Infections, NBK442017")
                  :belief-basis :illustrative
                  :note "Salmonella and Proteus are characteristically non-lactose-fermenters, so lactose fermentation argues against them -- the classic MacConkey teaching discriminator."))
  (organism (id ?o))
  (lactose (value fermenter) (of ?o))
  (organism-identity (value ?value) (of ?o))
  (test (member ?value '(:salmonella :proteus)))
  =>
  (assert (organism-identity (value ?value) (of ?o))))

;; The symmetric complement: NON-fermentation of lactose argues AGAINST the strong
;; fermenters (E. coli, Klebsiella, Enterobacter). Serratia is EXCLUDED -- it is a
;; slow/variable lactose reactor, so the marker is not clean for it (honest). -0.6.
(defrule lactose-non-fermenter-argues-against-fermenters
    (:belief -0.6
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Enterobacteriaceae), NBK8035"
                             "NCBI Bookshelf / StatPearls, Escherichia coli Infection, NBK564298")
                  :belief-basis :illustrative
                  :note "E. coli, Klebsiella, and Enterobacter are strong lactose fermenters, so a non-fermenting reading argues against them. Serratia is excluded because it is a slow/variable lactose reactor (the marker is not clean for it)."))
  (organism (id ?o))
  (lactose (value non-fermenter) (of ?o))
  (organism-identity (value ?value) (of ?o))
  (test (member ?value '(:e-coli :klebsiella :enterobacter)))
  =>
  (assert (organism-identity (value ?value) (of ?o))))

;;; ------------------------------------------------------------------
;;; Cross-disconfirmation among the GRAM-POSITIVE siblings (slice C;
;;; docs/gram-positive-cluster-design.md §3.4).
;;;
;;; Same pattern as the enterobacteriaceae cross-disconfirming rules, but with
;;; stronger negative beliefs, because these discriminators partition CLEANLY where
;;; the enterobacteriaceae biochemicals overlap: hemolysis is a three-way partition
;;; and coagulase a two-way one, so a contradictory reading is close to decisive
;;; rather than merely suggestive. Without these, mutually exclusive siblings both
;;; sit at pl 1.0 -- the gap culture-4 exists to display.
;;; ------------------------------------------------------------------
;; Coagulase is the defining split within the staphylococci, so a NEGATIVE coagulase
;; is strong evidence against S. aureus. -0.85.
(defrule coagulase-neg-argues-against-staph-aureus
    (:belief -0.85
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.12 (Staphylococcus), NBK8448"
                             "NCBI Bookshelf / StatPearls, Staphylococcus aureus Infection, NBK441868")
                  :belief-basis :illustrative
                  :note "S. aureus is by definition the coagulase-positive staphylococcus, so a negative coagulase argues strongly against it."))
  (organism (id ?o))
  (coagulase (value negative) (of ?o))
  (organism-identity (value ?value) (of ?o))
  (test (member ?value '(:staphylococcus-aureus)))
  =>
  (assert (organism-identity (value ?value) (of ?o))))

;; The symmetric complement: a POSITIVE coagulase argues against the
;; coagulase-negative staphylococci. -0.85.
(defrule coagulase-pos-argues-against-coagulase-negative-staph
    (:belief -0.85
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf / StatPearls, Staphylococcus epidermidis Infection, NBK563240"
                             "NCBI Bookshelf / StatPearls, Staphylococcus saprophyticus Infection, NBK482367")
                  :belief-basis :illustrative
                  :note "S. epidermidis and S. saprophyticus are coagulase-NEGATIVE staphylococci, so a positive coagulase argues against them and toward S. aureus."))
  (organism (id ?o))
  (coagulase (value positive) (of ?o))
  (organism-identity (value ?value) (of ?o))
  (test (member ?value '(:staphylococcus-epidermidis :staphylococcus-saprophyticus)))
  =>
  (assert (organism-identity (value ?value) (of ?o))))

;; Catalase-negative argues against the whole staphylococcus genus -- the textbook
;; staph-vs-strep split, entering as a disconfirmer rather than a tier-1 premise so
;; that scenarios which never run it are unaffected. -0.7.
(defrule catalase-neg-argues-against-staphylococci
    (:belief -0.7
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf / StatPearls, Gram-Positive Bacteria, NBK470553"
                             "NCBI Bookshelf, Medical Microbiology 4th ed. ch.12 (Staphylococcus), NBK8448")
                  :belief-basis :illustrative
                  :note "Staphylococci are catalase-POSITIVE while streptococci and enterococci are catalase-negative, so a negative catalase argues against any staphylococcal species."))
  (organism (id ?o))
  (catalase (value negative) (of ?o))
  (organism-identity (value ?value) (of ?o))
  (test (member ?value '(:staphylococcus-aureus :staphylococcus-epidermidis
                         :staphylococcus-saprophyticus)))
  =>
  (assert (organism-identity (value ?value) (of ?o))))

;; Hemolysis is a clean three-way partition, so a BETA reading argues against the
;; species that are characteristically alpha-hemolytic. -0.75.
(defrule beta-hemolysis-argues-against-non-beta-streptococci
    (:belief -0.75
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.13 (Streptococcus, Patterson), NBK7611"
                             "NCBI Bookshelf / StatPearls, Streptococcus pneumoniae, NBK470537")
                  :belief-basis :illustrative
                  :note "Streptococci are partitioned by hemolysis into beta (complete), alpha (green/partial) and gamma (none). S. pneumoniae and the viridans group are ALPHA-hemolytic, so a beta reading argues against them."))
  (organism (id ?o))
  (hemolysis (value beta) (of ?o))
  (organism-identity (value ?value) (of ?o))
  (test (member ?value '(:streptococcus-pneumoniae :streptococcus-viridans)))
  =>
  (assert (organism-identity (value ?value) (of ?o))))

;; The reciprocal: an ALPHA reading argues against the beta-hemolytic species. -0.75.
(defrule alpha-hemolysis-argues-against-beta-hemolytic-streptococci
    (:belief -0.75
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.13 (Streptococcus, Patterson), NBK7611"
                             "NCBI Bookshelf / StatPearls, Group B Streptococcus and Pregnancy, NBK482443")
                  :belief-basis :illustrative
                  :note "S. pyogenes (group A) and S. agalactiae (group B) are BETA-hemolytic, so an alpha-hemolytic reading argues against them."))
  (organism (id ?o))
  (hemolysis (value alpha) (of ?o))
  (organism-identity (value ?value) (of ?o))
  (test (member ?value '(:streptococcus-pyogenes :streptococcus-agalactiae)))
  =>
  (assert (organism-identity (value ?value) (of ?o))))

;; Optochin sensitivity is what separates the pneumococcus from the rest of the
;; alpha-hemolytic streptococci, so a SENSITIVE result argues against viridans. -0.7.
(defrule optochin-sensitive-argues-against-viridans
    (:belief -0.7
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.13 (Streptococcus, Patterson), NBK7611")
                  :belief-basis :illustrative
                  :note "The viridans group is defined among alpha-hemolytic streptococci by optochin RESISTANCE, so an optochin-sensitive result argues against it and toward S. pneumoniae."))
  (organism (id ?o))
  (optochin (value sensitive) (of ?o))
  (organism-identity (value ?value) (of ?o))
  (test (member ?value '(:streptococcus-viridans)))
  =>
  (assert (organism-identity (value ?value) (of ?o))))

;; A NEGATIVE bile-esculin argues against the enterococci. The mildest of this group
;; at -0.6: some non-enterococcal group D streptococci are also bile-esculin positive,
;; so the test is a better ruling-in than ruling-out marker.
(defrule bile-esculin-neg-argues-against-enterococci
    (:belief -0.6
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("J Clin Microbiol, Presumptive Identification of Group D Streptococci: the Bile-Esculin Test, PMC376909"
                             "J Clin Microbiol, Comparison of Several Laboratory Media for Presumptive Identification of Enterococci and Group D Streptococci, PMC379740")
                  :belief-basis :illustrative
                  :note "Enterococci hydrolyze esculin in the presence of bile, so a negative bile-esculin argues against them. Held to -0.6 because the test is shared with the non-enterococcal group D streptococci, making it a stronger ruling-IN than ruling-out marker."))
  (organism (id ?o))
  (bile-esculin (value negative) (of ?o))
  (organism-identity (value ?value) (of ?o))
  (test (member ?value '(:enterococcus-faecalis :enterococcus-faecium)))
  =>
  (assert (organism-identity (value ?value) (of ?o))))

;; Arabinose fermentation argues against E. faecalis, which characteristically does
;; NOT ferment it. -0.7, matching the conservative belief on the confirming pair --
;; the same contested-source caveat applies (see the species rules above).
(defrule arabinose-pos-argues-against-e-faecalis
    (:belief -0.7
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("Carriage of multidrug resistant Enterococcus faecium and Enterococcus faecalis among apparently healthy humans, PMC5476817")
                  :belief-basis :illustrative
                  :note "E. faecalis characteristically does not ferment arabinose while E. faecium does, so arabinose fermentation argues against E. faecalis. CONTESTED, as for the confirming rules: the biochemical key in PMC91588 does not treat arabinose as discriminating between these species -- hence -0.7 rather than something stronger."))
  (organism (id ?o))
  (arabinose (value fermenter) (of ?o))
  (organism-identity (value ?value) (of ?o))
  (test (member ?value '(:enterococcus-faecalis)))
  =>
  (assert (organism-identity (value ?value) (of ?o))))
