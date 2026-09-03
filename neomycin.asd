;; -*- Mode: LISP; Syntax: ANSI-Common-Lisp; Base: 10 -*-

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

;; Description: neomycin's ASDF system definition file. To use it, you must have asdf loaded.

(in-package :cl-user)

#-asdf
(error "The ASDF package is required. Please load it first")

(asdf:defsystem neomycin
  :name "neomycin"
  :version "1.0.0"
  :author "David E. Young"
  :maintainer "David E. Young"
  :licence "MIT"
  :description "A research reconstruction of Stanford's MYCIN/EMYCIN expert system, using Lisa and Claude"
  :depends-on ("lisa" "lisa-bridge")
  :components
  ((:module neomycin
    :components
      (;; The rulebase was one 1300-line file through v0.5.0. The gram-positive
       ;; increment took it past the ~40-rule threshold the corpus sketch (§7)
       ;; predicted would make a single file unreviewable, so it is split by cluster.
       ;; context.lisp defines every class the rule files are written against and so
       ;; must load first; everything else depends on it and is otherwise independent.
       (:file "package")
       (:module "rules"
        :components
          ((:file "context")
           ;; Rules assert ANSWERS -- the SET of organisms their evidence narrows
           ;; the question to. Confirming only; nothing is excluded by being named,
           ;; and no rule has an empty RHS. See docs/narrows-to-promotion-sketch.md.
           (:file "candidates-gram-pos" :depends-on ("context"))
           (:file "candidates-gram-neg" :depends-on ("context"))
           (:file "conclusion" :depends-on ("context"))
           (:file "drivers" :depends-on ("context"))))
       (:file "consensus" :depends-on ("package" "rules"))
       (:file "bridge" :depends-on ("consensus"))
       (:module "therapy"
        :depends-on ("rules" "consensus")
        :components
          ((:file "package")
           (:file "protocol" :depends-on ("package"))
           (:file "antibiogram" :depends-on ("package"))
           ;; kb-susceptibility overlays the antibiogram interval onto the curated
           ;; figure, so kb depends on the antibiogram counts->interval/combine core.
           (:file "kb" :depends-on ("package" "antibiogram"))
           (:file "authoring" :depends-on ("kb"))
           (:file "knowledge-base" :depends-on ("authoring"))
           ;; NOTE: antibiogram-data.lisp (the schematic site-local counts) is
           ;; deliberately NOT loaded by default. The antibiogram is an OPT-IN,
           ;; swappable layer (design doc 5): the canonical KB stays the pure
           ;; reference, and a deployment/demo LOADs its own counts file to overlay
           ;; local data onto the current *therapy-kb*.
           (:file "stub-solver" :depends-on ("protocol"))
           ;; Shared phase A (belief gate, contraindication filter, the scalar
           ;; reductions both gates read) -- solver-independent, so every solver
           ;; gates identically and comparisons between them stay meaningful
           ;; (exact-solver-design.md §4).
           (:file "solver-common" :depends-on ("protocol" "kb"))
           (:file "greedy-solver" :depends-on ("solver-common"))
           (:file "exact-solver" :depends-on ("solver-common"))
           ;; HTTP surface for the therapy phase (design doc step (c)); depends on
           ;; the solver protocol + the canonical KB it recommends over.
           (:file "bridge" :depends-on ("greedy-solver" "exact-solver" "knowledge-base"))))))))

;;; Fixture-based tests for the therapy solver. Reuses the dependency-free
;;; LISA-TEST harness. Run with (asdf:test-system "neomycin/test") or
;;; (asdf:load-system "neomycin/test") followed by (lisa-test:run-all).
;;; Depends on lisa/test-base (the rulebase-independent harness + belief-algebra),
;;; NOT lisa/test -- neomycin ships its OWN forked golden files (scenarios, rules)
;;; validating neomycin/rules/, which diverges from Lisa's examples/mycin.lisp
;;; once rules are re-parented (docs/attic/chaining-belief-spike.md §7.1). setup.lisp loads
;;; first and repoints the shared harness at neomycin's canonical rulebase.
(asdf:defsystem "neomycin/test"
  :description "Fixture-based tests for neomycin's rulebase + therapy solver (no external deps)."
  :depends-on ("neomycin" "lisa/test-base")
  :components
  ((:module neomycin
    :components
      ((:module "test"
        :components ((:file "setup")
                     (:file "property-tests")
                     ;; Guards the LLM system prompt against the compiled
                     ;; rulebase; depends on property-tests for DOMAIN-RULES.
                     (:file "prompt-tests" :depends-on ("property-tests"))
                     ;; Guards CLAUDE.md against the compiled image; reuses
                     ;; BACKTICKED-TOKENS from prompt-tests.
                     (:file "claude-md-tests" :depends-on ("prompt-tests"))
                     (:file "provenance-tests")
                     ;; The v0.11 shape end to end: scenario goldens, per-rule
                     ;; isolation, and the properties the shape exists for.
                     (:file "candidates-tests" :depends-on ("property-tests"))
                     (:file "therapy-tests")
                     ;; The exact solver + the ALTERNATIVES both solvers report;
                     ;; depends on therapy-tests for REGIMEN-DRUGS / TREATED.
                     (:file "exact-solver-tests" :depends-on ("therapy-tests"))
                     (:file "antibiogram-tests")
                     (:file "therapy-bridge-tests")
                     (:file "bridge-payload-tests")
                     ;; Guards docs/Neomycin.md -- the paper README.md points a
                     ;; first-time reader at -- against the compiled image. Loads
                     ;; LAST so its test-count guard sees every other test
                     ;; registered. Reuses PAPER-SAYS-P's wrap-insensitive search
                     ;; from prompt-tests, the scenario runners from
                     ;; candidates-tests, and SOLVE-WITH from exact-solver-tests.
                     (:file "paper-tests"
                      :depends-on ("prompt-tests" "candidates-tests"
                                   "exact-solver-tests")))))))
  :perform (asdf:test-op (o c)
             (unless (uiop:symbol-call "LISA-TEST" "RUN-ALL")
               (error "neomycin test suite reported failures"))))

(eval-when (:load-toplevel :execute)
  ;; KEEP IN STEP WITH :version ABOVE.
  (pushnew :neomycin1.0.0 *features*)
  (pushnew :neomycin.asdf *features*))

(defvar *neomycin-root-pathname*
  (make-pathname :directory
                 (pathname-directory *load-truename*)
                 :host (pathname-host *load-truename*)
                 :device (pathname-device *load-truename*)))

(defun make-neomycin-path (relative-path)
  (concatenate 'string (namestring *neomycin-root-pathname*)
               relative-path))

(setf (logical-pathname-translations "neomycin")
      `(("rulebase;*.*" ,(make-neomycin-path "neomycin/rules/"))))
