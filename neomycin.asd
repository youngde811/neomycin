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
  :version "0.5.0"
  :author "David E. Young"
  :maintainer "David E. Young"
  :licence "MIT"
  :description "A research reconstruction of Stanford's MYCIN/EMYCIN expert system, using Lisa and Claude"
  :depends-on ("lisa" "lisa-bridge")
  :components
  ((:module neomycin
    :components
      ((:file "rulebase")
       (:module "therapy"
        :depends-on ("rulebase")
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
           (:file "greedy-solver" :depends-on ("protocol" "kb"))
           ;; HTTP surface for the therapy phase (design doc step (c)); depends on
           ;; the solver protocol + the canonical KB it recommends over.
           (:file "bridge" :depends-on ("greedy-solver" "knowledge-base"))))))))

;;; Fixture-based tests for the therapy solver. Reuses the dependency-free
;;; LISA-TEST harness. Run with (asdf:test-system "neomycin/test") or
;;; (asdf:load-system "neomycin/test") followed by (lisa-test:run-all).
;;; Depends on lisa/test-base (the rulebase-independent harness + belief-algebra),
;;; NOT lisa/test -- neomycin ships its OWN forked golden files (scenarios, rules)
;;; validating neomycin/rulebase.lisp, which diverges from Lisa's examples/mycin.lisp
;;; once rules are re-parented (docs/chaining-belief-spike.md §7.1). setup.lisp loads
;;; first and repoints the shared harness at neomycin's canonical rulebase.
(asdf:defsystem "neomycin/test"
  :description "Fixture-based tests for neomycin's rulebase + therapy solver (no external deps)."
  :depends-on ("neomycin" "lisa/test-base")
  :components
  ((:module neomycin
    :components
      ((:module "test"
        :components ((:file "setup")
                     (:file "scenarios")
                     (:file "rules")
                     (:file "chain-tests")
                     (:file "provenance-tests")
                     (:file "therapy-tests")
                     (:file "antibiogram-tests")
                     (:file "therapy-bridge-tests"))))))
  :perform (asdf:test-op (o c)
             (unless (uiop:symbol-call "LISA-TEST" "RUN-ALL")
               (error "neomycin test suite reported failures"))))

(eval-when (:load-toplevel :execute)
  (pushnew :neomycin0.5.0 *features*)
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
      `(("rulebase;*.*" ,(make-neomycin-path "neomycin/"))))
