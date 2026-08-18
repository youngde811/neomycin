;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: neomycin's own HTTP surface -- /conclusions.
;;
;; It lives here rather than in src/llm/bridge/ for the same reason the therapy
;; endpoint does: reporting a differential over organisms is domain knowledge. The
;; substrate bridge has no business knowing what an organism is, and could not
;; reference this package in any case, since it loads first.
;;
;; Registered by hunchentoot's DEFINE-EASY-HANDLER, so a running acceptor picks it up
;; when this system is loaded.

(in-package :neomycin)

(defun organism-name (x)
  (and x (string-downcase (princ-to-string x))))

(defun answers->json (answers)
  (coerce (mapcar (lambda (a)
                    (let ((h (make-hash-table :test #'equal)))
                      ;; What the rule SAID, before anything was combined: the set its
                      ;; evidence narrowed to, and how strongly.
                      (setf (gethash "narrows_to" h)
                            (coerce (mapcar #'organism-name (car a)) 'vector))
                      (setf (gethash "belief" h) (cdr a))
                      h))
                  answers)
          'vector))

(defun hypotheses->json (organism)
  (coerce (mapcar (lambda (row)
                    (let ((h (make-hash-table :test #'equal)))
                      (setf (gethash "value" h) (organism-name (first row)))
                      (setf (gethash "bel" h) (second row))
                      (setf (gethash "pl" h) (third row))
                      (setf (gethash "ignorance" h) (- (third row) (second row)))
                      h))
                  (differential organism))
          'vector))

(defun set-valued->json (mass)
  (coerce (mapcar (lambda (e)
                    (let ((h (make-hash-table :test #'equal)))
                      (setf (gethash "members" h)
                            (coerce (mapcar #'organism-name (car e)) 'vector))
                      (setf (gethash "mass" h) (cdr e))
                      h))
                  (candidates:set-valued mass))
          'vector))

(defun differential->json (organism)
  "The differential for ORGANISM.

   Reports what a per-organism list cannot: the ANSWERS the rules actually gave, the
   set-valued belief that names no member, the conflict, and the residual ignorance --
   which is also the plausibility of any organism the corpus does not model."
  (let ((ht (make-hash-table :test #'equal)))
    (multiple-value-bind (mass conflict answers) (consensus organism)
      (setf (gethash "organism" ht) (organism-name organism))
      ;; K, read BEFORE normalization: both normalizations resolve it away, so it
      ;; cannot be recovered from the result. High K means the rules that fired
      ;; DISAGREE and the figures should be treated as unstable.
      (setf (gethash "conflict" ht) conflict)
      (setf (gethash "ignorance" ht) (candidates:ignorance mass))
      (setf (gethash "answers" ht) (answers->json answers))
      (setf (gethash "hypotheses" ht) (hypotheses->json organism))
      (setf (gethash "set_valued" ht) (set-valued->json mass)))
    ht))

(defun conclusions-payload ()
  (let ((result (make-hash-table :test #'equal))
        (organisms (organisms-with-answers)))
    ;; One differential per organism -- a polymicrobial culture is modelled as several
    ;; organisms, and each is a separate question.
    (setf (gethash "organisms" result)
          (coerce (mapcar #'differential->json organisms) 'vector))
    (setf (gethash "belief_system" result)
          (belief:belief-system-name belief:*belief-system*))
    ;; A flat leading-calls list, for clients that want only the differential's head.
    (setf (gethash "conclusions" result)
          (coerce (sort (loop for organism in organisms
                              append (loop for row in (differential organism)
                                           when (plusp (second row))
                                             collect (let ((h (make-hash-table :test #'equal)))
                                                       (setf (gethash "value" h)
                                                             (organism-name (first row)))
                                                       (setf (gethash "belief" h) (second row))
                                                       h)))
                        #'> :key (lambda (h) (gethash "belief" h)))
                  'vector))
    result))

(hunchentoot:define-easy-handler (conclusions-handler :uri "/conclusions"
                                                      :default-request-type :get) ()
  (handler-case (lisa-bridge:json-response (conclusions-payload))
    (error (e)
      (lisa-bridge:error-response
       (format nil "Failed to retrieve conclusions: ~A" e) :status 500))))
