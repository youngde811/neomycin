;; This file is part of Lisa, the Lisp-based Intelligent Software Agents platform.

;; MIT License

;; Copyright (c) 2000 David Young

;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to deal
;; in the Software without restriction, including without limitation the rights
;; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;; copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:

;; The above copyright notice and this permission notice shall be included in all
;; copies or substantial portions of the Software.

;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.

;; Description: Class representing the inference engine itself.

(in-package :lisa)

(defclass rete ()
  ((fact-table :initform (make-hash-table :test #'equalp)
               :accessor rete-fact-table)
   (fact-id-table :initform (make-hash-table)
                  :accessor fact-id-table)
   (instance-table :initform (make-hash-table)
                   :reader rete-instance-table)
   (rete-network :initform (make-rete-network)
                 :reader rete-network)
   (next-fact-id :initform -1
                 :accessor rete-next-fact-id)
   (autofacts :initform (list)
              :accessor rete-autofacts)
   (meta-data :initform (make-hash-table)
              :reader rete-meta-data)
   (dependency-table :initform (make-hash-table :test #'equal)
                     :accessor rete-dependency-table)
   ;; DERIVATION-TABLE (neomycin extension for the WHY/HOW facility): maps a
   ;; rule-CONCLUDED fact to the ordered list of firings that built its belief --
   ;; the authoritative record of "how did this belief get this value." Populated
   ;; at ADJUST-BELIEF time and cleared with the facts (FORGET-ALL-FACTS). Keyed by
   ;; fact object (EQ): duplicate conclusions reuse the same fact instance, so
   ;; successive firings accumulate onto one derivation list. Pure metadata -- it
   ;; never affects inference.
   (derivation-table :initform (make-hash-table :test #'eq)
                     :accessor rete-derivation-table)
   ;; EVIDENCE-POOLS (neomycin extension, shared frame of discernment): one pool per
   ;; ENTITY -- the thing the frame asks its question about. Under a frame-based
   ;; belief system this is where belief actually lives; the [Bel, Pl] on each fact is
   ;; a projection of it. Keyed by the entity designator (EQUAL), empty and unused
   ;; under the per-hypothesis systems, and cleared with the facts.
   ;; See docs/shared-frame-design.md 5.
   (evidence-pools :initform (make-hash-table :test #'equal)
                   :accessor rete-evidence-pools)
   (contexts :initform (make-hash-table :test #'equal)
             :reader rete-contexts)
   (focus-stack :initform (list)
                :accessor rete-focus-stack)
   (halted :initform nil
           :accessor rete-halted)
   (firing-count :initform 0
                 :accessor rete-firing-count)))

(defmethod initialize-instance :after ((self rete) &rest initargs)
  (declare (ignore initargs))
  (register-new-context self (make-context :initial-context))
  (reset-focus-stack self)
  self)

;;; FACT-META-OBJECT represents data about facts. Every Lisa fact is backed by
;;; a CLOS instance that was either defined by the application or internally
;;; by Lisa (via DEFTEMPLATE).

(defstruct fact-meta-object
  (class-name nil :type symbol)
  (slot-list nil :type list)
  (superclasses nil :type list))

(defun register-meta-object (rete key meta-object)
  (setf (gethash key (rete-meta-data rete)) meta-object))

(defun find-meta-object (rete symbolic-name)
  (gethash symbolic-name (rete-meta-data rete)))

(defun rete-fact-count (rete)
  (hash-table-count (rete-fact-table rete)))

(defun find-rule (rete rule-name)
  (with-rule-name-parts (context-name short-name long-name) rule-name
    (find-rule-in-context (find-context rete context-name) long-name)))

(defun add-rule-to-network (rete rule patterns)
  (flet ((load-facts (network)
           (maphash #'(lambda (key fact)
                        (declare (ignore key))
                        (add-fact-to-network network fact))
                    (rete-fact-table rete))))
    (when (find-rule rete (rule-name rule))
      (forget-rule rete rule))
    (if (zerop (rete-fact-count rete))
        (compile-rule-into-network (rete-network rete) patterns rule)
      (merge-rule-into-network 
       (rete-network rete) patterns rule :loader #'load-facts))
    (add-rule-to-context (rule-context rule) rule)
    rule))

(defmethod forget-rule ((self rete) (rule-name symbol))
  (flet ((disable-activations (rule)
           (mapc #'(lambda (activation)
                     (setf (activation-eligible activation) nil))
                 (find-all-activations
                  (context-strategy (rule-context rule)) rule))))
    (let ((rule (find-rule self rule-name)))
      (cl:assert (not (null rule)) nil
        "The rule named ~S is not known to be defined." rule-name)
      (remove-rule-from-network (rete-network self) rule)
      (remove-rule-from-context (rule-context rule) rule)
      (disable-activations rule)
      rule)))

(defmethod forget-rule ((self rete) (rule rule))
  (forget-rule self (rule-name rule)))

(defmethod forget-rule ((self rete) (rule-name string))
  (forget-rule self (find-symbol rule-name)))

(defun remember-fact (rete fact)
  (with-accessors ((fact-table rete-fact-table)
                   (id-table fact-id-table)) rete
    (setf (gethash (hash-key fact) fact-table) fact)
    (setf (gethash (fact-id fact) id-table) fact)))

(defun forget-fact (rete fact)
  (with-accessors ((fact-table rete-fact-table)
                   (id-table fact-id-table)) rete
    (remhash (hash-key fact) fact-table)
    (remhash (fact-id fact) id-table)))

(defun find-fact-by-id (rete fact-id)
  (gethash fact-id (fact-id-table rete)))

(defun find-fact-by-name (rete fact-name)
  (gethash fact-name (rete-fact-table rete)))

(defun forget-all-facts (rete)
  (clrhash (rete-fact-table rete))
  (clrhash (fact-id-table rete))
  ;; Derivations belong to facts, so they die with them (each reset starts a fresh
  ;; consultation with an empty derivation record). Evidence pools likewise: a pool is
  ;; the accumulated evidence of ONE consultation.
  (clrhash (rete-derivation-table rete))
  (clrhash (rete-evidence-pools rete)))

(defun get-fact-list (rete)
  (delete-duplicates
   (sort
    (loop for fact being the hash-values of (rete-fact-table rete)
        collect fact)
    #'(lambda (f1 f2) (< (fact-id f1) (fact-id f2))))))

(defun duplicate-fact-p (rete fact)
  (let ((f (gethash (hash-key fact) (rete-fact-table rete))))
    (if (and f (equals f fact))
        f
      nil)))

(defmacro ensure-fact-is-unique (rete fact)
  (let ((existing-fact (gensym)))
    `(unless *allow-duplicate-facts*
       (let ((,existing-fact
              (gethash (hash-key ,fact) (rete-fact-table ,rete))))
         (unless (or (null ,existing-fact)
                     (not (equals ,fact ,existing-fact)))
           (error (make-condition 'duplicate-fact :existing-fact ,existing-fact)))))))
  
(defmacro with-unique-fact ((rete fact) &body body)
  (let ((body-fn (gensym))
        (existing-fact (gensym)))
    `(flet ((,body-fn ()
              ,@body))
       (if *allow-duplicate-facts*
           (,body-fn)
         (let ((,existing-fact (duplicate-fact-p ,rete ,fact)))
           (if (not ,existing-fact)
               (,body-fn)
             (error (make-condition 'duplicate-fact
                                    :existing-fact ,existing-fact))))))))
  
(defun next-fact-id (rete)
  (incf (rete-next-fact-id rete)))

(defun add-autofact (rete deffact)
  (pushnew deffact (rete-autofacts rete) :key #'deffacts-name))

(defun remove-autofacts (rete)
  (setf (rete-autofacts rete) nil))

(defun assert-autofacts (rete)
  (mapc #'(lambda (deffact)
            (mapc #'(lambda (fact)
                      (assert-fact rete (make-fact-from-template fact)))
                  (deffacts-fact-list deffact)))
        (rete-autofacts rete)))

(defmethod assert-fact-aux ((self rete) fact)
  (with-truth-maintenance (self)
    (setf (fact-id fact) (next-fact-id self))
    (remember-fact self fact)
    (trace-assert fact)
    (add-fact-to-network (rete-network self) fact)
    (when (fact-shadowsp fact)
      (register-clos-instance self (find-instance-of-fact fact) fact)))
  fact)
  
(defmethod adjust-belief (rete fact (belief-factor number))
   (with-unique-fact (rete fact)
     ;; Route an explicit numeric :belief through the active belief system so
     ;; the stored value is in that system's internal representation (e.g. a
     ;; DS-BELIEF interval under Dempster-Shafer) rather than a bare number.
     ;; Without this, asserting a fact with a numeric :belief under DS would
     ;; store a raw float that later blows up CONJOIN-BELIEFS / COMBINE-BELIEFS.
     (setf (belief-factor fact)
           (if belief:*belief-system*
               (belief:normalize-belief belief:*belief-system* belief-factor)
               belief-factor))))

;;; ------------------------------------------------------------------
;;; Belief DERIVATION capture (neomycin WHY/HOW facility). One record per firing
;;; that contributed to a rule-concluded fact's belief; the ordered list of them
;;; for a fact is its authoritative derivation. See docs/why-how-provenance-design.md.
;;; ------------------------------------------------------------------

(defstruct (derivation-record (:constructor %make-derivation-record))
  "One firing that contributed to a concluded fact's belief. RULE is the qualified
   rule name (resolve provenance with FIND-RULE); RULE-BELIEF is that rule's own
   :belief; PREMISES is a list of (premise-fact . belief-snapshot) captured at fire
   time (the fact object lets a reader recurse into a derived premise's own
   derivation); BELIEF-BEFORE / BELIEF-AFTER bracket this firing's contribution
   (BELIEF-BEFORE is NIL on the first firing, so combination across firings is
   visible).

   Under a frame-based belief system two more fields carry what the scalar pair
   cannot: CLAIMS is the list of (mask . mass) this firing committed -- a rule may
   state several, at different granularities -- and CONFLICT is the pool's K after it.
   Without them a /why narration could not say WHICH hypotheses a firing supported,
   only how one of them moved. NIL under the per-hypothesis systems."
  rule rule-belief premises belief-before belief-after
  claims conflict)

(defun record-derivation (rete fact rule premises belief-before belief-after
                          &key claims conflict)
  "Append a DERIVATION-RECORD for the conclusion FACT under the derivation table.
   Prepended (O(1)); FACT-DERIVATION reverses to firing order on read."
  (push (%make-derivation-record
         :rule (rule-name rule)
         :rule-belief (belief-factor rule)
         :premises (mapcar #'(lambda (p) (cons p (belief-factor p))) premises)
         :belief-before belief-before
         :belief-after belief-after
         :claims claims
         :conflict conflict)
        (gethash fact (rete-derivation-table rete))))

(defun fact-derivation (rete fact)
  "The ordered list of DERIVATION-RECORDs for FACT, earliest firing first, or NIL if
   FACT was asserted as raw evidence rather than concluded by a rule."
  (reverse (gethash fact (rete-derivation-table rete))))

;;; ------------------------------------------------------------------
;;; Frame-based accumulation (shared frame of discernment).
;;;
;;; Under a frame-based system a rule's firing does NOT set a number on the fact it
;;; concluded. It contributes mass to a SUBSET of the frame, in the pool belonging to
;;; the entity the frame is asking about. Every hypothesis for that entity is then
;;; re-projected, which is where free exclusion comes from: evidence for one organism
;;; lowers the plausibility of the others by arithmetic, with no rule saying so.
;;; See docs/shared-frame-design.md 5.
;;; ------------------------------------------------------------------

(defvar *hypothesis-slot* "VALUE"
  "Name of the slot holding the hypothesis a fact asserts, for the DEFAULT method of
   FACT-HYPOTHESIS. A convention, not a requirement -- it is the shape MYCIN's
   param-mixin uses, which most Lisa examples do NOT. An application with a different
   schema either rebinds this and *ENTITY-SLOT*, or specializes the two generics
   below, which is the general answer.")

(defvar *entity-slot* "OF"
  "Name of the slot scoping a fact to the thing the frame asks about, for the DEFAULT
   method of FACT-ENTITY. See *HYPOTHESIS-SLOT*.")

(defun fact-slot-named (fact slot-name)
  "Value of FACT's slot called SLOT-NAME (a string), or NIL.

   The symbol is looked up in the package of the FACT'S OWN class, not in a hardwired
   application package -- so this works for any application, not only one whose facts
   live in LISA-USER. FIND-SYMBOL rather than INTERN: a query must not create symbols
   as a side effect."
  (let* ((name (fact-name fact))
         (package (and (symbolp name) (symbol-package name)))
         (slot (and package (find-symbol slot-name package))))
    (and slot (ignore-errors (get-slot-value fact slot)))))

;;; ------------------------------------------------------------------
;;; The application protocol.
;;;
;;; Frame-based reasoning needs two things from a fact that the engine cannot know
;;; on its own: WHICH HYPOTHESIS it asserts, and WHICH ENTITY the question is being
;;; asked about. Everything else in the frame machinery -- the algebra, the pools,
;;; the projections -- is domain-neutral; this is the one place an application's
;;; own fact schema has to be consulted.
;;;
;;; The default methods implement the value/of convention, so MYCIN-shaped rulebases
;;; work with no configuration. An application whose facts look different overrides:
;;;
;;;   (defmethod lisa:fact-hypothesis ((f lisa:fact))
;;;     (case (lisa:fact-name f)
;;;       (my-app::diagnosis (lisa:get-slot-value f 'my-app::condition))
;;;       (t nil)))
;;;
;;; Returning NIL means "this fact asserts no hypothesis" -- raw evidence, context
;;; wiring -- and such facts are left untouched by projection.
;;;
;;; Every Lisa fact is an instance of one class, so an application's method REPLACES
;;; the default rather than layering over it. That is the right granularity -- an
;;; application has one fact schema -- but it makes the contract explicit: a method
;;; must answer for the facts it recognizes and DELEGATE the rest, either by calling
;;; FACT-SLOT-NAMED as the default does or by returning NIL.
;;; ------------------------------------------------------------------

(defgeneric fact-hypothesis (fact)
  (:documentation
   "The hypothesis FACT asserts -- an element or named subset of the active frame --
    or NIL if it asserts none. Specialize for an application whose facts do not carry
    the value/of convention; see *HYPOTHESIS-SLOT*.")
  (:method ((fact fact))
    (fact-slot-named fact *hypothesis-slot*)))

(defgeneric fact-entity (fact)
  (:documentation
   "The entity FACT is scoped to -- the thing the frame is asking its question about.
    One evidence pool per distinct value. NIL is a legitimate answer for a rulebase
    that asks one global question. Specialize alongside FACT-HYPOTHESIS.")
  (:method ((fact fact))
    (fact-slot-named fact *entity-slot*)))

(defun entity-pool (rete entity)
  "The evidence pool for ENTITY, created on first use."
  (or (gethash entity (rete-evidence-pools rete))
      (setf (gethash entity (rete-evidence-pools rete))
            (belief:make-evidence-pool belief:*frame*))))

(defun raw-premise-strength (rete premises)
  "Strength of the RAW evidence behind a firing -- decision D1.

   Premises that were themselves CONCLUDED (they carry a derivation) are excluded: a
   chained rule's belief is unconditional support that the class premise GATES, not a
   conditional to be discounted by it. Composition between the two happens in the pool,
   by Dempster's rule, rather than by multiplication here. Raw premises carrying no
   explicit belief count as certain, which is what the per-hypothesis path does too."
  (let ((strengths
          (loop for p in premises
                unless (gethash p (rete-derivation-table rete))
                  when (belief-factor p)
                    collect (let ((b (belief-factor p)))
                              (if (belief:ds-belief-p b)
                                  (belief:ds-belief-bel b)
                                  (float b 1.0))))))
    (if strengths (reduce #'min strengths) 1.0)))

(defun project-onto (fact mass)
  "Set FACT's belief to its projection from MASS, if its hypothesis is in the frame.
   Returns true when it projected."
  (let ((hypothesis (fact-hypothesis fact)))
    (when (belief:hypothesis-mask mass hypothesis)
      (setf (belief-factor fact) (belief:project-mass mass hypothesis))
      t)))

(defun refresh-projections (rete entity &optional new-fact)
  "Re-project every hypothesis fact scoped to ENTITY from its pool.

   This is the step that has no counterpart under the per-hypothesis systems, and it
   is the whole point: one firing updates every hypothesis, not just the one the rule
   named. Facts whose hypothesis is not in the frame are left alone, so raw evidence
   keeps whatever belief it was asserted with.

   NEW-FACT is projected explicitly because ASSERT-FACT calls ADJUST-BELIEF *before*
   REMEMBER-FACT, so a fact being concluded for the first time is not yet in the fact
   table and the loop below would miss it. It is harmless to project it twice."
  (let* ((pool (entity-pool rete entity))
         (mass (belief:pool-mass pool)))
    (when new-fact (project-onto new-fact mass))
    ;; An ELEMENT (a leaf identity) or a named SUBSET (a taxonomic class) both
    ;; project; a class's Bel is the mass that has settled inside the family, however
    ;; it is distributed among the members.
    (loop for fact being the hash-values of (rete-fact-table rete)
          when (equal (fact-entity fact) entity)
            do (project-onto fact mass))
    mass))

(defun premise-entity (rule premises)
  "The entity a rule that asserts NOTHING is talking about.

   A rule that concludes a fact takes its entity from that fact, which is
   unambiguous. A rule that concludes nothing has only its premises, and those can
   legitimately span entities -- neomycin matches a patient's burn and an organism's
   gram stain in one rule. Signals rather than guessing when they do: contributing an
   organism's evidence to a patient's pool would be silently wrong, and an author
   should learn that at once."
  (let ((entities (remove nil (remove-duplicates (mapcar #'fact-entity premises)))))
    (cond ((null entities) nil)
          ((null (rest entities)) (first entities))
          (t (error "Rule ~A states claims but asserts nothing, and its premises span ~
                     several entities (~{~S~^, ~}); the engine cannot tell which the ~
                     claims are about. Give the rule a single-entity premise set, or ~
                     have it assert its conclusion."
                    (rule-name rule) entities)))))

(defun claim-audience (rete entity claim)
  "The existing hypothesis facts a CLAIM is ABOUT, for attaching a derivation record.

   The DESIGNATED set, not the focal set: an :excludes claim's focal set is the
   complement, but the reader who needs the explanation is asking about one of the
   organisms it excluded. So a red-pigment exclusion is recorded against E. coli and
   Klebsiella -- exactly where a clinician asking why their plausibility fell will
   look for it."
  (let ((designated (ignore-errors
                     (belief:resolve-mask belief:*frame* (claim-designator claim)))))
    (when designated
      (loop for fact being the hash-values of (rete-fact-table rete)
            when (and (equal (fact-entity fact) entity)
                      (let ((h (fact-hypothesis fact)))
                        (and h (let ((m (belief:hypothesis-mask
                                         (belief:pool-mass (entity-pool rete entity)) h)))
                                 (and m (plusp (logand m designated)))))))
              collect fact))))

(defun contribute-claims-per-hypothesis (rete rule premises)
  "Honor a rule's claims under a PER-HYPOTHESIS belief system (CF, Barnett DS).

   Those systems have no notion of mass on a set: a belief lives on one hypothesis at
   a time. An :excludes claim still translates exactly, though -- it is what the old
   ruling-out rules did by hand. For every hypothesis the claim names that has a fact
   for this entity, apply the claim's mass as NEGATIVE evidence against it.

   A :supports claim on a rule that asserts nothing has no per-hypothesis translation
   and is skipped: there is no fact to carry the belief, and these systems cannot hold
   a hypothesis that no rule concluded. That limit is not an oversight -- it is the
   representational gap the shared frame exists to close, showing up in miniature."
  (dolist (claim (rule-declared-claims rule))
    (destructuring-bind (mass verb designator) claim
      (when (member verb '(:excludes :exclude :opposes :oppose))
        (let ((targets (if (listp designator) designator (list designator)))
              (entity (premise-entity rule premises)))
          (dolist (fact (loop for f being the hash-values of (rete-fact-table rete)
                              when (and (equal (fact-entity f) entity)
                                        (member (fact-hypothesis f) targets)
                                        ;; Once per (rule, fact). A ruling-out rule
                                        ;; guards on a live hypothesis, so it fires
                                        ;; once per raised sibling -- and each firing
                                        ;; sees ALL the targets. Without this the
                                        ;; claim would be applied n times over.
                                        (notany (lambda (r)
                                                  (eq (derivation-record-rule r)
                                                      (rule-name rule)))
                                                (gethash f (rete-derivation-table rete))))
                                collect f))
            ;; Exclude the TARGET from its own premise list. A ruling-out rule guards
            ;; on the live hypothesis, so that fact is in the token -- and conjoining
            ;; its belief in would make the ruling-out force track how strongly the
            ;; hypothesis is already held rather than the contradicting observation.
            ;; ADJUST-BELIEF does the same removal for the assert-driven path; this is
            ;; the same hazard on the fire-driven one.
            (let ((before (belief-factor fact))
                  (evidence (remove fact premises :test #'eq)))
              (setf (belief-factor fact)
                    (belief:adjust-belief evidence (- (abs mass)) before))
              (record-derivation rete fact rule evidence before
                                 (belief-factor fact)))))))))

(defun contribute-unasserted-claims (rete rule premises)
  "Contribute the claims of a rule that asserted nothing.

   Belief accumulation is normally driven by fact assertion, because a rule that
   concludes something adjusts that conclusion. Under a shared frame a rule may
   legitimately conclude NOTHING and still be evidence -- a negative test result
   excludes without identifying anything -- so those rules contribute here instead.
   Their derivation is recorded against the hypotheses each claim is about."
  (let ((claims (rule-claims rule belief:*frame*)))
    (when claims
      (let ((entity (premise-entity rule premises)))
        (when entity
          (let ((pool (entity-pool rete entity))
                (strength (raw-premise-strength rete premises))
                (contributions '()))
            (dolist (claim claims)
              (let ((mask (claim-mask claim)))
                (when (and mask (plusp mask))
                  (let ((mass (* (claim-mass claim) strength)))
                    (belief:pool-add pool mask mass (rule-name rule))
                    (push (cons mask mass) contributions)))))
            (when contributions
              (refresh-projections rete entity)
              (let ((conflict (belief:pool-conflict pool))
                    (audience (remove-duplicates
                               (loop for c in claims append (claim-audience rete entity c)))))
                (dolist (fact audience)
                  (record-derivation rete fact rule premises nil (belief-factor fact)
                                     :claims (reverse contributions)
                                     :conflict conflict))))))))))

(defun accumulate-frame-evidence (rete fact rule premises)
  "Contribute one firing of RULE to the pool for FACT's entity, then re-project.

   A rule may state SEVERAL claims -- red pigment means Serratia at 0.75, and means
   none of these five at 0.80 -- and each becomes its own simple support function in
   the pool. That keeps the cautious rule exact (the pool holds only simple support
   functions) while letting one observation be authored in one place.

   Returns (values CONFLICT CONTRIBUTIONS), where CONTRIBUTIONS is a list of
   (mask . mass) actually added, or NIL when the rule designates nothing."
  (let* ((entity (fact-entity fact))
         (strength (raw-premise-strength rete premises))
         (pool (entity-pool rete entity))
         (contributions '()))
    (dolist (claim (rule-claims rule belief:*frame*))
      (let ((mask (claim-mask claim)))
        (when (and mask (plusp mask))
          (let ((mass (* (claim-mass claim) strength)))
            (belief:pool-add pool mask mass (rule-name rule))
            (push (cons mask mass) contributions)))))
    (when contributions
      (setf *frame-evidence-contributed* t)
      (refresh-projections rete entity fact)
      ;; The pool's UNNORMALIZED conflict: both normalizations resolve K away, so
      ;; reading it off the projected mass function would always give zero.
      (values (belief:pool-conflict pool) (nreverse contributions)))))

(defmethod adjust-belief (rete fact (belief-factor t))
  (when (in-rule-firing-p)
    (let* ((rule (active-rule))
           ;; Exclude the conclusion fact itself from the premise list. When a
           ;; rule matches the very fact it re-asserts (e.g. a disconfirming rule
           ;; that guards on an already-present hypothesis), that fact's prior
           ;; belief is not premise *evidence* and must not drive the combined
           ;; strength — otherwise ruling-out force would track how strongly the
           ;; hypothesis is already held instead of the contradicting observation.
           (premises (remove fact (token-make-fact-list *active-tokens*) :test #'eq))
           (belief-before (belief-factor fact)))
      (if (belief:frame-based-p belief:*belief-system*)
          ;; Shared frame: the rule contributes a focal set to the entity's pool, and
          ;; every hypothesis for that entity is re-projected from it.
          (multiple-value-bind (conflict contributions)
              (accumulate-frame-evidence rete fact rule premises)
            (when contributions
              (record-derivation rete fact rule premises belief-before
                                 (belief-factor fact)
                                 :claims contributions
                                 :conflict conflict)))
          ;; Per-hypothesis (CF, Barnett DS): the rule adjusts this fact's own number.
          (progn
            (setf (belief-factor fact)
                  (belief:adjust-belief premises (belief-factor rule) (belief-factor fact)))
            ;; Record what the engine ACTUALLY did (authoritative, not recomputed later).
            (record-derivation rete fact rule premises belief-before
                               (belief-factor fact)))))))

(defmethod assert-fact ((self rete) fact &key belief)
  (let ((duplicate (duplicate-fact-p self fact)))
    (cond (duplicate
           (adjust-belief self duplicate belief))
          (t
           (adjust-belief self fact belief)
           (assert-fact-aux self fact)))
    (if duplicate
        duplicate
      fact)))

(defmethod retract-fact ((self rete) (fact fact))
  (with-truth-maintenance (self)
    (forget-fact self fact)
    (trace-retract fact)
    (remove-fact-from-network (rete-network self) fact)
    (when (fact-shadowsp fact)
      (forget-clos-instance self (find-instance-of-fact fact)))
    fact))

(defmethod retract-fact ((self rete) (instance standard-object))
  (let ((fact (find-fact-using-instance self instance)))
    (cl:assert (not (null fact)) nil
      "This CLOS instance is unknown to LISA: ~S" instance)
    (retract-fact self fact)))

(defmethod retract-fact ((self rete) (fact-id integer))
  (let ((fact (find-fact-by-id self fact-id)))
    (and (not (null fact))
         (retract-fact self fact))))

(defmethod modify-fact ((self rete) fact &rest slot-changes)
  (retract-fact self fact)
  (mapc #'(lambda (slot)
            (set-slot-value fact (first slot) (second slot)))
        slot-changes)
  (assert-fact self fact)
  fact)

(defun clear-contexts (rete)
  (loop for context being the hash-values of (rete-contexts rete)
      do (clear-activations context)))

(defun clear-focus-stack (rete)
  (setf (rete-focus-stack rete) (list)))

(defun initial-context (rete)
  (find-context rete :initial-context))

(defun reset-focus-stack (rete)
  (setf (rete-focus-stack rete)
    (list (initial-context rete))))

(defun set-initial-state (rete)
  (forget-all-facts rete)
  (clear-contexts rete)
  (reset-focus-stack rete)
  (setf (rete-next-fact-id rete) -1)
  (setf (rete-firing-count rete) 0)
  t)

(defmethod reset-engine ((self rete))
  (reset-network (rete-network self))
  (forget-all-facts self)
  (set-initial-state self)
  (assert (initial-fact))
  (assert-autofacts self)
  t)

(defun get-rule-list (rete &optional (context-name nil))
  (if (null context-name)
      (loop for context being the hash-values of (rete-contexts rete)
          append (context-rule-list context))
    (context-rule-list (find-context rete context-name))))

(defun get-activation-list (rete &optional (context-name nil))
  (if (not context-name)
      (loop for context being the hash-values of (rete-contexts rete)
            for activations = (context-activation-list context)
            when activations
              nconc activations)
    (context-activation-list (find-context rete context-name))))

(defun find-fact-using-instance (rete instance)
  (gethash instance (rete-instance-table rete)))

(defun register-clos-instance (rete instance fact)
  (setf (gethash instance (rete-instance-table rete)) fact))

(defun forget-clos-instance (rete instance)
  (remhash instance (rete-instance-table rete)))

(defun forget-clos-instances (rete)
  (clrhash (rete-instance-table rete)))

(defmethod mark-clos-instance-as-changed ((self rete) instance &optional (slot-id nil))
  (let ((fact (find-fact-using-instance self instance))
        (network (rete-network self)))
    (unless (null fact)
      (remove-fact-from-network network fact)
      (synchronize-with-instance fact slot-id)
      (add-fact-to-network network fact))
    instance))

(defun find-context (rete defined-name &optional (errorp t))
  (let ((context
         (gethash (make-context-name defined-name) (rete-contexts rete))))
    (when (and (null context) errorp)
      (log:error "There's no context named: ~A" defined-name)
      (error t))
    context))

(defun register-new-context (rete context)
  (setf (gethash (context-name context) (rete-contexts rete)) context))

(defun forget-context (rete context-name)
  (let ((context (find-context rete context-name)))
    (dolist (rule (context-rule-list context))
      (forget-rule rete rule))
    (remhash context-name (rete-contexts rete))
    context))

(defun current-context (rete)
  (first (rete-focus-stack rete)))

(defun next-context (rete)
  (with-accessors ((focus-stack rete-focus-stack)) rete
    (pop focus-stack)
    (setf *active-context* (first focus-stack))))

(defun starting-context (rete)
  (first (rete-focus-stack rete)))

(defun push-context (rete context)
  (push context (rete-focus-stack rete))
  (setf *active-context* context))

(defun pop-context (rete)
  (next-context rete))

(defun retrieve-contexts (rete)
  (loop for context being the hash-values of (rete-contexts rete)
      collect context))

(defmethod add-activation ((self rete) activation)
  (let ((rule (activation-rule activation)))
    (trace-enable-activation activation)
    (add-activation (conflict-set rule) activation)
    (when (auto-focus-p rule)
      (push-context self (rule-context rule)))))

(defmethod disable-activation ((self rete) activation)
  (when (eligible-p activation)
    (trace-disable-activation activation)
    (setf (activation-eligible activation) nil))
  activation)

(defmethod run-engine ((self rete) &optional (step -1))
  (with-context (starting-context self)
    (setf (rete-halted self) nil)
    (do ((count 0))
        ((or (= count step) (rete-halted self)) count)
      (let ((activation 
             (next-activation (conflict-set (active-context)))))
        (cond ((null activation)
               (next-context self)
               (when (null (active-context))
                 (reset-focus-stack self)
                 (halt-engine self)))
              ((eligible-p activation)
               (incf (rete-firing-count self))
               (fire-activation activation)
               (incf count)))))))

(defun halt-engine (rete)
  (setf (rete-halted rete) t))

(defun make-rete ()
  (make-instance 'rete))

(defun make-inference-engine ()
  (make-rete))

(defun copy-network (engine)
  (let ((new-engine (make-inference-engine)))
    (mapc #'(lambda (rule)
              (copy-rule rule new-engine))
          (get-rule-list engine))
    new-engine))

(defun make-query-engine (source-rete)
  (let* ((query-engine (make-inference-engine)))
    (loop for fact being the hash-values of (rete-fact-table source-rete)
        do (remember-fact query-engine fact))
    query-engine))
