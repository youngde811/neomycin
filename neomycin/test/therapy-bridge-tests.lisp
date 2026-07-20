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

;;; culture-1 under CF yields three gram-negative identities (pseudomonas 0.76,
;;; enterobacteriaceae 0.80, klebsiella 0.50), all above *coverage-threshold* and
;;; all covered by the canonical KB's broad agents.

(deftest therapy-bridge-conclusions-are-keyword-organisms ()
  ;; The glue reads keyword organism ids straight off working memory -- no
  ;; conversion -- which is exactly what lets them key the therapy KB.
  (run-scenario 'lisa-user::culture-1 :certainty-factors)
  (let ((concl (therapy:conclusions-for-solver)))
    (is (= 3 (length concl)) "three organism-identity conclusions")
    (is (every #'keywordp (mapcar #'car concl)) "every organism id is a keyword")
    (is (assoc :pseudomonas concl) "pseudomonas present as :pseudomonas")
    (is (numberp (cdr (assoc :pseudomonas concl))) "belief is a CF number under CF")))

(deftest therapy-bridge-recommend-end-to-end ()
  ;; Full identify -> treat path in Lisp: engine conclusions -> solver -> regimen.
  (run-scenario 'lisa-user::culture-1 :certainty-factors)
  (therapy:with-greedy-solver
    (let ((rec (therapy:recommend (therapy:conclusions-for-solver)
                                  (therapy:therapy-kb) '())))
      (is (= 3 (length (therapy:recommendation-items-to-treat rec)))
          "all three organisms are items to treat")
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
      (is (= 3 (length (gethash "items_to_treat" json))) "three items_to_treat")
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