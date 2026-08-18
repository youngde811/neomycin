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

;; Description: Context tree, clinical parameters and conclusion classes -- the
;; vocabulary every rule file is written against. THIS FILE MUST LOAD FIRST.
;;
;; The rulebase was a single 1300-line file through v0.5.0; the gram-positive
;; increment split it into neomycin/rules/ by cluster, at the ~40-rule threshold the
;; corpus sketch (§7) predicted would make one file unreviewable. Load order is fixed
;; by neomycin.asd:
;;
;;   context                    -- this file: classes only, no rules
;;   identity-gram-neg          -- one-hop gram-negative identities
;;   chain-enterobacteriaceae   -- class -> species, the original chained cluster
;;   chain-gram-pos             -- class -> species for staph / strep / enterococcus
;;   host-factors               -- patient-level belief modifiers
;;   disconfirming              -- every ruling-out rule, all clusters
;;   conclusion                 -- the reporting rule
;;   drivers                    -- culture-* demonstration scenarios
;;
;; CONTEXT TREE (neomycin change): unlike a flat rulebase, the MYCIN world is a
;; hierarchy -- patient -> culture -> organism -- and every clinical parameter
;; belongs to exactly one context in that tree. We make that structure explicit:
;;
;;   * The context classes PATIENT, CULTURE and ORGANISM are asserted as facts
;;     carrying an ID and a parent link (a culture names its patient; an organism
;;     names its culture). IDs are plain values (symbols/strings), NOT CLOS
;;     instance identity, so Rete can join across the hierarchy by ordinary
;;     variable equality -- and so the LLM bridge, which already identifies
;;     entities by string name, maps onto the same model.
;;
;;   * Every parameter fact (a PARAM-MIXIN subclass) scopes to its context via
;;     the OF slot: gram/morphology/aerobicity/growth-conformation are ORGANISM
;;     level, culture-site/culture-age are CULTURE level, and burn/
;;     compromised-host/hospital-acquired/recent-travel/white-blood-count/
;;     infection-site are PATIENT level.
;;
;;   * Rules join through the lineage (organism -> its culture -> its patient),
;;     so evidence stays within a single organism's chain. With one organism
;;     this is behaviourally identical to the old flat rulebase; with N organisms
;;     it prevents the cross-product leakage the flat version silently produced.
;;
;; The rulebase also exercises the pluggable belief-system protocol (see
;; src/belief-systems/). The same rules run unchanged under MYCIN-style certainty
;; factors and under a simplified Dempster-Shafer system, where each hypothesis
;; carries a [Bel, Pl] interval whose width (Pl - Bel) is explicit ignorance.
;; Rule beliefs declared via (:belief ...) are interpreted by the active belief
;; system; the CONCLUSION rule reports the combined belief for each surviving
;; organism-identity hypothesis via BELIEF:BELIEF-FACTOR.
;;
;; Demonstration functions CULTURE-1/1A/2/3 drive the PAIP scenarios (pgs. 555,
;; 556) plus expanded multi-hypothesis differentials.

(in-package :lisa-user)

(clear)

(setf lisa::*allow-duplicate-facts* nil)

;;; ------------------------------------------------------------------
;;; Context tree: patient -> culture -> organism (asserted as facts).
;;; Identity is carried by the ID slot (a plain value), and the parent
;;; link names the parent's ID.
;;; ------------------------------------------------------------------
(defclass patient ()
  ((id   :initarg :id   :initform nil :reader id)
   (name :initarg :name :initform nil :reader name)
   (sex  :initarg :sex  :initform nil :reader sex)
   (age  :initarg :age  :initform nil :reader age)))

(defclass culture ()
  ((id      :initarg :id      :initform nil :reader id)
   (patient :initarg :patient :initform nil :reader culture-patient)))

(defclass organism ()
  ((id      :initarg :id      :initform nil :reader id)
   (culture :initarg :culture :initform nil :reader organism-culture)))

;;; ------------------------------------------------------------------
;;; Parameters: each scopes to its context via the OF slot (formerly
;;; ENTITY). VALUE holds the clinical reading.
;;; ------------------------------------------------------------------
(defclass param-mixin ()
  ((value :initarg :value :initform nil :reader value)
   (of    :initarg :of    :initform nil :reader context-of)))

;; Culture-level parameters
(defclass culture-site (param-mixin) ())
(defclass culture-age (param-mixin) ())

;; Patient-level parameters
(defclass burn (param-mixin) ())
(defclass compromised-host (param-mixin) ())
(defclass hospital-acquired (param-mixin) ())
(defclass recent-travel (param-mixin) ())
(defclass white-blood-count (param-mixin) ())
(defclass infection-site (param-mixin) ())
;; Host factors (sketch §5.5): patient-level context that SHIFTS belief on
;; hypotheses other rules raise, rather than naming an organism from morphology.
(defclass neutropenia (param-mixin) ())         ; value = t
(defclass prosthetic-material (param-mixin) ()) ; value = t
(defclass iv-drug-use (param-mixin) ())         ; value = t
(defclass age-group (param-mixin) ())           ; value = neonate | infant | adult | elderly

;; Organism-level parameters
(defclass gram (param-mixin) ())
(defclass morphology (param-mixin) ())
(defclass aerobicity (param-mixin) ())
(defclass growth-conformation (param-mixin) ())
;; Biochemical discriminators for enterobacteriaceae species refinement (tier 2).
(defclass lactose (param-mixin) ())     ; value = fermenter | non-fermenter
(defclass indole (param-mixin) ())      ; value = positive | negative
(defclass motility (param-mixin) ())    ; value = motile | non-motile | swarming
(defclass urease (param-mixin) ())      ; value = positive | negative
(defclass pigment (param-mixin) ())     ; value = red | none

;; Discriminators for the gram-POSITIVE COCCUS clusters (docs/gram-positive-cluster-
;; design.md §2). Catalase splits the staphylococci from the streptococci/enterococci;
;; coagulase and novobiocin refine the staphylococci; hemolysis, optochin and
;; bacitracin refine the streptococci; bile-esculin + salt tolerance recognize the
;; enterococci, which arabinose/sorbitol then split into species.
(defclass catalase (param-mixin) ())       ; value = positive | negative
(defclass coagulase (param-mixin) ())      ; value = positive | negative
(defclass hemolysis (param-mixin) ())      ; value = alpha | beta | gamma
(defclass optochin (param-mixin) ())       ; value = sensitive | resistant
(defclass bacitracin (param-mixin) ())     ; value = sensitive | resistant
(defclass novobiocin (param-mixin) ())     ; value = sensitive | resistant
(defclass bile-esculin (param-mixin) ())   ; value = positive | negative
(defclass salt-tolerance (param-mixin) ()) ; value = tolerant | intolerant (6.5% NaCl)
(defclass arabinose (param-mixin) ())      ; value = fermenter | non-fermenter
(defclass sorbitol (param-mixin) ())       ; value = fermenter | non-fermenter

;;; An ANSWER (v0.11 shape). VALUE holds the SET of organisms a piece of evidence
;;; narrows the question to -- '(:streptococcus-pyogenes :streptococcus-agalactiae)
;;; for beta hemolysis, say -- and the rule's own :belief says how strongly.
;;;
;;; This is what replaces both organism-identity and organism-class. A class IS a
;;; candidates set, so nothing has to reify one; and a species call is a candidates
;;; set with one member. Exclusion is never asserted: it is what remains when answers
;;; are intersected. See docs/narrows-to-promotion-sketch.md.
(defclass candidates (param-mixin) ())
