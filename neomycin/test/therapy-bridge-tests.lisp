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
;;; (pseudomonas 0.76, klebsiella 0.40), both above *coverage-threshold* (0.1 since v0.11) and both
;;; covered by the canonical KB's broad agents. Enterobacteriaceae is NO LONGER a
;;; conclusion here (C2): it is a family CLASS, and its member klebsiella clears the
;;; gate, so the family backstop is suppressed (see the backstop tests below).

(deftest therapy-bridge-conclusions-are-keyword-organisms ()
  ;; The glue reads keyword organism ids straight off working memory -- no
  ;; conversion -- which is exactly what lets them key the therapy KB.
  ;;
  ;; CONCLUSIONS NOW CARRIES TWO KINDS OF ENTRY. An organism entry is
  ;; (KEYWORD . BELIEF); a set-valued obligation is ((KEYWORD ...) . MASS), told
  ;; apart by whether the car is a list. Both must be covered and neither
  ;; substitutes for the other -- conflating them is what the suppression rule did.
  (run-scenario 'lisa-user::culture-1 :candidates)
  (let* ((concl (therapy:conclusions-for-solver))
         (organisms (remove-if #'therapy:set-entry-p concl))
         (sets (remove-if-not #'therapy:set-entry-p concl)))
    (is (= 2 (length organisms)) "two organism-identity conclusions")
    (is (every #'keywordp (mapcar #'car organisms)) "every organism id is a keyword")
    (is (assoc :pseudomonas organisms) "pseudomonas present as :pseudomonas")
    (is (numberp (cdr (assoc :pseudomonas organisms))) "belief is a number")
    ;; culture-1 puts 0.155 on the seven aerobic gram-negative rods.
    (is (= 1 (length sets)) "the seven-member aerobic gram-neg rod answer is carried too")
    (is (every #'keywordp (car (first sets))) "its members are keywords")))

(deftest therapy-bridge-recommend-end-to-end ()
  ;; Full identify -> treat path in Lisp: engine conclusions -> solver -> regimen.
  (run-scenario 'lisa-user::culture-1 :candidates)
  (therapy:with-greedy-solver
    (let ((rec (therapy:recommend (therapy:conclusions-for-solver)
                                  (therapy:therapy-kb) '())))
      ;; TWO items again, after the v0.11 recalibration of *coverage-threshold* from
      ;; 0.2 to 0.1. Klebsiella projects to Bel 0.194 here; it cleared the old gate at
      ;; 0.286 under the pre-v0.11 representation, missed the unchanged 0.2 gate by
      ;; 0.006 once organisms began competing for one unit of mass, and clears again
      ;; now that the dial matches the scale. The gate decides only five figures in the
      ;; whole corpus and 0.1 sits mid-plateau -- see the threshold's docstring.
      (is (= 2 (length (therapy:recommendation-items-to-treat rec)))
          "pseudomonas AND klebsiella are items to treat under the recalibrated gate")
      (is (plusp (length (therapy:recommendation-regimen rec))) "a regimen was produced")
      (is (null (therapy:recommendation-uncovered rec)) "culture-1 gram-negs fully covered"))))

(deftest therapy-bridge-recommendation->json-shape ()
  ;; The serializer renders JSON-ready hash-tables: lists as vectors (JSON
  ;; arrays), keyword ids as downcased strings.
  (run-scenario 'lisa-user::culture-1 :candidates)
  (therapy:with-greedy-solver
    (let* ((rec (therapy:recommend (therapy:conclusions-for-solver)
                                   (therapy:therapy-kb) '()))
           (json (therapy:recommendation->json rec)))
      (is (typep (gethash "regimen" json) 'vector) "regimen is a JSON array")
      (is (plusp (length (gethash "regimen" json))) "regimen non-empty")
      (is (= 2 (length (gethash "items_to_treat" json)))
          "two items_to_treat -- see therapy-bridge-recommend-end-to-end for why")
      (is (typep (gethash "uncovered" json) 'vector) "uncovered is a JSON array")
      (is (zerop (length (gethash "uncovered" json))) "nothing uncovered")
      (let ((drug (gethash "drug" (aref (gethash "regimen" json) 0))))
        (is (stringp drug) "regimen drug rendered as a string")
        (is (string= (string-downcase drug) drug) "drug name is downcased")))))

(deftest therapy-bridge-contraindication-serialized ()
  ;; A cephalosporin allergy excludes ceftazidime; the JSON records the exclusion
  ;; and an alternative still covers everything.
  (run-scenario 'lisa-user::culture-1 :candidates)
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
;;; Set-valued obligations reaching the solver (Stage D).
;;;
;;; These tests used to assert the FAMILY BACKSTOP: a set-valued answer was collapsed
;;; onto a KB family and carried in only when no member cleared the coverage gate.
;;; Both halves were unsound and both are gone.
;;;
;;;   SUPPRESSION. Mass on {A..G} is committed to no member in particular, so a
;;;   member clearing the gate does not discharge it. Measured: four of sixty
;;;   scenario x patient x objective configurations were silently under-covering.
;;;
;;;   THE FAMILY PROXY. Ceftazidime covers :enterobacteriaceae at bel 0.66 and
;;;   :salmonella at 0.46; against a 0.5 threshold the family read as covered while
;;;   the member was not. An obligation is now discharged MEMBER BY MEMBER.
;;; ------------------------------------------------------------------

(defun set-obligations-in (concl)
  "The set-valued entries of a CONCLUSIONS alist, as (members . mass)."
  (remove-if-not #'therapy:set-entry-p concl))

(deftest set-obligation-carried-when-no-member-is-identified ()
  ;; culture-multi's o1 is a bare aerobic gram-neg rod: it names a SET and no member
  ;; species. That set must reach the solver, or the organism goes untreated.
  ;;
  ;; o2 is the contrast: a coagulase-positive organism refined to S. aureus, which is
  ;; a named organism and appears as one. One scenario, both kinds of entry.
  (run-scenario 'lisa-user::culture-multi :candidates)
  (let* ((concl (therapy:conclusions-for-solver))
         (sets (set-obligations-in concl)))
    (is (plusp (length sets))
        "a set-valued obligation is carried when no member species was identified")
    (is (some (lambda (e) (member :klebsiella (car e))) sets)
        "and the aerobic gram-neg rod answer is among them")
    (is (not (assoc :enterobacteriaceae concl))
        "the KB FAMILY is not injected as a pseudo-organism -- it covers :salmonella at
         0.66 while the species itself sits at 0.46, so a family proxy hides the gap")
    (is (assoc :staphylococcus-aureus concl)
        "o2 is refined to the S. aureus species by its positive coagulase")))

(deftest set-obligation-is-not-suppressed-by-a-member-clearing-the-gate ()
  ;; THE REGRESSION. culture-1 identifies pseudomonas (0.613) and klebsiella (0.194),
  ;; both members of the seven-member aerobic gram-negative rod answer that carries
  ;; 0.155. The old rule dropped that answer BECAUSE those members cleared the gate.
  ;;
  ;; It should not have. 0.155 is mass committed to no member in particular; covering
  ;; two of the seven leaves it undischarged, and under a narrow regimen the leftover
  ;; is real -- see SET-OBLIGATION-UNCOVERED-IS-REPORTED.
  (run-scenario 'lisa-user::culture-1 :candidates)
  (let* ((concl (therapy:conclusions-for-solver))
         (sets (set-obligations-in concl)))
    (is (assoc :klebsiella concl) "klebsiella, a member, was identified and clears the gate")
    (is (plusp (length sets))
        "and the set-valued answer is STILL carried -- a member clearing the gate does
         not discharge mass committed to no member")
    (is (some (lambda (e) (and (member :salmonella (car e))
                               (member :pseudomonas (car e))))
              sets)
        "the seven-member answer is the one carried")))
;;; ------------------------------------------------------------------
;;; Stage D end to end: the obligation reaches the SOLVER, not just the payload.
;;;
;;; These run the whole pipeline -- scenario -> consensus -> conclusions-for-solver ->
;;; solver -- because that is the only level at which the defect was visible. The
;;; solver unit tests pass hand-built organism alists that carry no set-valued answer,
;;; so they stayed green through the entire bug and through its fix.
;;; ------------------------------------------------------------------

(deftest set-obligation-uncovered-is-reported ()
  ;; With the carbapenem removed, culture-1's regimen must still cover all seven
  ;; members of the 0.155 answer. Before Stage D it returned ceftazidime, which misses
  ;; Salmonella, and reported `uncovered: ()' -- a false all-clear.
  (run-scenario 'lisa-user::culture-1 :candidates)
  (therapy:with-exact-solver
    (let* ((rec (therapy:recommend (therapy:conclusions-for-solver)
                                   (therapy:therapy-kb) '(:allergy-carbapenem)))
           (obligations (therapy:recommendation-set-obligations rec)))
      (is (plusp (length obligations)) "the set-valued answer reached the solver")
      (dolist (o obligations)
        (is (null (therapy:set-obligation-uncovered o))
            (format nil "every member of the ~,3F answer is covered"
                    (therapy:set-obligation-mass o))))
      (is (not (member :ceftazidime (mapcar #'therapy:regimen-item-drug
                                            (therapy:recommendation-regimen rec))))
          "and ceftazidime is no longer chosen -- it misses salmonella at bel 0.46"))))

(deftest set-obligation-constrains-spectrum-sparing ()
  ;; The uncomfortable consequence, recorded rather than smoothed over. The measured
  ;; divergence table had culture-1 de-escalating from meropenem to ceftazidime under
  ;; :spectrum-sparing. That de-escalation was buying narrowness by silently dropping
  ;; a member of the set-valued answer, so it is gone: covering the whole obligation
  ;; in one drug takes a broad agent, and drug COUNT stays primary under both
  ;; objectives. The dial still de-escalates elsewhere (salmonella -> ciprofloxacin).
  (run-scenario 'lisa-user::culture-1 :candidates)
  (therapy:with-exact-solver
    (let ((lex (with-objective (:lexicographic)
                 (regimen-drugs (therapy:recommend (therapy:conclusions-for-solver)
                                                   (therapy:therapy-kb) '()))))
          (sparing (with-objective (:spectrum-sparing)
                     (regimen-drugs (therapy:recommend (therapy:conclusions-for-solver)
                                                       (therapy:therapy-kb) '())))))
      (is (equal '(:meropenem) lex) "culture-1 lexicographic is unchanged")
      (is (equal '(:meropenem) sparing)
          "and spectrum-sparing no longer diverges here -- the narrower agent did not
           cover the set-valued answer, which is why it looked narrower"))))

(deftest supporting-evidence-can-drop-an-organism-out-of-coverage ()
  ;; culture-1b is culture-1 plus `hospital-acquired'. That fact SUPPORTS klebsiella --
  ;; it fires a stronger, more specific rule (0.6) that subsumes the compromised-host
  ;; one (0.5) -- and klebsiella nonetheless falls from 0.194 to 0.097, across the 0.1
  ;; coverage gate, because the same fact fires a third pseudomonas rule.
  ;;
  ;; The engine is right and the optics are terrible, so the payload has to carry
  ;; everything needed to explain it. This is also the ONLY scenario that exercises
  ;; BELOW-THRESHOLD against the real corpus: measured across every other scenario x
  ;; patient x objective configuration, no organism falls below the gate at all.
  (run-scenario 'lisa-user::culture-1b :candidates)
  (therapy:with-exact-solver
    (let* ((rec (therapy:recommend (therapy:conclusions-for-solver)
                                   (therapy:therapy-kb) '()))
           (treated (mapcar #'therapy:treat-item-organism
                            (therapy:recommendation-items-to-treat rec)))
           (dropped (therapy:recommendation-below-threshold rec)))
      (is (member :pseudomonas treated) "pseudomonas is treated")
      (is (not (member :klebsiella treated))
          "klebsiella is NOT -- the supporting fact pushed it below the gate")
      (is (find :klebsiella dropped :key #'therapy:below-threshold-item-organism)
          "and it is reported in below_threshold rather than simply vanishing")
      ;; The half that keeps this defensible: the regimen covers it anyway, and says so.
      (let ((k (find :klebsiella dropped :key #'therapy:below-threshold-item-organism)))
        (is (therapy:below-threshold-item-covered-by k)
            "the chosen regimen covers klebsiella incidentally")
        (is (member :meropenem (mapcar #'therapy:incidental-cover-drug
                                       (therapy:below-threshold-item-covered-by k)))
            "specifically meropenem, at bel 0.88")))))
