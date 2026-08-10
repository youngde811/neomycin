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

;; Description: One-hop gram-NEGATIVE identity rules -- raw evidence straight to a
;; leaf species, with no intermediate abstraction. These are the rules that never
;; needed a class: Pseudomonas and Bacteroides are not members of any family the
;; corpus models, so there is nothing for them to refine from.
;;
;; Contrast neomycin/rules/chain-*.lisp, where evidence derives a genus/family class
;; first and species refine off it.

(in-package :lisa-user)

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
