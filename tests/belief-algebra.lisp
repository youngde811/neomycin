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
;;; Shared frame of discernment (src/belief-systems/frame/frame.lisp)
;;;
;;; The algebra only — frames, masks, mass functions, the two accumulation
;;; operators and the two normalizations. Every value asserted here was worked
;;; by hand in docs/shared-frame-design.md §6 or measured in
;;; docs/shared-frame-phase0-results.md, and is cited to it.
;;; ------------------------------------------------------------------

(defun family-frame ()
  "A miniature stand-in for neomycin's organism frame: three members of a family,
   one outsider, and a catch-all."
  (belief:make-frame '(:e-coli :klebsiella :salmonella :pseudomonas :other)))

(defun mask-for (frame &rest elements)
  (belief:elements->mask frame elements))

(defun pool-of (frame &rest contributions)
  "CONTRIBUTIONS are (support . elements) pairs."
  (let ((p (belief:make-evidence-pool frame)))
    (dolist (c contributions p)
      (belief:pool-add p (belief:elements->mask frame (cdr c)) (car c)))))

;;; --- frames and masks ---

(deftest frame-masks-and-membership ()
  (let ((f (family-frame)))
    (is (= 5 (belief:frame-size f)))
    (is (= #b11111 (belief:frame-theta f)))
    (is (belief:frame-member-p f :e-coli))
    (is (not (belief:frame-member-p f :serratia)))
    ;; a mask round-trips to its elements in declaration order
    (is (equal '(:e-coli :salmonella)
               (belief:mask->elements f (mask-for f :salmonella :e-coli))))
    ;; the complement is what a ruling-out rule supports
    (is (equal '(:klebsiella :salmonella :pseudomonas :other)
               (belief:mask->elements
                f (belief:mask-complement f (mask-for f :e-coli)))))
    (is (belief:mask-singleton-p (mask-for f :e-coli)))
    (is (not (belief:mask-singleton-p (mask-for f :e-coli :klebsiella))))))

(deftest frame-rejects-unknown-element ()
  ;; The staleness guard: naming a hypothesis the frame does not contain is an
  ;; error at the point of use, not a silently empty set.
  (let ((f (family-frame)))
    (is (not (null (nth-value 1 (ignore-errors (mask-for f :serratia))))))))

(deftest frame-rejects-duplicate-elements ()
  (is (not (null (nth-value 1 (ignore-errors
                               (belief:make-frame '(:a :b :a))))))))

;;; --- the design's worked arithmetic (§6.1) ---

(deftest frame-class-corroborates-species ()
  ;; docs/shared-frame-design.md §6.1, by hand: a class rule at 0.8 on the family
  ;; and a species rule at 0.8 on E. coli. Under the OLD chained multiplication
  ;; E. coli would be 0.8 × 0.8 = 0.64; family evidence AGREES with E. coli, so
  ;; Dempster gives 0.80 instead — it corroborates rather than discounts.
  (let* ((f (family-frame))
         (m (belief:pool-mass
             (pool-of f '(0.8d0 :e-coli :klebsiella :salmonella)
                        '(0.8d0 :e-coli)))))
    (is (approx= (belief:mass-conflict m) 0.0) "agreeing evidence has no conflict")
    (is (approx= (belief:mass-belief m :e-coli) 0.80))
    (is (approx= (belief:mass-plausibility m :e-coli) 1.0))
    ;; the leftover family mass — "in this family, which member is unsaid"
    (is (approx= (belief:mass-ref m (mask-for f :e-coli :klebsiella :salmonella)) 0.16))
    ;; and the payoff: klebsiella is squeezed with NO rule arguing against it
    (is (approx= (belief:mass-belief m :klebsiella) 0.0))
    (is (approx= (belief:mass-plausibility m :klebsiella) 0.20))))

(deftest frame-free-exclusion ()
  ;; Mass on one hypothesis caps every rival's plausibility, unaided. This is the
  ;; property the Barnett representation cannot express: under it, culture-1
  ;; reports pseudomonas 0.76 AND klebsiella 0.40 on one organism (sum 1.16).
  (let* ((f (family-frame))
         (m (belief:pool-mass (pool-of f '(0.76d0 :pseudomonas)))))
    (is (approx= (belief:mass-belief m :pseudomonas) 0.76))
    (is (approx= (belief:mass-plausibility m :klebsiella) 0.24))
    (is (approx= (belief:mass-plausibility m :other) 0.24))))

(deftest frame-single-rule-in-isolation-is-unchanged ()
  ;; docs/shared-frame-phase0-results.md §3: a confirming rule alone still yields
  ;; [belief, 1.0] and a ruling-out rule alone still yields [0, 1-belief], so the
  ;; 50 per-rule goldens in check-rule survive the representation change.
  (let ((f (family-frame)))
    (let ((m (belief:pool-mass (pool-of f '(0.4d0 :pseudomonas)))))
      (is (approx= (belief:mass-belief m :pseudomonas) 0.4))
      (is (approx= (belief:mass-plausibility m :pseudomonas) 1.0)))
    (let* ((against (belief:mask-complement f (mask-for f :pseudomonas)))
           (p (belief:make-evidence-pool f)))
      (belief:pool-add p against 0.8d0)
      (let ((m (belief:pool-mass p)))
        (is (approx= (belief:mass-belief m :pseudomonas) 0.0))
        (is (approx= (belief:mass-plausibility m :pseudomonas) 0.2))))))

;;; --- accumulation operators ---

(deftest frame-accumulation-is-order-independent ()
  ;; Rete firing order is a conflict-resolution artifact and must not reach the
  ;; numbers. Guaranteed by accumulating UNNORMALIZED and normalizing at readout.
  (let* ((f (family-frame))
         (a '(0.7d0 :e-coli)) (b '(0.5d0 :klebsiella))
         (c '(0.8d0 :e-coli :klebsiella :salmonella)))
    (dolist (op '(:cautious :conjunctive))
      (let ((m1 (belief:pool-mass (pool-of f a b c) :operator op))
            (m2 (belief:pool-mass (pool-of f c a b) :operator op))
            (m3 (belief:pool-mass (pool-of f b c a) :operator op)))
        (is (approx= (belief:mass-belief m1 :e-coli) (belief:mass-belief m2 :e-coli))
            (format nil "~A: order does not matter (1 vs 2)" op))
        (is (approx= (belief:mass-belief m1 :e-coli) (belief:mass-belief m3 :e-coli))
            (format nil "~A: order does not matter (1 vs 3)" op))))))

(deftest frame-cautious-rule-is-idempotent ()
  ;; The property the cautious rule was adopted for. Two rules reading ONE
  ;; observation to the same conclusion must credit it once, not compound it.
  ;; Measured consequence (phase 0.5 §11): culture-5's S. agalactiae returns from
  ;; an inflated 0.910 to 0.700 — 0.7 twice is 0.7, not 0.91.
  (let* ((f (family-frame))
         (once (belief:pool-mass (pool-of f '(0.7d0 :e-coli)) :operator :cautious))
         (twice (belief:pool-mass (pool-of f '(0.7d0 :e-coli) '(0.7d0 :e-coli))
                                  :operator :cautious)))
    (is (approx= (belief:mass-belief once :e-coli) 0.7))
    (is (approx= (belief:mass-belief twice :e-coli) 0.7) "cautious is idempotent")
    ;; the conjunctive operator, by contrast, compounds: 0.7 + 0.7 - 0.49
    (let ((conj (belief:pool-mass (pool-of f '(0.7d0 :e-coli) '(0.7d0 :e-coli))
                                  :operator :conjunctive)))
      (is (approx= (belief:mass-belief conj :e-coli) 0.91)
          "conjunctive double-counts the same observation"))))

(deftest frame-cautious-keeps-the-stronger-support ()
  ;; Per focal set the cautious rule takes the MAXIMUM support (minimum weight),
  ;; so a weak duplicate never dilutes a strong reading.
  (let* ((f (family-frame))
         (m (belief:pool-mass (pool-of f '(0.4d0 :pseudomonas) '(0.6d0 :pseudomonas))
                              :operator :cautious)))
    (is (approx= (belief:mass-belief m :pseudomonas) 0.6))))

;;; --- conflict and the two normalizations ---

(deftest frame-disjoint-support-creates-conflict ()
  (let* ((f (family-frame))
         (raw (belief:pool-mass (pool-of f '(0.7d0 :e-coli) '(0.6d0 :pseudomonas))
                                :normalization :none)))
    (is (> (belief:mass-conflict raw) 0.0) "disjoint sets conflict")
    (is (approx= (belief:mass-conflict raw) 0.42) "K = 0.7 × 0.6")))

(deftest frame-normalizations-agree-without-conflict ()
  ;; With K = 0 there is nothing to redistribute, so the choice cannot matter.
  (let* ((f (family-frame))
         (p (pool-of f '(0.8d0 :e-coli :klebsiella :salmonella) '(0.8d0 :e-coli))))
    (let ((d (belief:pool-mass p :normalization :dempster))
          (y (belief:pool-mass p :normalization :yager)))
      (is (approx= (belief:mass-belief d :e-coli) (belief:mass-belief y :e-coli))))))

(deftest frame-normalizations-diverge-under-conflict ()
  ;; Dempster redistributes conflict among the survivors (sharpens); Yager moves it
  ;; to Theta (widens). Both are readouts of ONE accumulation, which is why the
  ;; choice can be deferred — see D3.
  (let* ((f (family-frame))
         (p (pool-of f '(0.7d0 :e-coli) '(0.6d0 :pseudomonas)))
         (d (belief:pool-mass p :normalization :dempster))
         (y (belief:pool-mass p :normalization :yager)))
    (is (> (belief:mass-belief d :e-coli) (belief:mass-belief y :e-coli))
        "Dempster sharpens relative to Yager")
    (is (< (belief:mass-plausibility d :e-coli) (belief:mass-plausibility y :e-coli))
        "Yager leaves more plausibility, having parked conflict on Theta")
    (is (approx= (belief:mass-total d) 1.0) "Dempster readout is a mass function")
    (is (approx= (belief:mass-total y) 1.0) "Yager readout is a mass function")
    (is (approx= (belief:mass-conflict d) 0.0) "conflict is resolved, not carried")
    (is (approx= (belief:mass-conflict y) 0.0))))

(deftest frame-total-conflict-yields-full-ignorance ()
  ;; K = 1 must not divide by zero. Matches the existing Barnett guard.
  (let* ((f (family-frame))
         (m (belief:pool-mass (pool-of f '(1.0d0 :e-coli) '(1.0d0 :pseudomonas)))))
    (is (approx= (belief:mass-belief m :e-coli) 0.0))
    (is (approx= (belief:mass-plausibility m :e-coli) 1.0))))

(deftest frame-vacuous-pool-is-total-ignorance ()
  (let* ((f (family-frame))
         (m (belief:pool-mass (belief:make-evidence-pool f))))
    (is (approx= (belief:mass-belief m :e-coli) 0.0))
    (is (approx= (belief:mass-plausibility m :e-coli) 1.0))
    (is (approx= (belief:mass-total m) 1.0))))

(deftest frame-reports-set-valued-conclusions ()
  ;; Mass on a non-singleton, non-Theta set is a real conclusion: "some member of
  ;; this family". neomycin's therapy layer builds that by hand today
  ;; (FAMILY-BACKSTOPS); here it falls out of the arithmetic.
  (let* ((f (family-frame))
         (m (belief:pool-mass (pool-of f '(0.8d0 :e-coli :klebsiella :salmonella)
                                         '(0.8d0 :e-coli))))
         (sets (belief:mass-set-valued m)))
    (is (= 1 (length sets)) "exactly one set-valued conclusion")
    (is (equal '(:e-coli :klebsiella :salmonella)
               (belief:mask->elements f (car (first sets)))))
    (is (approx= (cdr (first sets)) 0.16))))
