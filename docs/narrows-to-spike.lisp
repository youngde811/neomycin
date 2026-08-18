;;; -*- Mode: Lisp -*-
;;;
;;; SPIKE: confirming rules only, over an OPEN frame. Throwaway.
;;; NOT part of any ASDF system, NOT loaded by anything, NOT tested.
;;;
;;; Written after David's review of v0.10.0 rejected the shape of what shipped:
;;;
;;;   1. The corpus still had 16 "disconfirming rules", and after conversion their
;;;      RHS was EMPTY. A rule that fires and does nothing visible is bad design in a
;;;      production-rule system -- the RHS is what a rule DOES.
;;;   2. DEFRAME hand-enumerates every pathogen. That does not scale to hundreds.
;;;   3. What he asked for: author CONFIRMING rules only; let DS and set intersection
;;;      produce the answer.
;;;   4. Rules should ASSERT facts that build a consensus.
;;;
;;; This spike tests whether that actually works, on the hardest case in the corpus.
;;;
;;; THREE DESIGN CHANGES FROM WHAT SHIPPED
;;;
;;; A. THETA IS SYMBOLIC. Everything Dempster-Shafer needs from the frame is
;;;    `Theta ∩ A = A` and `Theta contains x`. Both are answerable without a list. So
;;;    only the sets a rule actually NAMES ever materialize, and the corpus can hold
;;;    ten thousand pathogens with the same handful of focal sets. No DEFRAME, and no
;;;    :OTHER-ORGANISM catch-all -- an organism nobody has mentioned simply has
;;;    Pl = m(Theta), which is the honest answer: nothing has spoken to it.
;;;
;;; B. A RULE ASSERTS ITS ANSWER. Every rule concludes a CANDIDATES fact naming the
;;;    set its evidence narrows to, carrying its own belief. Visible RHS, belief on
;;;    the fact where Lisa has always put it. No hidden pool, no fire-time hook, no
;;;    fact-shape protocol.
;;;
;;; C. COMBINATION IS A READ. Belief is combined by reading the CANDIDATES facts out
;;;    of working memory, not by mutating anything during inference. What the engine
;;;    did is fully inspectable at any point.
;;;
;;; THE QUESTION THIS ANSWERS: with no disconfirming rules at all, does the corpus
;;; still rule things out? Section 5 runs culture-4, which is the case that needs it.

