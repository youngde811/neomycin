;; This file is part of Lisa, the Lisp-based Intelligent Software Agents platform.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: The belief system for a knowledge base whose rules assert ANSWERS --
;; sets of hypotheses their evidence narrows a question to.
;;
;; Deliberately small. Under this design belief lives on the asserted fact and the
;; interesting work -- intersecting answers -- happens when a client READS working
;; memory, not while the engine infers. So this system's only job is to say what
;; happens when two rules assert the SAME answer: their support reinforces,
;; a + b - ab, which is confirmatory Dempster-Shafer on a single proposition.
;;
;; What it deliberately does NOT do: negative belief (an answer that excludes is an
;; answer naming what remains), interval arithmetic (the interval comes from combining
;; answers, not from a single fact), or anything requiring a declared frame.

(in-package :belief)

(defclass candidates-system (belief-system)
  ()
  (:default-initargs :name "Dempster-Shafer (candidate sets)"))

(defmethod valid-belief-p ((system candidates-system) value)
  (or (null value) (and (realp value) (<= 0 value 1))))

(defmethod normalize-belief ((system candidates-system) value)
  (cond ((null value) nil)
        ((realp value) (max 0.0 (min 1.0 (float value 1.0))))
        (t value)))

(defmethod combine-beliefs ((system candidates-system) a b)
  "a + b - ab: two rules asserting the same answer REINFORCE it.

   Correct whenever the two rules bring distinct evidence, which across neomycin's
   corpus is every same-conclusion pair but one. The exception is subsumption -- one
   rule's premises a strict subset of another's -- and that is corrected where answers
   are read, because it needs the rules, which a belief system does not see."
  (declare (ignore system))
  (let ((a (float (or a 0.0) 1.0)) (b (float (or b 0.0) 1.0)))
    (- (+ a b) (* a b))))

(defmethod weaken-belief ((system candidates-system) belief factor)
  "Scale an answer by the strength of the evidence behind it."
  (declare (ignore system))
  (* (float (or belief 1.0) 1.0) (float factor 1.0)))

(defmethod conjoin-beliefs ((system candidates-system) beliefs)
  "AND-ed premises: the weakest link."
  (declare (ignore system))
  (reduce #'min (mapcar (lambda (b) (float (or b 1.0) 1.0)) beliefs)))

(defmethod belief->number ((system candidates-system) belief)
  (if (realp belief) belief 0.0))

(defmethod belief->english ((system candidates-system) belief)
  (cond ((null belief) "no evidence")
        ((not (realp belief)) (format nil "~A" belief))
        ((> belief 0.8) (format nil "strong support (~,0F%)" (* 100 belief)))
        ((> belief 0.5) (format nil "moderate support (~,0F%)" (* 100 belief)))
        ((> belief 0.2) (format nil "weak support (~,0F%)" (* 100 belief)))
        (t "little support")))

(defmethod belief->json ((system candidates-system) belief) belief)

(defvar *candidates-system* (make-instance 'candidates-system)
  "Singleton. Selected with (belief:use-system :candidates).")
