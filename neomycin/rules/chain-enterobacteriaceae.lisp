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

;; Description: The enterobacteriaceae chained cluster -- the corpus's first multi-hop
;; inference (sketch §3B/§5.1). Aerobic gram-neg rod -> derived organism-CLASS ->
;; competing sibling SPECIES, so belief composes THROUGH a belief-valued intermediate.
;; Cross-disconfirmation among these siblings lives in disconfirming.lisp.

(in-package :lisa-user)

;; NOTE: the one-hop `aerobic-gram-neg-rod-suggests-enterobacteriaceae` leaf
;; identity rule was RETIRED in slice C2. Enterobacteriaceae is now purely a
;; taxonomic FAMILY -- concluded as an ORGANISM-CLASS (see the tier-1 class rule
;; below), never as an ORGANISM-IDENTITY. The identity layer names only leaf
;; SPECIES (E. coli, Klebsiella, Salmonella, ...); the family is carried to the
;; therapy phase as a backstop item only when no member species clears the
;; coverage gate (conclusions-for-solver, therapy/bridge.lisp). Keeping the leaf
;; alongside the chain would have double-counted the same aerobic-gram-neg-rod
;; evidence (a leaf identity AND a class, then again through the species).

;;; ------------------------------------------------------------------
;;; Chained cluster, tier 1: evidence -> derived ORGANISM-CLASS.
;;;
;;; The corpus's first multi-hop inference (sketch §3B/§5.1). This tier concludes
;;; a belief-valued FAMILY abstraction from raw evidence; a later tier will refine
;;; class -> competing sibling species, so belief composes THROUGH the intermediate.
;;;
;;; Premises are those of the RETIRED aerobic-gram-neg-rod enterobacteriaceae leaf
;;; rule (same evidence, same 0.8); the difference is the CONCLUSION target -- a
;;; class, not a species. As of C2 this class rule is the SOLE consumer of that
;;; evidence: the leaf identity rule has been retired, so there is no longer a
;;; double path to enterobacteriaceae. 0.8 is carried over from the established
;;; leaf rather than invented; family membership is arguably firmer than any
;;; single species call, but the honest move is to reuse the corpus's existing
;;; value and let it be tuned against tier-2 goldens.
;;;
;;; Origin and authoritative sources now live in the rule's machine-readable
;;; :provenance (queryable via the WHY/HOW facility): :origin :neomycin-extrapolation,
;;; the family-abstraction/chaining structure following MYCIN's organism class context.
;;; ------------------------------------------------------------------
(defrule aerobic-gram-neg-rod-suggests-enterobacteriaceae-class
    (:belief 0.8
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Enterobacteriaceae), NBK8035"
                             "NCBI Bookshelf / StatPearls, Enterobacter Infections, NBK559296")
                  :belief-basis :illustrative
                  :note "Enterobacteriaceae are facultatively anaerobic gram-negative rods that grow aerobically -- the family-level abstraction. The class/genus-context chaining structure follows MYCIN (Buchanan & Shortliffe 1984); this rule is a neomycin reconstruction. 0.8 carried over from the retired one-hop enterobacteriaceae leaf."))
  (organism (id ?o))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  =>
  (assert (organism-class (value :enterobacteriaceae) (of ?o))))

