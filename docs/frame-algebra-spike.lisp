;;; -*- Mode: Lisp -*-
;;;
;;; PHASE 0 SPIKE for docs/shared-frame-design.md. Throwaway measurement code.
;;; NOT part of any ASDF system, NOT loaded by anything, NOT tested.
;;;
;;; Purpose: produce the numbers §6.3 of the design could not state, so the
;;; shared-frame decision is made from data. Implements the sparse mass algebra
;;; standalone (no engine hooks), then REPLAYS the real engine's firings through
;;; it and prints the comparison against the current DS goldens.
;;;
;;; Precedent for living in docs/: docs/belief-system-prototype.lisp, which is
;;; where the current DS system started.
;;;
;;; Usage, from an SBCL REPL at project root with :neomycin loaded:
;;;   (load "docs/frame-algebra-spike.lisp")
;;;   (frame-spike:report)
;;;
;;; DESIGN DECISIONS BEING MEASURED (docs/shared-frame-design.md §11):
;;;   D1 unconditional  — a chained rule's belief does NOT discount by its class.
;;;                       Operationally: premise strength excludes DERIVED premises
;;;                       (organism-class / organism-identity facts) and reflects only
;;;                       raw asserted evidence.
;;;   D3 both readouts  — accumulate CONJUNCTIVELY (associative, order-independent,
;;;                       conflict kept as m(∅)); Dempster and Yager are then two
;;;                       readouts of the same accumulation, not two combination
;;;                       rules. This is why the spike can report both.
;;;   D4 :other-organism— included in the frame, so Pl() is honest about the corpus
;;;                       not exhausting clinical microbiology.
;;;
;;; HELD FIXED (one variable at a time): the corpus is replayed exactly as authored.
;;; Confirming rules get SINGLETON focal sets even where §4.2 argues they should be
;;; wider (e.g. e-coli/klebsiella). Widening them is an authoring change and belongs
;;; to phase 2. This spike measures the REPRESENTATION change alone.

(defpackage :frame-spike
  (:use :common-lisp)
  (:export #:report #:self-test))

(in-package :frame-spike)

;;; ============================================================
;;; 1. The frame
;;; ============================================================
;;; Verified against neomycin/rules/: 17 leaf identities, 4 organism-classes.
;;; :other-organism is D4 — the catch-all that makes the frame exhaustive.

(defparameter *identities*
  '(:e-coli :klebsiella :salmonella :enterobacter :serratia :proteus
    :pseudomonas :bacteroides
    :staphylococcus-aureus :staphylococcus-epidermidis :staphylococcus-saprophyticus
    :streptococcus-pneumoniae :streptococcus-pyogenes :streptococcus-agalactiae
    :streptococcus-viridans
    :enterococcus-faecalis :enterococcus-faecium))

(defparameter *classes*
  '((:enterobacteriaceae . (:e-coli :klebsiella :salmonella :enterobacter :serratia :proteus))
    (:staphylococcus    . (:staphylococcus-aureus :staphylococcus-epidermidis
                           :staphylococcus-saprophyticus))
    (:streptococcus     . (:streptococcus-pneumoniae :streptococcus-pyogenes
                           :streptococcus-agalactiae :streptococcus-viridans))
    (:enterococcus      . (:enterococcus-faecalis :enterococcus-faecium))))

(defparameter *other* :other-organism)

(defun frame ()
  "Θ — the 17 leaf identities plus the D4 catch-all."
  (canonical (cons *other* *identities*)))

;;; ============================================================
;;; 2. Sparse mass functions
;;; ============================================================
;;; A SET is a canonical (sorted, deduped) list of keywords; NIL is ∅.
;;; A MASS FUNCTION is an alist ((set . mass) ...) which MAY carry a NIL key.
;;;
;;; The accumulation is the UNNORMALIZED CONJUNCTIVE rule: mass landing on ∅ is
;;; kept as m(∅) rather than renormalized away. That rule is associative and
;;; commutative, so the result does not depend on the order rules fired — which
;;; matters in a Rete system, where firing order is a conflict-resolution artifact.
;;; Yager's rule applied pairwise is NOT associative; accumulating conjunctively
;;; and choosing the normalization at READOUT time avoids that trap entirely.