(defpackage :narrows-to
  (:use :common-lisp)
  (:export #:report))

(in-package :narrows-to)

;;; ============================================================
;;; 1. Sets over an OPEN universe
;;; ============================================================
;;; A candidate set is a sorted list of keywords, or :UNIVERSE for Theta. NIL is the
;;; empty set. Nothing anywhere enumerates the universe.

(defconstant +universe+ :universe)

(defun canonical (elements)
  (sort (remove-duplicates (copy-list elements)) #'string< :key #'symbol-name))

(defun set-universe-p (s) (eq s +universe+))

(defun set-intersect (a b)
  "A ∩ B. Theta is the identity, which is the whole trick: it need not be a list."
  (cond ((set-universe-p a) b)
        ((set-universe-p b) a)
        (t (canonical (intersection a b)))))

(defun set-contains-p (s x)
  "Theta contains everything, by definition -- including organisms this corpus has
   never heard of. That is what makes Pl meaningful without an enumeration."
  (or (set-universe-p s) (member x s)))

(defun set-size (s) (if (set-universe-p s) :unbounded (length s)))

(defun set-name (s)
  (if (set-universe-p s) "Θ" (format nil "{~{~(~a~)~^, ~}}" s)))

;;; ============================================================
;;; 2. Mass functions
;;; ============================================================

(defun mass-ref (m s) (or (cdr (assoc s m :test #'equal)) 0.0d0))

(defun mass-incf (m s d)
  (let ((cell (assoc s m :test #'equal)))
    (if cell (progn (incf (cdr cell) d) m) (cons (cons s d) m))))

(defun simple-support (s mass)
  "A rule's answer: MASS on the set it narrows to, the rest on Theta."
  (let ((mass (float mass 1.0d0)))
    (if (>= mass 1.0d0)
        (list (cons s 1.0d0))
        (list (cons s mass) (cons +universe+ (- 1.0d0 mass))))))

(defun combine (m1 m2)
  "Unnormalized conjunctive rule. Mass on the empty set is conflict."
  (let ((out '()))
    (dolist (a m1 out)
      (dolist (b m2)
        (setf out (mass-incf out (set-intersect (car a) (car b))
                             (* (cdr a) (cdr b))))))))

(defun conflict (m) (mass-ref m nil))

(defun normalize (m)
  (let ((k (conflict m)))
    (if (>= k 1.0d0)
        (list (cons +universe+ 1.0d0))
        (loop for (s . mass) in m unless (null s)
              collect (cons s (/ mass (- 1.0d0 k)))))))

;;; --- the cautious rule, unchanged in spirit: one observation counts once ---

(defun cautious-pool (answers)
  "ANSWERS are (set . mass). Per distinct set keep the strongest, then combine.
   Two rules reading the same finding to the same conclusion count once."
  (let ((best '()))
    (dolist (a answers)
      (let ((cur (assoc (car a) best :test #'equal)))
        (if cur
            (when (> (cdr a) (cdr cur)) (setf (cdr cur) (cdr a)))
            (push (cons (car a) (cdr a)) best))))
    (if (null best)
        (list (cons +universe+ 1.0d0))
        (reduce #'combine
                (mapcar (lambda (a) (simple-support (car a) (cdr a))) best)))))

;;; --- read-out: no enumeration required ---

(defun bel (m x) (mass-ref m (canonical (list x))))

(defun pl (m x)
  "Pl(x) = total mass on sets consistent with x. Answerable for ANY x, including one
   no rule has ever named -- it simply picks up m(Theta) and nothing else."
  (let ((sum 0.0d0))
    (dolist (e m sum)
      (when (and (car e) (set-contains-p (car e) x)) (incf sum (cdr e))))))

(defun ignorance (m) (mass-ref m +universe+))

;;; ============================================================
;;; 3. The rules -- CONFIRMING ONLY, each asserting its answer
;;; ============================================================
;;; Real defrules through the real Rete, in docs/narrows-to-rules.lisp. Each narrows
;;; to the set its evidence licenses and asserts a CANDIDATES fact carrying its
;;; belief. There is no disconfirming rule anywhere in this spike, no rule has an
;;; empty RHS, and nothing declares a frame.

(defun install-rules ()
  "Load the spike's rulebase. Plain defrules in their own file, readable as rules --
   which matters, since the question is whether a HUMAN can author this shape."
  (load (merge-pathnames "docs/narrows-to-rules.lisp"
                         (asdf:system-source-directory "neomycin"))))

;;; ============================================================
;;; 4. Combination as a READ over working memory
;;; ============================================================

(defun answers-for (organism)
  "((set . belief) ...) -- every CANDIDATES fact the engine asserted for ORGANISM.
   Nothing was mutated during inference; this is just what is in working memory."
  (loop for fact in (lisa:get-fact-list (lisa:inference-engine))
        when (and (eq (lisa:fact-name fact) (intern "CANDIDATES" :lisa-user))
                  (eq (lisa:get-slot-value fact (intern "OF" :lisa-user)) organism))
          collect (cons (canonical (lisa:get-slot-value fact (intern "VALUE" :lisa-user)))
                        (let ((b (belief:belief-factor fact)))
                          (cond ((null b) 1.0d0)
                                ((belief:ds-belief-p b) (belief:ds-belief-bel b))
                                (t (float b 1.0d0)))))))

(defun consensus (organism)
  (let* ((answers (answers-for organism))
         (raw (cautious-pool answers)))
    (values (normalize raw) (conflict raw) answers)))

;;; ============================================================
;;; 5. The test
;;; ============================================================

(defun run-case (name asserts &key ask)
  (belief:use-system :dempster-shafer)
  (let ((*standard-output* (make-broadcast-stream)))
    (funcall (intern "RESET" :lisa) )
    (dolist (form asserts) (eval form))
    (funcall (intern "RUN" :lisa)))
  (multiple-value-bind (m k answers) (consensus (intern "O1" :lisa-user))
    (format t "~&~%======== ~A ========~%" name)
    (format t "answers asserted by the rules (each a visible RHS):~%")
    (dolist (a answers)
      (format t "    ~,2F  ~A~%" (cdr a) (set-name (car a))))
    (format t "~&conflict K = ~,4F     focal sets = ~D~%" k (length m))
    (format t "combined mass:~%")
    (dolist (e (sort (copy-list m) #'> :key #'cdr))
      (format t "    ~,4F on ~A~%" (cdr e) (set-name (car e))))
    (format t "~&projections:~%")
    (dolist (x ask)
      (format t "    ~30A bel=~,4F  pl=~,4F~%" x (bel m x) (pl m x)))
    ;; Two probes for the scaling claim: an organism the corpus models but no rule
    ;; in this case mentioned, and one the corpus does not model AT ALL. Both are
    ;; answerable without anything enumerating a universe.
    (let ((unmentioned (if (member :staphylococcus-aureus ask)
                           :enterococcus-faecium :staphylococcus-aureus)))
      (format t "    ~30A bel=~,4F  pl=~,4F   <- modelled, unmentioned here~%"
              unmentioned (bel m unmentioned) (pl m unmentioned)))
    (format t "    ~30A bel=~,4F  pl=~,4F   <- not in the corpus at all~%"
            :acinetobacter-baumannii (bel m :acinetobacter-baumannii)
            (pl m :acinetobacter-baumannii))
    m))

(defun assert-forms (&rest specs)
  "Sugar: (CLASS SLOT VALUE ...) -> the lisa:assert forms, so the cases below read as
   evidence rather than as ceremony."
  (mapcar (lambda (spec)
            (destructuring-bind (class &rest slots) spec
              (list 'lisa:assert
                    (cons (intern (string class) :lisa-user)
                          (loop for (slot value) on slots by #'cddr
                                collect (list (intern (string slot) :lisa-user)
                                              (if (keywordp value)
                                                  (intern (string value) :lisa-user)
                                                  value)))))))
          specs))

(defun lineage (&rest extras)
  (append (assert-forms '(patient id :p1)
                        '(culture id :c1 patient :p1)
                        '(organism id :o1 culture :c1))
          (apply #'assert-forms extras)))

(defun report ()
  (install-rules)
  (format t "~&~%################################################################~%")
  (format t "SPIKE 2: the FULL gram-positive cluster as narrows-to rules~%")
  (format t "23 rules. No organism-class. No frame. No disconfirming rules.~%")
  (format t "################################################################~%")

  ;; --- culture-3: chains in blood, compromised host, respiratory ------------
  ;; Shipped v0.10.0: s. pneumoniae [0.4737, 0.6316], K = 0.5250.
  (run-case "culture-3"
            (lineage '(culture-site value :blood of :c1)
                     '(infection-site value :respiratory of :p1)
                     '(compromised-host value t of :p1)
                     '(gram value :pos of :o1)
                     '(morphology value :coccus of :o1)
                     '(growth-conformation value :chains of :o1))
            :ask '(:streptococcus-pneumoniae :streptococcus-pyogenes
                   :enterococcus-faecalis))

  ;; --- culture-4: THE case that needed a ruling-out rule --------------------
  ;; Shipped v0.10.0: pyogenes [0.7640, 0.8989], pneumoniae [0.1011, 0.1348], K=0.7219.
  (run-case "culture-4"
            (lineage '(infection-site value :respiratory of :p1)
                     '(gram value :pos of :o1)
                     '(morphology value :coccus of :o1)
                     '(growth-conformation value :chains of :o1)
                     '(hemolysis value :beta of :o1)
                     '(bacitracin value :sensitive of :o1))
            :ask '(:streptococcus-pyogenes :streptococcus-pneumoniae
                   :streptococcus-agalactiae :enterococcus-faecalis))

  ;; --- culture-5: two rules, one hemolysis finding --------------------------
  ;; Shipped v0.10.0: s. agalactiae [0.7000, 1.0000], K = 0.
  (run-case "culture-5"
            (lineage '(age-group value :neonate of :p1)
                     '(gram value :pos of :o1)
                     '(morphology value :coccus of :o1)
                     '(growth-conformation value :chains of :o1)
                     '(hemolysis value :beta of :o1)
                     '(bacitracin value :resistant of :o1))
            :ask '(:streptococcus-agalactiae :streptococcus-pyogenes
                   :streptococcus-pneumoniae))

  ;; --- the STAPH path, which the first spike never reached ------------------
  ;; A prosthetic-joint infection: clumps, coagulase-negative, prosthetic material.
  ;; Tests the merged 0.85 coagulase-negative rule against a context rule.
  (run-case "staph: prosthetic joint, coagulase-negative"
            (lineage '(gram value :pos of :o1)
                     '(morphology value :coccus of :o1)
                     '(growth-conformation value :clumps of :o1)
                     '(coagulase value :negative of :o1)
                     '(prosthetic-material value t of :p1))
            :ask '(:staphylococcus-epidermidis :staphylococcus-saprophyticus
                   :staphylococcus-aureus))

  ;; Urinary isolate, coagulase-negative, novobiocin-resistant: two rules agreeing
  ;; on saprophyticus from genuinely different evidence.
  (run-case "staph: urinary, novobiocin-resistant"
            (lineage '(gram value :pos of :o1)
                     '(morphology value :coccus of :o1)
                     '(growth-conformation value :clumps of :o1)
                     '(coagulase value :negative of :o1)
                     '(novobiocin value :resistant of :o1)
                     '(infection-site value :urinary of :p1))
            :ask '(:staphylococcus-saprophyticus :staphylococcus-epidermidis
                   :staphylococcus-aureus))

  ;; --- the ENTEROCOCCUS path, also unreached before ------------------------
  (run-case "enterococcus: bile-esculin+, salt-tolerant, arabinose+"
            (lineage '(culture-site value :blood of :c1)
                     '(compromised-host value t of :p1)
                     '(gram value :pos of :o1)
                     '(morphology value :coccus of :o1)
                     '(growth-conformation value :chains of :o1)
                     '(catalase value :negative of :o1)
                     '(bile-esculin value :positive of :o1)
                     '(salt-tolerance value :tolerant of :o1)
                     '(arabinose value :fermenter of :o1)
                     '(sorbitol value :non-fermenter of :o1))
            :ask '(:enterococcus-faecium :enterococcus-faecalis
                   :streptococcus-pneumoniae))

  (format t "~&~%################################################################~%")
  (values))
