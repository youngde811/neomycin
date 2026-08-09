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

;; Description: An implementation of MYCIN as illustrated in PAIP, pg. 553, used
;; to illustrate (and test) uncertain reasoning. This is neomycin's rulebase.
;;
;; CONTEXT TREE (neomycin change): unlike a flat rulebase, the MYCIN world is a
;; hierarchy -- patient -> culture -> organism -- and every clinical parameter
;; belongs to exactly one context in that tree. We make that structure explicit:
;;
;;   * The context classes PATIENT, CULTURE and ORGANISM are asserted as facts
;;     carrying an ID and a parent link (a culture names its patient; an organism
;;     names its culture). IDs are plain values (symbols/strings), NOT CLOS
;;     instance identity, so Rete can join across the hierarchy by ordinary
;;     variable equality -- and so the LLM bridge, which already identifies
;;     entities by string name, maps onto the same model.
;;
;;   * Every parameter fact (a PARAM-MIXIN subclass) scopes to its context via
;;     the OF slot: gram/morphology/aerobicity/growth-conformation are ORGANISM
;;     level, culture-site/culture-age are CULTURE level, and burn/
;;     compromised-host/hospital-acquired/recent-travel/white-blood-count/
;;     infection-site are PATIENT level.
;;
;;   * Rules join through the lineage (organism -> its culture -> its patient),
;;     so evidence stays within a single organism's chain. With one organism
;;     this is behaviourally identical to the old flat rulebase; with N organisms
;;     it prevents the cross-product leakage the flat version silently produced.
;;
;; The rulebase also exercises the pluggable belief-system protocol (see
;; src/belief-systems/). The same rules run unchanged under MYCIN-style certainty
;; factors and under a simplified Dempster-Shafer system, where each hypothesis
;; carries a [Bel, Pl] interval whose width (Pl - Bel) is explicit ignorance.
;; Rule beliefs declared via (:belief ...) are interpreted by the active belief
;; system; the CONCLUSION rule reports the combined belief for each surviving
;; organism-identity hypothesis via BELIEF:BELIEF-FACTOR.
;;
;; Demonstration functions CULTURE-1/1A/2/3 drive the PAIP scenarios (pgs. 555,
;; 556) plus expanded multi-hypothesis differentials.

(in-package :lisa-user)

(clear)

(setf lisa::*allow-duplicate-facts* nil)

;;; ------------------------------------------------------------------
;;; Context tree: patient -> culture -> organism (asserted as facts).
;;; Identity is carried by the ID slot (a plain value), and the parent
;;; link names the parent's ID.
;;; ------------------------------------------------------------------

(defclass patient ()
  ((id   :initarg :id   :initform nil :reader id)
   (name :initarg :name :initform nil :reader name)
   (sex  :initarg :sex  :initform nil :reader sex)
   (age  :initarg :age  :initform nil :reader age)))

(defclass culture ()
  ((id      :initarg :id      :initform nil :reader id)
   (patient :initarg :patient :initform nil :reader culture-patient)))

(defclass organism ()
  ((id      :initarg :id      :initform nil :reader id)
   (culture :initarg :culture :initform nil :reader organism-culture)))

;;; ------------------------------------------------------------------
;;; Parameters: each scopes to its context via the OF slot (formerly
;;; ENTITY). VALUE holds the clinical reading.
;;; ------------------------------------------------------------------

(defclass param-mixin ()
  ((value :initarg :value :initform nil :reader value)
   (of    :initarg :of    :initform nil :reader context-of)))

;; Culture-level parameters
(defclass culture-site (param-mixin) ())
(defclass culture-age (param-mixin) ())

