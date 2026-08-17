;;; -*- Mode: Lisp -*-
;;;
;;; SPIKE RULES for docs/narrows-to-spike.lisp. Throwaway; not in any ASDF system.
;;;
;;; The streptococcus cluster, rewritten in the shape David asked for:
;;;
;;;   * CONFIRMING RULES ONLY. There is no disconfirming rule here, and no rule
;;;     mentions an organism in order to argue against it.
;;;   * EVERY RULE HAS A VISIBLE RHS. It asserts a CANDIDATES fact naming the set its
;;;     evidence narrows to. What the rule does is what you can read.
;;;   * BELIEF LIVES ON THE ASSERTED FACT, via the ordinary :belief keyword.
;;;   * NO FRAME IS DECLARED. Nothing enumerates the pathogens.
;;;
;;; Exclusion is never authored. It is what falls out when two answers cannot both be
;;; true -- the intersection of {pyogenes, agalactiae} with {pneumoniae} is empty, and
;;; that emptiness IS the ruling-out.

(in-package :lisa-user)

;;; The one new fact type: an ANSWER. The set of organisms this evidence narrows to.
(defclass candidates (param-mixin) ())

;;; --- what the stain and morphology establish -------------------------------
;;;
;;; Gram-positive cocci in chains are the streptococci AND the enterococci. The
;;; finding does not separate them and the rule does not pretend it does. Under the
;;; shipped corpus this named only the four streptococci, and a separate rule had to
;;; argue against the enterococci afterwards.

(defrule gram-pos-cocci-chains-narrows-to-chain-formers
    (:belief 0.7)
  (organism (id ?o))
  (gram (value pos) (of ?o))
  (morphology (value coccus) (of ?o))
  (growth-conformation (value chains) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-pneumoniae :streptococcus-pyogenes
                              :streptococcus-agalactiae :streptococcus-viridans
                              :enterococcus-faecalis :enterococcus-faecium))
                      (of ?o))))

;;; --- what hemolysis establishes --------------------------------------------
;;;
;;; THIS IS THE RULE THAT REPLACES beta-hemolysis-argues-against-non-beta-streptococci.
;;; Same clinical fact, stated as what it confirms rather than what it denies: beta
;;; hemolysis means one of the beta-hemolytic streptococci. Pneumococcus and viridans
;;; are excluded by arithmetic, not by being named.

(defrule beta-hemolysis-narrows-to-beta-hemolytic-strep
    (:belief 0.75)
  (organism (id ?o))
  (hemolysis (value beta) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-pyogenes :streptococcus-agalactiae))
                      (of ?o))))

(defrule alpha-hemolysis-narrows-to-alpha-hemolytic-strep
    (:belief 0.75)
  (organism (id ?o))
  (hemolysis (value alpha) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-pneumoniae :streptococcus-viridans))
                      (of ?o))))

;;; --- what bacitracin establishes -------------------------------------------
;;;
;;; Bacitracin separates group A from group B among the beta-hemolytics. These narrow
;;; to a single species, which is what a discriminating test legitimately does.

(defrule bacitracin-sensitive-narrows-to-pyogenes
    (:belief 0.85)
  (organism (id ?o))
  (hemolysis (value beta) (of ?o))
  (bacitracin (value sensitive) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-pyogenes)) (of ?o))))

(defrule bacitracin-resistant-narrows-to-agalactiae
    (:belief 0.7)
  (organism (id ?o))
  (hemolysis (value beta) (of ?o))
  (bacitracin (value resistant) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-agalactiae)) (of ?o))))

;;; --- what the context establishes ------------------------------------------
;;;
;;; A prior, not a deduction: the respiratory site makes pneumococcus likely without
;;; making anything impossible. It is the rule that will CONFLICT with beta hemolysis
;;; in the test case, which is the point.

(defrule respiratory-site-narrows-to-pneumoniae
    (:belief 0.75)
  (organism (id ?o))
  (culture (id ?c))
  (culture-site (value respiratory) (of ?c))
  (gram (value pos) (of ?o))
  (morphology (value coccus) (of ?o))
  (growth-conformation (value chains) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-pneumoniae)) (of ?o))))

;;; Reads the SAME hemolysis finding as the bacitracin rules, so the cautious rule has
;;; to recognise one observation rather than two.

(defrule neonate-beta-hemolytic-narrows-to-agalactiae
    (:belief 0.7)
  (organism (id ?o))
  (patient (id ?p))
  (age-group (value neonate) (of ?p))
  (hemolysis (value beta) (of ?o))
  =>
  (assert (candidates (value '(:streptococcus-agalactiae)) (of ?o))))