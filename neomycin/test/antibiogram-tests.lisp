;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: Golden tests for the antibiogram counts -> interval mapping
;; (docs/antibiogram-overlay-design.md 3 and 7). Pure-function tests: exercise the
;; Imprecise Dirichlet Model directly, with hand-computed [bel, pl] goldens at the
;; default concentration σ = 2, plus the requirement properties (vacuous at n = 0,
;; ignorance strictly decreasing in n, collapse toward s/n, sensitivity to σ, and
;; the authoring-error guard). No engine, no KB, no bridge. Reuses the LISA-TEST
;; harness (DEFTEST / IS / APPROX=). Counts are schematic -- NOT FOR CLINICAL USE.

(in-package "LISA-TEST")

(defun iv-bel (iv) (belief:ds-belief-bel iv))
(defun iv-pl  (iv) (belief:ds-belief-pl iv))
(defun iv-ign (iv) (belief:ds-ignorance iv))

;;; ------------------------------------------------------------------
;;; Requirement 1: no data (n = 0) is vacuous [0, 1] -- total ignorance.
;;; ------------------------------------------------------------------

(deftest antibiogram-no-data-is-vacuous ()
  (let ((iv (therapy:counts->interval 0 0)))
    (is (approx= (iv-bel iv) 0.0) "n=0 -> bel = 0")
    (is (approx= (iv-pl iv) 1.0) "n=0 -> pl = 1")
    (is (approx= (iv-ign iv) 1.0) "n=0 -> ignorance = 1 (fully vacuous)")))

;;; ------------------------------------------------------------------
;;; Golden [bel, pl] at the default σ = 2 (design doc 3 worked example).
;;;   (34, 50): bel = 34/52 = 0.653846, pl = 36/52 = 0.692308
;;; ------------------------------------------------------------------

(deftest antibiogram-golden-mid-sample ()
  (let ((iv (therapy:counts->interval 34 50)))       ; σ = 2 default
    (is (approx= (iv-bel iv) 0.653846) "34/50: bel = 34/52")
    (is (approx= (iv-pl iv) 0.692308) "34/50: pl = 36/52")
    (is (approx= (iv-ign iv) 0.038462) "34/50: ignorance = 2/52")))

;;; ------------------------------------------------------------------
;;; Requirement 3 (edges): large n collapses the interval toward s/n.
;;;   s = n large -> narrow near 1;  s = 0 large -> narrow near 0.
;;; ------------------------------------------------------------------

(deftest antibiogram-all-susceptible-narrow-near-1 ()
  (let ((iv (therapy:counts->interval 40 40)))       ; bel 40/42, pl 42/42
    (is (approx= (iv-bel iv) 0.952381) "40/40: bel = 40/42")
    (is (approx= (iv-pl iv) 1.0) "40/40: pl = 1")
    (is (< (iv-ign iv) 0.05) "40/40: narrow interval near 1")))

(deftest antibiogram-none-susceptible-narrow-near-0 ()
  (let ((iv (therapy:counts->interval 0 40)))        ; bel 0/42, pl 2/42
    (is (approx= (iv-bel iv) 0.0) "0/40: bel = 0")
    (is (approx= (iv-pl iv) 0.047619) "0/40: pl = 2/42")
    (is (< (iv-ign iv) 0.05) "0/40: narrow interval near 0")))

(deftest antibiogram-large-n-collapses-to-ratio ()
  ;; 680/1000 (= 0.68) with σ = 2 -> interval tightly brackets 0.68.
  (let ((iv (therapy:counts->interval 680 1000)))
    (is (approx= (iv-bel iv) 0.678643) "680/1000: bel ≈ 0.6786")
    (is (approx= (iv-pl iv) 0.680639) "680/1000: pl ≈ 0.6806")
    (is (< (iv-ign iv) 0.002) "680/1000: ignorance ~ 0.002, near-collapsed")))

;;; ------------------------------------------------------------------
;;; Requirement 2: ignorance decreases strictly monotonically in n
;;; (same susceptibility ratio, growing sample). ignorance = σ/(n+σ).
;;; ------------------------------------------------------------------

(deftest antibiogram-ignorance-strictly-decreasing-in-n ()
  (let ((i2  (iv-ign (therapy:counts->interval 1 2)))     ; 2/4  = 0.5
        (i10 (iv-ign (therapy:counts->interval 5 10)))    ; 2/12 = 0.1667
        (i50 (iv-ign (therapy:counts->interval 25 50))))  ; 2/52 = 0.0385
    (is (> i2 i10) "more isolates -> less ignorance (2 -> 10)")
    (is (> i10 i50) "more isolates -> less ignorance (10 -> 50)")
    (is (approx= i2 0.5) "n=2 ignorance = σ/(n+σ) = 2/4")))

;;; ------------------------------------------------------------------
;;; σ sensitivity: a smaller concentration yields a narrower interval
;;; for the same counts (design doc 3: σ = 1 lighter than σ = 2).
;;; ------------------------------------------------------------------

(deftest antibiogram-sigma-controls-width ()
  (let ((wide (iv-ign (therapy:counts->interval 34 50 2)))   ; 2/52
        (narrow (iv-ign (therapy:counts->interval 34 50 1)))) ; 1/51
    (is (> wide narrow) "larger σ -> wider interval (more cautious)")
    (is (approx= narrow 0.019608) "σ=1: ignorance = 1/51")))

;;; ------------------------------------------------------------------
;;; Every interval is a well-formed ds-belief: 0 <= bel <= pl <= 1.
;;; ------------------------------------------------------------------

