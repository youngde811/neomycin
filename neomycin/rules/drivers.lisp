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

;; Description: Demonstration scenarios. Each asserts a patient -> culture -> organism
;; lineage by ID and then the clinical parameters scoped to it.

(in-package :lisa-user)

;;; ------------------------------------------------------------------
;;; Demonstration scenarios. Each asserts a patient -> culture -> organism
;;; lineage (by ID) and then the clinical parameters scoped to it.
;;; ------------------------------------------------------------------
(defun culture-1 (&key (runp t))
  "First PAIP scenario (pg. 555): aerobic gram-neg rod cultured from the blood of a
   seriously burned, immunocompromised patient. Evidence enters at full belief.

   Four answers, and NOTHING IS EXCLUDED, because the only evidence is a stain and two
   patient facts. Two flat answers state what the stain narrows to -- the eight
   gram-negatives (0.70) and the seven AEROBIC gram-negative rods (0.80) -- and two
   GRADED epidemiological answers rank inside that set without excluding anyone: burn
   leans to pseudomonas, compromised-host to e-coli.

   The differential (K = 0.1800): e-coli 0.2322/0.5639, pseudomonas 0.1756/0.4683,
   klebsiella 0.1649/0.4576, enterobacter 0.0293/0.3805. Bacteroides keeps a
   plausibility of 0.0585 -- an obligate anaerobe is not admitted by the aerobic
   answer, and what is left is the residue on Theta.

   0.234 sits on the seven-member aerobic-gram-negative-rod SET without naming a
   member, which is often the honest headline: EPIDEMIOLOGY RANKS, IT DOES NOT
   IDENTIFY."
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

   The scenario where COMBINATION ADDS NOTHING, and that is the lesson. Five answers
   are asserted; three survive. Both dropped rules are gram-negative context rules
   SUBSUMED by a more specific one -- `compromised' and `hospital-acquired' each have
   premises that are a strict subset of `hospital-acquired-compromised', so they fire
   whenever it does and condition on nothing extra. (Verify with
   NEOMYCIN:SURVIVING-RULES-FOR; the evidence-group filter has nothing left to do here
   once subsumption has run.)

   What reaches the arithmetic is that one graded answer plus the two flat stain
   answers -- and those two are strict SUPERSETS of every focal set in the graded one,
   so intersecting changes nothing.

   So the differential IS the surviving rule's own distribution, unmodified --
   e-coli 0.2800/0.5800, klebsiella 0.2100/0.5100, pseudomonas 0.1200/0.4200 -- and
   K = 0.0000, because nothing disagreed with anything. The flat answers are not
   idle: they do not raise anyone's BELIEF (a coarse answer cannot) but they do bound
   PLAUSIBILITY, which is why bacteroides sits at 0.06 and salmonella at 0.30."
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

(defun culture-2-hedged (neg pos &key (runp t))
  "culture-2's scenario with the Gram stain hedged at NEG/POS.

   Parameterized because the hedge is the point: the two GRAM facts are asserted with
   explicit belief values, and the differential must MOVE when they change. It did not
   until v0.16 -- see the culture-2 docstring below and CANDIDATES-EVIDENCE-DISCOUNT."
  (reset)
  (assert (patient (id p1)))
  (assert (culture (id c1) (patient p1)))
  (assert (organism (id o1) (culture c1)))
  (assert (compromised-host (value t) (of p1)))
  (assert (burn (value serious) (of p1)))
  (assert (culture-site (value blood) (of c1)))
  (assert (culture-age (value 3) (of c1)))
  (assert (gram (value neg) (of o1)) :belief neg)
  (assert (gram (value pos) (of o1)) :belief pos)
  (assert (morphology (value rod) (of o1)))
  (assert (aerobicity (value anaerobic) (of o1)))
  (when runp
    (run)))

(defun culture-2 (&key (runp t))
  "Second PAIP scenario (pg. 556): same burned, immunocompromised patient, but the
   Gram stain is ambiguous. Two conflicting GRAM facts are asserted with explicit
   belief values (0.8 for neg, 0.2 for pos), exercising the belief-system protocol
   on the fact side as well as the rule side. With an anaerobic gram-neg rod in the
   blood the bacteroides answer leads (bel 0.706, pl 0.980), while the gram-POSITIVE
   answer is disjoint from every gram-negative one and drives K to 0.1228.

   THE FACT SIDE WAS INERT UNTIL v0.16, and this scenario is the only one that could
   have shown it. Every rule's answer entered combination at the rule's own declared
   :belief -- 0.7 / 0.7 / 0.9 -- so the hedge reached the CANDIDATES facts (0.56 /
   0.14 / 0.72) and stopped there. The differential was bit-identical whether the
   clinician called the stain 80% negative, 50/50, or 80% POSITIVE, and the old
   goldens (bacteroides 0.841, K 0.679) were measuring only that two gram rules had
   both fired. Answers are now DISCOUNTED by the strength of the premises that fired
   them (neomycin:answer-mass-of), which is what moved these numbers and no others.

   The organism is an ANAEROBE, which is what makes this the scenario that exposed the
   Category B premise gap: the two pseudomonas context rules used to fire here, having
   never gated on aerobicity, and asserted an obligate aerobe against the bacteroides
   answer. Gating them dropped pseudomonas to bel 0.0. What is left is the stain
   ambiguity, which is all this scenario ever meant to test -- and now measures."
  (culture-2-hedged 0.8 0.2 :runp runp))

(defun culture-3 (&key (runp t))
  "Gram-pos cocci in chains from a respiratory site in a compromised host. K = 0.5250.

   Morphology alone cannot separate the streptococci from the enterococci, so the
   chain-former answer names ALL SIX and says so. A graded respiratory answer then
   ranks inside that set without excluding the enterococci, which keep a plausibility
   of 0.5263 on no belief at all -- the highest plausibility in the scenario, and a
   good illustration that Pl is not a ranking.

   The differential: pneumoniae 0.2842/0.4421, viridans 0.1263/0.2842, pyogenes
   0.0632/0.2211. The headline sits on a SET, and naming a single organism here would
   be the wrong answer. Contrast culture-4, which has HIGHER conflict and is far more
   decided -- K is not a reliability score."
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

(defun culture-1b (&key (runp t))
  "culture-1 PLUS a hospital-acquired infection: the burn-ICU case from the
   2026-08-18 clinician session. K = 0.2072.

   ITS ORIGINAL HEADLINE NO LONGER REPRODUCES, and the reason is worth keeping. At
   v0.12 this case showed klebsiella gaining SUPPORT from `hospital-acquired' while its
   Bel FELL across the coverage gate -- support and share moving in opposite
   directions. That collapse needed {klebsiella} and {pseudomonas} to be disjoint
   SINGLETONS fighting over one unit of mass. Graded answers overlap, so klebsiella now
   RISES on the same fact: 0.1649 (culture-1) -> 0.2040 here.

   Support and share are still different quantities, and the case that still shows it
   is E-COLI across culture-1a -> culture-1b. Adding the burn fact brings a NEW answer
   that admits e-coli, so its ADMITTING MASS rises 3.50 -> 3.90 -- the total belief
   across every answer whose support admits it, summed BEFORE combination, which is why
   it exceeds 1 (see ADMITTING-MASS in candidates-tests.lisp). Its Bel nonetheless
   FALLS, 0.2800 -> 0.2402, because the same fact gave Pseudomonas far more: 0.20 on a
   singleton against e-coli's 0.08 share of a triple. The margin moves the same way,
   0.0700 -> 0.0362 -- the differential BLURS toward a three-way tie rather than
   sharpening. Gaining evidence is not winning, and it is not even clarity.

   Full differential: e-coli 0.2402/0.4975, klebsiella 0.2040/0.4310, pseudomonas
   0.1968/0.4238, enterobacter 0.0246/0.3198. `below_threshold' is still exercised
   against real rules rather than a hand-built conclusion list -- now by enterobacter
   at 0.0246, under the 0.1 coverage gate."
  (reset)
  (assert (patient (id p1)))
  (assert (culture (id c1) (patient p1)))
  (assert (organism (id o1) (culture c1)))
  (assert (burn (value serious) (of p1)))
  (assert (compromised-host (value t) (of p1)))
  (assert (hospital-acquired (value t) (of p1)))
  (assert (culture-site (value blood) (of c1)))
  (assert (gram (value neg) (of o1)))
  (assert (morphology (value rod) (of o1)))
  (assert (aerobicity (value aerobic) (of o1)))
  (when runp
    (run)))

(defun culture-multi (&key (runp t))
  "Two organisms in one culture, to exercise LINEAGE SCOPING. Each conclusion must
   stay on its own organism -- an unscoped morphology/gram join would cross-contaminate
   them, and this is the fixture that would catch it.

   o1 is an aerobic gram-neg rod and NOTHING ELSE, so it is the corpus's purest case of
   an answer that says nothing about any member: every gram-negative sits at bel 0.0000
   and pl 1.0000, with only bacteroides bounded (pl 0.2000) by the aerobic answer. A
   wide answer is not a weak answer about someone -- it is a firm answer about a
   coarser question, and there is no member to rank.

   o2 is a gram-pos coccus in clumps with a POSITIVE coagulase: staphylococcus-aureus
   at 0.8500/1.0000, with epidermidis and saprophyticus at 0.0000/0.1500. Both organisms
   run K = 0.0000."
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
  "Gram-positive differential: a beta-hemolytic, bacitracin-sensitive gram-pos coccus
   in chains from a patient with a respiratory infection site. K = 0.6256.

   THE BENCH OVERRULING EPIDEMIOLOGY, and the cleanest case of what high conflict
   actually means. The graded respiratory answer leans to S. pneumoniae (0.45 of its
   mass); the bench -- beta-hemolytic, bacitracin-sensitive -- narrows to
   {pyogenes, agalactiae} and then to {pyogenes}. A beta-hemolytic organism is not
   S. pneumoniae, which is alpha-hemolytic, and the arithmetic settles it without any
   rule arguing against anything: pyogenes 0.8347/0.9349, pneumoniae 0.0451/0.0701,
   viridans 0.0200/0.0451, agalactiae 0.0000/0.1002.

   K = 0.6256 IS THE EPIDEMIOLOGICAL ANSWER BEING OVERRULED, not instability. Read it
   with the margin, and against culture-3, whose LOWER conflict (0.5250) accompanies a
   far less decided picture. K rises as a winner strengthens; it is not a reliability
   score."
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

(defun culture-5 (&key (runp t))
  "Host factors REINFORCING a biochemical call: a beta-hemolytic, bacitracin-RESISTANT
   gram-pos coccus in chains from a NEONATE. K = 0.0000.

   Two independent paths reach S. agalactiae -- the biochemical one (beta-hemolytic and
   bacitracin-resistant) and the host-factor one (a neonate with a beta-hemolytic
   chain-former) -- and because they AGREE they reinforce rather than compete:
   agalactiae 0.9100/1.0000, the strongest identification in the corpus, at ZERO
   conflict. That is what a host factor is for, and it is the mirror image of culture-4,
   where two paths reached incompatible answers and the conflict is the whole story.

   Bacitracin-RESISTANT, so the group A rule never fires and S. pyogenes never enters;
   it holds no belief and a plausibility of 0.0900."
  (reset)
  (assert (patient (id p1)))
  (assert (culture (id c1) (patient p1)))
  (assert (organism (id o1) (culture c1)))
  (assert (culture-site (value blood) (of c1)))
  (assert (age-group (value neonate) (of p1)))
  (assert (gram (value pos) (of o1)))
  (assert (morphology (value coccus) (of o1)))
  (assert (growth-conformation (value chains) (of o1)))
  (assert (hemolysis (value beta) (of o1)))
  (assert (bacitracin (value resistant) (of o1)))
  (when runp
    (run)))


;;; ------------------------------------------------------------------
;;; Fact helpers for the evidence-group tests. Not scenarios: the redundant-evidence
;;; property is about which RULES contribute, so the test composes host factors onto a
;;; fixed gram-negative baseline rather than pinning a whole case.
;;; ------------------------------------------------------------------

(defun assert-lineage-for-test ()
  (assert (patient (id p1)))
  (assert (culture (id c1) (patient p1)))
  (assert (organism (id o1) (culture c1)))
  (assert (culture-site (value blood) (of c1)))
  (assert (gram (value neg) (of o1)))
  (assert (morphology (value rod) (of o1)))
  (assert (aerobicity (value aerobic) (of o1))))

(defun assert-compromised ()
  (assert (compromised-host (value t) (of p1))))

(defun assert-neutropenic ()
  (assert (neutropenia (value t) (of p1))))

