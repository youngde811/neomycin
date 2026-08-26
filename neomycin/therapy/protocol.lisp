;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.

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

;; Description: The pluggable therapy-solver protocol (design doc 4.5), modelled
;; on the belief-system protocol in src/belief-systems/protocol.lisp. A solver
;; turns identification conclusions + the therapy KB + patient state into an
;; auditable RECOMMENDATION. Implementations register themselves and are selected
;; with USE-SOLVER, so a new solver drops in without editing this file.

(in-package :neomycin-therapy)

;;; ============================================================
;;; Recommendation object (the auditable result; design doc 4.4)
;;;
;;; Every field is a fact a reviewer can audit and the LLM can narrate.
;;; Nothing here is inferred by a model.
;;; ============================================================

(defstruct (regimen-item (:constructor make-regimen-item))
  "One drug chosen for the regimen."
  drug             ; drug identifier
  dose             ; dose from the drug's (simulated) dosing model
  covers           ; list of organism ids this drug covers
  susceptibility)  ; list of SUSCEPTIBILITY-ITEM, one per covered organism

(defstruct (susceptibility-item (:constructor make-susceptibility-item))
  "One covered organism's susceptibility to a regimen drug, with antibiogram
   PROVENANCE so the interval's pedigree is narratable, not just its bounds
   (design doc 6)."
  organism         ; organism id
  value            ; the (possibly overlaid) belief-valued susceptibility
  n-tested         ; local antibiogram sample size (integer), or NIL if reference-only
  source)          ; :local-antibiogram (a local count contributed) | :reference

(defstruct (treat-item (:constructor make-treat-item))
  "An organism significant enough to require coverage (design doc 4.2)."
  organism         ; organism id
  belief)          ; its combined identification belief

(defstruct (exclusion (:constructor make-exclusion))
  "A drug that was ruled out, and why."
  drug
  reason)          ; :contraindication | :interaction

