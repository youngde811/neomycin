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
  susceptibility)  ; belief that the covered organisms are sensitive

(defstruct (treat-item (:constructor make-treat-item))
  "An organism significant enough to require coverage (design doc 4.2)."
  organism         ; organism id
  belief)          ; its combined identification belief

(defstruct (exclusion (:constructor make-exclusion))
  "A drug that was ruled out, and why."
  drug
  reason)          ; :contraindication | :interaction

(defstruct (recommendation (:constructor make-recommendation))
  "The full therapy recommendation returned by a solver."
  (regimen '())          ; list of regimen-item
  (items-to-treat '())   ; list of treat-item
  (excluded '())         ; list of exclusion
  (uncovered '()))       ; organisms in U that no candidate drug could cover
                         ; (an honest failure surfaced, not a silent partial cover)

;;; ============================================================
;;; Policy dials (design doc 4.2)
;;;
;;; Stewardship policy dials, NOT clinical constants and NOT literature-sourced.
;;; Per-session tunable; conservative (low) covers more, aggressive (high) covers
;;; narrower. Defaults are defensible starting points, nothing more.
;;; ============================================================

(defvar *coverage-threshold* 0.2
  "Minimum organism belief/plausibility to place it on the must-treat list.")

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