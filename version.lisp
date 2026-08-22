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

;; Update the version symbol in this file whenever you do a new release.
;;
;; 4.4.0 (2026-08-22) -- a MINOR bump: the engine gained exported API, and one
;; endpoint changed its behaviour on bad input.
;;
;;   ADDED   LISA:CORPUS-PREMISE-VOCABULARY / CORPUS-PREMISES-VALUE-P -- what a whole
;;           rulebase can HEAR: every literal premise value, by parameter. Derived from
;;           premises rather than declared fact classes, deliberately, because a class
;;           the knowledge base declares but no rule reads is assertable and INERT --
;;           accepted, matched by nothing, and silent about it. The query exists so a
;;           client cannot mistake that silence for an empty answer.
;;   ADDED   CANDIDATES:MARGIN / LEADING-FOCUS -- how far the leading answer sits above
;;           the nearest answer that CONTRADICTS it. The companion to CONFLICT-OF, and
;;           not optional: two answers naming different hypotheses conflict totally in
;;           this algebra, so K counts rival mass OVERRULED and rises as the winner
;;           strengthens. K alone is not a measure of disagreement and was read as one.
;;   CHANGED /assert-fact rejects an unknown fact_type by name with 400, in place of a
;;           500 leaking "There is no class named COMMON-LISP:NIL".
;;
;; Certainty factors and the Barnett per-hypothesis Dempster-Shafer system are again
;; UNCHANGED.
;;
;; 4.3.0 (2026-08-18) -- first Lisa version bump since the neomycin fork, and it is a
;; MINOR rather than a patch because the engine gained and lost real capability rather
;; than being tuned:
;;
;;   ADDED   rule :provenance, a machine-readable pedigree carried on any rule
;;   ADDED   the fire-time derivation record -- which rules produced which fact
;;   ADDED   src/core/rule-introspection.lisp, an exported domain-neutral API for
;;           querying the COMPILED rulebase (what a rule concludes, matches, believes,
;;           and whether one rule's premises subsume another's)
;;   ADDED   src/belief-systems/candidates/, Dempster-Shafer over an OPEN frame:
;;           set-valued answers combined by intersection, with Theta never enumerated
;;   REMOVED the declared-frame belief system of the neomycin v0.9/v0.10 line, along
;;           with evidence pools on the rete, fire-time belief accumulation, and the
;;           :supports/:opposes/:claims rule properties
;;
;; Certainty factors and the Barnett per-hypothesis Dempster-Shafer system are
;; UNCHANGED and still the systems Lisa's own examples and suite exercise.

(eval-when (:load-toplevel :execute)
  (pushnew :lisa4.4.0 *features*))
