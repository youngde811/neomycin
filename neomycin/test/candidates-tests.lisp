;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: End-to-end tests for the v0.11 shape -- rules that assert ANSWERS
;; (sets of organisms their evidence narrows the question to), combined by a read over
;; working memory.
;;
;; Nothing here declares a frame, nothing excludes an organism by naming it, and no
;; rule has an empty RHS. Exclusion is a consequence of intersecting answers.
;;
;; Every value was measured against the real Rete and cross-checked against
;; docs/narrows-to-spike.lisp. Where a golden matches v0.10.0's frame system exactly,
;; that is noted -- it is evidence that removing the disconfirming rules changed the
;; corpus's shape without changing what it concludes.

(in-package "LISA-TEST")

(defun candidates-run (scenario)
  "Run SCENARIO under the candidates system; return its consensus mass function."
  (belief:use-system :candidates)
  (let ((*standard-output* (make-broadcast-stream)))
    (funcall scenario))
  (neomycin:consensus 'lisa-user::o1))

(defun candidates-conflict (scenario)
  (belief:use-system :candidates)
  (let ((*standard-output* (make-broadcast-stream)))
    (funcall scenario))
  (nth-value 1 (neomycin:consensus 'lisa-user::o1)))

(defun check-candidates (mass name expected-bel expected-pl)
  (let ((organism (intern (string-upcase name) :keyword)))
    (if (approx= (candidates:bel mass organism) expected-bel)
        (record-pass)
        (record-fail "~A: bel expected ~,4F, got ~,4F"
                     name expected-bel (candidates:bel mass organism)))
    (if (approx= (candidates:pl mass organism) expected-pl)
        (record-pass)
        (record-fail "~A: pl expected ~,4F, got ~,4F"
                     name expected-pl (candidates:pl mass organism)))))

;;; ------------------------------------------------------------------
;;; Scenario goldens
;;; ------------------------------------------------------------------

(deftest candidates-culture-1 ()
  ;; Burn + immunocompromised + aerobic gram-negative rod. Two pseudomonas rules bring
  ;; DISTINCT evidence (a burn, an immunocompromised host) so they reinforce to 0.76;
  ;; the aerobic-gram-neg-rod answer admits pseudomonas, so it corroborates rather than
  ;; competing; and klebsiella's context rule is the only thing pointing elsewhere.
  (let ((c (candidates-run 'lisa-user::culture-1)))
    (check-candidates c "pseudomonas" 0.612903 0.806452)
    (check-candidates c "klebsiella"  0.193548 0.387097))
  (is (approx= (candidates-conflict 'lisa-user::culture-1) 0.380000)))

(deftest candidates-culture-1a ()
  ;; THE SUBSUMPTION CASE. Two klebsiella rules fire, and one's premises are a strict
  ;; subset of the other's -- it conditions on nothing extra, so it is dropped rather
  ;; than counted again. Klebsiella's answer is therefore 0.60, not 0.5 combined with
  ;; 0.6, and the conflict falls to 0.528 from the 0.704 blind reinforcement gives.
  (let ((c (candidates-run 'lisa-user::culture-1a)))
    (check-candidates c "pseudomonas" 0.745763 0.847458)
    (check-candidates c "klebsiella"  0.152542 0.254237))
  (is (approx= (candidates-conflict 'lisa-user::culture-1a) 0.528000)))

(deftest candidates-culture-2 ()
  ;; The ambiguous gram stain, and the shape is loud about it: gram-positive and
  ;; gram-negative answers are DISJOINT, so K reaches 0.90. That is the honest reading
  ;; of a contradictory stain, and considerably louder than the 0.4168 the frame
  ;; system reported for the same case.
  (let ((c (candidates-run 'lisa-user::culture-2)))
    (check-candidates c "bacteroides" 0.649038 0.721154)
    (check-candidates c "pseudomonas" 0.228365 0.300481))
  (is (> (candidates-conflict 'lisa-user::culture-2) 0.85)
      "an ambiguous stain should read as deeply conflicted"))

(deftest candidates-culture-3 ()
  ;; IDENTICAL to v0.10.0's frame goldens (0.473684 / 0.631579, K = 0.525) with the
  ;; disconfirming rules gone and no frame declared.
  (let ((c (candidates-run 'lisa-user::culture-3)))
    (check-candidates c "streptococcus-pneumoniae" 0.473684 0.631579))
  (is (approx= (candidates-conflict 'lisa-user::culture-3) 0.525000)))

(deftest candidates-culture-4 ()
  ;; ALSO IDENTICAL to v0.10.0 (0.764045 / 0.898876 and 0.101124 / 0.134831,
  ;; K = 0.721875) -- and this is the case that most needed a ruling-out rule. There
  ;; is none. {pyogenes, agalactiae} intersected with {pneumoniae} is empty, and that
  ;; emptiness IS the exclusion.
  (let ((c (candidates-run 'lisa-user::culture-4)))
    (check-candidates c "streptococcus-pyogenes"   0.764045 0.898876)
    (check-candidates c "streptococcus-pneumoniae" 0.101124 0.134831))
  (is (approx= (candidates-conflict 'lisa-user::culture-4) 0.721875)))

(deftest candidates-culture-5 ()
  ;; Bacitracin resistance and the patient being a neonate are different evidence
  ;; agreeing on one organism, so they reinforce to 0.91. v0.10.0's cautious rule
  ;; deduped them to 0.70, discarding the bacitracin result for reaching the same
  ;; conclusion -- the error the specificity policy replaced.
  (let ((c (candidates-run 'lisa-user::culture-5)))
    (check-candidates c "streptococcus-agalactiae" 0.910000 1.000000))
  (is (approx= (candidates-conflict 'lisa-user::culture-5) 0.0)))

;;; ------------------------------------------------------------------
;;; The properties the shape is FOR
;;; ------------------------------------------------------------------

(deftest candidates-excludes-without-naming ()
  ;; No rule in the corpus argues against anything. Organisms still get excluded.
  (let ((c (candidates-run 'lisa-user::culture-4)))
    (dolist (organism '(:streptococcus-viridans :enterococcus-faecalis
                        :staphylococcus-aureus))
      (is (zerop (candidates:bel c organism))
          (format nil "~S keeps no belief" organism))
      (is (< (candidates:pl c organism) 0.2)
          (format nil "~S is squeezed, with no rule having named it" organism)))))

(deftest candidates-answers-for-an-organism-outside-the-corpus ()
  ;; The scaling property, end to end: nothing enumerates a universe, so a plausibility
  ;; is answerable for an organism neomycin does not model at all. It is m(Theta) --
  ;; the honest statement that nothing has spoken to it.
  (let ((c (candidates-run 'lisa-user::culture-1)))
    (is (zerop (candidates:bel c :acinetobacter-baumannii)))
    (is (approx= (candidates:pl c :acinetobacter-baumannii)
                 (candidates:ignorance c))
        "an unmodelled organism's ceiling is exactly the residual ignorance")))

(deftest candidates-reports-set-valued-conclusions ()
  ;; "One of these, the evidence does not say which" -- and in culture-1 it is a large
  ;; share of the belief, which is the honest headline.
  (let ((sets (candidates:set-valued (candidates-run 'lisa-user::culture-1))))
    (is (plusp (length sets)) "culture-1 leaves belief on set-valued answers")
    (is (> (reduce #'+ (mapcar #'cdr sets)) 0.1)
        "and it is a meaningful share, not a rounding remnant")))

(deftest candidates-a-genus-needs-no-class-fact ()
  ;; Asking "is this a streptococcus" is asking Bel/Pl of that SET. Nothing reifies a
  ;; class, which is why the three carried-over class beliefs ceased to exist.
  (let* ((c (candidates-run 'lisa-user::culture-4))
         (genus '(:streptococcus-pneumoniae :streptococcus-pyogenes
                  :streptococcus-agalactiae :streptococcus-viridans)))
    (is (> (candidates:bel-of-set c genus) (candidates:bel c :streptococcus-pyogenes))
        "the genus is better supported than its best member")
    (is (>= (candidates:pl-of-set c genus) (candidates:pl c :streptococcus-pyogenes))
        "and at least as plausible as any of them")))

(deftest candidates-every-rule-has-a-visible-conclusion ()
  ;; David's objection to v0.10.0, as an invariant: no rule fires and does nothing.
  (dolist (rule (candidates-rules))
    (is (lisa:rule-asserted-facts rule)
        (format nil "~A fires but concludes nothing" (lisa:rule-short-name rule)))))

(deftest candidates-no-rule-carries-a-negative-belief ()
  ;; Nothing is excluded by being named, so no rule needs a sign.
  (dolist (rule (candidates-rules))
    (is (and (realp (lisa:rule-belief rule)) (plusp (lisa:rule-belief rule)))
        (format nil "~A must carry a positive belief" (lisa:rule-short-name rule)))))

(deftest candidates-rules-explain-a-hypothesis ()
  ;; Explanation names the rules whose answers ADMITTED a hypothesis -- under this
  ;; shape nothing argues against anything, so that is the honest account.
  (candidates-run 'lisa-user::culture-4)
  (let ((rules (neomycin:rules-behind 'lisa-user::o1 :streptococcus-pyogenes)))
    (is (plusp (length rules)) "S. pyogenes has rules behind it")
    (is (member 'lisa-user::bacitracin-sensitive-narrows-to-pyogenes rules)
        "including the bacitracin discriminator that narrowed to it")))
