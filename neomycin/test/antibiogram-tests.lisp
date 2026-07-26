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