;;; ------------------------------------------------------------------
;;; Chained cluster, tier 2: refine the enterobacteriaceae class -> species.
;;;
;;; Species rules read the derived organism-class as a premise, so belief composes
;;; THROUGH it: species belief = class belief (0.8) * this rule's belief. The raw
;;; discriminators (lactose, indole) carry nil belief and only gate firing. Because
;;; these rules depend on the class, they inherit its aerobic-gram-neg-rod premises.
;;;
;;; E. coli: lactose-fermenting AND indole-positive is the classic pair separating it
;;; from its siblings -- Klebsiella (lactose+ but indole-NEGATIVE) and Salmonella
;;; (lactose-NEGATIVE). E. coli is "the only major group of Enterobacteriaceae with
;;; both lactose utilization and indole production" (IMViC pattern ++--). Conditional
;;; belief 0.8: strong but not certain (K. oxytoca is also lactose+/indole+), composing
;;; to 0.8*0.8 = 0.64. Authoritative sources live in the rule's :provenance :evidence.
;;; ------------------------------------------------------------------
(defrule enterobacteriaceae-lactose-pos-indole-pos-suggests-e-coli
    (:belief 0.8
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf / StatPearls, Escherichia coli Infection, NBK564298"
                             "J Clin Microbiol (indole-positive vs indole-negative Klebsiella identification), PMC1594763")
                  :belief-basis :illustrative
                  :note "E. coli is characteristically lactose-fermenting and indole-positive, distinguishing it from indole-negative Klebsiella and lactose-negative Salmonella (K. oxytoca is also +/+, hence conditional 0.8)."))
  (organism (id ?o))
  (organism-class (value :enterobacteriaceae) (of ?o))
  (lactose (value fermenter) (of ?o))
  (indole (value positive) (of ?o))
  =>
  (assert (organism-identity (value :e-coli) (of ?o))))

;; Enterobacter: lactose-fermenting, indole-NEGATIVE, and MOTILE -- the motility is
;; what separates it from Klebsiella (lactose+/indole- but NON-motile). Belief 0.6
;; (moderate: it shares lactose+/indole- with Klebsiella, so motility is the only
;; discriminator; a near-tie by design). Composes to 0.8*0.6 = 0.48.
;; (Enterobacter motile, Klebsiella non-motile; authoritative sources in :provenance.)
(defrule enterobacteriaceae-motile-lactose-pos-indole-neg-suggests-enterobacter
    (:belief 0.6
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf / StatPearls, Enterobacter Infections, NBK559296"
                             "NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Enterobacteriaceae), NBK8035")
                  :belief-basis :illustrative
                  :note "Among lactose-positive, indole-negative Enterobacteriaceae, motility distinguishes motile Enterobacter from non-motile Klebsiella."))
  (organism (id ?o))
  (organism-class (value :enterobacteriaceae) (of ?o))
  (lactose (value fermenter) (of ?o))
  (indole (value negative) (of ?o))
  (motility (value motile) (of ?o))
  =>
  (assert (organism-identity (value :enterobacter) (of ?o))))

;; Serratia (marcescens): RED PIGMENT (prodigiosin) is the distinctive marker.
;; Belief 0.75 (distinctive but not universal -- many clinical isolates are
;; non-pigmented). Composes to 0.8*0.75 = 0.60. (Sources in :provenance :evidence.)
(defrule enterobacteriaceae-red-pigment-suggests-serratia
    (:belief 0.75
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("Scientific Reports 2024, Serratia marcescens prodigiosin red pigment, PMC11291754 (doi:10.1038/s41598-024-68747-3)"
                             "Microbiology (Mikrobiologiya) 2015, Pigmentation of Serratia marcescens and prodigiosin, PMID 25916146")
                  :belief-basis :illustrative
                  :note "Serratia marcescens produces the characteristic red pigment prodigiosin (many clinical isolates are non-pigmented, hence 0.75)."))
  (organism (id ?o))
  (organism-class (value :enterobacteriaceae) (of ?o))
  (pigment (value red) (of ?o))
  =>
  (assert (organism-identity (value :serratia) (of ?o))))

;; Proteus: rapid UREASE and SWARMING motility -- both highly characteristic.
;; Belief 0.8 (distinctive pair). Composes to 0.8*0.8 = 0.64. (Sources in :provenance.)
(defrule enterobacteriaceae-urease-pos-swarming-suggests-proteus
    (:belief 0.8
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf / StatPearls, Proteus mirabilis Infections, NBK442017"
                             "Nature Reviews Microbiology 2012 (Armbruster & Mobley), Proteus mirabilis lifestyle, doi:10.1038/nrmicro2890 (PMC3621030)")
                  :belief-basis :illustrative
                  :note "Proteus species show characteristic swarming motility and rapid, strong urease activity."))
  (organism (id ?o))
  (organism-class (value :enterobacteriaceae) (of ?o))
  (urease (value positive) (of ?o))
  (motility (value swarming) (of ?o))
  =>
  (assert (organism-identity (value :proteus) (of ?o))))

