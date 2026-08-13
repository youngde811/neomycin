;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: Tests for the exact set-cover solver and for the ALTERNATIVES
;; reporting both solvers now carry (exact-solver-design.md 5, slice 2).
;;
;; Three kinds of test here, in rising order of what they protect:
;;
;;   1. Fixture goldens for the exact search itself, on synthetic KBs we control.
;;   2. The EQUIVALENCE property -- greedy and exact return regimens of the same
;;      SIZE on every case. Deliberately not the same drugs: a tie broken
;;      differently is legitimate, but a size difference means greedy's
;;      approximation lost, and that should be a documented counterexample rather
;;      than something a clinician notices first.
;;   3. The 1.1 REGRESSION -- the case a clinician actually asked about, where the
;;      narration reported that no narrower agent existed. Pinned by name because
;;      it is the reason this slice exists.
;;
;; All pharmacology is schematic. NOT FOR CLINICAL USE.

(in-package "LISA-TEST")

(defun alt-agent-drugs (rec)
  (mapcar #'therapy:regimen-item-drug (therapy:recommendation-alternative-agents rec)))

(defun alt-regimen-drugsets (rec)
  (mapcar #'(lambda (a) (mapcar #'therapy:regimen-item-drug
                                (therapy:alternative-regimen-drugs a)))
          (therapy:recommendation-alternative-regimens rec)))

