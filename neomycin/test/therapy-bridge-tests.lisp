;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: Integration tests for the therapy phase's bridge glue (design doc
;; step (c)). Unlike therapy-tests.lisp (solver in isolation), these drive the
;; real engine through a MYCIN scenario, read the identification conclusions off
;; working memory with CONCLUSIONS-FOR-SOLVER, recommend over the canonical KB,
;; and render the result with RECOMMENDATION->JSON -- the whole Lisp path the
;; /recommend-therapy handler runs, minus HTTP (that is covered by the curl smoke
;; test, bin/test-therapy.sh). Reuses the LISA-TEST harness + its RUN-SCENARIO.

(in-package "LISA-TEST")

;;; culture-1 under CF yields two leaf-species gram-negative identities
;;; (pseudomonas 0.76, klebsiella 0.40), both above *coverage-threshold* and both
;;; covered by the canonical KB's broad agents. Enterobacteriaceae is NO LONGER a
;;; conclusion here (C2): it is a family CLASS, and its member klebsiella clears the
;;; gate, so the family backstop is suppressed (see the backstop tests below).

(deftest therapy-bridge-conclusions-are-keyword-organisms ()
  ;; The glue reads keyword organism ids straight off working memory -- no
  ;; conversion -- which is exactly what lets them key the therapy KB.
  (run-scenario 'lisa-user::culture-1 :certainty-factors)
  (let ((concl (therapy:conclusions-for-solver)))
    (is (= 2 (length concl)) "two organism-identity conclusions")
    (is (every #'keywordp (mapcar #'car concl)) "every organism id is a keyword")
    (is (assoc :pseudomonas concl) "pseudomonas present as :pseudomonas")
    (is (numberp (cdr (assoc :pseudomonas concl))) "belief is a CF number under CF")))

(deftest therapy-bridge-recommend-end-to-end ()
  ;; Full identify -> treat path in Lisp: engine conclusions -> solver -> regimen.
  (run-scenario 'lisa-user::culture-1 :certainty-factors)
  (therapy:with-greedy-solver
    (let ((rec (therapy:recommend (therapy:conclusions-for-solver)
                                  (therapy:therapy-kb) '())))
      (is (= 2 (length (therapy:recommendation-items-to-treat rec)))
          "both leaf-species organisms are items to treat")
      (is (plusp (length (therapy:recommendation-regimen rec))) "a regimen was produced")
      (is (null (therapy:recommendation-uncovered rec)) "culture-1 gram-negs fully covered"))))

(deftest therapy-bridge-recommendation->json-shape ()
  ;; The serializer renders JSON-ready hash-tables: lists as vectors (JSON
  ;; arrays), keyword ids as downcased strings.
  (run-scenario 'lisa-user::culture-1 :certainty-factors)
  (therapy:with-greedy-solver
    (let* ((rec (therapy:recommend (therapy:conclusions-for-solver)
                                   (therapy:therapy-kb) '()))
           (json (therapy:recommendation->json rec)))
      (is (typep (gethash "regimen" json) 'vector) "regimen is a JSON array")
      (is (plusp (length (gethash "regimen" json))) "regimen non-empty")
      (is (= 2 (length (gethash "items_to_treat" json))) "two items_to_treat")
      (is (typep (gethash "uncovered" json) 'vector) "uncovered is a JSON array")
      (is (zerop (length (gethash "uncovered" json))) "nothing uncovered")
      (let ((drug (gethash "drug" (aref (gethash "regimen" json) 0))))
        (is (stringp drug) "regimen drug rendered as a string")
        (is (string= (string-downcase drug) drug) "drug name is downcased")))))

(deftest therapy-bridge-contraindication-serialized ()
  ;; A cephalosporin allergy excludes ceftazidime; the JSON records the exclusion
  ;; and an alternative still covers everything.
  (run-scenario 'lisa-user::culture-1 :certainty-factors)
  (therapy:with-greedy-solver
    (let* ((rec (therapy:recommend (therapy:conclusions-for-solver)
                                   (therapy:therapy-kb) '(:allergy-cephalosporin)))
           (json (therapy:recommendation->json rec))
           (excluded (gethash "excluded" json)))
      (is (typep excluded 'vector) "excluded is a JSON array")
      (is (find "ceftazidime" excluded
                :key #'(lambda (e) (gethash "drug" e)) :test #'string=)
          "ceftazidime recorded as excluded")
      (is (null (therapy:recommendation-uncovered rec))
          "still fully covered by an alternative"))))

;;; ------------------------------------------------------------------
;;; Family-as-backstop item selection (C2). The family enterobacteriaceae is
;;; carried to the solver ONLY when no member species clears the coverage gate;
;;; when a member does, the member covers the family and the backstop is
;;; suppressed. We never treat both a family and its own member.
;;; ------------------------------------------------------------------

(deftest therapy-bridge-family-backstop-fires-when-no-species-identified ()
  ;; culture-multi's o1 is a bare aerobic gram-neg rod: it yields the
  ;; enterobacteriaceae CLASS but no member species. With nothing below it clearing
  ;; the gate, the family must be carried in as a backstop item so the organism is
  ;; still treated empirically.
  ;;
  ;; o2 now demonstrates the OPPOSITE arm of the same rule, which is why this scenario
  ;; is worth more than it used to be. Before the gram-positive increment o2 stopped at
  ;; a :staphylococcus leaf identity; it is now a coagulase-positive organism refined to
  ;; S. aureus, so the genus is suppressed exactly as enterobacteriaceae is in
  ;; therapy-bridge-family-backstop-suppressed-when-member-covers. One scenario, both
  ;; arms: family treated empirically where nothing is pinned down, species treated
  ;; alone where something is.
  (run-scenario 'lisa-user::culture-multi :certainty-factors)
  (let ((concl (therapy:conclusions-for-solver)))
    (is (assoc :enterobacteriaceae concl)
        "family enterobacteriaceae is a backstop item when no member species clears the gate")
    (is (null (intersection '(:klebsiella :e-coli :salmonella :enterobacter :serratia :proteus)
                            (mapcar #'car concl)))
        "no enterobacteriaceae member species was identified in culture-multi")
    (is (assoc :staphylococcus-aureus concl)
        "o2 is refined to the S. aureus species by its positive coagulase")
    (is (not (assoc :staphylococcus concl))
        "the staphylococcus GENUS is suppressed -- its member species covers it")))

(deftest therapy-bridge-family-backstop-suppressed-when-member-covers ()
  ;; culture-1 identifies klebsiella (0.40), a member species that clears the
  ;; coverage gate, so the enterobacteriaceae family is NOT separately treated --
  ;; the member carries the family's coverage need.
  (run-scenario 'lisa-user::culture-1 :certainty-factors)
  (let ((concl (therapy:conclusions-for-solver)))
    (is (assoc :klebsiella concl) "klebsiella (a family member) was identified")
    (is (not (assoc :enterobacteriaceae concl))
        "the family is suppressed because a member species clears the gate")))