;; Patient-level parameters
(defclass burn (param-mixin) ())
(defclass compromised-host (param-mixin) ())
(defclass hospital-acquired (param-mixin) ())
(defclass recent-travel (param-mixin) ())
(defclass white-blood-count (param-mixin) ())
(defclass infection-site (param-mixin) ())
;; Host factors (sketch §5.5): patient-level context that SHIFTS belief on
;; hypotheses other rules raise, rather than naming an organism from morphology.
(defclass neutropenia (param-mixin) ())         ; value = t
(defclass prosthetic-material (param-mixin) ()) ; value = t
(defclass iv-drug-use (param-mixin) ())         ; value = t
(defclass age-group (param-mixin) ())           ; value = neonate | infant | adult | elderly

;; Organism-level parameters
(defclass gram (param-mixin) ())
(defclass morphology (param-mixin) ())
(defclass aerobicity (param-mixin) ())
(defclass growth-conformation (param-mixin) ())
;; Biochemical discriminators for enterobacteriaceae species refinement (tier 2).
(defclass lactose (param-mixin) ())     ; value = fermenter | non-fermenter
(defclass indole (param-mixin) ())      ; value = positive | negative
(defclass motility (param-mixin) ())    ; value = motile | non-motile | swarming
(defclass urease (param-mixin) ())      ; value = positive | negative
(defclass pigment (param-mixin) ())     ; value = red | none

;; Discriminators for the gram-POSITIVE COCCUS clusters (docs/gram-positive-cluster-
;; design.md §2). Catalase splits the staphylococci from the streptococci/enterococci;
;; coagulase and novobiocin refine the staphylococci; hemolysis, optochin and
;; bacitracin refine the streptococci; bile-esculin + salt tolerance recognize the
;; enterococci, which arabinose/sorbitol then split into species.
(defclass catalase (param-mixin) ())       ; value = positive | negative
(defclass coagulase (param-mixin) ())      ; value = positive | negative
(defclass hemolysis (param-mixin) ())      ; value = alpha | beta | gamma
(defclass optochin (param-mixin) ())       ; value = sensitive | resistant
(defclass bacitracin (param-mixin) ())     ; value = sensitive | resistant
(defclass novobiocin (param-mixin) ())     ; value = sensitive | resistant
(defclass bile-esculin (param-mixin) ())   ; value = positive | negative
(defclass salt-tolerance (param-mixin) ()) ; value = tolerant | intolerant (6.5% NaCl)
(defclass arabinose (param-mixin) ())      ; value = fermenter | non-fermenter
(defclass sorbitol (param-mixin) ())       ; value = fermenter | non-fermenter

;; Conclusion (organism level)
(defclass organism-identity (param-mixin) ())

;; Derived intermediate abstraction (organism level). Unlike organism-identity
;; -- a leaf species -- organism-class names a taxonomic FAMILY and is designed
;; to appear on BOTH sides of => : concluded by tier-1 evidence rules, and (in a
;; later increment) read as a premise by tier-2 species-refinement rules. This is
;; the one structurally novel piece of the chained cluster (corpus sketch §3B/§7):
;; a param that is both a rule conclusion and a rule premise, so belief flows
;; THROUGH a belief-valued intermediate -- the DS composition path nothing else in
;; the corpus exercises yet.
(defclass organism-class (param-mixin) ())

;;; ------------------------------------------------------------------
;;; Confirming rules (1-15). Each joins the organism to its culture and
;;; patient as needed, then scopes every premise to that lineage.
;;; ------------------------------------------------------------------

(defrule gram-neg-rod-in-burn-patient-suggests-pseudomonas
    (:belief 0.4
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.27 (Pseudomonas), NBK8326"
                             "NCBI Bookshelf / StatPearls, Pseudomonas aeruginosa Infections, NBK557831")
                  :belief-basis :illustrative
                  :note "Pseudomonas aeruginosa is a leading cause of wound infection and frequently fatal bacteremia in patients with serious burns."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (culture-site (value blood) (of ?c))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (burn (value serious) (of ?p))
  =>
  (assert (organism-identity (value :pseudomonas) (of ?o))))

