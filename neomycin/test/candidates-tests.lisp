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
  ;; The ambiguous gram stain, and the shape is loud about it: the gram-positive and
  ;; gram-negative answers are DISJOINT, so K stays high. RE-CAPTURED IN THE CATEGORY B
  ;; PREMISE-GATE PASS, and the movement is the point.
  ;;
  ;; This organism is an ANAEROBE. Before the gate, the two pseudomonas context rules
  ;; premised on the gram stain and morphology but NOT on aerobicity, so both fired
  ;; here and asserted {pseudomonas} -- an obligate aerobe -- at a combined 0.76,
  ;; contradicting {bacteroides} at 0.9. K was 0.90 and this comment credited all of it
  ;; to the stain. Some of it was the corpus contradicting itself.
  ;;
  ;;   bacteroides  0.6490/0.7212 -> 0.8411/0.9346   (the answer stops being fought)
  ;;   pseudomonas  0.2284/0.3005 -> 0.0000/0.0935   (bel to ZERO, as it must be)
  ;;   K            0.90          -> 0.679
  ;;
  ;; Pseudomonas keeps a plausibility of 0.0935 and no belief at all -- and klebsiella
  ;; and e-coli sit at exactly the same pair, because on an anaerobe nothing separates
  ;; them. That residue is the gram ambiguity and nothing else, which is what K = 0.679
  ;; now measures. The number is smaller and it means what the comment says.
  (let ((c (candidates-run 'lisa-user::culture-2)))
    (check-candidates c "bacteroides" 0.841121 0.934579)
    (check-candidates c "pseudomonas" 0.000000 0.093458))
  (is (approx= (candidates-conflict 'lisa-user::culture-2) 0.679000)
      "an ambiguous stain should read as deeply conflicted -- by the STAIN"))

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

;;; ------------------------------------------------------------------
;;; Conflict is not a reliability score -- MARGIN is what makes it readable.
;;;
;;; The system prompt told the model that K above ~0.5 means "the evidence disagrees
;;; with itself, treat these figures as unstable". Under this algebra two answers
;;; naming different organisms conflict TOTALLY, so K counts how much rival mass was
;;; OVERRULED and grows as the winning side strengthens. In one consultation the model
;;; gave that caveat three times, escalating, while the identification was sharpening.
;;;
;;; These tests pin the claims the prompt now makes, so the guidance cannot drift from
;;; the algebra it describes.
;;; ------------------------------------------------------------------

(defun combined (&rest answers)
  (multiple-value-list (candidates:combine-answers answers)))

(deftest conflict-rises-while-the-answer-sharpens ()
  ;; The rival is FIXED at 0.60 throughout; only the challenger's support grows. If K
  ;; measured disagreement it would peak at the tie and fall away as one side won.
  ;;
  ;; It does neither. K rises MONOTONICALLY across the whole sweep -- straight through
  ;; the crossover and on past it -- because every increment of winning mass is more
  ;; mass that contradicts the rival. The margin, meanwhile, is V-shaped: it collapses
  ;; to zero at the tie and climbs again as the leader pulls away. That divergence IS
  ;; the finding. At 0.60 the two readouts disagree about the state of the evidence,
  ;; and the margin is the one that is right.
  (let ((rows (loop for b in '(0.40d0 0.60d0 0.76d0 0.85d0 0.928d0 0.97d0)
                    collect (destructuring-bind (mass k)
                                (combined (cons '(:pseudomonas) b)
                                          (cons '(:klebsiella) 0.60d0))
                              (list b k (candidates:margin mass))))))
    ;; K: monotone increasing, no exceptions.
    (loop for (a b) on rows while b
          do (is (> (second b) (second a))
                 (format nil "K rises from ~,2F to ~,2F support" (first a) (first b))))
    ;; The margin bottoms out exactly where the evidence is actually tied.
    (is (approx= (third (second rows)) 0.0d0)
        "margin is 0 at the crossover, where support is equal")
    (is (> (third (first rows)) 0.0d0)
        "positive before it, with the rival ahead")
    ;; ...and rises monotonically once the leader is clear.
    (loop for (a b) on (cddr rows) while b
          do (is (> (third b) (third a))
                 (format nil "margin widens from ~,2F to ~,2F support"
                         (first a) (first b))))))

(deftest near-equal-conflict-opposite-meaning ()
  ;; THE PAIR the prompt quotes. Two cases with K within 0.03 of each other, one as
  ;; decisive as this corpus gets and one exactly tied. Any narration keyed on K
  ;; alone must give these the same reading, and that reading is wrong for one of them.
  (destructuring-bind (decisive-mass decisive-k)
      (combined (cons '(:pseudomonas) 0.928d0) (cons '(:klebsiella) 0.60d0))
    (destructuring-bind (tied-mass tied-k)
        (combined (cons '(:pseudomonas) 0.76d0) (cons '(:klebsiella) 0.76d0))
      (is (< (abs (- decisive-k tied-k)) 0.03d0)
          "the two cases carry near-identical conflict")
      (is (> (candidates:margin decisive-mass) 0.7d0)
          "yet one is decisive")
      (is (approx= (candidates:margin tied-mass) 0.0d0)
          "and the other is a dead tie"))))

(deftest margin-ignores-a-coarser-answer-that-agrees ()
  ;; A set CONTAINING the leader is the same claim at lower resolution. Counting it as
  ;; a rival would report competition where there is agreement -- and would make every
  ;; well-supported species look contested by its own genus.
  (destructuring-bind (mass k)
      (combined (cons '(:pseudomonas) 0.928d0)
                (cons '(:e-coli :enterobacter :klebsiella :proteus :pseudomonas
                        :salmonella :serratia) 0.80d0))
    (is (approx= k 0.0d0) "nested answers do not conflict at all")
    (multiple-value-bind (margin leader rival) (candidates:margin mass)
      (declare (ignore leader))
      (is (null rival) "and nothing contradicts the leader")
      (is (> margin 0.9d0) "so the margin is the leader's own mass"))))

(deftest margin-counts-a-set-shaped-rival ()
  ;; The case a singleton-only margin gets WRONG, and it is a real scenario: a
  ;; respiratory gram-positive coccus in chains with beta hemolysis. Both members of
  ;; the beta pair have Bel 0 individually, so a leader-minus-runner-up-singleton
  ;; reading sees no rival at all and calls an exact tie decisive.
  (destructuring-bind (mass k)
      (combined (cons '(:streptococcus-pneumoniae) 0.75d0)
                (cons '(:streptococcus-pyogenes :streptococcus-agalactiae) 0.75d0))
    (declare (ignore k))
    (is (approx= (candidates:bel mass :streptococcus-pyogenes) 0.0d0)
        "neither member of the pair carries any belief of its own")
    (multiple-value-bind (margin leader rival) (candidates:margin mass)
      (declare (ignore leader))
      (is (approx= margin 0.0d0) "and the margin reports the tie")
      (is rival "naming the set it is tied against"))))

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

;;; ------------------------------------------------------------------
;;; SUPPORT and SHARE are different quantities, and they can move opposite ways.
;;;
;;; A clinician reported a hospital-acquired infection -- a fact that SUPPORTS
;;; Klebsiella, firing a stronger and more specific rule for it -- and Klebsiella's
;;; number went DOWN. That is correct: the same fact also fires a third Pseudomonas
;;; rule, and Bel is a share of one unit of mass, so a hypothesis can gain support
;;; while losing share.
;;;
;;; It is also the single most trust-destroying thing this engine does, so the
;;; behaviour is pinned here and the prompt is required to explain it rather than
;;; apologise for it. culture-1 and culture-1a differ by exactly that one fact.
;;; ------------------------------------------------------------------

(defun answer-strength (organism set)
  "The belief of the answer that narrows to exactly SET, or 0 if no rule gave it."
  (declare (ignore organism))
  (or (loop for (s . b) in (neomycin:answers-for 'lisa-user::o1)
            when (equal s set) return b)
      0.0d0))

(deftest support-can-rise-while-share-falls ()
  (let (support-1 bel-1 margin-1)
    (candidates-run 'lisa-user::culture-1)
    (setf support-1 (answer-strength :klebsiella '(:klebsiella))
          bel-1 (candidates:bel (neomycin:consensus 'lisa-user::o1) :klebsiella)
          margin-1 (candidates:margin (neomycin:consensus 'lisa-user::o1)))
    (candidates-run 'lisa-user::culture-1a)
    (let* ((mass (neomycin:consensus 'lisa-user::o1))
           (support-2 (answer-strength :klebsiella '(:klebsiella)))
           (bel-2 (candidates:bel mass :klebsiella))
           (margin-2 (candidates:margin mass)))
      (is (> support-2 support-1)
          (format nil "the answer naming klebsiella alone STRENGTHENS, ~,3F -> ~,3F"
                  support-1 support-2))
      (is (< bel-2 bel-1)
          (format nil "while its share of belief FALLS, ~,4F -> ~,4F" bel-1 bel-2))
      (is (> margin-2 margin-1)
          (format nil "because the differential sharpened, margin ~,3F -> ~,3F"
                  margin-1 margin-2)))))
