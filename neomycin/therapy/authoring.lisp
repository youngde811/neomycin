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

;; Description: The def* authoring surface for therapy knowledge (design doc 3.2).
;; These macros are a thin, reviewable DSL over the (already-tested) builder API
;; in kb.lisp -- they exist so a KB data file reads as declarative DATA and lands
;; as a clean git diff, which is exactly what the human-vetted KB-update loop
;; (design doc principle #3) depends on. They add no policy or belief logic of
;; their own; that all lives in the accessors and the solver.
;;
;; All forms populate *THERAPY-KB*. Rebind it (LET) to author into a different KB
;; -- e.g. a fixture in a test -- without disturbing the canonical one.

(in-package :neomycin-therapy)

(defvar *therapy-kb* (make-therapy-kb)
  "The therapy knowledge base that def* authoring forms populate. The canonical
   data file (knowledge-base.lisp) fills this at load time; bind it with LET to
   author into a throwaway KB (tests do this).")

;; The vocabulary is KEYWORDS end to end: organism ids match the engine's
;; keyword organism-identity values with no conversion seam (they are the same
;; global objects), and drug/class/route/trigger ids are keywords too for one
;; uniform, JSON-friendly namespace. Keywords self-evaluate, so these macros pass
;; their id arguments through unquoted; only DOSE and SUSCEPTIBILITY are ordinary
;; evaluated forms.

(defmacro defdrug (id &key class route dose)
  "Author drug ID (a keyword, e.g. :ceftazidime) into *THERAPY-KB*. CLASS and
   ROUTE are keywords (e.g. :cephalosporin-3, :iv); DOSE is an evaluated form,
   typically a simulated non-clinical dose string."
  `(add-drug *therapy-kb* ,id :class ,class :route ,route :dose ,dose))

(defmacro defsensitivity (organism drug susceptibility)
  "Author ORGANISM's SUSCEPTIBILITY to DRUG into *THERAPY-KB*. ORGANISM and DRUG
   are keywords; SUSCEPTIBILITY is EVALUATED and belief-valued -- a plain number,
   or a belief object such as (belief:make-ds-belief bel pl) -- so the belief
   algebra flows from the KB into the solver unchanged."
  `(add-sensitivity *therapy-kb* ,organism ,drug ,susceptibility))

(defmacro defcontraindication (drug &key when)
  "Author contraindication triggers for DRUG into *THERAPY-KB*. WHEN is a literal
   list of patient-state keyword tokens (e.g. (:allergy-cephalosporin
   :renal-impaired)); the solver excludes DRUG when any token is present in the
   patient's state. Idempotent, so reloading the data file does not duplicate."
  `(apply #'add-contraindication *therapy-kb* ,drug ',when))

(defmacro with-therapy-kb ((kb form) &body body)
  (let ((kbase (gensym)))
    `(let* ((,kbase ,form)
            (therapy:*therapy-kb* ,kbase)
            (,kb ,kbase))
       (progn ,@body))))

(defun therapy-kb ()
  *therapy-kb*)
