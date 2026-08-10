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

;; Description: Host-factor modifiers (corpus sketch §5.5) -- patient-level context
;; that shifts belief on hypotheses the morphology and biochemical rules already
;; raise, rather than naming an organism from a stain.

(in-package :lisa-user)

;;; ------------------------------------------------------------------
;;; HOST-FACTOR modifiers (slice D; corpus sketch §5.5,
;;; docs/gram-positive-cluster-design.md §3.3).
;;;
;;; Patient-level context that shifts belief on hypotheses the morphology/biochemical
;;; rules already raise, rather than naming an organism from a stain. Weak-to-moderate
;;; by design (0.5-0.7): this is the CF-vs-DS material, where a single number hides
;;; what an interval shows.
;;;
;;; HONEST FRAMING: "modifier" describes intent, not mechanism. These rules assert an
;;; organism-identity like every other confirming rule, so what they actually do is
;;; contribute an additional independent mass that COMBINES with the existing one. A
;;; true modifier would scale a belief already held, which the engine does not
;;; currently express -- engine-axis work, noted and not done here (design §8.2).
;;; ------------------------------------------------------------------
;; Pseudomonas is the feared gram-negative bloodstream pathogen of the neutropenic
;; host. One-hop rather than chained: Pseudomonas is NOT an enterobacteriaceae, so it
;; cannot refine from that class. 0.5 -- deliberately modest, see the note.
(defrule neutropenia-with-aerobic-gram-neg-rod-suggests-pseudomonas
    (:belief 0.5
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("High Rate of Inappropriate Antibiotics in Patients with Hematologic Malignancies and Pseudomonas aeruginosa Bacteremia following International Guideline Recommendations, PMC10434044"
                             "Clinical characteristics and outcomes of Pseudomonas aeruginosa bacteremia in febrile neutropenic children and adolescents, PMC5513208")
                  :belief-basis :illustrative
                  :note "P. aeruginosa is among the most severe bloodstream pathogens in immunocompromised/neutropenic patients, and empiric antipseudomonal beta-lactam cover is standard in febrile neutropenia. WEAKEST CITATION IN THE CORPUS, flagged deliberately: the sources support 'antipseudomonal cover is standard in febrile neutropenia', which is adjacent to but NOT identical with 'a gram-negative rod in a neutropenic patient is more likely to be Pseudomonas'. Held to 0.5 for that reason."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (neutropenia (value t) (of ?p))
  =>
  (assert (organism-identity (value :pseudomonas) (of ?o))))

;; Prosthetic material + a coagulase-negative staphylococcus is the classic
;; device-associated biofilm infection. Composes to 0.7*0.6 = 0.42.
(defrule prosthetic-material-with-coagulase-neg-staph-suggests-staph-epidermidis
    (:belief 0.6
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf / StatPearls, Staphylococcus epidermidis Infection, NBK563240")
                  :belief-basis :illustrative
                  :note "Patients with prosthetic valves, cardiac devices, central lines and catheters are at highest risk of coagulase-negative staphylococcal infection; the organisms travel the device and form protective biofilms. Up to 40% of prosthetic valve endocarditis is coagulase-negative staphylococcal."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (organism-class (value :staphylococcus) (of ?o))
  (coagulase (value negative) (of ?o))
  (prosthetic-material (value t) (of ?p))
  =>
  (assert (organism-identity (value :staphylococcus-epidermidis) (of ?o))))

;; Injection drug use shifts a staphylococcus toward S. aureus. No coagulase premise:
;; this is a clinical prior, deliberately usable before the biochemistry is back.
;; Composes to 0.7*0.55 = 0.385.
(defrule iv-drug-use-with-staphylococcus-suggests-staph-aureus
    (:belief 0.55
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("Microbial Epidemiology of Infectious Endocarditis in the Intravenous Drug Abuse Population, PMC6374230"
                             "NCBI Bookshelf / StatPearls, Tricuspid Valve Endocarditis, NBK538423")
                  :belief-basis :illustrative
                  :note "S. aureus is the most common pathogen in serious injection-drug-use-related infection, estimated at 60-70% of infective endocarditis cases in this population versus under a third in non-users."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (organism-class (value :staphylococcus) (of ?o))
  (iv-drug-use (value t) (of ?p))
  =>
  (assert (organism-identity (value :staphylococcus-aureus) (of ?o))))

;; A beta-hemolytic streptococcus in a neonate is group B until proven otherwise.
;; The strongest host factor in the set at 0.7; composes to 0.7*0.7 = 0.49.
(defrule neonate-with-beta-hemolytic-strep-suggests-strep-agalactiae
    (:belief 0.7
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("CDC MMWR RR-59-10, Prevention of Perinatal Group B Streptococcal Disease"
                             "NCBI Bookshelf / StatPearls, Group B Streptococcus and Pregnancy, NBK482443"
                             "CDC Active Bacterial Core surveillance, Early-Onset Neonatal Sepsis Surveillance and Trends")
                  :belief-basis :illustrative
                  :note "Group B Streptococcus (S. agalactiae) remains the leading cause of early-onset neonatal sepsis. Scoped honestly: GBS leads in TERM infants, while E. coli is the commonest cause in preterm infants, so this rule keys on the neonatal age group rather than claiming to cover all neonatal sepsis."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (organism-class (value :streptococcus) (of ?o))
  (hemolysis (value beta) (of ?o))
  (age-group (value neonate) (of ?p))
  =>
  (assert (organism-identity (value :streptococcus-agalactiae) (of ?o))))

;; A coagulase-negative staphylococcus from a urinary source shifts toward
;; S. saprophyticus. Composes to 0.7*0.65 = 0.455.
(defrule urinary-coagulase-neg-staph-suggests-staph-saprophyticus
    (:belief 0.65
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf / StatPearls, Staphylococcus saprophyticus Infection, NBK482367")
                  :belief-basis :illustrative
                  :note "S. saprophyticus is a common cause of uncomplicated urinary tract infection, predominantly in young sexually active women -- the one coagulase-negative staphylococcus with a characteristic clinical niche rather than a device association."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (organism-class (value :staphylococcus) (of ?o))
  (coagulase (value negative) (of ?o))
  (infection-site (value urinary) (of ?p))
  =>
  (assert (organism-identity (value :staphylococcus-saprophyticus) (of ?o))))
