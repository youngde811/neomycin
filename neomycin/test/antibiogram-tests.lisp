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
;;; combine-susceptibility: BAYESIAN pooling of the canonical figure (a Beta
;;; prior whose strength is set by its width) with the count-derived local
;;; interval (design doc 4 and 7).
;;; ==================================================================

;;; Golden. Canonical [0.6, 0.8] is a prior worth (6, 8) pseudo-counts; local
;;; counts (34, 50) pool to (40, 58) -> IDM interval [40/60, 42/60].
(deftest antibiogram-combine-golden ()
  (let ((c (therapy:combine-susceptibility (belief:make-ds-belief 0.6 0.8)
                                           (therapy:counts->interval 34 50))))
    (is (approx= (iv-bel c) 0.666667) "pooled bel = 40/60")
    (is (approx= (iv-pl c) 0.700000) "pooled pl = 42/60")))

;;; A vacuous local (n = 0 -> [0, 1], zero prior strength) leaves the canonical
;;; figure EXACTLY unchanged -- the overlay auto-scales to nothing with no isolates.
(deftest antibiogram-combine-vacuous-local-is-noop ()
  (let ((c (therapy:combine-susceptibility (belief:make-ds-belief 0.6 0.8)
                                           (therapy:counts->interval 0 0))))
    (is (approx= (iv-bel c) 0.6) "vacuous local: canonical bel preserved")
    (is (approx= (iv-pl c) 0.8) "vacuous local: canonical pl preserved")))

;;; A large local sample dominates a weak, wide canonical (worth ~1 pseudo-obs):
;;; canonical [0.3, 0.9] ⊕ counts(900, 1000) -> ~[0.898, 0.900], AT the local ratio
;;; 0.90, not inflated past it.
(deftest antibiogram-combine-sharp-local-dominates ()
  (let ((c (therapy:combine-susceptibility (belief:make-ds-belief 0.3 0.9)
                                           (therapy:counts->interval 900 1000))))
    (is (approx= (iv-bel c) 0.898006) "large-n local drives bel to ~0.898")
    (is (approx= (iv-pl c) 0.900000) "and pl to the local ratio 0.900")
    (is (< (iv-ign c) 0.005) "large-n local collapses the combined interval")))

;;; The property Dempster's rule INVERTED: a local antibiogram showing majority
;;; RESISTANCE pulls the estimate DOWN. Canonical [0.64, 0.88] (prior ~(5.33, 6.33))
;;; ⊕ counts(18, 40) = 45% susceptible -> [0.483, 0.524], now below the 0.5 gate.
(deftest antibiogram-combine-local-resistance-pulls-down ()
  (let ((c (therapy:combine-susceptibility (belief:make-ds-belief 0.64 0.88)
                                           (therapy:counts->interval 18 40))))
    (is (approx= (iv-bel c) 0.482759) "local resistance drops bel below the 0.5 gate")
    (is (approx= (iv-pl c) 0.524138) "and pulls the ceiling toward local")
    (is (< (iv-bel c) 0.64) "combined bel is BELOW canonical -- not inflated above it")))

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

;;; NIL means 'nothing to combine there'; a scalar canonical (no stated
;;; uncertainty) short-circuits to the empirical local interval (design doc 9.3).
(deftest antibiogram-combine-nil-and-scalar ()
  (let ((canon (belief:make-ds-belief 0.6 0.8)))
    (let ((c (therapy:combine-susceptibility canon nil)))
      (is (and (approx= (iv-bel c) 0.6) (approx= (iv-pl c) 0.8))
          "missing local returns canonical unchanged"))
    (let ((c (therapy:combine-susceptibility nil canon)))
      (is (and (approx= (iv-bel c) 0.6) (approx= (iv-pl c) 0.8))
          "missing canonical returns local unchanged")))
  (let ((c (therapy:combine-susceptibility 0.9 (belief:make-ds-belief 0.6 0.8))))
    (is (belief:ds-belief-p c) "scalar canonical yields the local ds-belief")
    (is (and (approx= (iv-bel c) 0.6) (approx= (iv-pl c) 0.8))
        "scalar canonical short-circuits to the empirical local interval")))

;;; ==================================================================
;;; defantibiogram authoring + the site-local counts table (design doc 5).
;;; ==================================================================

(deftest antibiogram-authoring-roundtrip ()
  ;; defantibiogram populates *therapy-kb*; kb-antibiogram reads the raw count back.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:defantibiogram :pseudomonas :ciprofloxacin :susceptible 34 :tested 50)
    (is (equal (therapy:kb-antibiogram kb :pseudomonas :ciprofloxacin) '(34 . 50))
        "defantibiogram stores (susceptible . tested)")
    (is (null (therapy:kb-antibiogram kb :klebsiella :meropenem))
        "an unrecorded (organism,drug) pair reads back NIL")
    ;; re-authoring the same pair overwrites (idempotent reload)
    (therapy:defantibiogram :pseudomonas :ciprofloxacin :susceptible 40 :tested 50)
    (is (equal (therapy:kb-antibiogram kb :pseudomonas :ciprofloxacin) '(40 . 50))
        "re-authoring overwrites in place")))

