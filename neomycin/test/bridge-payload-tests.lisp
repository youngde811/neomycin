;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: Tests for the payloads /why, /rules and /conclusions serve -- the
;; whole Lisp path each handler runs, minus HTTP.
;;
;; WHY THIS FILE EXISTS. The v0.11 promotion retired organism-identity, and /why went
;; on looking for it: it returned 404 for every organism in the corpus, and did so
;; through a green 892-assertion suite and a "passing" bin/test-why.sh. Nothing was
;; wrong with either -- the suite tested the engine and never called the handler, and
;; the smoke script piped a 404 body through json.tool and exited 0. The defect was
;; found by a clinician-driver session, which is a slow and expensive way to discover
;; that an endpoint has been dead since the refactor.
;;
;; The lesson is narrow and worth stating: a payload builder is code, and code that no
;; test calls will be broken by the next refactor without anyone hearing about it.
;; These tests call them.

(in-package "LISA-TEST")

;;; ------------------------------------------------------------------
;;; /why
;;; ------------------------------------------------------------------

(defun why-for (organism)
  "The /why payload for ORGANISM, built exactly as the handler builds it."
  (let ((entity (neomycin:entity-naming organism)))
    (and entity (neomycin::why-payload organism entity))))

(deftest why-explains-a-named-organism ()
  ;; The regression itself: every organism the corpus can conclude must be
  ;; explicable. This is the assertion whose absence let /why 404 for two commits.
  (run-scenario 'lisa-user::culture-1 :candidates)
  (dolist (organism '(:pseudomonas :klebsiella))
    (let ((payload (why-for organism)))
      (is (hash-table-p payload)
          (format nil "/why returns a payload for ~(~a~)" organism))
      (is (string= (gethash "organism" payload) (string-downcase (symbol-name organism)))
          "the payload echoes the organism asked about")
      (is (plusp (length (gethash "argument" payload)))
          "the argument is not empty"))))

(deftest why-reports-answers-that-exclude-as-well-as-admit ()
  ;; The load-bearing property. Nothing argues against anything here, so an
  ;; explanation that showed only the admitting answers could never account for why
  ;; a hypothesis is held DOWN -- and a reader would be left to assume some rule
  ;; objected. Both kinds must be present, flagged.
  (run-scenario 'lisa-user::culture-1 :candidates)
  (let* ((payload (why-for :klebsiella))
         (argument (coerce (gethash "argument" payload) 'list))
         (admitting (remove-if-not (lambda (a) (gethash "admits" a)) argument))
         (excluding (remove-if (lambda (a) (gethash "admits" a)) argument)))
    (is (plusp (length admitting)) "some answer admits klebsiella")
    (is (plusp (length excluding))
        "the pseudomonal answers are reported too, flagged admits=false")
    (is (every (lambda (a) (plusp (length (gethash "rules" a)))) argument)
        "every answer names the rules that gave it")))

(deftest why-intersection-is-what-the-admitting-answers-leave ()
  (run-scenario 'lisa-user::culture-1 :candidates)
  (let ((payload (why-for :klebsiella)))
    (is (equalp (gethash "intersection" payload) #("klebsiella"))
        "three answers admit klebsiella and intersect to it alone")))

(deftest why-carries-provenance-for-every-rule-it-cites ()
  ;; The citation path. A rule appearing in an explanation without its provenance
  ;; invites the narrator to supply one from memory, which is the failure mode the
  ;; whole WHY facility exists to prevent.
  (run-scenario 'lisa-user::culture-1 :candidates)
  (let* ((payload (why-for :pseudomonas))
         (rules (loop for answer across (gethash "argument" payload)
                      append (coerce (gethash "rules" answer) 'list))))
    (is (plusp (length rules)) "rules are cited")
    (is (every (lambda (r) (gethash "provenance" r)) rules)
        "every cited rule carries its provenance")
    (is (every (lambda (r) (plusp (length (gethash "evidence" (gethash "provenance" r)))))
               rules)
        "every provenance carries at least one verified citation")))

(deftest why-belief-interval-brackets-correctly ()
  (run-scenario 'lisa-user::culture-1 :candidates)
  (let ((payload (why-for :klebsiella)))
    (is (<= 0.0 (gethash "bel" payload) (gethash "pl" payload) 1.0)
        "0 <= bel <= pl <= 1")))

(deftest why-declines-an-organism-no-rule-named ()
  ;; A 404 here is correct and must stay reachable: the honest answer for an
  ;; unmodelled organism is that nothing has spoken to it, not a fabricated zero.
  (run-scenario 'lisa-user::culture-1 :candidates)
  (is (null (neomycin:entity-naming :nocardia))
      "an organism no rule named resolves to no entity, and /why 404s"))

;;; ------------------------------------------------------------------
;;; /rules
;;; ------------------------------------------------------------------

(deftest rules-summary-describes-the-real-corpus ()
  ;; The other half of the same regression: the summary went on reporting
  ;; organism-class and organism-identity, and every list came back EMPTY while the
  ;; endpoint returned 200. An empty list is not a visible failure, so it needs a
  ;; test that says what non-empty means.
  (let* ((rules (neomycin:catalogue-rules))
         (summary (neomycin::rules-summary rules))
         (organisms (gethash "organisms" summary)))
    (is (= (length rules) (gethash "total" summary)) "total counts the corpus")
    (is (plusp (length organisms)) "the organism list is not empty")
    (is (find "pseudomonas" organisms :test #'string=) "and names real organisms")
    (is (= (length rules)
           (loop for count being the hash-values of (gethash "resolutions" summary)
                 sum count))
        "every rule is counted in exactly one resolution bucket")))

(deftest every-rule-states-an-answer ()
  ;; RULE-ANSWER strips the quote the RHS carries. If that ever stops working the
  ;; catalogue renders Lisp reader syntax at a JSON client -- which it did, as
  ;; "'(staphylococcus-aureus ...)", for as long as nothing checked.
  (dolist (rule (neomycin:catalogue-rules))
    (let ((answer (neomycin:rule-answer rule)))
      (is (and (consp answer) (every #'keywordp answer))
          (format nil "~(~a~) answers with a set of keywords"
                  (lisa:rule-short-name rule))))))

(deftest rules-json-renders-a-usable-entry ()
  (let* ((rule (find-if (lambda (r)
                          (string-equal (symbol-name (lisa:rule-short-name r))
                                        "burn-blood-gram-neg-rod-narrows-to-pseudomonas"))
                        (neomycin:catalogue-rules)))
         (json (and rule (neomycin::rule->json rule))))
    (is (hash-table-p json) "the rule is in the catalogue")
    (is (equalp (gethash "narrows_to" json) #("pseudomonas")) "its answer renders as names")
    (is (= 1 (gethash "resolution" json)) "resolution is the answer's size")
    (is (plusp (length (gethash "premises" json))) "its premises are reported")
    (is (gethash "provenance" json) "its provenance is carried")))

;;; ------------------------------------------------------------------
;;; /conclusions
;;; ------------------------------------------------------------------

(deftest conclusions-payload-is-well-formed ()
  (run-scenario 'lisa-user::culture-1 :candidates)
  (let* ((payload (neomycin:conclusions-payload))
         (organisms (gethash "organisms" payload)))
    (is (plusp (length organisms)) "at least one entity is reported")
    (let ((differential (aref organisms 0)))
      (is (gethash "hypotheses" differential) "the differential names hypotheses")
      (is (numberp (gethash "conflict" differential)) "K is reported")
      (is (numberp (gethash "ignorance" differential)) "residual ignorance is reported"))
    (is (plusp (length (gethash "conclusions" payload)))
        "the flat leading-calls list is populated")))
;;; ------------------------------------------------------------------
;;; /rules ?premises= answers by PARAMETER as well as by value.
;;;
;;; Found by the release-check consultation, not by this suite. The filter compared
;;; values only, so `?premises=urease' returned zero rules -- and the model, having
;;; asked exactly that, told a clinician there was no rule reading a negative urease
;;; and that it could not rule out Proteus. Both false.
;;;
;;; The failure mode is the one this project keeps meeting: a query that returns
;;; NOTHING is indistinguishable from a corpus that CONTAINS nothing.
;;; ------------------------------------------------------------------

(deftest rules-premises-filter-matches-parameter-names ()
  (let ((by-name (neomycin::matching-rules :premises "urease")))
    (is (plusp (length by-name))
        "?premises=urease finds the rules that read urease -- naming the parameter is
         a sensible question and used to return silence")
    ;; Both polarities, which is the point of asking by parameter: a clinician wants
    ;; to know what the TEST is worth, not what one of its readings is worth.
    (dolist (expected '(lisa-user::urease-positive-narrows-to-urease-producers
                        lisa-user::urease-negative-narrows-to-non-proteus-rods))
      (is (find expected by-name :key #'lisa:rule-short-name)
          (format nil "~(~a~) is among them" expected)))))

(deftest rules-premises-filter-still-matches-values ()
  ;; The original behaviour, unchanged: naming a reading narrows to that reading.
  (let ((by-value (neomycin::matching-rules :premises "non-motile")))
    (is (plusp (length by-value)) "?premises=non-motile finds the rule reading it")
    (is (every (lambda (r) (member 'lisa-user::non-motile
                                   (lisa:rule-premise-values r 'lisa-user::motility)))
               by-value)
        "and only rules that actually read that value")))

(deftest rules-premises-filter-is-honestly-empty ()
  ;; An empty result must still be possible, or the filter would be useless. `oxidase'
  ;; is not a parameter this corpus has at all.
  (is (zerop (length (neomycin::matching-rules :premises "oxidase")))
      "a finding the corpus does not model returns nothing"))
