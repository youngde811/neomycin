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
  :version "0.1.0"
  :author "David E. Young"
  :maintainer "David E. Young"
  :licence "MIT"
  :description "A research reconstruction of Stanford's MYCIN/EMYCIN expert system, using Lisa and Claude"
  :depends-on ("lisa" "lisa-bridge")
  :components
  ((:module neomycin
    :components
      ((:file "rulebase")))))

(eval-when (:load-toplevel :execute)
  (pushnew :neomycin0.1.0 *features*)
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
