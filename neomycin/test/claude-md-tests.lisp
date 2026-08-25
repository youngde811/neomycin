;;; -*- Mode: Lisp -*-
;;;
;;; Part of neomycin's test suite.
;;;
;;; CLAUDE.md AGAINST THE COMPILED IMAGE.
;;;
;;; prompt-tests.lisp guards the two documents the MODEL reads -- system-prompt.md and
;;; tools.json. Nothing guarded the one every DEVELOPER and every agent session reads
;;; first, and which carries a denser concentration of claims than either: the endpoint
;;; table, the package roster, the corpus counts, the invariant list.
;;;
;;; It went wrong three times in one afternoon (2026-08-25). It described four
;;; property-test invariants that had been retired with the disconfirming rules; it
;;; credited bin/test-rules.sh with checking "every ruling-out rule's targets", which it
;;; never did; and its `belief' package bullet listed ELEVEN symbols -- the whole
;;; declared-frame layer -- that were deleted at v0.11 and had not existed for five
;;; releases. Every one was a claim nothing could falsify.
;;;
;;; This file falsifies the mechanical half. It cannot check that a sentence is TRUE,
;;; only that the names and counts in it are real -- which is exactly the split
;;; docs/release-check-design.md §5 draws for the release gate, and the same bargain:
;;; the mechanical half becomes impossible to get wrong, and the judgement half still
;;; needs a reader.

(in-package "LISA-TEST")

(defun claude-md-text ()
  "CLAUDE.md, as text."
  (with-open-file (in (asdf:system-relative-pathname "neomycin" "CLAUDE.md")
                      :external-format :utf-8)
    (let ((text (make-string (file-length in))))
      (subseq text 0 (read-sequence text in)))))

;;; ------------------------------------------------------------------
;;; What counts as a symbol reference
;;; ------------------------------------------------------------------

(defparameter *symbol-search-packages*
  '("LISA" "LISA-USER" "LISA.BELIEF" "LISA.CANDIDATES" "LISA-BRIDGE"
    "NEOMYCIN" "NEOMYCIN-THERAPY" "LISA-TEST" "COMMON-LISP")
  "Where a name CLAUDE.md quotes is allowed to live.")

(defun lisp-identifier-shaped-p (token)
  "True when TOKEN is written the way this project writes a Lisp name: kebab-case, or
   earmuffed. Deliberately narrow -- a token with no hyphen and no earmuffs is far more
   likely to be prose, a JSON field or a shell word than a symbol, and guessing wrong in
   that direction produces noise rather than safety."
  (and (>= (length token) 4)
       (some #'lower-case-p token)
       (notany (lambda (c) (find c ".:/ ")) token)
       ;; Not a command-line flag. `--plain' is kebab-shaped and is not a symbol; no
       ;; Lisp name in this codebase begins with a hyphen.
       (char/= (char token 0) #\-)
       (or (find #\- token) (char= (char token 0) #\*))))

(defun registered-test-name-p (name)
  "True when NAME is a test this harness has registered. CLAUDE.md cites tests by name
   and those citations should be guarded like any other."
  (member name *tests*
          :key (lambda (entry) (symbol-name (car entry)))
          :test #'string-equal))

(defun resolves-p (token)
  "True when TOKEN names something that actually EXISTS: a package, a bound or fbound
   symbol, a class, or a registered test."
  (let ((name (string-upcase token)))
    (or (and (find-package name) t)
        (registered-test-name-p name)
        (some (lambda (pkg-name)
                (let ((pkg (find-package pkg-name)))
                  (when pkg
                    (multiple-value-bind (sym status) (find-symbol name pkg)
                      (and sym status
                           (or (fboundp sym) (boundp sym)
                               (and (find-class sym nil) t)))))))
              *symbol-search-packages*))))

;;; ------------------------------------------------------------------
;;; The exemptions, each with its reason -- and checked in BOTH directions
;;; ------------------------------------------------------------------

(defparameter *claude-md-not-symbols*
  '(;; Model identifiers, not Lisp names.
    ("claude-opus-4-7"   . "an LLM model id")
    ("claude-sonnet-5"   . "an LLM model id")
    ;; A glob standing for the scenario drivers, not a name.
    ("culture-*"         . "a glob over the culture-N drivers")
    ;; NAMED IN ORDER TO BE DENIED. CLAUDE.md says there is no organism-class; if this
    ;; ever starts resolving, either the corpus grew one back or the sentence denying it
    ;; has gone false, and both are worth stopping for.
    ("organism-class"    . "named as ABSENT -- a genus IS a candidates set")
    ;; The declared-frame layer, deleted at v0.11. CLAUDE.md names these three in the
    ;; `belief' bullet specifically to record that it USED to list them and that they
    ;; never existed after v0.11 -- the drift this whole file exists to catch. Naming a
    ;; dead symbol in order to call it dead is legitimate; resolving is not.
    ("make-frame"        . "named as DELETED with the declared-frame system (v0.11)")
    ("evidence-pool"     . "named as DELETED with the declared-frame system (v0.11)")
    ("*frame-operator*"  . "named as DELETED with the declared-frame system (v0.11)"))
  "Backticked tokens that LOOK like Lisp names and deliberately are not, each with why.

   A token here MUST NOT resolve. That is the second direction, and it is the half that
   matters: an exemption list nobody rechecks is how a guard stops guarding. If one of
   these becomes real, this test fails and asks for a decision rather than silently
   waving the name through for the next five releases.")

(defun exempt-reason (token)
  (cdr (assoc token *claude-md-not-symbols* :test #'string-equal)))

;;; ------------------------------------------------------------------
;;; Guard 1 -- every Lisp name CLAUDE.md quotes exists.
;;; ------------------------------------------------------------------

(deftest claude-md-names-only-real-symbols ()
  (let ((missing '()))
    (dolist (token (remove-duplicates (backticked-tokens (claude-md-text))
                                      :test #'string=))
      (when (and (lisp-identifier-shaped-p token)
                 (not (exempt-reason token))
                 (not (resolves-p token)))
        (push token missing)))
    (is (null missing)
        (format nil "CLAUDE.md names ~R symbol~:P that do not exist: ~{~A~^, ~}~@
                     Either the name is stale, or it belongs in *CLAUDE-MD-NOT-SYMBOLS* ~
                     with a reason."
                (length missing) (sort missing #'string<)))))

;;; ------------------------------------------------------------------
;;; Guard 2 -- and every exemption is still needed.
;;; ------------------------------------------------------------------

(deftest claude-md-exemptions-are-still-exemptions ()
  (dolist (entry *claude-md-not-symbols*)
    (destructuring-bind (token . reason) entry
      (is (not (resolves-p token))
          (format nil "`~A' is exempted from the CLAUDE.md symbol guard as ~S, ~
                       but it now RESOLVES. The exemption has gone stale."
                  token reason)))))

;;; ------------------------------------------------------------------
;;; Guard 3 -- the exemption list is not carrying dead weight either.
;;; ------------------------------------------------------------------

(deftest claude-md-exemptions-are-all-cited ()
  ;; An exemption for a token CLAUDE.md no longer mentions is clutter that reads as
  ;; policy. The same argument as guard 2, pointed the other way.
  (let ((tokens (remove-duplicates (backticked-tokens (claude-md-text)) :test #'string=)))
    (dolist (entry *claude-md-not-symbols*)
      (let ((token (car entry)))
        (is (member token tokens :test #'string-equal)
            (format nil "`~A' is exempted from the CLAUDE.md symbol guard, ~
                         but CLAUDE.md no longer mentions it." token))))))

;;; ------------------------------------------------------------------
;;; Guard 4 -- the corpus counts CLAUDE.md states are the real ones.
;;;
;;; The suite's own assertion/test counts are deliberately NOT guarded: the guard
;;; would change the number it checks, and CLAUDE.md states them with a "~" for
;;; exactly that reason. Rule counts have no such excuse.
;;; ------------------------------------------------------------------

(deftest claude-md-states-the-real-rule-counts ()
  (let* ((text (claude-md-text))
         (rules (length (domain-rules)))
         (gram-pos (count-if (lambda (r) (search "CANDIDATES-GRAM-POS"
                                                 (string (lisa:rule-name r))))
                             (domain-rules))))
    (declare (ignorable gram-pos))
    (is (search (format nil "~D rules, every one CONFIRMING" rules) text)
        (format nil "CLAUDE.md no longer states the corpus size as \"~D rules, every ~
                     one CONFIRMING\" -- the compiled rulebase has ~D domain rules."
                rules rules))))
