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

(in-package :lisa-bridge)

;;; Context-tree session management (approach A: the bridge auto-manages the
;;; patient -> culture -> organism lineage).
;;;
;;; The rulebase scopes every clinical parameter to a context by ID (see
;;; examples/mycin.lisp). Callers of the bridge should not have to build that
;;; tree by hand: they assert facts by type and value (plus, for organism-level
;;; facts, which organism), and the bridge lazily creates the context facts and
;;; scopes each parameter to the right level. A consultation has one canonical
;;; patient and one canonical culture; organisms are created on demand and all
;;; hang off the canonical culture. IDs are LISA-USER symbols so Rete joins them
;;; by identity, exactly as the hand-written scenarios do.

(defvar *session-lock* (bt:make-lock "lisa-bridge-session")
  "Lock protecting session state.")

(defvar *asserted-contexts* (make-hash-table :test #'equal)
  "Names of context facts (patient/culture/organism) already asserted this
   session, so we assert each lineage node exactly once.")

(defparameter +patient-name+ "patient-1"
  "Canonical id of the single patient in a consultation.")
(defparameter +culture-name+ "culture-1"
  "Canonical id of the single culture in a consultation.")
(defparameter +default-organism-name+ "organism-1"
  "Organism used when an organism-level fact names no entity.")

(defparameter *param-level*
  '(("gram" . :organism) ("morphology" . :organism) ("aerobicity" . :organism)
    ("growth-conformation" . :organism) ("organism-identity" . :organism)
    ("culture-site" . :culture) ("culture-age" . :culture)
    ("burn" . :patient) ("compromised-host" . :patient)
    ("hospital-acquired" . :patient) ("recent-travel" . :patient)
    ("white-blood-count" . :patient) ("infection-site" . :patient))
  "Which context level each parameter fact scopes to.")

(defun param-level (fact-type)
  "Context level (:organism | :culture | :patient) for FACT-TYPE.
   Defaults to :organism (identification facts are organism-level)."
  (or (cdr (assoc (string-downcase (string fact-type)) *param-level* :test #'string=))
      :organism))

(defun lu-sym (name)
  "Intern NAME (a string) as a symbol in LISA-USER, for use as a context id."
  (intern (string-upcase (string name)) :lisa-user))

;;; The functions below are NOT internally locked; callers hold *SESSION-LOCK*.

(defun assert-context (class-name id-name &optional parent-slot parent-name)
  "Assert a context fact of CLASS-NAME with id ID-NAME (and an optional
   PARENT-SLOT -> PARENT-NAME link) exactly once per session."
  (unless (gethash id-name *asserted-contexts*)
    (let* ((class-sym (find-symbol (string-upcase class-name) :lisa-user))
           (initargs (list* :id (lu-sym id-name)
                            (when parent-slot
                              (list parent-slot (lu-sym parent-name))))))
      (lisa:assert-instance (apply #'make-instance class-sym initargs))
      (setf (gethash id-name *asserted-contexts*) t))))

(defun ensure-base-lineage ()
  "Ensure the canonical patient and culture (culture -> patient) exist."
  (assert-context "patient" +patient-name+)
  (assert-context "culture" +culture-name+ :patient +patient-name+))

(defun ensure-organism (name)
  "Ensure organism NAME exists under the canonical culture; return its id symbol."
  (ensure-base-lineage)
  (assert-context "organism" name :culture +culture-name+)
  (lu-sym name))

(defun context-id-for (fact-type entity-name)
  "Return the context id symbol a FACT-TYPE fact scopes to (its OF value),
   creating any missing lineage facts. For organism-level facts ENTITY-NAME
   selects the organism (default organism-1); patient- and culture-level facts
   use the canonical patient/culture regardless of ENTITY-NAME."
  (bt:with-lock-held (*session-lock*)
    (ecase (param-level fact-type)
      (:organism (ensure-organism (or entity-name +default-organism-name+)))
      (:culture  (ensure-base-lineage) (lu-sym +culture-name+))
      (:patient  (ensure-base-lineage) (lu-sym +patient-name+)))))

(defun reset-session ()
  "Clear all session state and reset the Lisa engine."
  (bt:with-lock-held (*session-lock*)
    (clrhash *asserted-contexts*)
    (lisa:reset)))