;; Tier-2 (chained): refines the enterobacteriaceae class -> klebsiella. The raw
;; gram-neg-rod premises are replaced by organism-class (which already encodes
;; aerobic gram-neg rod), so belief composes 0.8*0.6 through the intermediate and
;; the aerobic requirement now rides in via the class -- faithful, as
;; enterobacteriaceae are facultative. Re-parented from the one-hop leaf.
(defrule hospital-acquired-enterobacteriaceae-in-compromised-host-suggests-klebsiella
    (:belief 0.6
     :provenance (:origin :paip-subset
                  :evidence ("ASM Clinical Microbiology Reviews 1998 (Podschun & Ullmann), Klebsiella spp. as Nosocomial Pathogens, doi:10.1128/CMR.11.4.589 (PMC88898)"
                             "NCBI Bookshelf / StatPearls, Klebsiella Pneumonia, NBK519004")
                  :belief-basis :illustrative
                  :note "Klebsiella pneumoniae is a leading nosocomial pathogen, disproportionately affecting immunocompromised inpatients."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (organism-class (value :enterobacteriaceae) (of ?o))
  (hospital-acquired (value t) (of ?p))
  (compromised-host (value t) (of ?p))
  =>
  (assert (organism-identity (value :klebsiella) (of ?o))))

;; Tier-2 (chained): enterobacteriaceae class + compromised host -> klebsiella.
;; Belief composes 0.8*0.5. (The old rule's explicit aerobic premise is subsumed
;; by the class, so this is behaviour-equivalent on firing conditions, only the
;; belief now flows through the intermediate.)
(defrule enterobacteriaceae-in-compromised-host-suggests-klebsiella
    (:belief 0.5
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Escherichia, Klebsiella, Enterobacter, Serratia, Citrobacter, Proteus), NBK8035"
                             "NCBI Bookshelf / StatPearls, Klebsiella Pneumonia, NBK519004")
                  :belief-basis :illustrative
                  :note "Klebsiella, an Enterobacteriaceae, is an opportunistic pathogen in immunocompromised hosts."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (organism-class (value :enterobacteriaceae) (of ?o))
  (compromised-host (value t) (of ?p))
  =>
  (assert (organism-identity (value :klebsiella) (of ?o))))

;; Tier-2 (chained): enterobacteriaceae class + tropical travel -> salmonella.
;; Belief composes 0.8*0.65. Re-parenting adds an aerobic requirement (via the
;; class) the one-hop rule lacked -- faithful, salmonella is enterobacteriaceae.
(defrule enterobacteriaceae-with-tropical-travel-suggests-salmonella
    (:belief 0.65
     :provenance (:origin :paip-subset
                  :evidence ("CDC Yellow Book 2026, Typhoid & Paratyphoid Fever, NBK620886"
                             "NCBI Bookshelf / StatPearls, Typhoid Fever, NBK557513")
                  :belief-basis :illustrative
                  :note "Enteric (typhoid/paratyphoid) fever from Salmonella Typhi/Paratyphi is strongly associated with travel to endemic regions, especially South Asia."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (organism-class (value :enterobacteriaceae) (of ?o))
  (recent-travel (value tropical) (of ?p))
  =>
  (assert (organism-identity (value :salmonella) (of ?o))))

;; Tier-2 (chained): enterobacteriaceae class + blood + low WBC -> salmonella.
;; Belief composes 0.8*0.55. Re-parenting adds an aerobic requirement (via the
;; class) the one-hop rule lacked -- faithful, salmonella is enterobacteriaceae.
(defrule enterobacteriaceae-in-blood-with-low-wbc-suggests-salmonella
    (:belief 0.55
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf / StatPearls, Typhoid Fever, NBK557513")
                  :belief-basis :illustrative
                  :note "Typhoidal Salmonella bacteremia characteristically shows a normal-to-low WBC (leukopenia/neutropenia in ~15-25%) rather than the leukocytosis of pyogenic infection."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (culture-site (value blood) (of ?c))
  (organism-class (value :enterobacteriaceae) (of ?o))
  (white-blood-count (value low) (of ?p))
  =>
  (assert (organism-identity (value :salmonella) (of ?o))))
