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

(defun culture-2 (&key (runp t))
  "Second PAIP scenario (pg. 556): same burned, immunocompromised patient, but the
   Gram stain is ambiguous. Two conflicting GRAM facts are asserted with explicit
   belief values (0.8 for neg, 0.2 for pos), exercising the belief-system protocol
   on the fact side as well as the rule side. With an anaerobic gram-neg rod in the
   blood the bacteroides answer dominates (bel 0.841), while the gram-POSITIVE answer
   is disjoint from every gram-negative one and drives K to 0.679 -- a good workout
   for both combinators.

   The organism is an ANAEROBE, which is what makes this the scenario that exposed the
   Category B premise gap: the two pseudomonas context rules used to fire here, having
   never gated on aerobicity, and asserted an obligate aerobe against the bacteroides
   answer. Gating them dropped pseudomonas to bel 0.0 and K from 0.90 to 0.679. What
   is left is the stain ambiguity, which is all this scenario ever meant to test."
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

(defun culture-1b (&key (runp t))
  "culture-1 PLUS a hospital-acquired infection: the burn-ICU case from the
   2026-08-18 clinician session, and the sharpest form of a behaviour worth pinning.

   Learning `hospital-acquired' SUPPORTS klebsiella -- it fires a stronger, more
   specific rule (0.6) that subsumes the compromised-host-only one (0.5). Klebsiella's
   belief nonetheless FALLS, 0.194 -> 0.097, because the same fact also fires a third
   pseudomonas rule and the two compete for one unit of mass. SUPPORT and SHARE are
   different quantities and they move in opposite directions here.

   Far enough for the fall to cross the 0.1 coverage gate, so klebsiella stops being
   an item to treat -- which is also the only scenario in the corpus that exercises
   BELOW-THRESHOLD and its incidental-coverage reporting against real rules rather
   than a hand-built conclusion list."
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

(defun culture-5 (&key (runp t))
  "Host factors reinforcing a biochemical call (slice D): a beta-hemolytic,
   bacitracin-RESISTANT gram-pos coccus in chains from a NEONATE.

   Two independent paths reach S. agalactiae -- the biochemical one (beta +
   bacitracin-resistant, 0.7*0.7 = 0.49) and the host-factor one (neonate +
   beta-hemolytic, 0.7*0.7 = 0.49) -- and their masses COMBINE rather than one
   overriding the other, which is what a host factor is for. Contrast culture-4,
   where two paths reached mutually exclusive species and produced conflict instead.

   Bacitracin-resistant, so the group A rule does not fire and S. pyogenes never
   enters; the alpha-hemolysis disconfirmer is likewise silent on a beta reading."
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