(defstruct (set-obligation (:constructor make-set-obligation))
  "A SET-valued conclusion the regimen must cover: 'one of these, the evidence does
   not say which', carrying enough mass to clear the coverage gate.

   WHY IT IS AN OBLIGATION IN ITS OWN RIGHT. A set answer used to be discarded the
   moment any ONE of its members cleared the gate, on the reasoning that the member
   'carries the coverage need'. It does not. Mass on {A..G} is mass committed to no
   member in particular, and covering A and B leaves it undischarged. Measured on the
   corpus: culture-1 puts 0.155 on the seven aerobic gram-negative rods, and the
   narrow regimens -- ceftazidime under spectrum-sparing, or under a carbapenem
   allergy -- miss Salmonella while reporting nothing uncovered.

   DISCHARGED MEMBER-WISE, never through a family. The KB's family roll-up exists so a
   species with no entry of its own inherits one; it is not a proxy for the whole set,
   and using it as one is what made the gap invisible. Ceftazidime covers
   :enterobacteriaceae at bel 0.66 and :salmonella at 0.46 -- against a 0.5 threshold
   the family reads covered and the member does not."
  members          ; the organisms the answer named
  mass             ; belief committed to the set without naming a member
  (uncovered '())) ; members the chosen regimen does not cover; NIL when fully covered

(defstruct (incidental-cover (:constructor make-incidental-cover))
  "A chosen drug that covers an organism the coverage gate DROPPED.

   Not part of why the drug was chosen -- the solver never considered this organism
   -- but a fact about the regimen it returned, and one a clinician needs."
  drug
  susceptibility)  ; SUSCEPTIBILITY-ITEM for that drug against that organism

(defstruct (below-threshold-item (:constructor make-below-threshold-item))
  "An organism in the differential that did NOT clear *coverage-threshold*, with
   whatever coverage the chosen regimen happens to give it anyway.

   WHY THIS EXISTS. The gate is a hard cut on a number the identification layer
   often reports as unstable, and the payload used to record only which side of it
   an organism landed on. So a case where Klebsiella sat at 0.097 against a 0.1 gate
   was narrated as `Klebsiella was not targeted' -- while the meropenem the solver
   returned covers Klebsiella at [0.88, 0.99]. Both halves were true and the
   conjunction was badly misleading: the clinician was told the runner-up was
   untreated when the drug on the page covers it well.

   The regimen is UNCHANGED by any of this. What changes is that the report no
   longer understates itself, and that a near-miss at the gate is visible as a near
   miss rather than as an absence."
  organism
  belief           ; its identification belief, as reported (interval or scalar)
  (covered-by '())); list of INCIDENTAL-COVER; empty when the regimen misses it

(defstruct (alternative-regimen (:constructor make-alternative-regimen))
  "Another regimen of the SAME minimum size the solver could have returned, but
   did not -- the objective's tiebreak chose against it.

   Reported because a tiebreak no clinician stated is not a clinical judgement, and
   presenting only the winner implies a decisiveness the solver does not have. Only
   an exhaustive search can populate this; a greedy search never learns what it
   passed over (exact-solver-design.md 4)."
  (drugs '()))           ; list of regimen-item, exactly as REGIMEN is shaped

(defstruct (recommendation (:constructor make-recommendation))
  "The full therapy recommendation returned by a solver."
  (regimen '())          ; list of regimen-item
  (items-to-treat '())   ; list of treat-item
  (excluded '())         ; list of exclusion
  (uncovered '())        ; organisms in U that no candidate drug could cover
                         ; (an honest failure surfaced, not a silent partial cover)
  ;; The gate's OTHER side. UNCOVERED is "we had to treat it and could not";
  ;; BELOW-THRESHOLD is "we chose not to treat it" -- together with what the
  ;; regimen covers there regardless. Solver-independent: a fact about the gate
  ;; and the KB, so both solvers report it.
  (below-threshold '()) ; list of BELOW-THRESHOLD-ITEM
  ;; Set-valued conclusions the regimen had to cover, each with any member it
  ;; missed. Emitted whether or not anything was missed: a fully-covered set is
  ;; the answer to "does this regimen cover the group you could not resolve?",
  ;; which is a question worth answering explicitly rather than by silence.
  (set-obligations '()) ; list of SET-OBLIGATION
  ;; The two "what else was possible" fields (exact-solver-design.md 1.1). Neither
  ;; is a recommendation: they exist so that "is there a narrower agent?" has a
  ;; truthful answer. Without them the payload contains only the winner, and a
  ;; reader -- human or LLM -- infers from its silence that nothing else covered.
  ;; That inference was drawn, stated to a clinician, and was false.
  (alternative-agents '())    ; list of regimen-item: candidate drugs NOT chosen that
                              ; nonetheless cover >= 1 treated organism. Solver-
                              ; independent -- a KB fact about the gated items, so
                              ; every solver reports it, greedy included.
  (alternative-regimens '())) ; list of alternative-regimen; exact search only

;;; ============================================================
;;; Policy dials (design doc 4.2)
;;;
;;; Stewardship policy dials, NOT clinical constants and NOT literature-sourced.
;;; Per-session tunable; conservative (low) covers more, aggressive (high) covers
;;; narrower. Defaults are defensible starting points, nothing more.
;;; ============================================================

(defvar *coverage-threshold* 0.1
  "Minimum organism belief to place it on the must-treat list.

   RECALIBRATED FOR v0.11 (was 0.2), and the reason is a change of scale, not a change
   of policy. Under the pre-v0.11 per-hypothesis representation each organism carried
   its own belief and they did not compete -- several could sit high at once. Under the
   candidate-set shape they share one unit of mass, so individual beliefs are
   systematically LOWER for the same evidence. 0.2 was therefore stricter than it had
   been, without anyone deciding it should be: in culture-1 Klebsiella fell from 0.286
   to 0.194 and dropped out of empiric cover by 0.006.

   THE PLATEAU ARGUMENT THAT USED TO SIT HERE WAS WITHDRAWN AT v0.14, because it had
   become false. It read: 0.1 IS NOT A TASTE, it is where the corpus is flat ... this
   gate decides exactly five figures -- 0.242, 0.228, 0.194, 0.153 and 0.101. Nothing
   else in the corpus is affected by any value between 0.05 and 0.20.

   Not one of those five figures still exists. Category B replaced every epidemiological
   singleton with a graded answer, which moved every runner-up in the corpus, and the
   claim was never re-measured. Re-measured now, across all eight drivers and counting
   both organism beliefs and set-valued masses (38 gated figures):

     gate 0.05 -> 31 of 38 clear      gate 0.125 -> 20
     gate 0.075 -> 25                 gate 0.15  -> 18
     gate 0.10  -> 23                 gate 0.20  -> 14

   THE CORPUS IS NOT FLAT ACROSS THAT RANGE. Moving the dial from 0.05 to 0.20 changes
   the outcome for seventeen of thirty-eight figures. This gate decides real things, and
   any future statement about it should be measured rather than inherited.

   WHAT IS STILL TRUE OF 0.1: it sits in a gap rather than on an edge. The nearest gated
   figures are 0.0900 below and 0.1050 above, so a small movement in the belief scale
   will not silently flip it. That property was briefly LOST -- between v0.13 and v0.14
   culture-1a's Pseudomonas sat at exactly 0.1000, on the boundary, which is what made
   the single/double float-comparison bug reachable at all (see CLEARS-GATE-P). The
   belief-coherence fix moved it to 0.12 and restored the gap.

   The value is also deliberately INCLUSIVE, which is the right direction for EMPIRIC
   therapy -- the cost of covering a runner-up is breadth, and the cost of missing it is
   an untreated organism. That is a policy argument and it is the honest basis for the
   number; the plateau was never the whole reason and is no longer any of it.

   THE GATE NOW READS SETS TOO, and against the same number. Belief committed to a
   SET rather than an organism used to be invisible to it: in the respiratory strep
   case the largest single focal mass in the differential -- 0.368 on {E. faecalis,
   E. faecium} -- belongs to organisms whose individual Bel is 0.000, so no value of
   this threshold reached them. A set clearing this gate is now a coverage obligation
   in its own right, discharged member by member (see SET-OBLIGATION). That was a gap
   in the gate's SHAPE rather than its value, which is why lowering the number would
   never have fixed it.

   Set masses are counted in the re-measurement above rather than argued about
   separately, which is the correction the old text needed: it treated them as a side
   note on the grounds that none sat near 0.1, and that was checked against figures the
   corpus no longer produces.")

(defvar *susceptibility-threshold* 0.5
  "Minimum susceptibility for a drug to count as covering an organism.")

(defvar *susceptibility-gate* :belief
  "Which point of a belief-valued susceptibility interval the coverage gate reads
   (susceptibility-belief-design.md 5) -- a STEWARDSHIP dial, not a clinical
   constant. Only affects belief-valued (DS-interval) susceptibilities; a bare
   scalar reduces to itself under every setting.

     :belief       -- conservative (DEFAULT): gate on `bel` (lower bound). Count a
                      drug as covering only when we are confident it is susceptible;
                      wide ignorance makes coverage HARDER.
     :plausibility -- optimistic: gate on `pl` (upper bound). Count it as covering
                      unless there is evidence against; wide ignorance makes
                      coverage EASIER.
     :midpoint     -- gate on (bel + pl) / 2, a middle ground.

   The same case and KB can yield different regimens under different gates, and the
   divergence is legible precisely because the interval is explicit -- a question
   the certainty-factor world cannot even pose.")

(defvar *objective* :lexicographic
  "Which objective the exact solver optimises among minimum-size regimens -- the
   THIRD policy dial, alongside BELIEF:*BELIEF-SYSTEM* and *SUSCEPTIBILITY-GATE*
   (exact-solver-design.md 3.5). Cardinality is primary under both settings; this
   chooses only how ties on drug count are broken.

     :lexicographic    -- DEFAULT. Maximise summed susceptibility x identification
                          belief, then drug name. This is the greedy solver's
                          policy, promoted from an implementation detail to a
                          declared one. It is NOT stewardship: it has no notion of
                          spectrum, and because breadth correlates with
                          susceptibility by construction it tends to pick the
                          broadest agent available (1, 1.1).
     :spectrum-sparing -- Minimise summed declared spectrum breadth, then fall back
                          to the above. Implements the narrow-spectrum preference
                          the project had claimed but never built. NARROW IS NOT
                          CHEAP: see the reserve-status warning below.
     :stewardship      -- Minimise summed WHO AWaRe rank (Access < Watch < Reserve),
                          then fall back to the above. The axis :spectrum-sparing
                          cannot see, added after a live consultation showed the gap
                          (3.7).

   Turning this dial CHANGES THE RECOMMENDATION, and sometimes toward a drug a
   clinician would reject: with the canonical tiers it prefers gentamicin
   monotherapy for gram-negative bacteraemia, which is narrower and not better
   (measured in 3.6). That was shipped knowingly rather than patched -- a dial that
   visibly does the wrong thing for a stateable reason is more honest than one
   quietly constrained until it looks sensible. The narration MUST state the trade;
   it must never present a spectrum-sparing regimen as simply better.

   Spectrum breadth is also blind to RESERVE status: vancomycin and linezolid are
   narrow-spectrum and are exactly the agents a steward holds back. Do not read a
   low summed breadth as low stewardship cost -- that is what :stewardship is for,
   and the two dials disagree in exactly the cases that matter. On a group A strep
   with no contraindications, :spectrum-sparing returns VANCOMYCIN (Watch) because
   vancomycin, nafcillin and linezolid tie in the :narrow tier; :stewardship returns
   ampicillin (Access), which is the clinically standard choice.

   WHAT NONE OF THESE DIALS CAN DO: cardinality is primary under all three, so no
   objective can prefer TWO Access agents over ONE Reserve agent. Real stewardship
   sometimes wants exactly that. Expressing it would mean changing what the solver
   SEARCHES rather than how it breaks ties, and that is deliberately not done here --
   a dial with a stated limit is worth more than one that quietly approximates.")

;;; ============================================================
;;; Solver base class + protocol generic function
;;; ============================================================

(defclass solver ()
  ((name :initarg :name :reader solver-name))
  (:documentation "Base class for pluggable therapy solvers."))

(defvar *solver* nil
  "The active therapy solver. Set via USE-SOLVER.")

(defgeneric solve-regimen (solver conclusions kb patient)
  (:documentation
   "Return a RECOMMENDATION covering the significant organisms in CONCLUSIONS,
    using the therapy knowledge base KB, subject to PATIENT contraindications and
    drug-drug interactions.

    CONCLUSIONS -- the identification results (organism-identity facts or a
                   digest), each with a belief from the active belief system.
    KB          -- the therapy knowledge base abstraction (drugs, sensitivities,
                   contraindications, interactions, dosing, antibiogram).
    PATIENT     -- patient-level state consulted for contraindications.

    Implementations MUST be deterministic and return an auditable object. The LLM
    narrates this result; it never chooses a drug."))

;;; ============================================================
;;; Registry + selector
;;;
;;; A hash registry (rather than the belief protocol's ECASE selector) so a new
;;; solver registers itself and becomes selectable without editing this file --
;;; the pluggability David asked for.
;;; ============================================================

(defvar *solvers* (make-hash-table :test #'eq)
  "Registry mapping a solver keyword to a SOLVER instance.")

(defun register-solver (name solver)
  "Register SOLVER (a SOLVER instance) under keyword NAME, replacing any prior
   solver of that name."
  (check-type name keyword)
  (check-type solver solver)
  (setf (gethash name *solvers*) solver))

(defun available-solvers ()
  "The keywords of all registered solvers."
  (loop for k being the hash-keys of *solvers* collect k))

(defun use-solver (name)
  "Make the solver registered under keyword NAME the active solver."
  (let ((s (gethash name *solvers*)))
    (unless s
      (error "Unknown solver ~S. Registered: ~S" name (available-solvers)))
    (setf *solver* s)))

(defun recommend (conclusions kb patient)
  "Dispatch to the active solver (design doc 4.5). Signals an error if no solver
   has been selected."
  (unless *solver*
    (error "No therapy solver selected; call (neomycin-therapy:use-solver ...) first."))
  (solve-regimen *solver* conclusions kb patient))