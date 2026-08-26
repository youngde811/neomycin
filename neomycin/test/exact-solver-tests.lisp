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
  ;; Threshold bound explicitly -- see the note on the greedy twin in therapy-tests.lisp.
  (let ((therapy:*coverage-threshold* 0.2))
    (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
      (therapy:add-drug kb :d :dose "1g")
      (therapy:add-sensitivity kb :loud :d 0.9)
      (therapy:add-sensitivity kb :faint :d 0.9)
      (let ((rec (solve-with :exact '((:loud . 0.7) (:faint . 0.1)) kb)))
        (is (equal '(:loud) (treated rec)) "sub-threshold organism is not an item to treat")))))

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
;;; 2b. The :spectrum-sparing objective (slice 4, design doc 3.5 / 3.6)
;;;
;;; These goldens pin a DIVERGENCE, so nobody can quietly "improve" the objective
;;; back to carbapenem-first -- and, equally, so nobody quietly patches away the
;;; awkward answer it gives. Both were shipped knowingly (3.6, option (a)).
;;; ------------------------------------------------------------------

(defmacro with-objective ((objective) &body body)
  `(let ((therapy:*objective* ,objective)) ,@body))

(deftest spectrum-sparing-default-is-lexicographic ()
  ;; The dial must default to today's behaviour: turning it on is opt-in, exactly
  ;; like the coverage gate and the belief system.
  (is (eq :lexicographic therapy:*objective*) "the objective defaults to :lexicographic"))

(deftest spectrum-sparing-diverges-klebsiella-to-gentamicin ()
  ;; design doc 3.6, finding 1 + 2. THE awkward golden. Klebsiella alone moves from
  ;; meropenem to GENTAMICIN -- not to ceftriaxone, which 3.2 assumed before the
  ;; tiers were authored: ceftriaxone is :broad and gentamicin :moderate, so the
  ;; objective walks past the cephalosporin entirely.
  ;;
  ;; The coverage-confidence cost is asserted alongside, because that is the trade
  ;; the narration is required to state: a narrower agent with a LOWER floor.
  (belief:use-system :dempster-shafer)
  (let ((conclusions '((:klebsiella . 0.40))))
    (with-objective (:lexicographic)
      (is (equal '(:meropenem)
                 (regimen-drugs (solve-with :exact conclusions (therapy:therapy-kb))))
          ":lexicographic returns the carbapenem"))
    (with-objective (:spectrum-sparing)
      (let* ((rec (solve-with :exact conclusions (therapy:therapy-kb)))
             (susc (therapy:susceptibility-item-value
                    (first (therapy:regimen-item-susceptibility
                            (first (therapy:recommendation-regimen rec)))))))
        (is (equal '(:gentamicin) (regimen-drugs rec))
            ":spectrum-sparing returns gentamicin, NOT ceftriaxone (3.6 finding 1)")
        (is (approx= 0.64 (belief:ds-belief-bel susc))
            "at a coverage floor of 0.64 -- against meropenem's 0.90")
        (is (< (belief:ds-belief-bel susc) 0.90)
            "narrowing costs coverage confidence, and the payload shows it")))))

(deftest spectrum-sparing-de-escalates-salmonella-and-culture-1 ()
  ;; design doc 3.6, the cases where the objective clearly earns its keep: both
  ;; move off the carbapenem to an agent a clinician would recognise as reasonable.
  (belief:use-system :dempster-shafer)
  (with-objective (:lexicographic)
    (is (equal '(:meropenem) (regimen-drugs (solve-with :exact '((:salmonella . 0.65))
                                                        (therapy:therapy-kb))))
        "salmonella: :lexicographic reaches for the carbapenem"))
  (with-objective (:spectrum-sparing)
    (is (equal '(:ciprofloxacin) (regimen-drugs (solve-with :exact '((:salmonella . 0.65))
                                                            (therapy:therapy-kb))))
        "salmonella: de-escalates to ciprofloxacin")
    ;; NOTE THE INPUT. This is a hand-built pair of organism conclusions, NOT culture-1
    ;; through the pipeline, and since Stage D the two no longer agree. Real culture-1
    ;; also carries 0.155 on the seven aerobic gram-negative rods, and covering that
    ;; obligation takes an agent ceftazidime cannot match -- so spectrum-sparing returns
    ;; meropenem there. See SET-OBLIGATION-CONSTRAINS-SPECTRUM-SPARING in
    ;; therapy-bridge-tests.lisp, which asserts what a clinician actually gets.
    ;;
    ;; Kept as a SOLVER unit test, which is what it always was: given exactly these two
    ;; organisms and nothing else, the narrower agent wins. The old name claimed more
    ;; than the input supported, and that mislabelling is why the pipeline could change
    ;; underneath a green suite.
    (is (equal '(:ceftazidime)
               (regimen-drugs (solve-with :exact '((:pseudomonas . 0.76) (:klebsiella . 0.40))
                                          (therapy:therapy-kb))))
        "two gram-negative organisms alone: de-escalates to ceftazidime, as 3.2 predicted")))

(deftest spectrum-sparing-agrees-where-narrow-already-won ()
  ;; bacteroides + S. aureus does NOT diverge: :lexicographic ALREADY returns
  ;; metronidazole + vancomycin, because the narrow agents happen to carry the best
  ;; susceptibility figures for their organisms. Pinned deliberately -- an earlier
  ;; draft of design doc 3.6 claimed this pair as a spectrum-sparing win, which was
  ;; an artifact of a buggy simulation rather than a real divergence. The objective
  ;; does not deserve credit for an answer the default already gives.
  (belief:use-system :dempster-shafer)
  (let ((conclusions '((:bacteroides . 0.55) (:staphylococcus-aureus . 0.60))))
    (flet ((run (obj) (with-objective (obj)
                        (sort (copy-list (regimen-drugs
                                          (solve-with :exact conclusions
                                                      (therapy:therapy-kb))))
                              #'string< :key #'symbol-name))))
      (is (equal '(:metronidazole :vancomycin) (run :lexicographic))
          ":lexicographic already picks the narrow pair here")
      (is (equal (run :lexicographic) (run :spectrum-sparing))
          "so the objectives agree -- no divergence to claim"))))

(deftest spectrum-sparing-keeps-cardinality-primary ()
  ;; design doc 7's open question, answered "no for now": the objective may NOT buy
  ;; narrowness with an extra drug. Two narrow agents must lose to one broad one.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:add-drug kb :one-broad :dose "1g" :spectrum :very-broad)
    (therapy:add-drug kb :narrow-a :dose "1g" :spectrum :very-narrow)
    (therapy:add-drug kb :narrow-b :dose "1g" :spectrum :very-narrow)
    (therapy:add-sensitivity kb :bug-1 :one-broad 0.8)
    (therapy:add-sensitivity kb :bug-2 :one-broad 0.8)
    (therapy:add-sensitivity kb :bug-1 :narrow-a 0.9)
    (therapy:add-sensitivity kb :bug-2 :narrow-b 0.9)
    (with-objective (:spectrum-sparing)
      (is (equal '(:one-broad)
                 (regimen-drugs (solve-with :exact '((:bug-1 . 0.7) (:bug-2 . 0.7)) kb)))
          "one very-broad drug still beats two very-narrow ones -- count stays primary"))))

(deftest spectrum-sparing-unauthored-tier-is-not-preferred ()
  ;; A drug with no authored tier must not win on breadth. Ranking the unknown as
  ;; narrowest would make a GAP IN THE KB read as a clinical virtue.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:add-drug kb :untiered :dose "1g")                      ; no :spectrum
    (therapy:add-drug kb :known-broad :dose "1g" :spectrum :broad)
    (therapy:add-sensitivity kb :bug :untiered 0.9)
    (therapy:add-sensitivity kb :bug :known-broad 0.8)
    (with-objective (:spectrum-sparing)
      (is (equal '(:known-broad) (regimen-drugs (solve-with :exact '((:bug . 0.7)) kb)))
          "an authored :broad beats an unauthored tier, despite lower susceptibility"))))

(deftest spectrum-sparing-agrees-where-spectrum-is-silent ()
  ;; When every candidate shares a tier, the objective must fall through to the
  ;; lexicographic key -- the two dials should differ only where breadth differs.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:add-drug kb :a-drug :dose "1g" :spectrum :moderate)
    (therapy:add-drug kb :b-drug :dose "1g" :spectrum :moderate)
    (therapy:add-sensitivity kb :bug :a-drug 0.7)
    (therapy:add-sensitivity kb :bug :b-drug 0.9)
    (let ((lex (with-objective (:lexicographic)
                 (regimen-drugs (solve-with :exact '((:bug . 0.7)) kb))))
          (spare (with-objective (:spectrum-sparing)
                   (regimen-drugs (solve-with :exact '((:bug . 0.7)) kb)))))
      (is (equal '(:b-drug) lex) "lexicographic takes the stronger agent")
      (is (equal lex spare) "equal breadth -> the objectives agree"))))

(deftest spectrum-sparing-cannot-see-reserve-status ()
  ;; design doc 3.6, finding 3 -- pinned as a KNOWN LIMITATION, not an aspiration.
  ;;
  ;; This does not merely lurk; it FIRES. For enterococcus the objective moves off
  ;; ampicillin (WHO AWaRe *Access*, :moderate) onto linezolid (AWaRe *Reserve*,
  ;; :narrow), because linezolid is genuinely the narrower agent and breadth is the
  ;; only axis the objective can see. Narrowing spectrum and escalating reserve
  ;; status are different things, and optimising the first can worsen the second.
  ;;
  ;; Shipped as measured (3.6, option (a)) rather than patched: the honest
  ;; demonstration of a policy dial includes what it gets wrong.
  (belief:use-system :dempster-shafer)
  (with-objective (:lexicographic)
    (is (equal '(:ampicillin) (regimen-drugs (solve-with :exact '((:enterococcus . 0.60))
                                                         (therapy:therapy-kb))))
        "enterococcus: the default picks ampicillin (AWaRe Access)"))
  (with-objective (:spectrum-sparing)
    (is (equal '(:linezolid) (regimen-drugs (solve-with :exact '((:enterococcus . 0.60))
                                                        (therapy:therapy-kb))))
        "enterococcus: spectrum-sparing escalates to linezolid (AWaRe Reserve)"))
  (let ((kb (therapy:therapy-kb)))
    (is (< (therapy:spectrum-rank (therapy:kb-drug-spectrum kb :linezolid))
           (therapy:spectrum-rank (therapy:kb-drug-spectrum kb :ampicillin)))
        "and it is not a bug in the search: linezolid really is the narrower agent")
    (is (eq (therapy:kb-drug-spectrum kb :nafcillin)
            (therapy:kb-drug-spectrum kb :vancomycin))
        "the axis likewise cannot separate nafcillin from vancomycin"))
  ;; And the blindness is not the objective's alone. The engine never produces
  ;; enterococcus in isolation -- the bile-esculin rule fires alongside the
  ;; gram-positive-cocci-in-chains rule, so a real case carries streptococcus 0.7 AND
  ;; enterococcus 0.8. Both linezolid and ampicillin cover that pair, and linezolid
  ;; wins on susceptibility, so :LEXICOGRAPHIC reaches for the Reserve agent too
  ;; (design doc 3.6). Pinned here so the limitation is not filed under
  ;; "spectrum-sparing's fault".
  (let ((pair '((:streptococcus . 0.7) (:enterococcus . 0.8))))
    (dolist (obj '(:lexicographic :spectrum-sparing))
      (with-objective (obj)
        (is (equal '(:linezolid) (regimen-drugs (solve-with :exact pair
                                                            (therapy:therapy-kb))))
            (format nil "~A picks linezolid for the streptococcus/enterococcus pair"
                    obj))))
    (with-objective (:lexicographic)
      (is (member '(:ampicillin)
                  (alt-regimen-drugsets (solve-with :exact pair (therapy:therapy-kb)))
                  :test #'equal)
          "and ampicillin, the Access agent, is reported as an equally minimal option"))))

;;; ------------------------------------------------------------------
;;; 2c. The :stewardship objective -- the WHO AWaRe axis (design doc 3.7)
;;;
;;; Added after a live consultation (2026-08-26) asked for `spectrum-sparing' on a
;;; group A strep and got VANCOMYCIN. That was not a bug: vancomycin, nafcillin and
;;; linezolid all sit in the :narrow tier, so the tiebreak fell through to
;;; susceptibility and vancomycin won it. Breadth and reserve status are different
;;; axes, and SPECTRUM-SPARING-CANNOT-SEE-RESERVE-STATUS below has pinned that gap as
;;; a known limitation since slice 4. These tests pin the axis that closes it.
;;; ------------------------------------------------------------------

(deftest stewardship-tiers-are-authored-for-every-drug ()
  ;; Same completeness argument as the spectrum tiers, and the same silent failure
  ;; mode: an unauthored drug is invisible to the ordering.
  (let ((kb (therapy:therapy-kb)))
    (dolist (d (therapy:kb-drug-ids kb))
      (let ((tier (therapy:kb-drug-stewardship kb d)))
        (is (member tier therapy:*stewardship-tiers*)
            (format nil "~A carries a valid AWaRe tier (got ~S)" d tier))))))

(deftest stewardship-tiers-are-ordinal-cheapest-first ()
  (is (= 0 (therapy:stewardship-rank :access)) "access ranks lowest -- cheapest to spend")
  (is (< (therapy:stewardship-rank :access) (therapy:stewardship-rank :watch))
      "access < watch")
  (is (< (therapy:stewardship-rank :watch) (therapy:stewardship-rank :reserve))
      "watch < reserve")
  (is (null (therapy:stewardship-rank :not-a-tier)) "an unknown tier has no rank"))

(deftest stewardship-assignments-match-the-published-classification ()
  ;; UNLIKE the spectrum tiers, these are NOT this project's judgement -- WHO AWaRe is
  ;; published, and every tier here was already annotated in knowledge-base.lisp's
  ;; per-drug sections before it was encoded. Pinned so a future edit has to be
  ;; deliberate, and so the two axes can be seen coming apart.
  (let ((kb (therapy:therapy-kb)))
    (flet ((tier (d) (therapy:kb-drug-stewardship kb d)))
      (is (eq :reserve (tier :linezolid)) "linezolid is AWaRe Reserve")
      (is (eq :access (tier :ampicillin)) "ampicillin is AWaRe Access")
      (is (eq :access (tier :nafcillin)) "nafcillin is AWaRe Access")
      (is (eq :watch (tier :vancomycin)) "vancomycin is AWaRe Watch")
      (is (eq :watch (tier :meropenem)) "meropenem is AWaRe Watch")
      ;; THE POINT OF THE WHOLE AXIS, stated as a relation: on breadth vancomycin is
      ;; narrower than ampicillin; on stewardship it is dearer. Neither is wrong --
      ;; they answer different questions, and no single ordering can carry both.
      (is (< (therapy:spectrum-rank (therapy:kb-drug-spectrum kb :vancomycin))
             (therapy:spectrum-rank (therapy:kb-drug-spectrum kb :ampicillin)))
          "vancomycin is the NARROWER agent")
      (is (> (therapy:stewardship-rank (tier :vancomycin))
             (therapy:stewardship-rank (tier :ampicillin)))
          "...and simultaneously the DEARER one -- the axes disagree by construction"))))

(deftest stewardship-closes-the-reserve-gap ()
  ;; The counterpart to SPECTRUM-SPARING-CANNOT-SEE-RESERVE-STATUS, which pins the
  ;; same case going the wrong way. Enterococcus: spectrum-sparing escalates to
  ;; linezolid (Reserve) because it is genuinely narrower; stewardship keeps
  ;; ampicillin (Access). Both objectives are behaving correctly on their own axis.
  (belief:use-system :dempster-shafer)
  (let ((solo '((:enterococcus . 0.60))))
    (with-objective (:spectrum-sparing)
      (is (equal '(:linezolid) (regimen-drugs (solve-with :exact solo (therapy:therapy-kb))))
          "spectrum-sparing still escalates to the Reserve agent -- unchanged"))
    (with-objective (:stewardship)
      (is (equal '(:ampicillin) (regimen-drugs (solve-with :exact solo (therapy:therapy-kb))))
          "stewardship holds the Access agent")))
  ;; And on the pair the engine actually produces, where BOTH existing objectives
  ;; reach for linezolid, stewardship is the only one that does not.
  (let ((pair '((:streptococcus . 0.7) (:enterococcus . 0.8))))
    (dolist (obj '(:lexicographic :spectrum-sparing))
      (with-objective (obj)
        (is (equal '(:linezolid) (regimen-drugs (solve-with :exact pair (therapy:therapy-kb))))
            (format nil "~A reaches for linezolid on the pair" obj))))
    (with-objective (:stewardship)
      (is (equal '(:ampicillin) (regimen-drugs (solve-with :exact pair (therapy:therapy-kb))))
          "stewardship picks ampicillin on the pair -- the Access agent"))))

(deftest stewardship-diverges-on-the-live-group-a-strep-case ()
  ;; THE CASE THAT MOTIVATED THE AXIS, pinned from the 2026-08-26 transcript: an
  ;; 85-year-old with a beta-hemolytic, bacitracin-sensitive group A strep and no
  ;; contraindications. Both existing objectives return vancomycin (Watch); the model
  ;; had to talk the clinician out of the recommendation in prose.
  (belief:use-system :dempster-shafer)
  (let ((pyogenes '((:streptococcus-pyogenes . 0.8347))))
    (dolist (obj '(:lexicographic :spectrum-sparing))
      (with-objective (obj)
        (is (equal '(:vancomycin)
                   (regimen-drugs (solve-with :exact pyogenes (therapy:therapy-kb))))
            (format nil "~A returns vancomycin for group A strep" obj))))
    (with-objective (:stewardship)
      (is (equal '(:ampicillin)
                 (regimen-drugs (solve-with :exact pyogenes (therapy:therapy-kb))))
          "stewardship returns ampicillin -- the clinically standard choice"))
    ;; With ampicillin and nafcillin contraindicated, falling back to the Watch agent
    ;; is correct rather than a failure: there is no Access agent left to hold.
    (with-objective (:stewardship)
      (is (equal '(:vancomycin)
                 (regimen-drugs (solve-with :exact pyogenes (therapy:therapy-kb)
                                            '(:allergy-penicillin))))
          "under a penicillin allergy it falls back to Watch, as it must"))))

(deftest stewardship-keeps-cardinality-primary ()
  ;; THE LIMITATION, pinned so it cannot be mistaken for an oversight: no objective
  ;; can buy a cheaper tier with an extra drug. Real stewardship sometimes wants
  ;; exactly that trade, and expressing it would mean changing what the solver
  ;; SEARCHES rather than how it breaks ties.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:add-drug kb :one-reserve :dose "1g" :stewardship :reserve)
    (therapy:add-drug kb :access-a :dose "1g" :stewardship :access)
    (therapy:add-drug kb :access-b :dose "1g" :stewardship :access)
    (therapy:add-sensitivity kb :bug-1 :one-reserve 0.8)
    (therapy:add-sensitivity kb :bug-2 :one-reserve 0.8)
    (therapy:add-sensitivity kb :bug-1 :access-a 0.9)
    (therapy:add-sensitivity kb :bug-2 :access-b 0.9)
    (with-objective (:stewardship)
      (is (equal '(:one-reserve)
                 (regimen-drugs (solve-with :exact '((:bug-1 . 0.7) (:bug-2 . 0.7)) kb)))
          "one Reserve drug still beats two Access ones -- count stays primary")))
  ;; And it FIRES on the real corpus, not only on a fixture: culture-3's differential
  ;; has exactly one single-drug cover, and it is linezolid.
  (belief:use-system :dempster-shafer)
  (with-objective (:stewardship)
    (let ((rec (solve-with :exact '((:streptococcus-pneumoniae . 0.2842)
                                    (:streptococcus-viridans . 0.1263)
                                    (:enterococcus-faecalis . 0.11))
                           (therapy:therapy-kb))))
      (is (equal '(:linezolid) (regimen-drugs rec))
          "stewardship still returns the Reserve agent when it is the only 1-drug cover")
      (is (null (alt-regimen-drugsets rec))
          "...and there is genuinely no other minimum-size regimen to prefer"))))

(deftest stewardship-unauthored-tier-is-not-preferred ()
  ;; Mirrors SPECTRUM-SPARING-UNAUTHORED-TIER-IS-NOT-PREFERRED, and matters more here:
  ;; a KB gap must never read as "cheap to spend".
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:add-drug kb :untiered :dose "1g")                        ; no :stewardship
    (therapy:add-drug kb :known-reserve :dose "1g" :stewardship :reserve)
    (therapy:add-sensitivity kb :bug :untiered 0.9)
    (therapy:add-sensitivity kb :bug :known-reserve 0.8)
    (with-objective (:stewardship)
      (is (equal '(:known-reserve) (regimen-drugs (solve-with :exact '((:bug . 0.7)) kb)))
          "an authored :reserve beats an unauthored tier, despite lower susceptibility"))))

(deftest stewardship-agrees-where-the-axis-is-silent ()
  ;; Equal tiers -> fall through to the lexicographic key, so the three objectives
  ;; differ only where their axis has something to say.
  (therapy:with-therapy-kb (kb (therapy:make-therapy-kb))
    (therapy:add-drug kb :a-drug :dose "1g" :stewardship :watch)
    (therapy:add-drug kb :b-drug :dose "1g" :stewardship :watch)
    (therapy:add-sensitivity kb :bug :a-drug 0.7)
    (therapy:add-sensitivity kb :bug :b-drug 0.9)
    (let ((lex (with-objective (:lexicographic)
                 (regimen-drugs (solve-with :exact '((:bug . 0.7)) kb))))
          (stew (with-objective (:stewardship)
                  (regimen-drugs (solve-with :exact '((:bug . 0.7)) kb)))))
      (is (equal '(:b-drug) lex) "lexicographic takes the stronger agent")
      (is (equal lex stew) "equal AWaRe tier -> the objectives agree"))))

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

;;; ------------------------------------------------------------------
;;; 3.1 The gate's other side -- BELOW-THRESHOLD and incidental coverage.
;;;
;;; The defect: a live consultation put Klebsiella at 0.097 against a 0.1 gate, so
;;; it was not treated -- and the meropenem the solver returned covers Klebsiella
;;; at [0.88, 0.99]. The payload said `items_to_treat: [pseudomonas]` and the
;;; regimen said `covers: [pseudomonas]`, both true, and the clinician was told the
;;; runner-up was untreated while holding a prescription that covers it well.
;;;
;;; REGIMEN-ITEM-COVERS reports what the solver was TARGETING; it cannot be widened
;;; to mean "everything this drug happens to cover" without changing what the
;;; solver's own coverage arithmetic means. So the fact is reported alongside it
;;; instead.
;;; ------------------------------------------------------------------

(defun below-threshold-organisms (rec)
  (mapcar #'therapy:below-threshold-item-organism
          (therapy:recommendation-below-threshold rec)))

(defun incidental-drugs-for (rec organism)
  (let ((item (find organism (therapy:recommendation-below-threshold rec)
                    :key #'therapy:below-threshold-item-organism)))
    (and item (mapcar #'therapy:incidental-cover-drug
                      (therapy:below-threshold-item-covered-by item)))))

(deftest below-threshold-reports-incidental-coverage ()
  ;; The regression, at the beliefs the live case actually produced.
  (let* ((conclusions '((:pseudomonas . 0.8375) (:klebsiella . 0.0975)))
         (rec (solve-with :exact conclusions (therapy:therapy-kb))))
    (is (equal (treated rec) '(:pseudomonas))
        "the 0.1 gate still drops klebsiella at 0.0975 -- the gate is unchanged")
    (is (equal (below-threshold-organisms rec) '(:klebsiella))
        "and klebsiella is now REPORTED as dropped rather than simply absent")
    (is (member :meropenem (incidental-drugs-for rec :klebsiella))
        "the chosen regimen covers klebsiella anyway, and the payload says so")))

(deftest below-threshold-covered-by-is-empty-when-truly-uncovered ()
  ;; The other half, and the reason COVERED-BY is a list rather than a flag: a
  ;; dropped organism the regimen does NOT reach must be distinguishable from one
  ;; it does. Bacteroides is below the gate here and nafcillin does not cover it.
  (let* ((conclusions '((:staphylococcus-aureus . 0.70) (:bacteroides . 0.02)))
         (rec (solve-with :exact conclusions (therapy:therapy-kb))))
    (is (equal (below-threshold-organisms rec) '(:bacteroides))
        "bacteroides is below the gate and reported")
    (is (null (incidental-drugs-for rec :bacteroides))
        "and nothing in the regimen covers it -- an empty covered_by, not a missing one")))

(deftest below-threshold-and-treated-partition-the-differential ()
  ;; Nothing in the differential may be silently dropped from the report, and
  ;; nothing may appear on both sides of the gate. This is the invariant that makes
  ;; the field trustworthy to narrate from.
  (dolist (case *equivalence-cases*)
    (destructuring-bind (label conclusions) case
      (let* ((rec (solve-with :exact conclusions (therapy:therapy-kb)))
             (all (sort (mapcar #'car conclusions) #'string< :key #'symbol-name))
             (reported (sort (append (treated rec) (below-threshold-organisms rec))
                             #'string< :key #'symbol-name)))
        (is (equal all reported)
            (format nil "~A: every concluded organism appears exactly once, either ~
                         treated or below threshold" label))))))

(deftest exact-greedy-agree-on-below-threshold ()
  ;; Like ALTERNATIVE-AGENTS, this is a fact about the gate and the KB rather than
  ;; about the search, so a solver swap must not change it. It is computed against
  ;; the CHOSEN regimen, so incidental coverage is only comparable when the two
  ;; solvers picked the same drugs.
  (dolist (case *equivalence-cases*)
    (destructuring-bind (label conclusions) case
      (let ((g (solve-with :greedy conclusions (therapy:therapy-kb)))
            (e (solve-with :exact conclusions (therapy:therapy-kb))))
        (is (equal (below-threshold-organisms g) (below-threshold-organisms e))
            (format nil "~A: both solvers drop the same organisms at the gate" label))
        (when (equal (sort (copy-list (regimen-drugs g)) #'string< :key #'symbol-name)
                     (sort (copy-list (regimen-drugs e)) #'string< :key #'symbol-name))
          (dolist (org (below-threshold-organisms e))
            (is (equal (incidental-drugs-for g org) (incidental-drugs-for e org))
                (format nil "~A: same regimen => same incidental coverage of ~A"
                        label org))))))))

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