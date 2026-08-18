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

;; Description: Package declarations for Lisa.

(in-package :cl-user)

;;; accommodate implementations whose CLOS is really PCL, like CMUCL...

(eval-when (:compile-toplevel :load-toplevel :execute)
  (when (and (not (find-package 'clos))
             (find-package 'pcl))
    (rename-package (find-package 'pcl) 'pcl
                    `(clos ,@(package-nicknames 'pcl)))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defpackage "LISA"
    (:use "COMMON-LISP")
    (:export
      "ASSERT"
      "DEFAULT"
      .
      #1=(
          "*SHOW-LISA-WARNINGS*"
          "=>"
          "ACTIVATION"
          "ACTIVE-NETWORK"
          "ACTIVE-RULE"
          "AGENDA"
          "ALLOW-DUPLICATE-FACTS"
          "ASSERT-INSTANCE"
          "AUTO-FOCUS-P"
          "BINDINGS"
          "BREAKPOINTS"
          "CLEAR"
          "CLEAR-BREAK"
          "CLEAR-BREAKS"
          "CONFIRMING-RULE-P"
          "RULE-PREMISE-SIGNATURE"
          "RULE-SUBSUMES-P"
          "CONSIDER-TAXONOMY"
          "CONTEXT"
          "CONTEXT-NAME"
          "CONTEXTS"
          "CURRENT-ENGINE"
          "DEFCONTEXT"
          "DEFFACTS"
          "DEFIMPORT"
          "DEFRULE"
          "DEFTEMPLATE"
          "DEPENDENCIES"
          "DERIVATION-RECORD"
          "DERIVATION-RECORD-P"
          "DERIVATION-RECORD-RULE"
          "DERIVATION-RECORD-RULE-BELIEF"
          "DERIVATION-RECORD-PREMISES"
          "DERIVATION-RECORD-BELIEF-BEFORE"
          "DERIVATION-RECORD-BELIEF-AFTER"
          "DERIVATION-RECORD-CONFLICT"
          "DISCONFIRMING-RULE-P"
          "DUPLICATE-FACT"
          "ENGINE"
          "EXISTS"
          "FACT"
          "FACT-DERIVATION"
          "FACT-ID"
          "FACT-NAME"
          "FACTS"
          "FIND-CONTEXT"
          "FIND-FACT-BY-ID"
          "FIND-FACT-BY-NAME"
          "FIND-RULE"
          "GET-FACT-LIST"
          "GET-RULE-LIST"
          "GET-SLOT-VALUE"
          "FOCUS"
          "FOCUS-STACK"
          "HALT"
          "IN-RULE-FIRING-P"
          "INFERENCE-ENGINE"
          "INITIAL-FACT"
          "INSTANCE"
          "KNOWLEDGE-RULE-P"
          "LOGICAL"
          "LOGGER-ADD-FILE-APPENDER"
          "MAKE-INFERENCE-ENGINE"
          "MARK-INSTANCE-AS-CHANGED"
          "MODIFY"
          "NEXT"
          "REFOCUS"
          "RESET"
          "RESUME"
          "RETE"
          "RETE-DERIVATION-TABLE"
          "RETE-NETWORK"
          "RETRACT"
          "RETRACT-INSTANCE"
          "RETRIEVE"
          "RULE"
          "RULE-ASSERTED-FACTS"
          "RULE-BELIEF"
          "RULE-COMMENT"
          "RULE-CONCLUDES-P"
          "RULE-CONTEXT"
          "RULE-DEFAULT-NAME"
          "RULE-MEMBER-TEST-VALUES"
          "RULE-NAME"
          "RULE-PREMISE-CLASSES"
          "RULE-PREMISE-VALUES"
          "RULE-PREMISES-P"
          "RULE-PROVENANCE"
          "RULE-SALIENCE"
          "RULE-SHORT-NAME"
          "RULES"
          "RUN"
          "SET-BREAK"
          "SHOW-NETWORK"
          "SLOT"
          "SLOT-VALUE-OF-INSTANCE"
          "STANDARD-KB-CLASS"
          "TEST"
          "TOKEN"
          "TOKENS"
          "UNDEFCONTEXT"
          "UNDEFRULE"
          "UNWATCH"
          "USE-DEFAULT-ENGINE"
          "USE-FANCY-ASSERT"
          "USE-LISA"
          "WALK"
          "WATCH"
          "WATCHING"
          "WITH-INFERENCE-ENGINE"
          "WITH-SIMPLE-QUERY"))
    (:shadow "ASSERT"))

  (defpackage "LISA-USER"
    (:use "COMMON-LISP")
    (:shadowing-import-from "LISA" "ASSERT" "DEFAULT")
    (:import-from "LISA" . #1#)))

(defpackage "LISA.REFLECT"
  (:use "COMMON-LISP")
  (:nicknames "REFLECT")
  #+(or Allegro LispWorks)
  (:import-from "CLOS"
                "ENSURE-CLASS"
                "CLASS-DIRECT-SUPERCLASSES"
                "CLASS-FINALIZED-P"
                "FINALIZE-INHERITANCE")

  #+CMU
  (:import-from "CLOS"
                "CLASS-FINALIZED-P"
                "FINALIZE-INHERITANCE")
  #+:sbcl
  (:import-from "SB-MOP"
                "CLASS-FINALIZED-P"
                "FINALIZE-INHERITANCE")
  (:export
   "CLASS-ALL-SUPERCLASSES"
   "CLASS-FINALIZED-P"
   "CLASS-SLOT-LIST"
   "ENSURE-CLASS"
   "FINALIZE-INHERITANCE"
   "FIND-DIRECT-SUPERCLASSES"))

(defpackage "LISA.BELIEF"
  (:use "COMMON-LISP")
  (:nicknames "BELIEF")
  (:export
   "ADJUST-BELIEF"
   "ADJUST-BELIEF*"
   "BELIEF->ENGLISH"
   "BELIEF->JSON"
   "BELIEF->NUMBER"
   "BELIEF-FACTOR"
   "BELIEF-SYSTEM"
   "BELIEF-SYSTEM-NAME"
   "*BELIEF-SYSTEM*"
   "*CF-SYSTEM*"
   "*DS-SYSTEM*"
   "CERTAINTY-FACTOR-SYSTEM"
   "COMBINE-BELIEFS"
   "CONJOIN-BELIEFS"
   "DEFAULT-BELIEF"
   "DEMPSTER-SHAFER-SYSTEM"
   "DS-BELIEF"
   "DS-BELIEF-BEL"
   "DS-BELIEF-P"
   "DS-BELIEF-PL"
   "DS-COMBINE"
   "DS-IGNORANCE"
   "DS-MIDPOINT"
   "FALSE-P"
   ;; --- shared frame of discernment (src/belief-systems/frame/) ---
   "*CANDIDATES-SYSTEM*"
   "CANDIDATES-SYSTEM"
   "MAKE-DS-BELIEF"
   "NORMALIZE-BELIEF"
   "TRUE-P"
   "UKNOWN-P"
   "USE-SYSTEM"
   "VALID-BELIEF-P"
   "WEAKEN-BELIEF"))

(defpackage "LISA.CANDIDATES"
  (:use "COMMON-LISP")
  (:nicknames "CANDIDATES")
  (:documentation
   "Dempster-Shafer over an OPEN frame of discernment. An answer is the SET of
    hypotheses some evidence narrows a question to; answers combine by intersection,
    and exclusion falls out rather than being authored. The frame is never enumerated
    -- Theta is symbolic -- so a knowledge base scales without a declaration to keep
    in step with it.")
  (:export
   "+UNIVERSE+"
   "CANONICAL"
   "UNIVERSE-P"
   "SET-INTERSECT"
   "SET-CONTAINS-P"
   "SET-SUBSET-P"
   "SET-SIZE"
   "SET-NAME"
   "ANSWER"
   "COMBINE-TWO"
   "VACUOUS"
   "CONFLICT-OF"
   "*NORMALIZATION*"
   "NORMALIZE"
   "COMBINE-ANSWERS"
   "BEL"
   "PL"
   "INTERVAL"
   "BEL-OF-SET"
   "PL-OF-SET"
   "IGNORANCE"
   "HYPOTHESES-NAMED"
   "SET-VALUED"
   "TOTAL-MASS"))

(defpackage "LISA.HEAP"
  (:use "COMMON-LISP")
  (:nicknames "HEAP")
  (:export
   "CREATE-HEAP"
   "HEAP-CLEAR"
   "HEAP-COUNT"
   "HEAP-COLLECT"
   "HEAP-EMPTY-P"
   "HEAP-FIND"
   "HEAP-INSERT"
   "HEAP-PEEK"
   "HEAP-REMOVE"))
   
(defpackage "LISA.UTILS"
  (:use "COMMON-LISP")
  (:nicknames "UTILS")
  (:export
   "COLLECT"
   "COMPOSE"
   "COMPOSE-ALL"
   "COMPOSE-F"
   "FIND-AFTER"
   "FIND-BEFORE"
   "FIND-IF-AFTER"
   "FLATTEN"
   "LSTHASH"
   "MAP-IN"
   "STRING-TOKENS"))