(defun solve-with (solver conclusions kb &optional (patient '()))
  (therapy:use-solver solver)
  (therapy:recommend conclusions kb patient))

;;; ------------------------------------------------------------------
;;; 1. The exact search
;;; ------------------------------------------------------------------

(deftest exact-single-drug-covers-all ()
  ;; The base case: one agent covers everything, so the minimum cover has size 1.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:add-drug kb :broad :dose "1g")
    (therapy:add-sensitivity kb :pseudomonas :broad 0.9)
    (therapy:add-sensitivity kb :klebsiella :broad 0.7)
    (let ((rec (solve-with :exact '((:pseudomonas . 0.76) (:klebsiella . 0.50)) kb)))
      (is (equal '(:broad) (regimen-drugs rec)) "single broad drug chosen")
      (is (null (therapy:recommendation-uncovered rec)) "nothing uncovered"))))

(deftest exact-prefers-one-drug-over-two ()
  ;; Ascending-k must stop at k=1: a 2-drug cover exists and must NOT be returned
  ;; when a 1-drug cover does. This is the property greedy also has; the point is
  ;; that the exhaustive search does not lose it by enumerating 2-subsets first.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:add-drug kb :broad :dose "1g")
    (therapy:add-drug kb :narrow-a :dose "1g")
    (therapy:add-drug kb :narrow-b :dose "1g")
    (therapy:add-sensitivity kb :bug-1 :broad 0.8)
    (therapy:add-sensitivity kb :bug-2 :broad 0.8)
    (therapy:add-sensitivity kb :bug-1 :narrow-a 0.9)
    (therapy:add-sensitivity kb :bug-2 :narrow-b 0.9)
    (let ((rec (solve-with :exact '((:bug-1 . 0.7) (:bug-2 . 0.7)) kb)))
      (is (= 1 (length (regimen-drugs rec))) "the 1-drug cover wins on cardinality")
      (is (equal '(:broad) (regimen-drugs rec)) "and it is the broad agent"))))

(deftest exact-finds-two-drug-cover-when-needed ()
  ;; No single drug covers both -> the minimum is 2, and both organisms are
  ;; attributed to exactly one drug each (disjoint COVERS, as greedy reports).
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:add-drug kb :gram-neg :dose "1g")
    (therapy:add-drug kb :gram-pos :dose "1g")
    (therapy:add-sensitivity kb :bug-neg :gram-neg 0.9)
    (therapy:add-sensitivity kb :bug-pos :gram-pos 0.9)
    (let* ((rec (solve-with :exact '((:bug-neg . 0.7) (:bug-pos . 0.7)) kb))
           (covers (mapcar #'therapy:regimen-item-covers
                           (therapy:recommendation-regimen rec))))
      (is (= 2 (length (regimen-drugs rec))) "two drugs needed")
      (is (every #'(lambda (c) (= 1 (length c))) covers)
          "each drug is attributed exactly one organism -- covers stay disjoint")
      (is (null (therapy:recommendation-uncovered rec)) "full coverage"))))

(deftest exact-uncoverable-reported-not-fatal ()
  ;; An organism no candidate covers must not prevent a regimen for the rest. The
  ;; search runs over the COVERABLE subset and reports the remainder honestly --
  ;; the same partial result greedy produces, rather than failing to return.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:add-drug kb :only :dose "1g")
    (therapy:add-sensitivity kb :treatable :only 0.9)
    (let ((rec (solve-with :exact '((:treatable . 0.7) (:untreatable . 0.7)) kb)))
      (is (equal '(:only) (regimen-drugs rec)) "the coverable organism is still covered")
      (is (equal '(:untreatable) (therapy:recommendation-uncovered rec))
          "the uncoverable one is surfaced, not silently dropped"))))

(deftest exact-belief-gate-drops-subthreshold ()
  ;; Phase A is shared, so the gate must behave identically under the exact solver.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:add-drug kb :d :dose "1g")
    (therapy:add-sensitivity kb :loud :d 0.9)
    (therapy:add-sensitivity kb :faint :d 0.9)
    (let ((rec (solve-with :exact '((:loud . 0.7) (:faint . 0.1)) kb)))
      (is (equal '(:loud) (treated rec)) "sub-threshold organism is not an item to treat"))))

(deftest exact-deterministic ()
  ;; Same inputs, same answer, twice -- for both solvers. An exhaustive search that
  ;; depended on hash order would be a silently irreproducible recommendation.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:add-drug kb :a-drug :dose "1g")
    (therapy:add-drug kb :b-drug :dose "1g")
    (therapy:add-sensitivity kb :bug :a-drug 0.8)
    (therapy:add-sensitivity kb :bug :b-drug 0.8)   ; exact tie -> name breaks it
    (dolist (solver '(:greedy :exact))
      (let ((first-run (regimen-drugs (solve-with solver '((:bug . 0.7)) kb)))
            (second-run (regimen-drugs (solve-with solver '((:bug . 0.7)) kb))))
        (is (equal first-run second-run)
            (format nil "~A is deterministic across runs" solver))
        (is (equal '(:a-drug) first-run)
            (format nil "~A breaks an exact tie by name" solver))))))

;;; ------------------------------------------------------------------
;;; 2. Alternatives
;;; ------------------------------------------------------------------

(deftest alternatives-agents-reported-by-both-solvers ()
  ;; The solver-INDEPENDENT half. Greedy must report it too: the clinician in 1.1
  ;; was on the default solver, so a fix only the exact search could deliver would
  ;; not have reached them.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:add-drug kb :chosen :dose "1g")
    (therapy:add-drug kb :also-covers :dose "1g")
    (therapy:add-drug kb :covers-nothing :dose "1g")
    (therapy:add-sensitivity kb :bug :chosen 0.9)
    (therapy:add-sensitivity kb :bug :also-covers 0.6)
    (therapy:add-sensitivity kb :other-bug :covers-nothing 0.9)
    (dolist (solver '(:greedy :exact))
      (let ((rec (solve-with solver '((:bug . 0.7)) kb)))
        (is (equal '(:chosen) (regimen-drugs rec))
            (format nil "~A picks the stronger agent" solver))
        (is (equal '(:also-covers) (alt-agent-drugs rec))
            (format nil "~A reports the agent it passed over" solver))
        (is (not (member :covers-nothing (alt-agent-drugs rec)))
            (format nil "~A omits a drug covering no treated organism" solver))))))

(deftest alternatives-agents-name-sorted-not-ranked ()
  ;; Ordering is by NAME, deliberately. Ranking them by coverage weight would imply
  ;; the solver judged one alternative better than another; it never compared them.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:add-drug kb :zzz-best-alternative :dose "1g")
    (therapy:add-drug kb :aaa-worst-alternative :dose "1g")
    (therapy:add-drug kb :chosen :dose "1g")
    (therapy:add-sensitivity kb :bug :chosen 0.95)
    (therapy:add-sensitivity kb :bug :zzz-best-alternative 0.90)
    (therapy:add-sensitivity kb :bug :aaa-worst-alternative 0.55)
    (let ((rec (solve-with :exact '((:bug . 0.7)) kb)))
      (is (equal '(:aaa-worst-alternative :zzz-best-alternative) (alt-agent-drugs rec))
          "alternatives come back name-sorted, not strongest-first"))))

(deftest alternatives-regimens-are-exact-only ()
  ;; Greedy cannot know what it passed over -- it never enumerated. Rather than
  ;; faking the field from the drugs it happened to skip, it leaves it empty.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:add-drug kb :chosen :dose "1g")
    (therapy:add-drug kb :runner-up :dose "1g")
    (therapy:add-sensitivity kb :bug :chosen 0.9)
    (therapy:add-sensitivity kb :bug :runner-up 0.8)
    (is (null (alt-regimen-drugsets (solve-with :greedy '((:bug . 0.7)) kb)))
        "greedy reports no alternative regimens")
    (is (equal '((:runner-up)) (alt-regimen-drugsets (solve-with :exact '((:bug . 0.7)) kb)))
        "exact reports the equally-minimal regimen it chose against")))

(deftest alternatives-regimens-only-of-minimum-size ()
  ;; A 2-drug cover is NOT an alternative to a 1-drug regimen. Alternatives are the
  ;; ties the objective broke, not every regimen that would have worked -- listing
  ;; larger ones would present a worse answer as an equal option.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:add-drug kb :broad :dose "1g")
    (therapy:add-drug kb :other-broad :dose "1g")
    (therapy:add-drug kb :narrow-a :dose "1g")
    (therapy:add-drug kb :narrow-b :dose "1g")
    (therapy:add-sensitivity kb :bug-1 :broad 0.9)
    (therapy:add-sensitivity kb :bug-2 :broad 0.9)
    (therapy:add-sensitivity kb :bug-1 :other-broad 0.8)
    (therapy:add-sensitivity kb :bug-2 :other-broad 0.8)
    (therapy:add-sensitivity kb :bug-1 :narrow-a 0.95)
    (therapy:add-sensitivity kb :bug-2 :narrow-b 0.95)
    (let ((alts (alt-regimen-drugsets (solve-with :exact '((:bug-1 . 0.7) (:bug-2 . 0.7)) kb))))
      (is (equal '((:other-broad)) alts)
          "only the other 1-drug cover is an alternative; the 2-drug pair is not"))))

(deftest alternatives-serialize-always-even-when-empty ()
  ;; The payload is the contract. Both keys are emitted unconditionally: an ABSENT
  ;; key reads as "not applicable", an EMPTY ARRAY reads as "asked and answered --
  ;; nothing else covered". Only the second is true, and collapsing that distinction
  ;; is what let a reader infer, wrongly, that no alternative existed.
  (belief:use-system :dempster-shafer)
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:add-drug kb :only-drug :dose "1g")
    (therapy:add-sensitivity kb :bug :only-drug (belief:make-ds-belief 0.8 0.95))
    (let ((json (therapy:recommendation->json (solve-with :exact '((:bug . 0.7)) kb))))
      (is (nth-value 1 (gethash "alternative_agents" json))
          "alternative_agents key present even with nothing to report")
      (is (nth-value 1 (gethash "alternative_regimens" json))
          "alternative_regimens key present even with nothing to report")
      (is (zerop (length (gethash "alternative_agents" json))) "and it is an empty array")))
  ;; With something to report, each entry carries the full regimen-entry shape --
  ;; drug, dose, covers, and the susceptibility interval to compare against.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:add-drug kb :chosen :dose "1g")
    (therapy:add-drug kb :passed-over :dose "500mg")
    (therapy:add-sensitivity kb :bug :chosen (belief:make-ds-belief 0.90 0.99))
    (therapy:add-sensitivity kb :bug :passed-over (belief:make-ds-belief 0.72 0.92))
    (let* ((json (therapy:recommendation->json (solve-with :exact '((:bug . 0.7)) kb)))
           (alt (aref (gethash "alternative_agents" json) 0))
           (susc (aref (gethash "susceptibility" alt) 0)))
      (is (string= "passed-over" (gethash "drug" alt)) "the passed-over drug is named")
      (is (string= "500mg" (gethash "dose" alt)) "with its dose")
      (is (approx= 0.72 (gethash "bel" susc))
          "and its susceptibility floor, so the narrowing trade is in the payload")
      (is (= 1 (length (gethash "alternative_regimens" json)))
          "and the equally-minimal regimen it lost to the tiebreak"))))

;;; ------------------------------------------------------------------
;;; 2a. Spectrum breadth -- authored data only (slice 3, design doc 3.4)
;;;
;;; No solver reads :spectrum yet. These tests guard the DATA: that it is complete,
;;; validated, and ordinal. The objective that will consume it is slice 4.
;;; ------------------------------------------------------------------

(deftest spectrum-every-canonical-drug-has-a-tier ()
  ;; Completeness matters more than it looks: a drug with no tier would be invisible
  ;; to a breadth ordering, and the failure mode is silent -- it would simply never
  ;; be preferred, or would sort as though it were narrowest, depending on the
  ;; comparator. Catch it at authoring time instead.
  (let ((kb (therapy:therapy-kb)))
    (dolist (d (therapy:kb-drug-ids kb))
      (let ((tier (therapy:kb-drug-spectrum kb d)))
        (is (member tier therapy:*spectrum-tiers*)
            (format nil "~A carries a valid spectrum tier (got ~S)" d tier))))
    (is (= 11 (length (therapy:kb-drug-ids kb))) "all 11 canonical drugs present")))

(deftest spectrum-tiers-are-ordinal-narrowest-first ()
  (is (= 0 (therapy:spectrum-rank :very-narrow)) "very-narrow ranks lowest")
  (is (< (therapy:spectrum-rank :very-narrow) (therapy:spectrum-rank :narrow))
      "very-narrow < narrow")
  (is (< (therapy:spectrum-rank :narrow) (therapy:spectrum-rank :moderate))
      "narrow < moderate")
  (is (< (therapy:spectrum-rank :moderate) (therapy:spectrum-rank :broad))
      "moderate < broad")
  (is (< (therapy:spectrum-rank :broad) (therapy:spectrum-rank :very-broad))
      "broad < very-broad")
  (is (null (therapy:spectrum-rank :not-a-tier)) "an unknown tier has no rank"))

(deftest spectrum-assignments-pin-the-clinical-judgement ()
  ;; These are judgements, not measurements, so they are pinned: changing one should
  ;; be a deliberate edit with a visible diff, not a drive-by. The ordering claims
  ;; that matter for slice 4 are asserted as relations, not just literals.
  (let ((kb (therapy:therapy-kb)))
    (flet ((tier (d) (therapy:kb-drug-spectrum kb d))
           (rank (d) (therapy:spectrum-rank (therapy:kb-drug-spectrum kb d))))
      (is (eq :very-narrow (tier :metronidazole)) "metronidazole is the narrowest agent")
      (is (eq :very-broad (tier :meropenem)) "meropenem is very-broad")
      (is (eq :very-broad (tier :piperacillin-tazobactam)) "pip-tazo is very-broad")
      (is (< (rank :vancomycin) (rank :ceftriaxone))
          "vancomycin is NARROWER than ceftriaxone -- gram-positives only")
      (is (< (rank :gentamicin) (rank :ceftriaxone))
          "gentamicin is narrower than ceftriaxone (design doc 3.6 finding 1)")
      (is (< (rank :ceftriaxone) (rank :meropenem))
          "ceftriaxone is narrower than the carbapenem"))))

(deftest spectrum-rejects-an-unknown-tier-at-authoring-time ()
  ;; A typo must fail loudly. Reading back as NIL would remove the drug from any
  ;; breadth ordering silently -- the same class of silent-gap failure the corpus
  ;; property tests exist to catch on the rulebase side.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (is (block probe
          (handler-case (progn (therapy:add-drug kb :typo :spectrum :quite-narrow)
                               nil)
            (error () t)))
        "an unknown spectrum tier signals at authoring time")
    (is (therapy:add-drug kb :fine :spectrum :narrow) "a valid tier is accepted")
    (is (null (therapy:kb-drug-spectrum kb :unauthored))
        "an unauthored drug simply has no tier")))

(deftest spectrum-is-not-yet-consumed-by-any-solver ()
  ;; Guards the claim made in kb.lisp and knowledge-base.lisp that nothing reads
  ;; :spectrum yet. If a solver starts consuming it, this test should be REPLACED by
  ;; the objective's own goldens -- not deleted quietly, which would let the docs go
  ;; stale exactly the way section 1.1 records.
  (belief:use-system :dempster-shafer)
  (let ((conclusions (list (cons :e-coli (belief:make-ds-belief 0.64 1.0)))))
    (dolist (solver '(:greedy :exact))
      (is (equal '(:meropenem) (regimen-drugs (solve-with solver conclusions
                                                          (therapy:therapy-kb))))
          (format nil "~A still ignores spectrum: meropenem, not the narrower agent"
                  solver)))))

;;; ------------------------------------------------------------------
;;; 3. The equivalence property (design doc 5)
;;; ------------------------------------------------------------------

(defparameter *equivalence-cases*
  '(("e-coli alone"            ((:e-coli . 0.64)))
    ("pseudomonas alone"       ((:pseudomonas . 0.76)))
    ("klebsiella alone"        ((:klebsiella . 0.40)))
    ("culture-1 pair"          ((:pseudomonas . 0.76) (:klebsiella . 0.40)))
    ("gram-neg pair"           ((:pseudomonas . 0.76) (:enterobacteriaceae . 0.80)))
    ("mixed gram +/-"          ((:pseudomonas . 0.70) (:staphylococcus-aureus . 0.70)))
    ("s-aureus + klebsiella"   ((:staphylococcus-aureus . 0.60) (:klebsiella . 0.50)))
    ("anaerobe + gram-pos"     ((:bacteroides . 0.55) (:staphylococcus-aureus . 0.60)))
    ("three organisms"         ((:pseudomonas . 0.76) (:klebsiella . 0.40)
                                (:staphylococcus-aureus . 0.60)))
    ("enterococcus alone"      ((:enterococcus . 0.60)))
    ("strep pneumoniae"        ((:streptococcus-pneumoniae . 0.70)))
    ("sub-threshold only"      ((:pseudomonas . 0.10))))
  "Representative conclusion sets over the CANONICAL KB, including every case in
   exact-solver-design.md 1's table. Beliefs are plain scalars: the equivalence
   property is about the search, not the belief algebra, which both solvers reduce
   through the same shared phase A.")

(deftest exact-greedy-equivalence-on-canonical-kb ()
  ;; THE property of slice 2: exact(:lexicographic) is greedy's policy computed
  ;; exactly rather than approximated, so the regimens must be the same SIZE. Not
  ;; necessarily the same drugs -- a tie broken differently is legitimate -- but a
  ;; size difference means greedy's approximation lost on a real case, which is a
  ;; finding to document, not a test to relax.
  (dolist (patient '(() (:allergy-cephalosporin) (:allergy-penicillin :allergy-carbapenem)))
    (dolist (case *equivalence-cases*)
      (destructuring-bind (label conclusions) case
        (let ((g (solve-with :greedy conclusions (therapy:therapy-kb) patient))
              (e (solve-with :exact conclusions (therapy:therapy-kb) patient)))
          (is (= (length (regimen-drugs g)) (length (regimen-drugs e)))
              (format nil "~A ~S: greedy and exact agree on regimen size" label patient))
          (is (equal (sort (copy-list (therapy:recommendation-uncovered g))
                           #'string< :key #'symbol-name)
                     (sort (copy-list (therapy:recommendation-uncovered e))
                           #'string< :key #'symbol-name))
              (format nil "~A ~S: both solvers leave the same organisms uncovered"
                      label patient))
          (is (equal (sort (copy-list (treated g)) #'string< :key #'symbol-name)
                     (sort (copy-list (treated e)) #'string< :key #'symbol-name))
              (format nil "~A ~S: shared phase A gates identically" label patient)))))))

(deftest exact-greedy-agree-on-alternative-agents ()
  ;; ALTERNATIVE-AGENTS is a KB fact about the gated items, not a search artifact,
  ;; so the two solvers must produce the same list whenever they chose the same
  ;; drugs. (When they break a tie differently the lists legitimately differ, so
  ;; this only asserts the case where the regimens match.)
  (dolist (case *equivalence-cases*)
    (destructuring-bind (label conclusions) case
      (let ((g (solve-with :greedy conclusions (therapy:therapy-kb)))
            (e (solve-with :exact conclusions (therapy:therapy-kb))))
        (when (equal (sort (copy-list (regimen-drugs g)) #'string< :key #'symbol-name)
                     (sort (copy-list (regimen-drugs e)) #'string< :key #'symbol-name))
          (is (equal (alt-agent-drugs g) (alt-agent-drugs e))
              (format nil "~A: same regimen -> same alternative agents" label)))))))

;;; ------------------------------------------------------------------
;;; 4. The 1.1 regression
;;; ------------------------------------------------------------------

(deftest regression-e-coli-narrower-agents-are-reported ()
  ;; exact-solver-design.md 1.1. A clinician resolved a blood culture to E. coli at
  ;; bel 0.64, asked for a narrower first-line agent, and was told the KB had none
  ;; registered that cleared coverage. It had five. E. coli carries no species-level
  ;; susceptibility and rolls up to :enterobacteriaceae, which six drugs cover, all
  ;; above the 0.5 threshold.
  ;;
  ;; This test does NOT assert the regimen changes -- under :lexicographic it
  ;; correctly does not, since that objective is greedy's policy and meropenem wins
  ;; its tiebreak at 0.90. What it asserts is that the false ANSWER is no longer
  ;; available: the five narrower agents are in the payload, under both solvers.
  ;; The regimen itself moves off meropenem only under :spectrum-sparing (slice 4).
  (belief:use-system :dempster-shafer)
  (let ((conclusions (list (cons :e-coli (belief:make-ds-belief 0.64 1.0))))
        (expected '(:ceftazidime :ceftriaxone :ciprofloxacin :gentamicin
                    :piperacillin-tazobactam)))
    (dolist (solver '(:greedy :exact))
      (let ((rec (solve-with solver conclusions (therapy:therapy-kb))))
        (is (equal '(:meropenem) (regimen-drugs rec))
            (format nil "~A still returns meropenem under :lexicographic" solver))
        (is (equal expected (alt-agent-drugs rec))
            (format nil "~A names all five narrower covering agents" solver))
        (is (= 5 (length (alt-agent-drugs rec)))
            (format nil "~A: the payload can no longer imply none exists" solver))))
    ;; Each alternative carries its own susceptibility interval, so the trade a
    ;; clinician is being asked to weigh -- narrower agent, lower coverage floor --
    ;; is visible in the payload rather than asserted in prose.
    (let* ((rec (solve-with :exact conclusions (therapy:therapy-kb)))
           (ceftriaxone (find :ceftriaxone (therapy:recommendation-alternative-agents rec)
                              :key #'therapy:regimen-item-drug)))
      (is ceftriaxone "ceftriaxone is among the reported alternatives")
      (is (equal '(:e-coli) (therapy:regimen-item-covers ceftriaxone))
          "and it is reported as covering e-coli")
      (let ((s (therapy:susceptibility-item-value
                (first (therapy:regimen-item-susceptibility ceftriaxone)))))
        (is (belief:ds-belief-p s) "carrying its susceptibility interval")
        (is (< (belief:ds-belief-bel s) 0.90)
            "whose floor is below meropenem's 0.90 -- the cost of narrowing, in the payload")))))

(deftest regression-e-coli-alternative-regimens-under-exact ()
  ;; The same case through the other reading of "alternatives": every equally
  ;; minimal (1-drug) regimen the exact search chose against.
  (belief:use-system :dempster-shafer)
  (let* ((rec (solve-with :exact (list (cons :e-coli (belief:make-ds-belief 0.64 1.0)))
                          (therapy:therapy-kb)))
         (alts (alt-regimen-drugsets rec)))
    (is (= 5 (length alts)) "five equally-minimal single-drug regimens were passed over")
    (is (every #'(lambda (a) (= 1 (length a))) alts)
        "each is a single agent, the same size as the chosen regimen")
    (is (member '(:ceftriaxone) alts :test #'equal)
        "ceftriaxone among them -- the agent the narration said did not exist")))