;; NOTE: the one-hop `gram-pos-cocci-in-clumps-suggests-staphylococcus` leaf identity
;; rule was RETIRED in slice A of the gram-positive cluster. Staphylococcus is a
;; GENUS, not a species -- exactly the defect C2 fixed for enterobacteriaceae. It is
;; now concluded as an ORGANISM-CLASS (see the tier-1 class rules below), never as an
;; ORGANISM-IDENTITY; the identity layer names only leaf SPECIES (S. aureus,
;; S. epidermidis, S. saprophyticus). Keeping the leaf alongside the chain would have
;; double-counted the same clumps evidence (a leaf identity AND a class, then again
;; through the species).

(defrule anaerobic-gram-neg-rod-in-blood-suggests-bacteroides
    (:belief 0.9
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf / StatPearls, Bacteroides Fragilis, NBK553032"
                             "NCBI Bookshelf, Medical Microbiology 4th ed. ch.20 (Anaerobic Gram-Negative Bacilli, Finegold), NBK8438")
                  :belief-basis :illustrative
                  :note "Anaerobic gram-negative rods from blood suggest Bacteroides; the B. fragilis group is the most common cause of anaerobic bacteremia."))
  (organism (id ?o) (culture ?c))
  (culture-site (value blood) (of ?c))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value anaerobic) (of ?o))
  =>
  (assert (organism-identity (value :bacteroides) (of ?o))))

(defrule gram-neg-rod-in-compromised-host-suggests-pseudomonas
    (:belief 0.6
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf / StatPearls, Pseudomonas aeruginosa Infections, NBK557831"
                             "NCBI Bookshelf, Medical Microbiology 4th ed. ch.27 (Pseudomonas), NBK8326")
                  :belief-basis :illustrative
                  :note "Pseudomonas aeruginosa is a major opportunistic pathogen of immunocompromised and hospitalized hosts."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (compromised-host (value t) (of ?p))
  =>
  (assert (organism-identity (value :pseudomonas) (of ?o))))

;; NOTE: the one-hop `aerobic-gram-neg-rod-suggests-enterobacteriaceae` leaf
;; identity rule was RETIRED in slice C2. Enterobacteriaceae is now purely a
;; taxonomic FAMILY -- concluded as an ORGANISM-CLASS (see the tier-1 class rule
;; below), never as an ORGANISM-IDENTITY. The identity layer names only leaf
;; SPECIES (E. coli, Klebsiella, Salmonella, ...); the family is carried to the
;; therapy phase as a backstop item only when no member species clears the
;; coverage gate (conclusions-for-solver, therapy/bridge.lisp). Keeping the leaf
;; alongside the chain would have double-counted the same aerobic-gram-neg-rod
;; evidence (a leaf identity AND a class, then again through the species).

;; NOTE: the one-hop `gram-pos-cocci-in-chains-suggests-streptococcus` leaf identity
;; rule was RETIRED in slice A, for the same reason as the staphylococcus leaf above:
;; Streptococcus is a GENUS. It is now an ORGANISM-CLASS, refined to leaf SPECIES
;; (S. pyogenes, S. agalactiae, S. pneumoniae, viridans) by hemolysis + optochin /
;; bacitracin.

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

(defrule hospital-acquired-aerobic-gram-neg-rod-suggests-pseudomonas
    (:belief 0.7
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf / StatPearls, Pseudomonas aeruginosa Infections, NBK557831"
                             "NCBI Bookshelf, Medical Microbiology 4th ed. ch.27 (Pseudomonas), NBK8326")
                  :belief-basis :illustrative
                  :note "Pseudomonas aeruginosa is a leading nosocomial aerobic gram-negative rod pathogen (ventilator-associated pneumonia, catheter/bloodstream infection)."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (hospital-acquired (value t) (of ?p))
  =>
  (assert (organism-identity (value :pseudomonas) (of ?o))))

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

