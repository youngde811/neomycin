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

(in-package :lisa)

(defclass rule ()
  ((short-name :initarg :short-name
               :initform nil
               :reader rule-short-name)
   (qualified-name :reader rule-name)
   (comment :initform nil
            :initarg :comment
            :reader rule-comment)
   (salience :initform 0
             :initarg :salience
             :reader rule-salience)
   (context :initarg :context
            :reader rule-context)
   (auto-focus :initform nil
               :initarg :auto-focus
               :reader rule-auto-focus)
   (behavior :initform nil
             :initarg :behavior
             :accessor rule-behavior)
   (binding-set :initarg :binding-set
                :initform nil
                :reader rule-binding-set)
   (node-list :initform nil
              :reader rule-node-list)
   (activations :initform (make-hash-table :test #'equal)
                :accessor rule-activations)
   (patterns :initform (list)
             :initarg :patterns
             :reader rule-patterns)
   (actions :initform nil
            :initarg :actions
            :reader rule-actions)
   (logical-marker :initform nil
                   :initarg :logical-marker
                   :reader rule-logical-marker)
   (belief-factor :initarg :belief
                  :initform nil
                  :reader belief-factor)
   ;; Machine-readable rule PROVENANCE (neomycin extension): a plist describing the
   ;; rule's pedigree and authority -- (:origin :genuine-mycin | :paip-subset |
   ;; :neomycin-extrapolation :citation ... :note ...). Pure metadata: the engine
   ;; never reads it during inference; it exists so the explanation facility can
   ;; surface a rule's justification (citations) instead of leaving it in source
   ;; comments. Defaults NIL, so rules that declare no :provenance are unaffected.
   (provenance :initarg :provenance
               :initform nil
               :reader rule-provenance)
   ;; DECLARED FOCAL SET (neomycin extension). When a rulebase reasons over a shared
   ;; frame of discernment, a rule's evidence bears on a SET of hypotheses, not on one
   ;; -- "lactose+/indole+ means E. coli or K. oxytoca" is a statement about a pair.
   ;; SUPPORTS names the set the evidence narrows the answer TO; OPPOSES names the set
   ;; it argues AGAINST (sugar for supporting the complement, which is why ruling-out
   ;; stops being a separate rule kind). Both hold unresolved designators -- elements,
   ;; subset names, or a list of either -- resolved against the frame by
   ;; RULE-FOCAL-SET. Both default NIL, and a rule declaring neither falls back to
   ;; what it asserts, so every existing rule is unaffected.
   ;; See docs/shared-frame-design.md 4.2.
   ;; CLAIMS: the general form. A rule states one or more claims about what its
   ;; evidence establishes, each with its own strength -- ((0.75 :supports :serratia)
   ;; (0.80 :excludes (...))). One observation, one rule, however many granularities
   ;; the author can honestly claim. :belief + :supports/:opposes below is the
   ;; single-claim shorthand and normalizes into this; RULE-CLAIMS is the accessor
   ;; every consumer should use. See docs/multi-claim-rules.md.
   (claims :initarg :claims
           :initform nil
           :reader rule-declared-claims)
   (supports :initarg :supports
             :initform nil
             :reader rule-supports)
   (opposes :initarg :opposes
            :initform nil
            :reader rule-opposes)
   (active-dependencies :initform (make-hash-table :test #'equal)
                        :reader rule-active-dependencies)
   (engine :initarg :engine
           :initform nil
           :reader rule-engine))
  (:documentation
   "Represents production rules after they've been analysed by the language
  parser."))

(defmethod fire-rule ((self rule) tokens)
  (let ((*active-rule* self)
        (*active-engine* (rule-engine self))
        (*active-tokens* tokens))
    (unbind-rule-activation self tokens)
    (funcall (rule-behavior self) tokens)))

(defun rule-default-name (rule)
  (if (initial-context-p (rule-context rule))
      (rule-short-name rule)
    (rule-name rule)))

(defun bind-rule-activation (rule activation tokens)
  (setf (gethash (hash-key tokens) (rule-activations rule))
    activation))

(defun unbind-rule-activation (rule tokens)
  (remhash (hash-key tokens) (rule-activations rule)))

(defun clear-activation-bindings (rule)
  (clrhash (rule-activations rule)))

(defun find-activation-binding (rule tokens)
  (gethash (hash-key tokens) (rule-activations rule)))

(defun attach-rule-nodes (rule nodes)
  (setf (slot-value rule 'node-list) nodes))

(defun compile-rule-behavior (rule actions)
  (with-accessors ((behavior rule-behavior)) rule
    (unless behavior
      (setf (rule-behavior rule)
        (make-behavior (rule-actions-actions actions)
                       (rule-actions-bindings actions))))))

(defmethod conflict-set ((self rule))
  (conflict-set (rule-context self)))

(defmethod print-object ((self rule) strm)
  (print-unreadable-object (self strm :type t)
    (format strm "~A"
            (if (initial-context-p (rule-context self))
                (rule-short-name self)
              (rule-name self)))))

(defun compile-rule (rule patterns actions)
  (compile-rule-behavior rule actions)
  (add-rule-to-network (rule-engine rule) rule patterns)
  rule)

(defun logical-rule-p (rule)
  (numberp (rule-logical-marker rule)))

(defun auto-focus-p (rule)
  (rule-auto-focus rule))

(defun find-any-logical-boundaries (patterns)
  (flet ((ensure-logical-blocks-are-valid (addresses)
           (cl:assert (= (first (last addresses)) 1) nil "Logical patterns must appear first within a rule.")
           ;; BUG FIX - FEB 17, 2004 - Aneil Mallavarapu
           ;;         - replaced: 
           ;; (reduce #'(lambda (first second) 
           ;; arguments need to be inverted because address values are PUSHed
           ;; onto the list ADDRESSES, and therefore are in reverse order
           (reduce #'(lambda (second first)
                       (cl:assert (= second (1+ first)) nil
                         "All logical patterns within a rule must be contiguous.")
                       second)
                   addresses :from-end t)))
    (let ((addresses (list)))
      (dolist (pattern patterns)
        (when (logical-pattern-p pattern)
          (push (parsed-pattern-address pattern) addresses)))
      (unless (null addresses)
        (ensure-logical-blocks-are-valid addresses))
      (first addresses))))

(defmethod initialize-instance :after ((self rule) &rest initargs)
  (declare (ignore initargs))
  (with-slots ((qual-name qualified-name)) self
    (setf qual-name
      (intern (format nil "~A.~A" 
                      (context-name (rule-context self))
                      (rule-short-name self))))))
                    
(defun make-rule (name engine patterns actions
                  &key (doc-string nil)
                       (salience 0)
                       (context (active-context))
                       (auto-focus nil)
                       (belief nil)
                       (provenance nil)
                       (supports nil)
                       (opposes nil)
                       (claims nil)
                       (compiled-behavior nil))
  (flet ((make-rule-binding-set ()
           (delete-duplicates
            (loop for pattern in patterns
                append (parsed-pattern-binding-set pattern)))))
    (compile-rule
     (make-instance 'rule 
       :short-name name 
       :engine engine
       :patterns patterns
       :actions actions
       :behavior compiled-behavior
       :comment doc-string
       :belief belief
       :provenance provenance
       :supports supports
       :opposes opposes
       :claims claims
       :salience salience
       :context (if (null context)
                    (find-context (inference-engine) :initial-context)
                  (find-context (inference-engine) context))
       :auto-focus auto-focus
       :logical-marker (find-any-logical-boundaries patterns)
       :binding-set (make-rule-binding-set))
     patterns actions)))

(defun copy-rule (rule engine)
  (let ((initargs `(:doc-string ,(rule-comment rule)
                    :salience ,(rule-salience rule)
                    :context ,(if (initial-context-p (rule-context rule))
                                  nil
                                (context-name (rule-context rule)))
                    :compiled-behavior ,(rule-behavior rule)
                    :provenance ,(rule-provenance rule)
                    :supports ,(rule-supports rule)
                    :opposes ,(rule-opposes rule)
                    :claims ,(rule-declared-claims rule)
                    :auto-focus ,(rule-auto-focus rule))))
    (with-inference-engine (engine)
      (apply #'make-rule
             (rule-short-name rule)
             engine
             (rule-patterns rule)
             (rule-actions rule)
             initargs))))
