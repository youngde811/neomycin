;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: Fixture-based tests for the therapy solver (design doc 8). Each
;; test builds a small synthetic KB with the builder API and exercises the greedy
;; solver in isolation -- no real pharmacology data, no engine, no bridge -- so
;; the algorithm is verified against inputs we control exactly. Reuses the
;; dependency-free LISA-TEST harness (DEFTEST / IS). All pharmacology is schematic.
;;
;; Vocabulary is KEYWORDS throughout (organism and drug ids alike), matching the
;; engine's keyword organism-identity values so conclusions interoperate with the
;; therapy KB with no conversion. Fixture drug/organism ids (:broad, :cef, ...)
;; are synthetic; the canonical section exercises the real keyword vocabulary.

(in-package "LISA-TEST")

;;; Convenience: neomycin-therapy is nicknamed THERAPY.
(defun regimen-drugs (rec)
  (mapcar #'therapy:regimen-item-drug (therapy:recommendation-regimen rec)))

(defun treated (rec)
  (mapcar #'therapy:treat-item-organism (therapy:recommendation-items-to-treat rec)))

;;; ------------------------------------------------------------------
;;; Core greedy set cover (CF / plain-number susceptibilities & beliefs)
;;; ------------------------------------------------------------------

(deftest therapy-single-drug-covers-all ()
  ;; One broad agent covers every organism -> minimal 1-drug regimen.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:with-greedy-solver
      (therapy:add-drug kb :broad :dose "1g")
      (therapy:add-sensitivity kb :pseudomonas :broad 0.9)
      (therapy:add-sensitivity kb :enterobacteriaceae :broad 0.8)
      (therapy:add-sensitivity kb :klebsiella :broad 0.7)
      (let ((rec (therapy:recommend
                  '((:pseudomonas . 0.76) (:enterobacteriaceae . 0.80) (:klebsiella . 0.50))
                  kb '())))
        (is (equal '(:broad) (regimen-drugs rec)) "single broad drug chosen")
        (is (= 3 (length (treated rec))) "all three organisms are items to treat")
        (is (null (therapy:recommendation-uncovered rec)) "nothing left uncovered")))))

;;; ------------------------------------------------------------------
;;; KB family roll-up (chaining decision 4): a species with no sensitivity of its
;;; own inherits its family's figure; a species-specific entry overrides it.
;;; ------------------------------------------------------------------

(deftest therapy-family-rollup-inherits-and-overrides ()
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:add-drug kb :cef :dose "1g")
    (therapy:add-sensitivity kb :enterobacteriaceae :cef 0.8)   ; family figure
    (therapy:add-sensitivity kb :klebsiella :cef 0.6)           ; species-specific override
    (therapy:add-family-member kb :e-coli :enterobacteriaceae)
    (therapy:add-family-member kb :klebsiella :enterobacteriaceae)
    ;; e-coli has no entry of its own -> inherits the family's 0.8
    (is (= 0.8 (therapy:kb-susceptibility kb :cef :e-coli))
        "e-coli inherits the enterobacteriaceae family susceptibility")
    ;; klebsiella has its own entry -> that wins over the family (OR short-circuits)
    (is (= 0.6 (therapy:kb-susceptibility kb :cef :klebsiella))
        "a species-specific entry overrides the family figure")
    ;; an unmapped organism with no entry -> nil (no roll-up)
    (is (null (therapy:kb-susceptibility kb :cef :pseudomonas))
        "an unmapped organism with no entry has no susceptibility")
    ;; roll-up is per drug: family has no entry for :other -> nil even for a member
    (is (null (therapy:kb-susceptibility kb :other :e-coli))
        "roll-up yields nil when the family has no entry for that drug")))

(deftest therapy-disjoint-coverage-two-drugs ()
  ;; No single drug covers both a gram-neg and a gram-pos -> 2-drug regimen.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:with-greedy-solver
      (therapy:add-drug kb :cef :dose "1g")
      (therapy:add-drug kb :vanco :dose "1g")
      (therapy:add-sensitivity kb :pseudomonas :cef 0.9)
      (therapy:add-sensitivity kb :staphylococcus :vanco 0.95)
      (let* ((rec (therapy:recommend '((:pseudomonas . 0.7) (:staphylococcus . 0.7)) kb '()))
             (drugs (regimen-drugs rec)))
        (is (= 2 (length drugs)) "two-drug regimen")
        (is (and (member :cef drugs) (member :vanco drugs)) "both agents chosen")
        (is (null (therapy:recommendation-uncovered rec)) "full coverage")))))

(deftest therapy-belief-gate-drops-subthreshold ()
  ;; An organism below *coverage-threshold* is not an item to treat.
  ;;
  ;; The threshold is BOUND here rather than inherited. This test is about whether the
  ;; gate excludes what sits under it -- not about where the dial happens to be set --
  ;; and when the shipped default moved from 0.2 to 0.1 for v0.11 it silently redefined
  ;; this fixture's 0.1 from "clearly below" to "exactly at". Stating the premise keeps
  ;; a calibration decision from reading as a behavioural regression.
  (let ((therapy:*coverage-threshold* 0.2))
    (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
      (therapy:with-greedy-solver
        (therapy:add-drug kb :broad :dose "1g")
        (therapy:add-sensitivity kb :pseudomonas :broad 0.9)
        (therapy:add-sensitivity kb :klebsiella :broad 0.9)
        (let* ((rec (therapy:recommend '((:pseudomonas . 0.7) (:klebsiella . 0.1)) kb '()))
               (items (treated rec)))
          (is (member :pseudomonas items) "above-threshold organism treated")
          (is (not (member :klebsiella items)) "sub-threshold organism dropped from U")
          (is (equal '(:broad) (regimen-drugs rec)) "one drug for the one item"))))))

(deftest therapy-contraindication-forces-alternative ()
  ;; The most-sensitive drug is contraindicated -> the alternative is chosen and
  ;; the excluded drug is recorded with its reason.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:with-greedy-solver
      (therapy:add-drug kb :cef :dose "1g")
      (therapy:add-drug kb :alt :dose "1g")
      (therapy:add-sensitivity kb :pseudomonas :cef 0.95)
      (therapy:add-sensitivity kb :pseudomonas :alt 0.6)
      (therapy:add-contraindication kb :cef :allergy-cephalosporin)
      (let* ((rec (therapy:recommend '((:pseudomonas . 0.7)) kb '(:allergy-cephalosporin)))
             (drugs (regimen-drugs rec))
             (excl (mapcar #'therapy:exclusion-drug (therapy:recommendation-excluded rec))))
        (is (equal '(:alt) drugs) "alternative chosen")
        (is (not (member :cef drugs)) "contraindicated drug not used")
        (is (member :cef excl) "contraindicated drug recorded as excluded")))))

(deftest therapy-uncoverable-reported ()
  ;; An organism no drug covers is surfaced in UNCOVERED, not silently dropped;
  ;; the coverable organism is still treated.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:with-greedy-solver
      (therapy:add-drug kb :cef :dose "1g")
      (therapy:add-sensitivity kb :pseudomonas :cef 0.9)
      (let* ((rec (therapy:recommend '((:pseudomonas . 0.7) (:exotic . 0.7)) kb '()))
             (unc (therapy:recommendation-uncovered rec)))
        (is (member :exotic unc) "uncoverable organism reported")
        (is (not (member :pseudomonas unc)) "coverable organism not in uncovered")
        (is (member :cef (regimen-drugs rec)) "the coverable organism is still treated")))))

(deftest therapy-below-susceptibility-threshold-does-not-cover ()
  ;; A drug whose susceptibility is under *susceptibility-threshold* does not cover.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:with-greedy-solver
      (therapy:add-drug kb :weak :dose "1g")
      (therapy:add-sensitivity kb :pseudomonas :weak 0.3) ; < 0.5 default
      (let ((rec (therapy:recommend '((:pseudomonas . 0.7)) kb '())))
        (is (null (regimen-drugs rec)) "no drug clears the susceptibility threshold")
        (is (member :pseudomonas (therapy:recommendation-uncovered rec)) "organism uncovered")))))

(deftest therapy-deterministic-and-name-tiebreak ()
  ;; Equal coverage and weight -> tie broken by drug name (ascending); and the
  ;; result is identical across runs.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:with-greedy-solver
      (therapy:add-drug kb :zzz :dose "1g")
      (therapy:add-drug kb :aaa :dose "1g")
      (therapy:add-sensitivity kb :pseudomonas :zzz 0.9)
      (therapy:add-sensitivity kb :pseudomonas :aaa 0.9)
      (let ((r1 (therapy:recommend '((:pseudomonas . 0.7)) kb '()))
            (r2 (therapy:recommend '((:pseudomonas . 0.7)) kb '())))
        (is (equal (regimen-drugs r1) (regimen-drugs r2)) "same inputs -> identical regimen")
        (is (equal '(:aaa) (regimen-drugs r1)) "tie broken by name ascending (aaa before zzz)")))))

;;; ------------------------------------------------------------------
;;; Belief-valued path: susceptibilities/beliefs as Dempster-Shafer intervals
;;; reduce through the active belief system (design doc decision #3).
;;; ------------------------------------------------------------------

(deftest therapy-ds-interval-susceptibility ()
  (belief:use-system :dempster-shafer)
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:with-greedy-solver
      (therapy:add-drug kb :broad :dose "1g")
      ;; Strongly sensitive: bel 0.9. Reduces (via belief->number) to 0.9 >= 0.5.
      (therapy:add-sensitivity kb :pseudomonas :broad (belief:make-ds-belief 0.9 1.0))
      (let ((rec (therapy:recommend
                  (list (cons :pseudomonas (belief:make-ds-belief 0.7 1.0)))
                  kb '())))
        (is (equal '(:broad) (regimen-drugs rec)) "DS-interval susceptibility covers")
        (is (null (therapy:recommendation-uncovered rec)) "nothing uncovered under DS")))))

(deftest therapy-ds-weak-interval-does-not-cover ()
  (belief:use-system :dempster-shafer)
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:with-greedy-solver
      (therapy:add-drug kb :broad :dose "1g")
      ;; Weakly sensitive: bel 0.3 -> reduces to 0.3 < 0.5, no coverage.
      (therapy:add-sensitivity kb :pseudomonas :broad (belief:make-ds-belief 0.3 1.0))
      (let ((rec (therapy:recommend
                  (list (cons :pseudomonas (belief:make-ds-belief 0.7 1.0)))
                  kb '())))
        (is (null (regimen-drugs rec)) "low-belief interval does not cover")
        (is (member :pseudomonas (therapy:recommendation-uncovered rec)) "organism uncovered")))))

;;; ------------------------------------------------------------------
;;; Decision (C): susceptibility reduction is DECOUPLED from the active
;;; identification belief system (susceptibility-belief-design.md 4). A
;;; ds-belief susceptibility must reduce natively -- to its lower bound -- under
;;; BOTH algebras. Under CF this errored before the decoupling, because CF's
;;; BELIEF->NUMBER has no method for a ds-belief struct.
;;; ------------------------------------------------------------------

(deftest therapy-cf-interval-susceptibility-covers ()
  ;; The crux of decision (C): identification runs under certainty factors, yet a
  ;; DS-interval susceptibility still reduces (to its bel) and covers -- no error.
  (belief:use-system :certainty-factors)
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:with-greedy-solver
      (therapy:add-drug kb :broad :dose "1g")
      ;; bel 0.9 -> reduces natively to 0.9 >= 0.5, independent of the CF algebra.
      (therapy:add-sensitivity kb :pseudomonas :broad (belief:make-ds-belief 0.9 1.0))
      ;; Identification belief is a plain CF scalar, as it would be under CF.
      (let ((rec (therapy:recommend '((:pseudomonas . 0.7)) kb '())))
        (is (equal '(:broad) (regimen-drugs rec))
            "DS-interval susceptibility covers under CF (decision C: no belief->number error)")
        (is (null (therapy:recommendation-uncovered rec)) "nothing uncovered under CF")))))

(deftest therapy-cf-weak-interval-does-not-cover ()
  ;; Same decoupling, negative direction: under CF the interval reduces to its bel
  ;; (0.3), which is < 0.5, so it does not cover -- proving the native reduction
  ;; takes the lower bound rather than, say, plausibility.
  (belief:use-system :certainty-factors)
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:with-greedy-solver
      (therapy:add-drug kb :broad :dose "1g")
      (therapy:add-sensitivity kb :pseudomonas :broad (belief:make-ds-belief 0.3 1.0))
      (let ((rec (therapy:recommend '((:pseudomonas . 0.7)) kb '())))
        (is (null (regimen-drugs rec)) "low-bel interval does not cover under CF")
        (is (member :pseudomonas (therapy:recommendation-uncovered rec)) "organism uncovered")))))

;;; ------------------------------------------------------------------
;;; S3: the coverage-gate dial (*susceptibility-gate*). The SAME case and KB yield
;;; different coverage under the conservative (:belief) vs optimistic
;;; (:plausibility) gate -- the research artifact. Legible only because the
;;; susceptibility interval is explicit.
;;; ------------------------------------------------------------------

(deftest therapy-gate-flips-coverage ()
  (belief:use-system :dempster-shafer)
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:with-greedy-solver
      (therapy:add-drug kb :only :dose "1g")
      ;; Straddles the 0.5 threshold: bel 0.4 < 0.5 <= pl 0.8, midpoint 0.6.
      (therapy:add-sensitivity kb :pseudomonas :only (belief:make-ds-belief 0.4 0.8))
      (flet ((covered-p (gate)
               (let ((therapy:*susceptibility-gate* gate))
                 (null (therapy:recommendation-uncovered
                        (therapy:recommend '((:pseudomonas . 0.8)) kb '()))))))
        (is (not (covered-p :belief)) "conservative :belief gate (bel 0.4 < 0.5): not covered")
        (is (covered-p :plausibility) "optimistic :plausibility gate (pl 0.8 >= 0.5): covered")
        (is (covered-p :midpoint) "midpoint gate (0.6 >= 0.5): covered")))))

(deftest therapy-gate-default-is-conservative ()
  ;; The dial defaults to :belief, so the engine's out-of-the-box behavior is the
  ;; conservative gate -- no surprise change for callers that never touch it.
  (is (eq :belief therapy:*susceptibility-gate*) "default gate is :belief"))

(deftest therapy-canonical-gate-recovers-provisional ()
  ;; On the CANONICAL KB: contraindicate every SOLID anti-pseudomonal, leaving only
  ;; PROVISIONAL agents (cipro/gentamicin, bel < 0.5). The conservative gate leaves
  ;; pseudomonas honestly UNCOVERED; the optimistic gate lets a provisional agent
  ;; cover it. Same case, different regimen -- the stewardship dial in action.
  (belief:use-system :dempster-shafer)
  (therapy:with-greedy-solver
    (let ((patient '(:allergy-cephalosporin :allergy-carbapenem :allergy-penicillin)))
      (flet ((pseudomonas-covered-p (gate)
               (let ((therapy:*susceptibility-gate* gate))
                 (not (member :pseudomonas
                              (therapy:recommendation-uncovered
                               (therapy:recommend '((:pseudomonas . 0.8))
                                                  (therapy:therapy-kb) patient)))))))
        (is (not (pseudomonas-covered-p :belief))
            "conservative gate: only provisional anti-pseudomonals remain -> uncovered")
        (is (pseudomonas-covered-p :plausibility)
            "optimistic gate: a provisional agent (pl >= 0.5) now covers pseudomonas")))))

;;; ------------------------------------------------------------------
;;; S2: the susceptibility interval is surfaced through to JSON as
;;; {bel, pl, ignorance}, rendered NATIVELY so the shape is identical under CF and
;;; DS (decision C). This is the payload that lets Claude narrate a wide interval
;;; as provisional.
;;; ------------------------------------------------------------------

(deftest therapy-susceptibility-serializes-as-interval ()
  (dolist (sys '(:certainty-factors :dempster-shafer))
    (belief:use-system sys)
    (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
      (therapy:with-greedy-solver
        (therapy:add-drug kb :broad :dose "1g")
        (therapy:add-sensitivity kb :pseudomonas :broad (belief:make-ds-belief 0.7 0.9))
        (let* ((rec (therapy:recommend '((:pseudomonas . 0.8)) kb '()))
               (json (therapy:recommendation->json rec))
               (regimen (gethash "regimen" json))
               (entry (aref (gethash "susceptibility" (aref regimen 0)) 0)))
          (is (string= "pseudomonas" (gethash "organism" entry))
              (format nil "organism serialized under ~S" sys))
          (is (approx= 0.7 (gethash "bel" entry)) (format nil "bel surfaced under ~S" sys))
          (is (approx= 0.9 (gethash "pl" entry)) (format nil "pl surfaced under ~S" sys))
          (is (approx= 0.2 (gethash "ignorance" entry))
              (format nil "ignorance surfaced under ~S" sys)))))))

(deftest therapy-scalar-susceptibility-serializes-as-degenerate-interval ()
  ;; A bare scalar susceptibility serializes as a zero-ignorance interval, so
  ;; consumers see a uniform {bel, pl, ignorance} shape regardless of authoring.
  (belief:use-system :dempster-shafer)
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:with-greedy-solver
      (therapy:add-drug kb :broad :dose "1g")
      (therapy:add-sensitivity kb :pseudomonas :broad 0.85) ; plain scalar
      (let* ((rec (therapy:recommend '((:pseudomonas . 0.8)) kb '()))
             (entry (aref (gethash "susceptibility"
                                   (aref (gethash "regimen" (therapy:recommendation->json rec)) 0))
                          0)))
        (is (approx= 0.85 (gethash "bel" entry)) "scalar becomes bel")
        (is (approx= 0.85 (gethash "pl" entry)) "scalar becomes pl")
        (is (approx= 0.0 (gethash "ignorance" entry)) "scalar has zero ignorance")))))

;;; ------------------------------------------------------------------
;;; def* authoring surface (design doc 3.2): the macros are thin wrappers over
;;; the builder API and populate *THERAPY-KB*. Bind it to a throwaway KB so these
;;; never touch the canonical one.
;;; ------------------------------------------------------------------

(deftest therapy-defstar-macros-populate-kb ()
  ;; defdrug / defsensitivity / defcontraindication read back through the accessors
  ;; exactly as the equivalent builder calls would.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:defdrug :testdrug :class :test-class :route :iv :dose "1 g IV q8h")
    (therapy:defsensitivity :pseudomonas :testdrug 0.9)
    (therapy:defcontraindication :testdrug :when (:allergy-test))
    (is (member :testdrug (therapy:kb-drug-ids (therapy:therapy-kb))) "drug authored")
    (is (eq :test-class (therapy:kb-drug-class (therapy:therapy-kb) :testdrug)) "class stored")
    (is (eq :iv (therapy:kb-drug-route (therapy:therapy-kb) :testdrug)) "route stored")
    (is (equal "1 g IV q8h" (therapy:kb-dose (therapy:therapy-kb) :testdrug)) "dose stored")
    (is (= 0.9 (therapy:kb-susceptibility (therapy:therapy-kb) :testdrug :pseudomonas))
        "sensitivity authored")
    (is (member :allergy-test
                (therapy:kb-contraindication-triggers (therapy:therapy-kb) :testdrug))
        "contraindication trigger authored")))

(deftest therapy-defcontraindication-idempotent ()
  ;; Re-authoring a trigger (as a file reload would) does not duplicate it.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:defdrug :testdrug :dose "1 g")
    (therapy:defcontraindication :testdrug :when (:allergy-test))
    (therapy:defcontraindication :testdrug :when (:allergy-test))
    (is (equal '(:allergy-test)
               (therapy:kb-contraindication-triggers (therapy:therapy-kb) :testdrug))
        "trigger present exactly once after re-authoring")))

;;; ------------------------------------------------------------------
;;; Canonical knowledge base (knowledge-base.lisp) loaded end to end. All values
;;; are the schematic, non-clinical figures authored there; these lock in the KB
;;; the solver actually ships with. If that data is intentionally revised,
;;; re-verify and update these expectations.
;;; ------------------------------------------------------------------

(deftest therapy-canonical-kb-loaded ()
  (is (member :ceftazidime (therapy:kb-drug-ids (therapy:therapy-kb)))
      "canonical KB has ceftazidime")
  ;; Susceptibilities are now DS intervals (susceptibility-belief-design.md S1),
  ;; not bare scalars: ceftazidime/pseudomonas is authored as [0.70, 0.90].
  (let ((s (therapy:kb-susceptibility (therapy:therapy-kb) :ceftazidime :pseudomonas)))
    (is (belief:ds-belief-p s) "authored susceptibility is a DS interval")
    (is (= 0.70 (belief:ds-belief-bel s)) "ceftazidime/pseudomonas belief (lower bound)")
    (is (= 0.90 (belief:ds-belief-pl s)) "ceftazidime/pseudomonas plausibility (upper bound)"))
  (is (eq :iv (therapy:kb-drug-route (therapy:therapy-kb) :ceftazidime)) "route present")
  (is (stringp (therapy:kb-dose (therapy:therapy-kb) :ceftazidime)) "dose present")
  (is (member :allergy-cephalosporin
              (therapy:kb-contraindication-triggers (therapy:therapy-kb) :ceftazidime))
      "cephalosporin allergy contraindicates ceftazidime"))

(deftest therapy-canonical-susceptibilities-are-intervals ()
  ;; S1: the canonical KB carries DS intervals, not scalars, and the width tiers
  ;; are disciplined -- a SOLID entry's bel clears the coverage gate; a
  ;; [PROVISIONAL] entry's bel falls below it (so it does not cover under the
  ;; conservative default), yet still has genuine ignorance (pl > bel).
  (let ((solid (therapy:kb-susceptibility (therapy:therapy-kb) :meropenem :pseudomonas))
        (provisional (therapy:kb-susceptibility (therapy:therapy-kb) :ciprofloxacin :pseudomonas)))
    (is (belief:ds-belief-p solid) "canonical susceptibility is a DS interval")
    (is (belief:ds-belief-p provisional) "provisional susceptibility is a DS interval too")
    (is (>= (belief:ds-belief-bel solid) therapy:*susceptibility-threshold*)
        "solid meropenem/pseudomonas covers (bel >= gate)")
    (is (< (belief:ds-belief-bel provisional) therapy:*susceptibility-threshold*)
        "provisional cipro/pseudomonas does not cover under the conservative gate")
    (is (> (belief:ds-belief-pl provisional) (belief:ds-belief-bel provisional))
        "the provisional interval carries genuine ignorance (pl > bel)")))

(deftest therapy-canonical-gram-negative-minimal ()
  ;; Two gram-negatives both covered by broad agents -> one drug suffices (minimality).
  (therapy:with-greedy-solver
    (let* ((rec (therapy:recommend '((:pseudomonas . 0.76) (:enterobacteriaceae . 0.80))
                                   (therapy:therapy-kb) '()))
           (drugs (regimen-drugs rec)))
      (is (= 1 (length drugs)) "one broad agent covers both gram-negatives")
      (is (= 2 (length (treated rec))) "both organisms are items to treat")
      (is (null (therapy:recommendation-uncovered rec)) "nothing left uncovered"))))

(deftest therapy-canonical-mixed-needs-two ()
  ;; A gram-negative plus a resistant S. aureus: no single canonical drug covers
  ;; both -> a two-drug regimen, still fully covering.
  (therapy:with-greedy-solver
    (let* ((rec (therapy:recommend '((:pseudomonas . 0.7) (:staphylococcus-aureus . 0.7))
                                   (therapy:therapy-kb) '()))
           (drugs (regimen-drugs rec)))
      (is (= 2 (length drugs)) "two drugs needed for the disjoint pair")
      (is (null (therapy:recommendation-uncovered rec)) "full coverage"))))

(deftest therapy-canonical-contraindication-forces-alternative ()
  ;; A cephalosporin allergy removes ceftazidime; another anti-pseudomonal covers.
  (therapy:with-greedy-solver
    (let* ((rec (therapy:recommend '((:pseudomonas . 0.7)) (therapy:therapy-kb)
                                   '(:allergy-cephalosporin)))
           (drugs (regimen-drugs rec))
           (excl (mapcar #'therapy:exclusion-drug (therapy:recommendation-excluded rec))))
      (is (not (member :ceftazidime drugs)) "contraindicated ceftazidime not used")
      (is (member :ceftazidime excl) "ceftazidime recorded as excluded")
      (is (null (therapy:recommendation-uncovered rec)) "pseudomonas still covered"))))