(defun canonical (set)
  (sort (remove-duplicates (copy-list set)) #'string< :key #'symbol-name))

(defun set-intersect (a b)
  (canonical (intersection a b)))

(defun mass-of (m set)
  (or (cdr (assoc set m :test #'equal)) 0.0d0))

(defun mass-incf (m set delta)
  "Functional-ish: destructively add DELTA to SET's mass in alist M, return M."
  (let ((cell (assoc set m :test #'equal)))
    (if cell
        (progn (incf (cdr cell) delta) m)
        (cons (cons set delta) m))))

(defun simple-support (set mass)
  "A rule's contribution: MASS on SET, the remainder on Θ. This is the only shape
   a rule can produce — a simple support function."
  (let ((s (canonical set)))
    (if (>= mass 1.0d0)
        (list (cons s 1.0d0))
        (list (cons s (float mass 1.0d0))
              (cons (frame) (- 1.0d0 (float mass 1.0d0)))))))

(defun conjunctive-combine (m1 m2)
  "Unnormalized conjunctive rule. Mass on ∅ accumulates under the NIL key."
  (let ((out '()))
    (dolist (a m1 out)
      (dolist (b m2)
        (setf out (mass-incf out
                             (set-intersect (car a) (car b))
                             (* (cdr a) (cdr b))))))))

(defun combine-all (bpas)
  (if (null bpas)
      (list (cons (frame) 1.0d0))
      (reduce #'conjunctive-combine bpas)))

(defun conflict (m) (mass-of m nil))

;;; ------------------------------------------------------------
;;; Readouts — D3. Both are functions of the SAME accumulation.
;;; ------------------------------------------------------------

(defun dempster-readout (m)
  "m_D(A) = m∩(A) / (1 − q) for A ≠ ∅. Renormalizes conflict away; this is what
   the current ds-combine does, generalized off the dichotomous frame."
  (let ((q (conflict m)))
    (if (>= q 1.0d0)
        (list (cons (frame) 1.0d0))          ; total conflict: full ignorance
        (loop for (set . mass) in m
              unless (null set)
                collect (cons set (/ mass (- 1.0d0 q)))))))

(defun yager-readout (m)
  "m_Y(A) = m∩(A) for A ≠ ∅, Θ; m_Y(Θ) = m∩(Θ) + q. Conflict becomes IGNORANCE
   rather than being renormalized into the survivors — never inflates, but can be
   uninformatively conservative."
  (let ((q (conflict m))
        (theta (frame))
        (out '()))
    (loop for (set . mass) in m
          unless (null set)
            do (setf out (mass-incf out set mass)))
    (mass-incf out theta q)))

(defun bel (m x)
  "Bel(X) for singleton X = m({X}). (Sum over non-empty subsets of {X}.)"
  (mass-of m (canonical (list x))))

(defun pl (m x)
  "Pl(X) = Σ { m(A) : X ∈ A }."
  (loop for (set . mass) in m
        when (and set (member x set)) sum mass))

(defun total-mass (m)
  (loop for (set . mass) in m sum mass))

;;; ============================================================
;;; 3. Self-test — the algebra alone, before any engine data
;;; ============================================================

(defun approx= (a b &optional (eps 1.0d-6)) (< (abs (- a b)) eps))

(defun self-test ()
  "Hand-checkable properties. Prints PASS/FAIL; returns T iff all pass."
  (let ((ok t))
    (flet ((chk (name pass) (format t "~&  ~:[FAIL~;pass~] ~A~%" pass name)
             (unless pass (setf ok nil))))
      ;; §6.1 of the design, worked by hand: class 0.8 + species 0.8.
      (let* ((fam (cdr (assoc :enterobacteriaceae *classes*)))
             (m (combine-all (list (simple-support fam '0.8d0)
                                   (simple-support '(:e-coli) 0.8d0))))
             (d (dempster-readout m)))
        (chk "6.1 no conflict (K = 0)" (approx= (conflict m) 0.0d0))
        (chk "6.1 Bel(e-coli) = 0.80 (design says 0.80, today 0.64)"
             (approx= (bel d :e-coli) 0.80d0))
        (chk "6.1 Pl(e-coli) = 1.00" (approx= (pl d :e-coli) 1.0d0))
        (chk "6.1 m(family) = 0.16" (approx= (mass-of d (canonical fam)) 0.16d0))
        (chk "6.1 Pl(klebsiella) = 0.20 with NO disconfirming rule"
             (approx= (pl d :klebsiella) 0.20d0)))
      ;; Free exclusion: mass on one singleton caps every rival's plausibility.
      (let* ((m (combine-all (list (simple-support '(:pseudomonas) 0.76d0))))
             (d (dempster-readout m)))
        (chk "free exclusion: Pl(klebsiella) = 0.24 from pseudomonas 0.76 alone"
             (approx= (pl d :klebsiella) 0.24d0)))
      ;; §7 prediction: one confirming rule in isolation is UNCHANGED.
      (let* ((m (combine-all (list (simple-support '(:pseudomonas) 0.4d0))))
             (d (dempster-readout m)))
        (chk "§7 single confirming rule in isolation → [0.4, 1.0] (unchanged)"
             (and (approx= (bel d :pseudomonas) 0.4d0)
                  (approx= (pl d :pseudomonas) 1.0d0))))
      ;; §7 prediction: one disconfirming rule in isolation is UNCHANGED.
      (let* ((theta (frame))
             (against (canonical (remove :bacteroides theta)))
             (m (combine-all (list (simple-support against 0.8d0))))
             (d (dempster-readout m)))
        (chk "§7 single disconfirming rule in isolation → [0.0, 0.2] (unchanged)"
             (and (approx= (bel d :bacteroides) 0.0d0)
                  (approx= (pl d :bacteroides) 0.2d0))))
      ;; Order independence (the reason for conjunctive accumulation).
      (let* ((a (simple-support '(:e-coli) 0.7d0))
             (b (simple-support '(:klebsiella) 0.5d0))
             (c (simple-support (cdr (assoc :enterobacteriaceae *classes*)) 0.8d0))
             (m1 (combine-all (list a b c)))
             (m2 (combine-all (list c a b)))
             (m3 (combine-all (list b c a))))
        (chk "conjunctive accumulation is order-independent"
             (and (approx= (bel (dempster-readout m1) :e-coli)
                           (bel (dempster-readout m2) :e-coli))
                  (approx= (bel (dempster-readout m1) :e-coli)
                           (bel (dempster-readout m3) :e-coli)))))
      ;; Both readouts are normalized.
      (let* ((m (combine-all (list (simple-support '(:e-coli) 0.7d0)
                                   (simple-support '(:klebsiella) 0.6d0)))))
        (chk "Dempster readout sums to 1" (approx= (total-mass (dempster-readout m)) 1.0d0))
        (chk "Yager readout sums to 1"    (approx= (total-mass (yager-readout m)) 1.0d0))
        (chk "conflict is non-zero for disjoint singletons" (> (conflict m) 0.0d0))))
    ok))

;;; ============================================================
;;; 4. Replay harness — real engine firings, no hand transcription
;;; ============================================================
;;; The firings are READ from the engine's derivation table after running the real
;;; scenario, so nothing here is a second copy of the corpus. Focal sets are DERIVED
;;; mechanically from the compiled rulebase via the exported introspection API:
;;;   confirming + concludes organism-identity V → {V}
;;;   confirming + concludes organism-class C    → the class subset
;;;   disconfirming                              → Θ ∖ (its member-test list)

(defun engine () (lisa:inference-engine))

(defun derived-fact-p (fact)
  "True when FACT was concluded by a rule (has a derivation) rather than asserted
   as raw evidence. D1: derived premises do NOT discount a rule's contribution."
  (and (lisa:fact-derivation (engine) fact) t))

(defparameter *conditional-composition* nil
  "D1 A/B switch. NIL = unconditional (the decision under test): a chained rule
   contributes its full belief and Dempster composes it with the class evidence.
   T = the CURRENT reading: derived premises discount the rule, reproducing
   species = class x rule inside the frame algebra. Flipping this isolates how much
   of the measured change is D1 rather than the representation.")

(defun premise-strength (record)
  "Strength of the RAW evidence behind one firing, under D1.

   Mirrors what the engine itself does (belief:adjust-belief*): conjoin the premise
   beliefs, minimum-style, and fall back to 1.0 when no premise carries a belief
   (the default-belief NIL case, which is every culture-* fact except culture-2's
   explicit gram values). Derived premises are EXCLUDED — that is D1."
  (let ((strengths
          (loop for (fact . belief) in (lisa:derivation-record-premises record)
                unless (and (not *conditional-composition*) (derived-fact-p fact))
                  when belief
                    collect (cond ((realp belief) (float belief 1.0d0))
                                  ((belief:ds-belief-p belief)
                                   (float (belief:ds-belief-bel belief) 1.0d0))
                                  (t 1.0d0)))))
    (if strengths (reduce #'min strengths) 1.0d0)))

(defun rule-focal-set (rule-name)
  "The set a rule contributes mass to, derived from the COMPILED rulebase.
   Returns (values set kind) or (values NIL :unmapped)."
  (let ((rule (lisa:find-rule (engine) rule-name)))
    (unless rule (return-from rule-focal-set (values nil :no-such-rule)))
    (cond
      ((lisa:disconfirming-rule-p rule)
       (let ((targets (lisa:rule-member-test-values rule)))
         (if targets
             (values (canonical (set-difference (frame) targets)) :opposes)
             (values nil :unmapped))))
      ((lisa:confirming-rule-p rule)
       (let* ((asserted (lisa:rule-asserted-facts rule))
              (ident (cdr (assoc (intern "ORGANISM-IDENTITY" :lisa-user) asserted)))
              (class (cdr (assoc (intern "ORGANISM-CLASS" :lisa-user) asserted))))
         (cond (ident (values (widen rule-name (canonical (list ident))) :identity))
               (class (let ((members (cdr (assoc class *classes*))))
                        (if members
                            (values (widen rule-name (canonical members)) :class)
                            (values nil :unknown-class))))
               (t (values nil :unmapped)))))
      (t (values nil :unmapped)))))

(defun collect-firings ()
  "Every rule firing that contributed belief in the current run, deduped by
   (rule, entity).

   The dedupe is load-bearing. A disconfirming rule fires once PER raised
   hypothesis today — red-pigment-argues-against-non-serratia produces five
   derivation records on five different facts. Under a shared frame that is ONE
   observation contributing ONE mass assignment, so the five collapse to one."
  (let ((seen (make-hash-table :test #'equal))
        (out '()))
    (dolist (fact (lisa:get-fact-list (engine)))
      (dolist (record (lisa:fact-derivation (engine) fact))
        (let* ((rule (lisa:derivation-record-rule record))
               (entity (ignore-errors (lisa:get-slot-value fact 'lisa-user::of)))
               (key (list rule entity)))
          (unless (gethash key seen)
            (setf (gethash key seen) t)
            (push (list :rule rule
                        :entity entity
                        :belief (lisa:derivation-record-rule-belief record)
                        :strength (premise-strength record)
                        :evidence (raw-evidence-signature record))
                  out)))))
    (nreverse out)))

;;; ------------------------------------------------------------
;;; Independence diagnostic — §9.4, and the finding phase 0 exists for.
;;; ------------------------------------------------------------
;;; Dempster's rule requires the combined bodies of evidence to be INDEPENDENT.
;;; The corpus does not honour that: several rules read the SAME raw observations
;;; and are then combined as if they were separate sources. Under the current
;;; per-hypothesis representation that is invisible, because the rules never meet.
;;; Under a shared frame they meet, and correlated evidence manufactures conflict.
;;; This measures how much.

(defparameter *context-classes*
  '(lisa-user::patient lisa-user::culture lisa-user::organism)
  "The context TREE, not evidence. Every rule matches (organism (id ?o)) as wiring;
   counting that as a shared observation would make every rule trivially entangled
   with every other. Excluded from the evidence signature.")

(defun raw-evidence-signature (record)
  "Sorted printed identifiers of the RAW (non-derived, non-context) premise facts
   behind one firing — the actual OBSERVATIONS the rule read. Two firings sharing an
   entry read the same observation and are therefore not independent sources."
  (sort (loop for (fact . belief) in (lisa:derivation-record-premises record)
              unless (or (derived-fact-p fact)
                         (member (lisa:fact-name fact) *context-classes*))
                collect (format nil "~A=~A"
                                (lisa:fact-name fact)
                                (ignore-errors (lisa:get-slot-value fact 'lisa-user::value))))
        #'string<))

(defun shared-evidence-report (firings)
  "((raw-fact rule ...) ...) for every raw observation read by MORE THAN ONE rule.
   Each such observation is a single body of evidence being fed to Dempster's rule
   two or more times."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (f firings)
      (dolist (e (getf f :evidence))
        (pushnew (getf f :rule) (gethash e table))))
    (sort (loop for e being the hash-keys of table using (hash-value rules)
                when (> (length rules) 1) collect (cons e (reverse rules)))
          #'> :key (lambda (x) (length (cdr x))))))

(defun evidence-components (firings)
  "Firings partitioned into connected components under 'shares at least one raw
   observation'. A component is one entangled body of evidence: no two firings in
   different components read any fact in common."
  (let ((comps '()))
    (dolist (f firings)
      (let* ((ev (getf f :evidence))
             (hits (remove-if-not
                    (lambda (c) (intersection ev (getf c :evidence) :test #'string=))
                    comps)))
        (if hits
            (let ((merged (list :evidence (reduce (lambda (a b) (union a b :test #'string=))
                                                  (cons ev (mapcar (lambda (c) (getf c :evidence)) hits)))
                                :firings (cons f (mapcan (lambda (c) (copy-list (getf c :firings)))
                                                         hits)))))
              (setf comps (cons merged (set-difference comps hits))))
            (push (list :evidence ev :firings (list f)) comps))))
    comps))

(defun collapse-components (firings)
  "EXTREME LOWER BOUND, not a proposal: one firing per entangled evidence component
   (the highest-mass one), so a body of evidence contributes exactly once. Together
   with the uncollapsed run this BRACKETS how much of the measured conflict is the
   independence artifact rather than genuine disagreement between distinct
   observations. The right answer lies between; finding it is a design question this
   spike deliberately does not settle."
  (mapcar (lambda (c)
            (first (sort (copy-list (getf c :firings)) #'>
                         :key (lambda (f) (* (abs (float (getf f :belief) 1.0d0))
                                             (getf f :strength))))))
          (evidence-components firings)))

(defun firings->bpas (firings)
  "Map firings to simple support functions. Returns (values bpas unmapped)."
  (let ((bpas '()) (unmapped '()))
    (dolist (f firings (values (nreverse bpas) (nreverse unmapped)))
      (multiple-value-bind (set kind) (rule-focal-set (getf f :rule))
        (if (null set)
            (push (list (getf f :rule) kind) unmapped)
            (push (simple-support set (cdr (firing->spec f))) bpas))))))

;;; ============================================================
;;; 5. Report
;;; ============================================================

(defparameter *scenarios*
  '((culture-1  . "pseudomonas 0.76 / klebsiella 0.40")
    (culture-1a . "pseudomonas 0.88 / klebsiella 0.688")
    (culture-2  . "bacteroides [0.689,0.956] / pseudomonas [0.611,0.946]")
    (culture-3  . "s. pneumoniae 0.525")
    (culture-4  . "s. pyogenes [0.595,1.0] / s. pneumoniae [0.216,0.412]")
    (culture-5  . "s. agalactiae 0.7399")))

(defun current-ds-conclusions ()
  "What the CURRENT engine reports: ((name bel pl) ...) for organism-identity facts."
  (loop for fact in (lisa:get-fact-list (engine))
        when (eq (lisa:fact-name fact) 'lisa-user::organism-identity)
          collect (let ((b (belief:belief-factor fact)))
                    (list (lisa:get-slot-value fact 'lisa-user::value)
                          (if (belief:ds-belief-p b) (belief:ds-belief-bel b) b)
                          (if (belief:ds-belief-p b) (belief:ds-belief-pl b) 1.0)))))

;;; ============================================================
;;; 4b. PHASE 0.5 — operators that tolerate dependent evidence
;;; ============================================================
;;; Phase 0 found that the corpus's rules are not independent bodies of evidence
;;; (several read the same observation), which is what Dempster's rule requires.
;;; These are the candidate responses, measured against the same six scenarios.

(defparameter *focal-widening* nil
  "Alist (RULE-NAME-SUBSTRING . EXTRA-ELEMENTS) widening a rule's focal set.

   Phase 0 HELD FOCAL SETS AT THE AUTHORED WIDTH deliberately, to measure the
   representation change alone. This hook relaxes that, to test the hypothesis that
   the culture-1 inversion comes from co-triggered rules concluding DISJOINT sets
   from one observation -- which the current representation cannot express, and which
   design 4.2's :supports is exactly the fix for.")

(defun widen (rule-name set)
  (let ((extra (loop for (frag . elts) in *focal-widening*
                     when (search frag (string-downcase (string rule-name)))
                       append elts)))
    (if extra (canonical (append set extra)) set)))

(defparameter *class-belief-override* nil
  "When non-NIL, a single float replacing the declared :belief of every rule that
   concludes an organism-CLASS. Exists to test whether culture-1's ranking inversion
   is driven by the three CARRIED-OVER class constants that belief-conditional-audit.md
   3.2 flagged as answering no conditional at all -- rather than by the choice of
   combination operator.")

(defun firing->spec (f)
  "(set . mass) for one firing, or NIL if its rule maps to no focal set."
  (multiple-value-bind (set kind) (rule-focal-set (getf f :rule))
    (when set
      (let ((belief (if (and *class-belief-override* (eq kind :class))
                        *class-belief-override*
                        (abs (float (getf f :belief) 1.0d0)))))
        (cons set (* belief (getf f :strength)))))))

(defun specs-of (firings)
  (remove nil (mapcar #'firing->spec firings)))

;;; ------------------------------------------------------------
;;; (b) Denoeux's CAUTIOUS CONJUNCTIVE RULE, exactly.
;;; ------------------------------------------------------------
;;; The cautious rule takes the MINIMUM weight per focal set over the canonical
;;; decompositions of the operands. In general that needs a Mobius transform over
;;; the superset lattice — intractable on an 18-element frame.
;;;
;;; It is exact and cheap HERE because every operand is already a simple support
;;; function: a rule contributes mass s on one set A and 1-s on Theta, which IS
;;; A^w with weight w = 1-s, i.e. its own canonical decomposition. So the cautious
;;; combination of a collection of SSFs is: per focal set take the minimum weight
;;; (= the MAXIMUM support), then conjunctively combine one SSF per set.
;;;
;;; Being idempotent, this makes redundant evidence free: firing the same rule
;;; twice, or two rules with the same conclusion and the same strength, changes
;;; nothing. NOTE THE LIMIT, which phase 0.5 exists to test: it only deduplicates
;;; rules sharing a focal SET. Two rules reading one observation but concluding
;;; DIFFERENT sets — culture-1's pseudomonas rules versus the enterobacteriaceae
;;; class rule — are untouched by it.

(defun cautious-combine (specs)
  "Cautious conjunctive rule over simple support functions (see above)."
  (let ((best (make-hash-table :test #'equal)))
    (dolist (s specs)
      (let ((cur (gethash (car s) best)))
        (when (or (null cur) (> (cdr s) cur))
          (setf (gethash (car s) best) (cdr s)))))
    (combine-all
     (loop for set being the hash-keys of best using (hash-value mass)
           collect (simple-support set (min mass 0.999d0))))))

;;; ------------------------------------------------------------
;;; (c) POOL WITHIN A BODY OF EVIDENCE, combine ACROSS bodies.
;;; ------------------------------------------------------------
;;; The structural reading: one body of evidence should induce ONE mass function.
;;; Where several rules read the same observation they are partial opinions about
;;; what it means, so they are AVERAGED (Murphy-style) rather than treated as
;;; independent confirmations. Distinct bodies of evidence are still combined by
;;; Dempster's rule, so genuinely independent findings still accumulate and still
;;; conflict.
;;;
;;; Averaging deliberately does NOT accumulate: two rules reading one observation
;;; must not strengthen belief the way two separate observations would. That is the
;;; point, and it is also why the resulting numbers are lower.

(defun average-bpas (bpas)
  "Element-wise mean of a list of mass functions."
  (let ((n (float (length bpas) 1.0d0))
        (out '()))
    (dolist (b bpas out)
      (dolist (e b)
        (setf out (mass-incf out (car e) (/ (cdr e) n)))))))

(defun pooled-by-component (firings pool-fn)
  "Partition FIRINGS into entangled evidence components, reduce each to ONE mass
   function with POOL-FN, then combine the components conjunctively."
  (combine-all
   (mapcar (lambda (c) (funcall pool-fn (specs-of (getf c :firings))))
           (evidence-components firings))))

(defun pool-average (specs)
  (average-bpas (mapcar (lambda (s) (simple-support (car s) (min (cdr s) 0.999d0)))
                        specs)))

(defun pool-cautious (specs)
  (cautious-combine specs))

;;; ------------------------------------------------------------
;;; Ranking agreement — the metric that matters clinically
;;; ------------------------------------------------------------

(defun ranking-agreement (current readout)
  "Fraction of organism PAIRS whose belief ordering READOUT agrees with CURRENT on.
   Returns (values agreed total). Culture-1's inversion is what this catches."
  (let ((agreed 0) (total 0))
    (loop for (a . rest) on current do
      (dolist (b rest)
        (let ((cur (- (second a) (second b)))
              (new (- (bel readout (first a)) (bel readout (first b)))))
          (incf total)
          (when (or (and (plusp cur) (plusp new))
                    (and (minusp cur) (minusp new))
                    (and (zerop cur) (zerop new)))
            (incf agreed)))))
    (values agreed total)))

(defun run-one (scenario)
  (belief:use-system :dempster-shafer)
  (let ((*standard-output* (make-broadcast-stream)))
    (funcall (intern (symbol-name scenario) :lisa-user)))
  (let* ((current (current-ds-conclusions))
         (firings (collect-firings)))
    (multiple-value-bind (bpas unmapped) (firings->bpas firings)
      (let* ((m (combine-all bpas))
             (d (dempster-readout m))
             (y (yager-readout m))
             ;; D1 A/B: same run, conditional composition instead of unconditional.
             (cond-firings (let ((*conditional-composition* t)) (collect-firings)))
             (m-cond (combine-all (firings->bpas cond-firings)))
             (d-cond (dempster-readout m-cond))
             ;; Independence counterfactual (design 9.4).
             (dedup (collapse-components firings))
             (m2 (combine-all (firings->bpas dedup)))
             (d2 (dempster-readout m2))
             ;; PHASE 0.5 variants.
             (specs (specs-of firings))
             (m-caut (cautious-combine specs))
             (m-avgc (pooled-by-component firings #'pool-average))
             (m-cautc (pooled-by-component firings #'pool-cautious)))
        (list :current current :firings firings :unmapped unmapped
              :raw m :dempster d :yager y :conflict (conflict m)
              :focal-count (count-if #'car m)
              :shared (shared-evidence-report firings)
              :components (length (evidence-components firings))
              :dedup-n (length dedup)
              :dedup-conflict (conflict m2)
              :dedup-dempster d2
              :cond-dempster d-cond :cond-conflict (conflict m-cond)
              :cautious (dempster-readout m-caut)   :cautious-k (conflict m-caut)
              :avg-comp (dempster-readout m-avgc)   :avg-comp-k (conflict m-avgc)
              :caut-comp (dempster-readout m-cautc) :caut-comp-k (conflict m-cautc))))))

(defun class-belief-sweep (&optional (scenarios '(culture-1 culture-1a)))
  "Sweep the organism-CLASS rules' belief and report where each scenario's ranking
   flips, under both the conjunctive and cautious operators. Isolates the carried-over
   class constants from the choice of operator."
  (format t "~&~%--- class-belief sensitivity (audit 3.2's carried-over constants) ---~%")
  (format t "declared: enterobacteriaceae 0.8, staph 0.7, strep 0.7 -- all CARRIED OVER~%~%")
  (dolist (scenario scenarios)
    (format t "~&~A:~%" scenario)
    (format t "  ~9A ~26A ~26A~%" "class bel" "conjunctive (bel/bel)" "cautious (bel/bel)")
    (dolist (cb '(0.8d0 0.7d0 0.6d0 0.5d0 0.4d0 0.3d0 0.2d0))
      (let* ((*class-belief-override* cb)
             (r (run-one scenario))
             (current (getf r :current))
             (pairs (sort (mapcar #'first current) #'string< :key #'symbol-name)))
        (multiple-value-bind (a1 t1) (ranking-agreement current (getf r :dempster))
          (multiple-value-bind (a2 t2) (ranking-agreement current (getf r :cautious))
            (format t "  ~9,2F ~{~,3F ~}~5A(~D/~D)~7A~{~,3F ~}~5A(~D/~D)~A~%"
                    cb
                    (mapcar (lambda (o) (bel (getf r :dempster) o)) pairs) ""
                    a1 t1 ""
                    (mapcar (lambda (o) (bel (getf r :cautious) o)) pairs) ""
                    a2 t2
                    (if (and (= a1 t1) (= a2 t2)) "  <== both agree" ""))))))
    (format t "  (columns are ~{~A~^ / ~})~%"
            (mapcar (lambda (o) (string-downcase (symbol-name o)))
                    (sort (mapcar #'first (getf (run-one scenario) :current))
                          #'string< :key #'symbol-name)))))

(defun widening-experiment ()
  "THE experiment phase 0 deferred. In culture-1 four rules read one observation --
   an aerobic gram-negative rod -- and conclude DISJOINT sets: {pseudomonas} twice and
   the six-member enterobacteriaceae family once. Disjoint conclusions from shared
   evidence are what manufactures the conflict.

   But 'aerobic gram-negative rod' does not mean 'enterobacteriaceae'. It means one of
   the seven aerobic gram-negative rods in the frame -- the six family members AND
   pseudomonas. Bacteroides is excluded: it is an ANAEROBE. Widening the class rule's
   focal set to what the premise actually licenses is not a fudge; it is stating the
   rule correctly, which is what design 4.2's :supports keyword is for."
  (format t "~&~%--- focal-set widening (the variable phase 0 held fixed) ---~%")
  (format t "aerobic-gram-neg-rod class rule: {6 enterobacteriaceae} -> +{pseudomonas}~%")
  (format t "(the 7 aerobic gram-neg rods in the frame; bacteroides is anaerobic)~%~%")
  (dolist (scenario '(culture-1 culture-1a culture-2 culture-4))
    (dolist (widened '(nil t))
      (let* ((*focal-widening*
               (when widened '(("aerobic-gram-neg-rod-suggests-enterobacteriaceae"
                                . (:pseudomonas)))))
             (r (run-one scenario))
             (current (getf r :current))
             (orgs (sort (mapcar #'first current) #'string< :key #'symbol-name)))
        (multiple-value-bind (a1 t1) (ranking-agreement current (getf r :dempster))
          (multiple-value-bind (a2 t2) (ranking-agreement current (getf r :cautious))
            (format t "  ~11A ~9A K=~,3F/~,3F  conj ~{~,3F ~}(~D/~D)  caut ~{~,3F ~}(~D/~D)~A~%"
                    (if widened "" (string scenario))
                    (if widened "WIDENED" "as authored")
                    (getf r :conflict) (getf r :cautious-k)
                    (mapcar (lambda (o) (bel (getf r :dempster) o)) orgs) a1 t1
                    (mapcar (lambda (o) (bel (getf r :cautious) o)) orgs) a2 t2
                    (if (and (= a1 t1) (= a2 t2)) "  <== both agree" ""))))))
    (format t "              (~{~A~^ / ~})~%"
            (mapcar (lambda (o) (string-downcase (symbol-name o)))
                    (sort (mapcar #'first (getf (run-one scenario) :current))
                          #'string< :key #'symbol-name)))))

(defun report ()
  (format t "~&~%================================================================~%")
  (format t "PHASE 0 — shared frame vs. current DS, replayed on the real corpus~%")
  (format t "D1 unconditional · D3 both readouts · D4 :other-organism in frame~%")
  (format t "Frame: ~D elements (17 identities + :other-organism)~%" (length (frame)))
  (format t "================================================================~%")
  (format t "~&~%--- algebra self-test ---~%")
  (let ((ok (self-test)))
    (format t "~&  => ~:[SELF-TEST FAILED~;self-test passed~]~%" ok))
  (dolist (pair *scenarios*)
    (destructuring-bind (scenario . golden) pair
      (let* ((r (run-one scenario))
             (current (getf r :current))
             (organisms (sort (mapcar #'first current) #'string< :key #'symbol-name)))
        (format t "~&~%================ ~A ================~%" scenario)
        (format t "current golden: ~A~%" golden)
        (format t "firings: ~D   focal sets: ~D   conflict K = ~,4F~%"
                (length (getf r :firings)) (getf r :focal-count) (getf r :conflict))
        (when (getf r :unmapped)
          (format t "!! UNMAPPED RULES: ~S~%" (getf r :unmapped)))
        (format t "~&~%~26A ~15A ~15A ~15A ~15A ~A~%"
                "organism" "current" "(a) conjunct" "(b) cautious"
                "(c) avg/cmpnt" "(d) caut/cmpnt")
        (format t "~26A ~15A ~15A ~15A ~15A ~A~%"
                (make-string 26 :initial-element #\-) (make-string 15 :initial-element #\-)
                (make-string 15 :initial-element #\-) (make-string 15 :initial-element #\-)
                (make-string 15 :initial-element #\-) (make-string 15 :initial-element #\-))
        (dolist (o organisms)
          (let ((cur (assoc o current)))
            (format t "~26A [~,2F,~,2F]     [~,2F,~,2F]     [~,2F,~,2F]     [~,2F,~,2F]     [~,2F,~,2F]~%"
                    (string-downcase (symbol-name o))
                    (second cur) (third cur)
                    (bel (getf r :dempster) o) (pl (getf r :dempster) o)
                    (bel (getf r :cautious) o) (pl (getf r :cautious) o)
                    (bel (getf r :avg-comp) o) (pl (getf r :avg-comp) o)
                    (bel (getf r :caut-comp) o) (pl (getf r :caut-comp) o))))
        (format t "~&~26A ~15A" "conflict K" "     --   ")
        (dolist (k (list (getf r :conflict) (getf r :cautious-k)
                         (getf r :avg-comp-k) (getf r :caut-comp-k)))
          (format t "  ~,4F        " k))
        (format t "~%~26A ~15A" "ranking vs current" "     --   ")
        (dolist (v (list :dempster :cautious :avg-comp :caut-comp))
          (multiple-value-bind (ag tot) (ranking-agreement current (getf r v))
            (format t "  ~D/~D~:[  !!~;    ~]      " ag tot (= ag tot))))
        (format t "~%")
        ;; The independence diagnostic.
        (when (getf r :shared)
          (format t "~&~%  !! SHARED EVIDENCE (design 9.4) -- one observation, several rules.~%")
          (format t "     Dempster's rule treats each as an INDEPENDENT source. They are not:~%")
          (dolist (g (getf r :shared))
            (format t "     ~24A read by ~D rules: ~{~A~^, ~}~%"
                    (car g) (length (cdr g)) (cdr g)))
          (format t "~&     entangled evidence components: ~D (from ~D firings)~%"
                  (getf r :components) (length (getf r :firings)))
          (format t "     K with correlation = ~,4F   K collapsed to one-per-component = ~,4F~%"
                  (getf r :conflict) (getf r :dedup-conflict)))
        ;; Organisms the frame SQUEEZES that the current system never touches.
        (let ((squeezed
                (loop for x in *identities*
                      unless (member x organisms)
                        when (< (pl (getf r :dempster) x) 0.999d0)
                          collect (cons x (pl (getf r :dempster) x)))))
          (when squeezed
            (format t "~&~%  squeezed for free (current system leaves all of these at pl 1.0):~%")
            (dolist (s (sort squeezed #'< :key #'cdr))
              (format t "    ~28A pl = ~,3F~%"
                      (string-downcase (symbol-name (car s))) (cdr s)))))
        ;; Non-singleton focal mass — the family backstop, natively.
        (let ((sets (remove-if (lambda (e) (or (null (car e)) (= 1 (length (car e)))
                                               (= (length (car e)) (length (frame)))))
                               (getf r :dempster))))
          (when sets
            (format t "~&~%  set-valued mass (what family-backstops builds by hand):~%")
            (dolist (e (sort (copy-list sets) #'> :key #'cdr))
              (format t "    ~,4F on ~S~%" (cdr e)
                      (mapcar (lambda (k) (string-downcase (symbol-name k))) (car e))))))
        (format t "~&~%  Pl(:other-organism) = ~,3F   m(Θ) = ~,4F~%"
                (pl (getf r :dempster) *other*)
                (mass-of (getf r :dempster) (frame))))))
  (class-belief-sweep)
  (widening-experiment)
  (format t "~&~%================================================================~%")
  (values))