(deftest antibiogram-authoring-rejects-bad-counts ()
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (is (nth-value 1 (ignore-errors
                       (therapy:add-antibiogram kb :pseudomonas :meropenem
                                                :susceptible 9 :tested 4)))
        "susceptible > tested is rejected at authoring time")))

(deftest antibiogram-data-is-opt-in ()
  ;; The schematic counts are NOT loaded into the canonical KB by default -- the
  ;; antibiogram is an opt-in, swappable layer (design doc 5).
  (is (null (therapy:kb-antibiogram therapy:*therapy-kb* :pseudomonas :ciprofloxacin))
      "canonical KB carries no antibiogram counts by default"))

(deftest antibiogram-data-file-loads-into-current-kb ()
  ;; Loading the data file overlays its counts onto the CURRENT *therapy-kb*; bind
  ;; that to a fixture so the load authors there, not into the canonical KB.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (load (asdf:system-relative-pathname
           "neomycin" "neomycin/therapy/antibiogram-data.lisp"))
    (is (equal (therapy:kb-antibiogram kb :pseudomonas :ciprofloxacin) '(34 . 50))
        "data file authors pseudomonas/ciprofloxacin into the current KB")
    (is (equal (therapy:kb-antibiogram kb :pseudomonas :meropenem) '(3 . 4))
        "data file authors the tiny-sample entry")
    (is (null (therapy:kb-antibiogram kb :bacteroides :metronidazole))
        "a pair with no local isolates has no entry")))

;;; ==================================================================
;;; kb-susceptibility overlay integration (design doc 5): a local count
;;; refines the curated figure; absence leaves it untouched.
;;; ==================================================================

(deftest antibiogram-kb-overlay-combines-when-present ()
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:add-sensitivity kb :pseudomonas :cip (belief:make-ds-belief 0.46 0.85))
    (therapy:add-antibiogram kb :pseudomonas :cip :susceptible 34 :tested 50)
    (let ((s (therapy:kb-susceptibility kb :cip :pseudomonas)))
      (is (belief:ds-belief-p s) "overlaid susceptibility is a ds-belief")
      ;; canonical [0.46,0.85] (Beta prior ~(2.36,3.13)) ⊕ counts(34,50)
      ;; -> pooled (36.36,53.13) -> [0.6595, 0.6958]
      (is (approx= (iv-bel s) 0.659527) "local data lifts bel above the 0.5 gate")
      (is (approx= (iv-pl s) 0.695807) "toward the local 68% ratio"))))

(deftest antibiogram-kb-overlay-absent-returns-canonical ()
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:add-sensitivity kb :klebsiella :mero (belief:make-ds-belief 0.88 0.99))
    ;; no antibiogram entry for this pair -> curated figure returned unchanged
    (let ((s (therapy:kb-susceptibility kb :mero :klebsiella)))
      (is (and (approx= (iv-bel s) 0.88) (approx= (iv-pl s) 0.99))
          "no local count -> curated figure unchanged"))))

(deftest antibiogram-kb-overlay-local-only-is-empirical ()
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    ;; a local count but NO curated figure -> the empirical interval itself
    (therapy:add-antibiogram kb :pseudomonas :newdrug :susceptible 40 :tested 40)
    (let ((s (therapy:kb-susceptibility kb :newdrug :pseudomonas)))
      (is (belief:ds-belief-p s) "local-only susceptibility is the IDM interval")
      (is (approx= (iv-bel s) 0.952381) "40/40 -> bel 40/42")
      (is (approx= (iv-pl s) 1.0) "40/40 -> pl 1"))))

(deftest antibiogram-kb-overlay-live-on-canonical ()
  ;; End-to-end over an explicitly-overlaid KB: author the schematic cipro count
  ;; onto a copy of the canonical figure and confirm kb-susceptibility promotes
  ;; pseudomonas/ciprofloxacin from the [PROVISIONAL] canonical [0.46, 0.85] (bel
  ;; below the 0.5 gate) to a covering interval.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:add-sensitivity kb :pseudomonas :ciprofloxacin (belief:make-ds-belief 0.46 0.85))
    (therapy:add-antibiogram kb :pseudomonas :ciprofloxacin :susceptible 34 :tested 50)
    (let ((cip (therapy:kb-susceptibility kb :ciprofloxacin :pseudomonas)))
      (is (belief:ds-belief-p cip) "overlaid susceptibility is a ds-belief")
      (is (approx= (iv-bel cip) 0.659527) "local count promotes bel above the gate")
      (is (approx= (iv-pl cip) 0.695807) "toward the local ratio"))
    ;; a pair with a curated figure but NO local count is unchanged
    (therapy:add-sensitivity kb :staphylococcus :vancomycin (belief:make-ds-belief 0.88 0.99))
    (let ((van (therapy:kb-susceptibility kb :vancomycin :staphylococcus)))
      (is (and (approx= (iv-bel van) 0.88) (approx= (iv-pl van) 0.99))
          "no local count -> canonical unchanged"))))
