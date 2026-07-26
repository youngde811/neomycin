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

;; Description: The antibiogram overlay -- empirical susceptibility interval from
;; isolate counts, and its Bayesian combination with a curated figure
;; (docs/antibiogram-overlay-design.md 3-4).
;;
;; A site-local (organism, drug) -> (n-susceptible, n-tested) count becomes a
;; susceptibility interval whose ignorance shrinks as n grows (COUNTS->INTERVAL,
;; the Imprecise Dirichlet Model). When a curated figure also exists, the two are
;; combined by a BAYESIAN UPDATE (COMBINE-SUSCEPTIBILITY): the canonical interval
;; is a Beta PRIOR whose strength is encoded by its WIDTH, the local isolates are
;; observations, and the pooled counts yield the posterior interval.
;;
;; This replaced an earlier Dempster's-rule combination: on real examples Dempster
;; INFLATED susceptibility and INVERTED local resistance (a ward at 45% susceptible
;; combined *upward*), defeating the overlay's whole purpose. The Bayesian pooling
;; moves the estimate toward the local data, auto-scales with sample size, and
;; never inflates past both sources or inverts a resistance signal (design doc 4).
;;
;; NOT FOR CLINICAL USE. Any counts fed here are schematic, not real surveillance.

(in-package :neomycin-therapy)

(defparameter *antibiogram-concentration* 2.0
  "The Imprecise Dirichlet Model concentration σ -- the number of 'hidden trials'
   that governs how fast a count-derived susceptibility interval tightens as
   isolates accumulate (design doc 3). A policy knob, NOT a clinical constant:
   larger σ keeps small-n intervals wider (more cautious). σ = 1 is the light
   prior; σ = 2 is Walley's classic IDM default and neomycin's chosen value. Must
   be positive.")

(defun %idm-interval (susceptible tested sigma)
  "The core Imprecise Dirichlet Model interval for (possibly REAL) pseudo-counts:
   [s/(n+σ), (s+σ)/(n+σ)]. Real-valued so it serves both COUNTS->INTERVAL (integer
   isolate counts) and COMBINE-SUSCEPTIBILITY (pooled prior + data pseudo-counts).
   Returns a BELIEF:DS-BELIEF built directly, so it is belief-system-agnostic."
  (let ((denom (+ tested sigma)))
    (belief:make-ds-belief (coerce (/ susceptible denom) 'single-float)
                           (coerce (/ (+ susceptible sigma) denom) 'single-float))))

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
   its combination are native to susceptibility, never routed through
   BELIEF:*BELIEF-SYSTEM*."
  (check-type susceptible (integer 0))
  (check-type tested (integer 0))
  (assert (<= susceptible tested) (susceptible tested)
          "Antibiogram authoring error: susceptible (~D) cannot exceed tested (~D)."
          susceptible tested)
  (assert (plusp sigma) (sigma)
          "Antibiogram concentration σ must be positive; got ~S." sigma)
  (%idm-interval susceptible tested sigma))

(defun interval->pseudocounts (interval &optional (sigma *antibiogram-concentration*))
  "Invert the IDM: recover the (susceptible, tested) pseudo-counts an INTERVAL is
   equivalent to, so a canonical figure can act as a Beta PRIOR that local counts
   update. For [b, p] with width w = p - b:  tested = σ(1-w)/w,  susceptible = b·σ/w.

   Exact inverse of %IDM-INTERVAL: counts->interval(s, n) round-trips to (s, n), and
   a canonical [b, p] recovers the prior strength its WIDTH encodes -- a narrow
   canonical is worth many pseudo-observations (a strong prior); a vacuous [0, 1] is
   worth none (no prior). A (near-)degenerate width is clamped so a zero-width
   interval becomes a very strong, but finite, prior. Returns (values susceptible
   tested) as reals."
  (let* ((bel (belief:ds-belief-bel interval))
         (pl (belief:ds-belief-pl interval))
         (w (max (- pl bel) 1.0e-4)))
    (values (/ (* bel sigma) w)
            (/ (* sigma (- 1.0 w)) w))))

(defun combine-susceptibility (canonical local
                               &optional (sigma *antibiogram-concentration*))
  "Combine a CANONICAL susceptibility with a count-derived LOCAL antibiogram interval
   (design doc 4) by a BAYESIAN UPDATE: the canonical figure is a Beta PRIOR and the
   local isolates are observations. Both intervals are inverted to pseudo-counts
   (INTERVAL->PSEUDOCOUNTS), POOLED, and turned back into an IDM interval.

   This gives what Dempster's rule failed to: local data moves the estimate TOWARD
   itself and its influence AUTO-SCALES with sample size, without ever inflating past
   both sources or inverting a local resistance signal. A vacuous local (n ≈ 0)
   leaves the canonical unchanged (exact round-trip); a large local sample dominates
   a wide canonical; a solid narrow canonical resists a thin local sample -- because
   the canonical's WIDTH sets its prior strength.

   Belief-system-agnostic (decision C): pure arithmetic over ds-belief bounds, no
   *belief-system* dispatch, so the result is identical under CF and DS. NIL on
   either side returns the other. A scalar CANONICAL (no stated uncertainty) is a
   weak reference we short-circuit past to the empirically-grounded LOCAL interval
   (design doc 9.3)."
  (cond ((null local) canonical)
        ((null canonical) local)
        ((not (belief:ds-belief-p canonical)) local)
        (t (multiple-value-bind (sc nc) (interval->pseudocounts canonical sigma)
             (multiple-value-bind (sl nl) (interval->pseudocounts local sigma)
               (%idm-interval (+ sc sl) (+ nc nl) sigma))))))
