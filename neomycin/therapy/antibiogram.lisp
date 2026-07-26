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

;; Description: The antibiogram overlay -- empirical susceptibility interval width
;; from isolate counts (docs/antibiogram-overlay-design.md 3). This file is the
;; FOUNDATION: the pure counts -> interval mapping, built and tested in isolation
;; before any authoring (defantibiogram), kb-susceptibility wiring, or native
;; canonical-local combination is added.
;;
;; A site-local (organism, drug) -> (n-susceptible, n-tested) count becomes a
;; susceptibility interval whose ignorance shrinks as n grows: few isolates read as
;; provisional (wide), many as solid (narrow) -- BY CONSTRUCTION, not by hand.
;;
;; NOTE: NOT FOR CLINICAL USE. Any counts fed here are schematic, not real
;; surveillance data.

(in-package :neomycin-therapy)

(defparameter *antibiogram-concentration* 2.0
  "The Imprecise Dirichlet Model concentration σ -- the number of 'hidden trials'
   that governs how fast a count-derived susceptibility interval tightens as
   isolates accumulate (design doc 3). A policy knob, NOT a clinical constant:
   larger σ keeps small-n intervals wider (more cautious). σ = 1 is the light
   prior; σ = 2 is Walley's classic IDM default and neomycin's chosen value. Must
   be positive.")

(defun counts->interval (susceptible tested
                         &optional (sigma *antibiogram-concentration*))
  "Map an antibiogram count -- SUSCEPTIBLE of TESTED isolates -- to a belief-valued
   susceptibility interval via the Imprecise Dirichlet Model (design doc 3):

       bel = s / (n + σ)        pl = (s + σ) / (n + σ)        ignorance = σ / (n + σ)

   The interval is vacuous [0, 1] with no data (n = 0); its ignorance shrinks
   monotonically as n grows and → 0; and it brackets s/n, collapsing to that point
   as n → ∞. So few isolates read as provisional, many as solid -- the sample size
   is legible in the interval WIDTH.

   Returns a BELIEF:DS-BELIEF regardless of the active belief system. An
   antibiogram's data-sparseness is orthogonal to the CF-vs-DS *diagnostic* algebra
   (susceptibility-belief-design.md decision C): this reduction, its display, and
   its later combination must be native to susceptibility, never routed through
   BELIEF:*BELIEF-SYSTEM* -- so counts->interval builds the ds-belief directly."
  (check-type susceptible (integer 0))
  (check-type tested (integer 0))
  (assert (<= susceptible tested) (susceptible tested)
          "Antibiogram authoring error: susceptible (~D) cannot exceed tested (~D)."
          susceptible tested)
  (assert (plusp sigma) (sigma)
          "Antibiogram concentration σ must be positive; got ~S." sigma)
  (let* ((s (coerce susceptible 'single-float))
         (n (coerce tested 'single-float))
         (denom (+ n sigma)))
    (belief:make-ds-belief (/ s denom)
                           (/ (+ s sigma) denom))))

(defun susceptibility->ds-belief (susceptibility)
  "Coerce a susceptibility to a BELIEF:DS-BELIEF for combination: a ds-belief is
   itself; a raw scalar x is the degenerate point interval [x, x] (a fully
   committed probability, zero ignorance). Signals on anything else."
  (cond ((belief:ds-belief-p susceptibility) susceptibility)
        ((realp susceptibility)
         (let ((x (coerce susceptibility 'single-float)))
           (belief:make-ds-belief x x)))
        (t (error "Cannot combine susceptibility ~S: expected a real or a ~
                   BELIEF:DS-BELIEF." susceptibility))))

(defun combine-susceptibility (canonical local)
  "Combine a CANONICAL susceptibility with a count-derived LOCAL antibiogram
   interval (design doc 4) into one belief-valued susceptibility, via native
   Dempster combination (BELIEF:DS-COMBINE) on the frame 'this organism is
   susceptible to this drug'.

   The combination AUTO-SCALES with the local sample size, which is the whole
   point: a vacuous LOCAL interval (small n, ≈ [0, 1]) leaves CANONICAL essentially
   unchanged, while a sharp LOCAL interval (large n) dominates -- no threshold
   needed. NIL on either side means 'nothing to combine there': a missing LOCAL
   returns CANONICAL (the pre-overlay behavior); a missing CANONICAL returns LOCAL.

   Combined NATIVELY over ds-belief structs, never through BELIEF:*BELIEF-SYSTEM*
   (decision C): susceptibility handling -- reduction, display, AND combination --
   is orthogonal to the identification algebra, so this yields the same result
   under CF and DS. A scalar CANONICAL is treated as the degenerate interval [s, s]
   and combined; the alternative (short-circuit to LOCAL) is noted in design doc
   9.3, but degenerate-combine keeps the algebra uniform."
  (cond ((null local) canonical)
        ((null canonical) local)
        (t (belief:ds-combine (susceptibility->ds-belief canonical)
                              (susceptibility->ds-belief local)))))