(defrule anaerobic-gram-neg-rod-in-abdomen-suggests-bacteroides
    (:belief 0.8
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf / StatPearls, Bacteroides Fragilis, NBK553032"
                             "NCBI Bookshelf / StatPearls, Anaerobic Infections, NBK482349"
                             "IDSA/SIS, Complicated Intra-abdominal Infection guideline (Solomkin et al.), Clin Infect Dis 2010;50(2):133")
                  :belief-basis :illustrative
                  :note "Bacteroides fragilis group anaerobes are predominant in intra-abdominal infections, typically polymicrobial after a breach of the gut barrier."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value anaerobic) (of ?o))
  (infection-site (value abdominal) (of ?p))
  =>
  (assert (organism-identity (value :bacteroides) (of ?o))))

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

;;; --- Conclusion rule ---

(defrule conclusion (:salience -10)
  (?identity (organism-identity (value ?value)))
  =>
  (format t "Identity: ~A (~,3F)~%" ?value (belief:belief-factor ?identity)))

;;; ------------------------------------------------------------------
;;; Demonstration scenarios. Each asserts a patient -> culture -> organism
;;; lineage (by ID) and then the clinical parameters scoped to it.
;;; ------------------------------------------------------------------

(defun culture-1 (&key (runp t))
  "First PAIP scenario (pg. 555): aerobic gram-neg rod cultured from the blood of a
   seriously burned, immunocompromised patient. Evidence enters with the active
   belief system's default (full belief / no ignorance). Multiple rules fire on
   overlapping evidence, producing competing pseudomonas and klebsiella species
   hypotheses (the latter chained off the derived enterobacteriaceae CLASS) that
   the belief system must combine. Enterobacteriaceae itself is an organism-CLASS
   here, not a leaf identity (C2)."
  (reset)
  (assert (patient (id p1)))
  (assert (culture (id c1) (patient p1)))
  (assert (organism (id o1) (culture c1)))
  (assert (compromised-host (value t) (of p1)))
  (assert (burn (value serious) (of p1)))
  (assert (culture-site (value blood) (of c1)))
  (assert (culture-age (value 3) (of c1)))
  (assert (gram (value neg) (of o1)))
  (assert (morphology (value rod) (of o1)))
  (assert (aerobicity (value aerobic) (of o1)))
  (when runp
    (run)))

(defun culture-1a (&key (runp t))
  "Hospital-acquired gram-neg infection in an immunocompromised patient.
   Produces competing species hypotheses pseudomonas and klebsiella (chained off
   the derived enterobacteriaceae CLASS, which is not itself a leaf identity)."
  (reset)
  (assert (patient (id p1)))
  (assert (culture (id c1) (patient p1)))
  (assert (organism (id o1) (culture c1)))
  (assert (compromised-host (value t) (of p1)))
  (assert (hospital-acquired (value t) (of p1)))
  (assert (culture-site (value blood) (of c1)))
  (assert (gram (value neg) (of o1)))
  (assert (morphology (value rod) (of o1)))
  (assert (aerobicity (value aerobic) (of o1)))
  (when runp
    (run)))

(defun culture-3 (&key (runp t))
  "Gram-pos cocci in chains from a respiratory site in a compromised host.
   After slice A, streptococcus is an organism-CLASS (not a leaf identity) and the
   enterococcus rule concludes its own CLASS, so the only surviving leaf identity here
   is streptococcus-pneumoniae; slice B refines both classes into competing species."
  (reset)
  (assert (patient (id p1)))
  (assert (culture (id c1) (patient p1)))
  (assert (organism (id o1) (culture c1)))
  (assert (compromised-host (value t) (of p1)))
  (assert (culture-site (value blood) (of c1)))
  (assert (infection-site (value respiratory) (of p1)))
  (assert (gram (value pos) (of o1)))
  (assert (morphology (value coccus) (of o1)))
  (assert (growth-conformation (value chains) (of o1)))
  (when runp
    (run)))

