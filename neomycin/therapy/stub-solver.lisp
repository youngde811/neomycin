;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.

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

;; Description: A trivial reference solver that returns an empty recommendation.
;; Its only jobs are to prove the protocol wiring loads and dispatches, and to be
;; the "second solver" the protocol test selects (design doc 8). The real greedy
;; weighted set-cover solver (design doc 4.3) is a separate, later file.

(in-package :neomycin-therapy)

(defclass stub-solver (solver) ()
  (:documentation "Placeholder solver: returns an empty recommendation. Proves
   the protocol dispatches; does no selection."))

(defmethod solve-regimen ((solver stub-solver) conclusions kb patient)
  (declare (ignore conclusions kb patient))
  (make-recommendation))

;; Register on load so (use-solver :stub) works out of the box.
(register-solver :stub (make-instance 'stub-solver :name "stub"))