(deftest antibiogram-intervals-are-valid ()
  (dolist (sn '((0 0) (1 2) (34 50) (40 40) (0 40) (680 1000)))
    (let ((iv (therapy:counts->interval (first sn) (second sn))))
      (is (belief:ds-belief-p iv) "counts->interval returns a ds-belief")
      (is (<= 0.0 (iv-bel iv)) "bel >= 0")
      (is (<= (iv-bel iv) (iv-pl iv)) "bel <= pl")
      (is (<= (iv-pl iv) 1.0) "pl <= 1"))))

;;; ------------------------------------------------------------------
;;; Authoring guard: susceptible > tested is a data error, not a silent
;;; malformed interval.
;;; ------------------------------------------------------------------

(deftest antibiogram-rejects-s-greater-than-n ()
  (is (nth-value 1 (ignore-errors (therapy:counts->interval 10 5)))
      "susceptible > tested signals an error")
  (is (nth-value 1 (ignore-errors (therapy:counts->interval 3 5 0)))
      "non-positive σ signals an error"))

;;; ==================================================================
;;; combine-susceptibility: native Dempster combination of the canonical
;;; figure with the count-derived local interval (design doc 4 and 7).
;;; ==================================================================

;;; Golden DS combination. Canonical [0.6, 0.8] ⊕ local [0.65, 0.69]:
;;;   K = .6*.31 + .2*.65 = .316; norm = .684
;;;   bel = (.6*.65 + .6*.04 + .2*.65)/.684 = .544/.684 = 0.795322
;;;   pl  = 1 - (.2*.31 + .2*.04 + .2*.31)/.684 = 1 - .132/.684 = 0.807018
(deftest antibiogram-combine-golden ()
  (belief:use-system :dempster-shafer)
  (let ((c (therapy:combine-susceptibility (belief:make-ds-belief 0.6 0.8)
                                           (belief:make-ds-belief 0.65 0.69))))
    (is (approx= (iv-bel c) 0.795322) "combined bel = 0.795322")
    (is (approx= (iv-pl c) 0.807018) "combined pl = 0.807018")
    (is (< (iv-ign c) 0.02) "agreement sharpens the interval")))

;;; A vacuous local (n = 0 -> [0, 1]) leaves the canonical figure unchanged --
;;; the overlay's influence auto-scales to nothing when there are no isolates.
(deftest antibiogram-combine-vacuous-local-is-noop ()
  (belief:use-system :dempster-shafer)
  (let ((c (therapy:combine-susceptibility (belief:make-ds-belief 0.6 0.8)
                                           (therapy:counts->interval 0 0))))
    (is (approx= (iv-bel c) 0.6) "vacuous local: canonical bel preserved")
    (is (approx= (iv-pl c) 0.8) "vacuous local: canonical pl preserved")))

;;; A sharp local (large n) dominates a weak/uncertain canonical.
;;; canonical [0.3, 0.9] ⊕ local counts(900,1000)=[0.898204, 0.900200] -> ~[0.919, 0.920]
(deftest antibiogram-combine-sharp-local-dominates ()
  (belief:use-system :dempster-shafer)
  (let ((c (therapy:combine-susceptibility (belief:make-ds-belief 0.3 0.9)
                                           (therapy:counts->interval 900 1000))))
    (is (approx= (iv-bel c) 0.919046) "sharp local drives bel up to ~0.919")
    (is (approx= (iv-pl c) 0.920409) "sharp local drives pl to ~0.920")
    (is (< (iv-ign c) 0.005) "large-n local collapses the combined interval")))

;;; Decision C strikes a third time: combination must NOT route through
;;; *belief-system* -- identical result under CF and DS, and NO error under CF.
(deftest antibiogram-combine-is-algebra-independent ()
  (let ((canonical (belief:make-ds-belief 0.6 0.8))
        (local (therapy:counts->interval 34 50))
        ds cf)
    (belief:use-system :dempster-shafer)
    (setf ds (therapy:combine-susceptibility canonical local))
    (belief:use-system :certainty-factors)          ; must not error here
    (setf cf (therapy:combine-susceptibility canonical local))
    (is (belief:ds-belief-p cf) "combination yields a ds-belief even under CF")
    (is (approx= (iv-bel ds) (iv-bel cf)) "bel identical under CF and DS")
    (is (approx= (iv-pl ds) (iv-pl cf)) "pl identical under CF and DS")
    (belief:use-system :dempster-shafer)))          ; restore default

;;; NIL means 'nothing to combine there'; a scalar canonical is the degenerate
;;; interval [s, s] (design doc 9.3).
(deftest antibiogram-combine-nil-and-scalar ()
  (belief:use-system :dempster-shafer)
  (let ((canon (belief:make-ds-belief 0.6 0.8)))
    (let ((c (therapy:combine-susceptibility canon nil)))
      (is (and (approx= (iv-bel c) 0.6) (approx= (iv-pl c) 0.8))
          "missing local returns canonical unchanged"))
    (let ((c (therapy:combine-susceptibility nil canon)))
      (is (and (approx= (iv-bel c) 0.6) (approx= (iv-pl c) 0.8))
          "missing canonical returns local unchanged")))
  ;; scalar canonical 0.9 -> [0.9, 0.9] ⊕ [0.6, 0.8] = [0.947368, 0.947368]
  (let ((c (therapy:combine-susceptibility 0.9 (belief:make-ds-belief 0.6 0.8))))
    (is (belief:ds-belief-p c) "scalar canonical combines to a ds-belief")
    (is (approx= (iv-bel c) 0.947368) "scalar canonical (degenerate [s,s]) dominates")))