(defun culture-2 (&key (runp t))
  "Second PAIP scenario (pg. 556): same burned, immunocompromised patient, but the
   Gram stain is ambiguous. Two conflicting GRAM facts are asserted with explicit
   belief values (0.8 for neg, 0.2 for pos), exercising the belief-system protocol
   on the fact side as well as the rule side. With an anaerobic gram-neg rod in the
   blood, the bacteroides rule dominates while the gram-pos disconfirming rule pulls
   plausibility below 1.0 -- a good workout for both combinators."
  (reset)
  (assert (patient (id p1)))
  (assert (culture (id c1) (patient p1)))
  (assert (organism (id o1) (culture c1)))
  (assert (compromised-host (value t) (of p1)))
  (assert (burn (value serious) (of p1)))
  (assert (culture-site (value blood) (of c1)))
  (assert (culture-age (value 3) (of c1)))
  (assert (gram (value neg) (of o1)) :belief 0.8)
  (assert (gram (value pos) (of o1)) :belief 0.2)
  (assert (morphology (value rod) (of o1)))
  (assert (aerobicity (value anaerobic) (of o1)))
  (when runp
    (run)))

(defun culture-multi (&key (runp t))
  "Two organisms in one culture, to exercise lineage scoping. o1 is an aerobic
   gram-neg rod (=> enterobacteriaceae CLASS only, no leaf identity after C2); o2
   is a gram-pos coccus in clumps with a POSITIVE coagulase (=> staphylococcus
   class, refined to the S. aureus species at 0.7*0.85 = 0.595). Each conclusion
   must stay on its own organism -- the flat rulebase would cross-contaminate via
   unscoped morphology/gram joins. The coagulase was added in slice B so the
   identity layer is non-empty again: slice A had left o2 stopping at its genus."
  (reset)
  (assert (patient (id p1)))
  (assert (culture (id c1) (patient p1)))
  (assert (organism (id o1) (culture c1)))
  (assert (organism (id o2) (culture c1)))
  (assert (gram (value neg) (of o1)))
  (assert (morphology (value rod) (of o1)))
  (assert (aerobicity (value aerobic) (of o1)))
  (assert (gram (value pos) (of o2)))
  (assert (morphology (value coccus) (of o2)))
  (assert (growth-conformation (value clumps) (of o2)))
  (assert (coagulase (value positive) (of o2)))
  (when runp
    (run)))

(defun culture-4 (&key (runp t))
  "Gram-positive differential (slice B): a beta-hemolytic, bacitracin-sensitive
   gram-pos coccus in chains from a patient with a respiratory infection site.

   Two rules refine the derived streptococcus CLASS to competing species along
   different axes -- the biochemical one to S. pyogenes (0.7*0.85 = 0.595) and the
   clinical/site one to S. pneumoniae (0.7*0.75 = 0.525) -- so the differential is
   genuinely two-sided rather than a single hypothesis with a number on it.

   The pair is mutually exclusive in reality: a BETA-hemolytic organism is not
   S. pneumoniae, which is alpha-hemolytic. Until slice C adds the hemolysis
   cross-disconfirming rules, both nonetheless sit at plausibility 1.0 with neither
   pulling the other down -- precisely the gap observed live on the enterobacteriaceae
   siblings before v0.5.0. This driver is the fixture that makes slice C's effect
   visible."
  (reset)
  (assert (patient (id p1)))
  (assert (culture (id c1) (patient p1)))
  (assert (organism (id o1) (culture c1)))
  (assert (culture-site (value blood) (of c1)))
  (assert (infection-site (value respiratory) (of p1)))
  (assert (gram (value pos) (of o1)))
  (assert (morphology (value coccus) (of o1)))
  (assert (growth-conformation (value chains) (of o1)))
  (assert (hemolysis (value beta) (of o1)))
  (assert (bacitracin (value sensitive) (of o1)))
  (when runp
    (run)))