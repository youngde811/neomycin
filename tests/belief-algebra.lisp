;; This file is part of Lisa, the Lisp-based Intelligent Software Agents platform.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: Unit tests for the pluggable belief algebras themselves —
;; certainty factors (Shortliffe-Buchanan) and simplified Dempster-Shafer.
;; These exercise combine/weaken/conjoin/normalize directly, independent of
;; the rulebase, including the clamp and total-conflict edge cases that the
;; 4.1.0 review surfaced.

(in-package "LISA-TEST")

;;; ------------------------------------------------------------------
;;; Certainty factors
;;; ------------------------------------------------------------------

(deftest cf-combine ()
  (let ((cf belief:*cf-system*))
    ;; both positive: a + b - a*b
    (is (approx= (belief:combine-beliefs cf 0.4 0.6) 0.76))
    ;; both negative: a + b + a*b
    (is (approx= (belief:combine-beliefs cf -0.4 -0.6) -0.76))
    ;; mixed sign: (a + b) / (1 - min(|a|,|b|))
    (is (approx= (belief:combine-beliefs cf 0.8 -0.5) 0.6))))

(deftest cf-weaken-and-conjoin ()
  (let ((cf belief:*cf-system*))
    (is (approx= (belief:weaken-belief cf 0.8 0.5) 0.4))       ; multiply
    (is (approx= (belief:conjoin-beliefs cf '(0.8 0.5 0.9)) 0.5)) ; weakest link
    (is (approx= (belief:normalize-belief cf 0.7) 0.7))))

;;; ------------------------------------------------------------------
;;; Dempster-Shafer: representation and normalization
;;; ------------------------------------------------------------------

(deftest ds-normalize ()
  (let ((ds belief:*ds-system*))
    ;; a bare number becomes a support interval [x, 1]
    (let ((r (belief:normalize-belief ds 0.7)))
      (is (approx= (belief:ds-belief-bel r) 0.7))
      (is (approx= (belief:ds-belief-pl r) 1.0)))
    ;; a negative number becomes disconfirming mass: [0, 1+x]
    (let ((r (belief:normalize-belief ds -0.3)))
      (is (approx= (belief:ds-belief-bel r) 0.0))
      (is (approx= (belief:ds-belief-pl r) 0.7)))))

;;; ------------------------------------------------------------------
;;; Dempster-Shafer: Dempster's rule of combination
;;; ------------------------------------------------------------------

(deftest ds-combine-no-conflict-is-noisy-or ()
  ;; With no disconfirming mass, K = 0 and the rule reduces to a+b-ab, pl = 1.
  (let* ((ds belief:*ds-system*)
         (r (belief:combine-beliefs ds
                                    (belief:make-ds-belief 0.4 1.0)
                                    (belief:make-ds-belief 0.6 1.0))))
    (is (approx= (belief:ds-belief-bel r) 0.76))
    (is (approx= (belief:ds-belief-pl r) 1.0))))

(deftest ds-combine-with-conflict-drops-plausibility ()
  ;; A "for" hypothesis (m(H)=0.76) meets an "against" one (m(not-H)=0.14).
  ;; Conflict K > 0 must renormalize: bel falls below 0.76 and pl below 1.0,
  ;; and the result must remain a valid interval.
  (let* ((ds belief:*ds-system*)
         (r (belief:combine-beliefs ds
                                    (belief:make-ds-belief 0.76 1.0)
                                    (belief:make-ds-belief 0.0 0.86))))
    (is (< (belief:ds-belief-pl r) 1.0) "conflict should pull pl below 1.0")
    (is (< (belief:ds-belief-bel r) 0.76) "conflict should reduce bel")
    (is (> (belief:ds-belief-bel r) 0.0))
    (is (belief:valid-belief-p ds r) "combined interval must be valid")))

(deftest ds-weaken-positive-and-negative ()
  (let ((ds belief:*ds-system*))
    ;; positive rule factor -> support for H (mass on H)
    (let ((r (belief:weaken-belief ds (belief:make-ds-belief 0.8 1.0) 0.5)))
      (is (approx= (belief:ds-belief-bel r) 0.4))
      (is (approx= (belief:ds-belief-pl r) 1.0)))
    ;; negative rule factor -> support against H (mass on not-H): pl = 1 - m
    (let ((r (belief:weaken-belief ds (belief:make-ds-belief 0.5 1.0) -0.8)))
      (is (approx= (belief:ds-belief-bel r) 0.0))
      (is (approx= (belief:ds-belief-pl r) 0.6)))))

(deftest ds-conjoin-is-min-min ()
  (let* ((ds belief:*ds-system*)
         (r (belief:conjoin-beliefs ds (list (belief:make-ds-belief 0.8 1.0)
                                             (belief:make-ds-belief 0.5 0.9)))))
    (is (approx= (belief:ds-belief-bel r) 0.5))
    (is (approx= (belief:ds-belief-pl r) 0.9))))

;;; ------------------------------------------------------------------
;;; Dempster-Shafer: defensive edge cases (from the 4.1.0 review)
;;; ------------------------------------------------------------------

(deftest ds-weaken-clamps-out-of-range-factor ()
  (let ((ds belief:*ds-system*))
    ;; |factor| > 1 must not produce an invalid interval
    (let ((r (belief:weaken-belief ds (belief:make-ds-belief 0.9 1.0) 1.5)))
      (is (approx= (belief:ds-belief-bel r) 1.0))
      (is (approx= (belief:ds-belief-pl r) 1.0))
      (is (belief:valid-belief-p ds r)))
    (let ((r (belief:weaken-belief ds (belief:make-ds-belief 0.9 1.0) -1.5)))
      (is (approx= (belief:ds-belief-bel r) 0.0))
      (is (approx= (belief:ds-belief-pl r) 0.0))
      (is (belief:valid-belief-p ds r)))))

(deftest ds-combine-total-conflict-yields-full-ignorance ()
  ;; K = 1 (irreconcilable) must return [0, 1] rather than divide by zero.
  (let* ((ds belief:*ds-system*)
         (r (belief:combine-beliefs ds
                                    (belief:make-ds-belief 1.0 1.0)
                                    (belief:make-ds-belief 0.0 0.0))))
    (is (approx= (belief:ds-belief-bel r) 0.0))
    (is (approx= (belief:ds-belief-pl r) 1.0))
    (is (belief:valid-belief-p ds r))))

(deftest ds-combine-clamps-malformed-input ()
  ;; A malformed input interval (bel > pl) must still yield a valid result.
  (let* ((ds belief:*ds-system*)
         (r (belief:combine-beliefs ds
                                    (belief:make-ds-belief 0.6 1.0)
                                    (belief:make-ds-belief 0.9 0.3))))
    (is (<= (belief:ds-belief-bel r) (belief:ds-belief-pl r)))
    (is (belief:valid-belief-p ds r))))
;;; ------------------------------------------------------------------
;;; Dempster-Shafer over an OPEN frame (src/belief-systems/candidates/)
;;;
;;; An answer is the SET of hypotheses some evidence narrows a question to. Answers
;;; combine by intersection; exclusion is never authored. Theta is symbolic, so
;;; nothing here enumerates a universe -- which is the property that lets a knowledge
;;; base scale without a frame declaration to keep in step with it.
;;;
;;; Values below are either hand-workable or measured in docs/narrows-to-spike.lisp
;;; against the real Rete, and cited where so.
;;; ------------------------------------------------------------------

;;; --- sets over an open universe ---

(deftest candidates-theta-is-symbolic ()
  ;; The whole scaling argument in three assertions: Theta is the identity for
  ;; intersection and contains everything, without ever being a list.
  (is (candidates:universe-p candidates:+universe+))
  (is (equal '(:a :b) (candidates:set-intersect candidates:+universe+ '(:a :b)))
      "Theta is the identity for intersection")
  (is (candidates:set-contains-p candidates:+universe+ :never-heard-of-this)
      "and contains a hypothesis nothing has ever named")
  (is (eq :unbounded (candidates:set-size candidates:+universe+))
      "its size is unbounded, not a number"))

(deftest candidates-sets-canonicalize ()
  (is (equal (candidates:canonical '(:b :a :b))
             (candidates:canonical '(:a :b)))
      "order and duplicates do not make a different set")
  (is (null (candidates:set-intersect '(:a) '(:b)))
      "disjoint answers intersect to the empty set -- which IS the exclusion"))

;;; --- combination ---

(deftest candidates-nested-answers-do-not-conflict ()
  ;; A smaller set inside a larger one AGREES. This is what replaces chaining: urease+
  ;; narrows to four organisms, urease+ with swarming narrows within that to one, and
  ;; the two compose with no conflict and no composition law.
  ;; Measured on the real corpus (docs/narrows-to-spike.lisp): proteus [0.80, 1.00], K=0.
  (multiple-value-bind (m k)
      (candidates:combine-answers '(((:klebsiella :enterobacter :serratia :proteus) . 0.7)
                                    ((:proteus) . 0.8)))
    (is (approx= k 0.0) "nested answers produce no conflict")
    (is (approx= (candidates:bel m :proteus) 0.8))
    (is (approx= (candidates:pl m :proteus) 1.0)
        "and nothing caps the ceiling of the hypothesis they agree on")))

(deftest candidates-intersection-replaces-disconfirming-rules ()
  ;; THE claim this whole design rests on. Two confirming answers, no rule mentioning
  ;; Klebsiella in order to exclude it, and Klebsiella is excluded anyway.
  ;; lactose+ narrows to four; indole+ narrows to two; only E. coli is in both.
  (multiple-value-bind (m k)
      (candidates:combine-answers '(((:e-coli :klebsiella :enterobacter :serratia) . 0.7)
                                    ((:e-coli :proteus) . 0.6)))
    ;; NOTE what does NOT happen: there is no conflict. The two answers OVERLAP -- both
    ;; admit E. coli -- so they agree, and agreement narrows without contradiction.
    ;; Conflict arises only between answers that are disjoint. Exclusion here is purely
    ;; a matter of which hypotheses survive the intersection.
    (is (approx= k 0.0) "overlapping answers narrow without conflicting")
    (is (approx= (candidates:bel m :e-coli) 0.42)
        "0.7 x 0.6 lands on the one hypothesis both answers admit")
    (is (zerop (candidates:bel m :klebsiella)) "Klebsiella keeps no belief")
    (is (approx= (candidates:pl m :klebsiella) 0.40)
        "and its ceiling falls to 0.40 with no rule having named it -- which is the
         whole claim: exclusion is a consequence, not an authored rule")
    (is (approx= (candidates:pl m :proteus) 0.30)
        "Proteus, admitted by only one of the two answers, is squeezed harder still")))

(deftest candidates-combination-is-order-independent ()
  ;; Rete firing order is a conflict-resolution artifact and must not reach the
  ;; numbers. Guaranteed by accumulating unnormalized and normalizing at readout.
  (let ((a '((:a :b) . 0.7)) (b '((:b :c) . 0.5)) (c '((:b) . 0.6)))
    (flet ((bel-of (answers)
             (candidates:bel (candidates:combine-answers answers) :b)))
      (is (approx= (bel-of (list a b c)) (bel-of (list c a b))))
      (is (approx= (bel-of (list a b c)) (bel-of (list b c a)))))))

;;; --- reading the result without an enumeration ---

(deftest candidates-answers-for-an-unnamed-hypothesis ()
  ;; The scaling property, stated as a test. A hypothesis no answer mentions -- and
  ;; that the knowledge base may not model at all -- still gets a defensible
  ;; plausibility: m(Theta), meaning nothing has spoken to it.
  (let ((m (candidates:combine-answers '(((:e-coli :klebsiella) . 0.75)))))
    (is (zerop (candidates:bel m :acinetobacter-baumannii))
        "nothing supports a hypothesis nobody named")
    (is (approx= (candidates:pl m :acinetobacter-baumannii) 0.25)
        "but its ceiling is the residual ignorance, not zero and not one")
    (is (approx= (candidates:pl m :acinetobacter-baumannii)
                 (candidates:ignorance m))
        "which is exactly m(Theta)")))

(deftest candidates-projects-a-set-as-a-hypothesis ()
  ;; A genus is a set. Asking "is this a streptococcus" is asking Bel/Pl of that set,
  ;; which is why there is no organism-class fact and nothing needs to replace it.
  (let ((m (candidates:combine-answers
            '(((:strep-pyogenes :strep-agalactiae :strep-pneumoniae) . 0.7)
              ((:strep-pyogenes) . 0.6)))))
    (let ((genus '(:strep-pyogenes :strep-agalactiae :strep-pneumoniae)))
      (is (> (candidates:bel-of-set m genus) (candidates:bel m :strep-pyogenes))
          "the genus is better supported than any member -- a statement a
           per-hypothesis frame cannot make")
      (is (approx= (candidates:pl-of-set m genus) 1.0)
          "and nothing argues the organism is outside it"))))

(deftest candidates-reports-set-valued-conclusions ()
  ;; "One of these, the evidence does not say which" -- often the honest headline.
  (let* ((m (candidates:combine-answers '(((:a :b :c) . 0.8) ((:a) . 0.5))))
         (sets (candidates:set-valued m)))
    (is (= 1 (length sets)) "exactly one set-valued conclusion")
    (is (equal '(:a :b :c) (car (first sets))))
    (is (member :b (candidates:hypotheses-named m))
        "and the payload can say which hypotheses it is able to speak about")))

;;; --- normalization ---

(deftest candidates-normalizations-agree-without-conflict ()
  (let ((answers '(((:a :b) . 0.8) ((:a) . 0.7))))
    (is (approx= (candidates:bel (candidates:combine-answers
                                  answers :normalization :dempster) :a)
                 (candidates:bel (candidates:combine-answers
                                  answers :normalization :yager) :a))
        "with K = 0 there is nothing to redistribute, so the choice cannot matter")))

(deftest candidates-normalizations-diverge-under-conflict ()
  (let* ((answers '(((:a) . 0.7) ((:b) . 0.6)))
         (d (candidates:combine-answers answers :normalization :dempster))
         (y (candidates:combine-answers answers :normalization :yager)))
    (is (> (candidates:bel d :a) (candidates:bel y :a)) "Dempster sharpens")
    (is (< (candidates:pl d :a) (candidates:pl y :a))
        "Yager leaves more plausibility, having parked conflict on Theta")
    (is (approx= (candidates:total-mass d) 1.0))
    (is (approx= (candidates:total-mass y) 1.0))))

(deftest candidates-conflict-is-read-before-normalizing ()
  ;; Both normalizations resolve K away by construction, so it has to come back from
  ;; the combination itself -- a lesson from v0.9.0, where it silently read zero.
  (multiple-value-bind (m k) (candidates:combine-answers '(((:a) . 0.7) ((:b) . 0.6)))
    (is (approx= k 0.42) "K = 0.7 x 0.6, reported from the raw combination")
    (is (approx= (candidates:conflict-of m) 0.0)
        "while the normalized result carries none")))

(deftest candidates-total-conflict-is-full-ignorance ()
  (let ((m (candidates:combine-answers '(((:a) . 1.0) ((:b) . 1.0)))))
    (is (approx= (candidates:bel m :a) 0.0))
    (is (approx= (candidates:pl m :a) 1.0) "irreconcilable answers yield no knowledge")))

(deftest candidates-no-answers-is-total-ignorance ()
  (let ((m (candidates:combine-answers '())))
    (is (approx= (candidates:ignorance m) 1.0))
    (is (approx= (candidates:pl m :anything) 1.0))))
