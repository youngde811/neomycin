;; This file is part of neomycin, a research reconstruction of MYCIN/EMYCIN.
;; MIT License. Copyright (c) 2000 David Young.

;; Description: docs/Neomycin.md -- THE PAPER -- against the compiled image.
;;
;; The project has guarded its documents in the order it discovered they drift.
;; prompt-tests.lisp guards the two the MODEL reads. claude-md-tests.lisp guards the
;; one every DEVELOPER reads. Nothing guarded the one every OUTSIDER reads: the paper
;; README.md hands a first-time reader as "a detailed look at Neomycin".
;;
;; It was audited on 2026-09-03, three weeks after it was written, and had already
;; accumulated six stale claims:
;;
;;   * `K = 0.557' and `margin = 0.740' presented as "a burn-ICU case elsewhere in
;;     this project". They are a CONSTRUCTED pair of masses. system-prompt.md carries
;;     the identical figures with an explicit warning -- "not consultations ... do not
;;     attach a clinical scenario to them" -- because the prompt made this exact
;;     mistake first and was corrected at v0.15. The real burn-ICU case (culture-1b)
;;     runs K = 0.207, margin 0.036: low conflict, nothing settled, the opposite
;;     reading. The paper reproduced the error the corpus had already fixed once.
;;   * A convergent gram-positive case quoted at `bel 0.963' over "three answers".
;;     Measured: FOUR nested answers and `bel 0.850'. The accompanying claim -- that
;;     it lands "higher than any single rule's own weight" -- was not merely wrong but
;;     impossible: nested consonant answers settle AT the sharpest rule's weight.
;;   * A /why walkthrough describing three admitting answers and a {pseudomonas}
;;     answer that excluded Klebsiella. Both context rules have been GRADED since
;;     v0.13; the engine's own narrative says "Every answer admits klebsiella".
;;   * "44 medical rules", against 46 in the same document twice.
;;   * Two therapy objectives, against the three the solver has had since v0.17.
;;   * 1589 assertions across 197 tests.
;;
;; Every one was a number or a name recalled from memory rather than read off the
;; engine -- the failure mode docs/release-check-design.md §3 names, one layer out.
;;
;; So this file recomputes them. Where the paper quotes a figure, the guard drives the
;; engine and asserts the paper still states what came back; where it quotes a name,
;; the guard resolves it. It cannot check that a sentence is TRUE -- the same bargain
;; claude-md-tests.lisp strikes -- but the paper's numbers can no longer be wrong
;; quietly.

(in-package "LISA-USER")

;;; ------------------------------------------------------------------
;;; The two scenarios the paper describes and drivers.lisp does not.
;;;
;;; Both are worked in docs/clinician-scenarios.md (Scenario 9's contradictory
;;; biochemistry, and the agreeing variation on Scenario 12), but neither is a named
;;; driver. They live here rather than in drivers.lisp because they exist to pin a
;;; document, not to demonstrate the corpus -- and a fixture that only the paper's
;;; guard uses belongs beside the guard.
;;; ------------------------------------------------------------------

(defun paper-contradiction-case (&key (runp t))
  "Lactose+, indole+ AND a red pigment: two bench answers that cannot both hold.
   {e-coli} at 0.80 against {serratia} at 0.80, K = 0.7360, margin 0.4273."
  (reset)
  (assert (patient (id p1)))
  (assert (culture (id c1) (patient p1)))
  (assert (organism (id o1) (culture c1)))
  (assert (culture-site (value blood) (of c1)))
  (assert (gram (value neg) (of o1)))
  (assert (morphology (value rod) (of o1)))
  (assert (aerobicity (value aerobic) (of o1)))
  (assert (lactose (value fermenter) (of o1)))
  (assert (indole (value positive) (of o1)))
  (assert (pigment (value red) (of o1)))
  (when runp (run)))

(defun paper-agreement-case (&key (runp t))
  "The same case WITHOUT the pigment: four overlapping answers that agree, so
   e-coli reaches 0.8840 -- above the sharpest rule's own 0.80 -- at K = 0."
  (reset)
  (assert (patient (id p1)))
  (assert (culture (id c1) (patient p1)))
  (assert (organism (id o1) (culture c1)))
  (assert (culture-site (value blood) (of c1)))
  (assert (gram (value neg) (of o1)))
  (assert (morphology (value rod) (of o1)))
  (assert (aerobicity (value aerobic) (of o1)))
  (assert (lactose (value fermenter) (of o1)))
  (assert (indole (value positive) (of o1)))
  (when runp (run)))

(defun paper-convergent-case (&key (runp t))
  "Chain-forming gram-positive coccus, alpha-hemolytic, optochin-sensitive: four
   answers, each NESTED inside the last. Belief settles at the sharpest rule's own
   weight (0.85) rather than climbing past it, which is what distinguishes nested
   evidence from the merely overlapping evidence of PAPER-AGREEMENT-CASE."
  (reset)
  (assert (patient (id p1)))
  (assert (culture (id c1) (patient p1)))
  (assert (organism (id o1) (culture c1)))
  (assert (culture-site (value blood) (of c1)))
  (assert (gram (value pos) (of o1)))
  (assert (morphology (value coccus) (of o1)))
  (assert (growth-conformation (value chains) (of o1)))
  (assert (hemolysis (value alpha) (of o1)))
  (assert (optochin (value sensitive) (of o1)))
  (when runp (run)))

(in-package "LISA-TEST")

;;; ------------------------------------------------------------------
;;; Reading the paper
;;; ------------------------------------------------------------------

(defun paper-text ()
  "docs/Neomycin.md, as text."
  (with-open-file (in (asdf:system-relative-pathname "neomycin" "docs/Neomycin.md")
                      :external-format :utf-8)
    (let ((text (make-string (file-length in))))
      (subseq text 0 (read-sequence text in)))))

(defun paper-says-p (needle)
  "True when the paper contains NEEDLE, insensitive to hard wrapping. The paper is
   wrapped at 90 columns and a quoted phrase routinely straddles a newline, so a
   literal SEARCH would fail silently -- a guard that matches nothing passes."
  (search (collapse-whitespace needle)
          (collapse-whitespace (paper-text))
          :test #'char-equal))

(defun check-figure (label value &optional (places 3))
  "Assert the paper still quotes VALUE, rounded to PLACES, for LABEL.

   Deliberately a search for the FIGURE rather than for the sentence around it. A
   guard tied to phrasing breaks on every edit and gets deleted; a guard tied to the
   number survives rewriting and fails exactly when the engine moves underneath it."
  (if (paper-says-p (format nil "~,vF" places value))
      (record-pass)
      (record-fail "docs/Neomycin.md no longer quotes ~A as ~,vF -- the engine ~
                    moved and the paper did not"
                   label places value)))

(defun check-phrase (needle what)
  (if (paper-says-p needle)
      (record-pass)
      (record-fail "docs/Neomycin.md no longer states ~A (expected ~S)" what needle)))

;;; ------------------------------------------------------------------
;;; Guard 1 -- every rule the paper names still exists.
;;;
;;; The paper quotes one rule in full, inside a fenced block rather than in
;;; backticks, so this scans the whole text for name-shaped tokens instead of
;;; reusing BACKTICKED-TOKENS. RULE-REFERENCE-P is the same predicate prompt-tests
;;; uses, and RULE-NAMING-CONVENTION-STILL-HOLDS keeps it from going blind.
;;; ------------------------------------------------------------------

(defun name-shaped-tokens (text)
  "Every maximal run of [a-z0-9-] in TEXT. Coarser than BACKTICKED-TOKENS on
   purpose: the paper's rule reference is source code, not prose markup."
  (let ((acc '()) (start nil))
    (flet ((emit (end)
             (when (and start (> (- end start) 1))
               (push (subseq text start end) acc))
             (setf start nil)))
      (dotimes (i (length text))
        (let ((ch (char text i)))
          (if (or (char<= #\a ch #\z) (digit-char-p ch) (char= ch #\-))
              (unless start (setf start i))
              (emit i))))
      (emit (length text)))
    (nreverse acc)))

(deftest paper-names-only-real-rules ()
  (let ((rules (mapcar (lambda (r) (string-downcase (symbol-name (lisa:rule-short-name r))))
                       (domain-rules)))
        (quoted (remove-duplicates
                 (remove-if-not #'rule-reference-p (name-shaped-tokens (paper-text)))
                 :test #'string=)))
    (is (plusp (length quoted))
        "docs/Neomycin.md no longer quotes any rule by name -- the paper's worked ~
         example was the reason this guard exists")
    (dolist (token quoted)
      (is (member token rules :test #'string=)
          (format nil "docs/Neomycin.md quotes rule `~A`, which is not in the ~
                       compiled rulebase (renamed, retired, or a typo)" token)))))

;;; ------------------------------------------------------------------
;;; Guard 2 -- the rule the paper prints is the rule that compiled.
;;;
;;; The worked example is a verbatim listing, which is the most quotable thing in the
;;; document and the easiest to leave behind: the corpus WIDENED this rule once
;;; already, from a {pseudomonas} singleton to a graded answer, and a stale listing
;;; would still have looked like Lisp.
;;; ------------------------------------------------------------------

(defparameter +paper-worked-rule+
  "burn-blood-aerobic-gram-neg-rod-narrows-to-opportunist-rods"
  "The rule docs/Neomycin.md prints in full.")

(defun rule-named (name)
  (find name (domain-rules)
        :key (lambda (r) (string-downcase (symbol-name (lisa:rule-short-name r))))
        :test #'string=))

(defun paper-listing-containing (marker)
  "The fenced code block containing MARKER, or NIL.

   Scoped deliberately. Searching the whole document for a mass would let the LISTING
   go stale while the prose that reads it back stayed right -- and every figure in the
   listing is also written out in the paragraph below it, so a whole-document search
   is satisfied by the prose alone and never looks at the code."
  (let* ((text (paper-text))
         (at (search marker text)))
    (when at
      (let ((open (search "```" text :from-end t :end2 at))
            (close (search "```" text :start2 at)))
        (when (and open close) (subseq text open close))))))

(deftest paper-prints-the-compiled-worked-rule ()
  (let ((rule (rule-named +paper-worked-rule+))
        (listing (paper-listing-containing +paper-worked-rule+)))
    (is rule (format nil "docs/Neomycin.md prints `~A`, which is not in the corpus"
                     +paper-worked-rule+))
    (is listing "docs/Neomycin.md no longer prints the worked rule as a fenced listing")
    (when (and rule listing)
      (let ((grading (neomycin:rule-grading rule))
            (belief (abs (lisa:rule-belief rule))))
        (is grading (format nil "`~A` no longer asserts a GRADED answer -- the paper ~
                                 prints it as the example of one" +paper-worked-rule+))
        ;; The declared belief, as the listing shows it.
        (is (search (format nil "(:belief ~,1F" belief) listing)
            (format nil "the listing in docs/Neomycin.md no longer shows `~A' declaring ~
                         :belief ~,1F" +paper-worked-rule+ belief))
        ;; Every focal mass, IN THE LISTING -- as the source it is quoting writes it.
        (dolist (pair grading)
          (let ((written (format nil "(~,2F ~{:~(~A~)~^ ~})" (car pair) (cdr pair))))
            (is (search written listing)
                (format nil "the listing in docs/Neomycin.md no longer shows the focal ~
                             mass ~A -- the compiled rule has widened, narrowed or been ~
                             recalibrated underneath it" written))))
        ;; And the arithmetic the prose draws from them (invariant 14, restated for
        ;; a reader who will not run the suite).
        (check-phrase (format nil "~R masses total ~,2F" (length grading) belief)
                      "the worked rule's masses totalling its declared belief")))))

;;; ------------------------------------------------------------------
;;; Guard 3 -- the corpus counts the paper states are the real ones.
;;;
;;; EVERY occurrence, not merely one. The paper stated its rule count three times and
;;; got it right twice; a guard that stops at the first match would have passed that
;;; document, because "46 rules" was there to be found while "44 medical rules" sat
;;; two hundred lines away. So each count is checked in both directions: the right
;;; figure must appear, and no wrong figure may -- with the exemptions named.
;;; ------------------------------------------------------------------

(defun count-stated-before (text at)
  "The integer written immediately before position AT, ignoring emphasis markup.
   NIL when what precedes is not a number -- \"one of these six organisms\" spells
   its count as a word and is not a claim this guard can check."
  (let ((i at))
    (loop while (and (plusp i) (member (char text (1- i)) '(#\Space #\*))) do (decf i))
    (let ((end i))
      (loop while (and (plusp i) (digit-char-p (char text (1- i)))) do (decf i))
      (when (< i end) (parse-integer text :start i :end end)))))

(defun check-every-count (noun actual what &optional allowed)
  "Assert every integer the paper writes before NOUN is ACTUAL, or is in ALLOWED."
  (let ((text (collapse-whitespace (paper-text)))
        (found nil))
    (loop with start = 0
          for at = (search noun text :start2 start)
          while at
          do (let ((stated (count-stated-before text at)))
               (when stated
                 (if (or (= stated actual) (member stated allowed))
                     (progn (when (= stated actual) (setf found t)) (record-pass))
                     (record-fail "docs/Neomycin.md says \"~D~A\" -- ~A is ~D"
                                  stated noun what actual))))
             (setf start (1+ at)))
    (is found (format nil "docs/Neomycin.md no longer states ~A as ~D" what actual))))

(defun check-spelled-count (noun actual what)
  "The same, for a count the paper spells out. Written numbers have no digits to
   scan back to, so this asserts the right word and denies every other."
  (check-phrase (format nil "~R ~A" actual noun) what)
  (loop for n from 1 to 20
        unless (= n actual)
          do (is (not (paper-says-p (format nil "~R ~A" n noun)))
                 (format nil "docs/Neomycin.md says \"~R ~A\" -- ~A is ~R"
                         n noun what actual))))

(deftest paper-states-the-real-corpus-counts ()
  (let* ((rules (length (domain-rules)))
         (organisms (let ((acc '()))
                      (dolist (r (neomycin:catalogue-rules) (length acc))
                        (dolist (o (neomycin:rule-answer r))
                          (pushnew o acc :test #'eq)))))
         (drugs (length (therapy::kb-drug-ids therapy:*therapy-kb*))))
    ;; 450 is MYCIN's corpus, which the paper contrasts against twice and which is
    ;; not a claim about this one.
    (check-every-count " rules" rules "the corpus size" '(450))
    (check-every-count " medical rules" rules "the corpus size" '())
    (check-every-count " organisms" organisms "how many organisms the corpus can name" '())
    (check-spelled-count "drugs" drugs "how many drugs the therapy KB holds")))

;;; ------------------------------------------------------------------
;;; Guard 4 -- the identification figures, recomputed.
;;;
;;; culture-1 is the case the paper narrates end to end, and every figure in that
;;; narration is quoted to three places.
;;; ------------------------------------------------------------------

(deftest paper-quotes-the-real-identification-figures ()
  (let ((mass (candidates-run 'lisa-user::culture-1)))
    (dolist (organism '(:e-coli :pseudomonas :klebsiella))
      (check-figure (format nil "culture-1 ~A bel" organism) (candidates:bel mass organism))
      (check-figure (format nil "culture-1 ~A pl" organism) (candidates:pl mass organism)))
    ;; The set-valued headline: 0.234 on the seven aerobic gram-negative rods, which
    ;; the paper calls "often the right headline" and is the largest single figure.
    (check-figure "culture-1's mass on the seven aerobic gram-negative rods"
                  (candidates:margin mass))
    (check-figure "culture-1 conflict"
                  (candidates-conflict 'lisa-user::culture-1))))

;;; ------------------------------------------------------------------
;;; Guard 5 -- the contradiction case, recomputed.
;;;
;;; The paper's central worked example, and the one carrying its argument that a
;;; system reporting its own inputs disagree beats one that averages them away.
;;; ------------------------------------------------------------------

(deftest paper-quotes-the-real-contradiction-figures ()
  (let ((mass (candidates-run 'lisa-user::paper-contradiction-case)))
    (check-figure "the contradiction case's e-coli bel" (candidates:bel mass :e-coli))
    (check-figure "the contradiction case's e-coli pl" (candidates:pl mass :e-coli))
    (check-figure "the contradiction case's serratia bel" (candidates:bel mass :serratia))
    (check-figure "the contradiction case's serratia pl" (candidates:pl mass :serratia))
    (check-figure "the contradiction case's margin" (candidates:margin mass))
    (check-figure "the contradiction case's conflict"
                  (candidates-conflict 'lisa-user::paper-contradiction-case))
    ;; Both ceilings must still be BELOW 1.0 -- the paper tells the reader to read
    ;; the ceilings first, and that instruction is only sound while they have fallen.
    (is (< (candidates:pl mass :e-coli) 1.0)
        "the contradiction case no longer bounds e-coli's plausibility below 1.0, ~
         which is the signature docs/Neomycin.md tells the reader to look for")))

;;; ------------------------------------------------------------------
;;; Guard 6 -- and the two agreeing cases it contrasts against.
;;;
;;; These are a PAIR, and the paper's claim is about the difference between them:
;;; overlapping evidence climbs past the sharpest rule's weight, nested evidence
;;; settles at it. Pinning only the numbers would let that distinction rot, so the
;;; relation is asserted too.
;;; ------------------------------------------------------------------

(deftest paper-quotes-the-real-agreement-figures ()
  (let ((overlapping (candidates-run 'lisa-user::paper-agreement-case))
        (nested (candidates-run 'lisa-user::paper-convergent-case)))
    (check-figure "the agreeing case's e-coli bel" (candidates:bel overlapping :e-coli))
    (check-figure "the convergent case's pneumoniae bel"
                  (candidates:bel nested :streptococcus-pneumoniae))
    (check-phrase (format nil "pl ~,3F" (candidates:pl nested :streptococcus-pneumoniae))
                  "the convergent case's unbounded plausibility")
    ;; Both are quoted as conflict-free; if either stops being so, the sentence
    ;; "same machinery, opposite reading" stops being about conflict at all.
    (is (approx= (candidates-conflict 'lisa-user::paper-agreement-case) 0.0)
        "the agreeing case is no longer conflict-free")
    (is (approx= (candidates-conflict 'lisa-user::paper-convergent-case) 0.0)
        "the convergent case is no longer conflict-free")
    ;; THE RELATION, which is what the paragraph actually claims. RULES-BEHIND hands
    ;; back short NAMES -- it feeds /why, which quotes rules rather than reading their
    ;; beliefs -- so each is resolved to the compiled rule to read its declared weight.
    (let ((sharpest (reduce #'max
                            (mapcar (lambda (name)
                                      (abs (lisa:rule-belief
                                            (rule-named (string-downcase (symbol-name name))))))
                                    (neomycin:rules-behind 'lisa-user::o1
                                                           :streptococcus-pneumoniae)))))
      (is (approx= (candidates:bel nested :streptococcus-pneumoniae) sharpest)
          (format nil "docs/Neomycin.md says NESTED answers settle at the sharpest ~
                       rule's own weight; the convergent case gives ~,4F against a ~
                       sharpest rule of ~,4F"
                  (candidates:bel nested :streptococcus-pneumoniae) sharpest)))
    (is (> (candidates:bel overlapping :e-coli) 0.80)
        "docs/Neomycin.md says OVERLAPPING answers climb past any single rule's ~
         weight; the agreeing case no longer exceeds its sharpest rule's 0.80")))

;;; ------------------------------------------------------------------
;;; Guard 7 -- the explanation figures.
;;;
;;; The /why walkthrough is the section that drifted worst, because it narrates a
;;; payload in prose and prose does not fail to compile. Both organisms are pinned:
;;; the one every answer admits, and the one no answer mentions.
;;; ------------------------------------------------------------------

(deftest paper-quotes-the-real-explanation-figures ()
  (let ((mass (candidates-run 'lisa-user::culture-1)))
    (dolist (organism '(:klebsiella :salmonella))
      ;; Quoted as an adjacent pair in the paper, so pin them as a pair: a bel and a
      ;; pl that are each real but belong to different organisms is exactly the
      ;; misreading release-check.py check 5 exists to catch.
      (check-phrase (format nil "bel ~,3F, pl ~,3F"
                            (candidates:bel mass organism) (candidates:pl mass organism))
                    (format nil "the ~A interval it narrates" organism)))
    ;; The structural claim underneath the walkthrough, which no figure would catch:
    ;; every answer in culture-1 admits klebsiella, and none admits salmonella.
    (let ((answers (neomycin:answer-details 'lisa-user::o1)))
      ;; ANSWER-DETAILS gives (SET BELIEF RULES GRADING); SET is what an answer admits.
      (is (every (lambda (d) (member :klebsiella (first d))) answers)
          "docs/Neomycin.md says every answer in this case admits Klebsiella")
      (is (notevery (lambda (d) (member :salmonella (first d))) answers)
          "docs/Neomycin.md uses Salmonella as its example of an organism some ~
           answers do NOT admit; every answer now admits it"))))

;;; ------------------------------------------------------------------
;;; Guard 8 -- the constructed pair, recomputed, and NOT sold as a consultation.
;;;
;;; Two directions, because the figures and the label failed independently: the
;;; numbers were right and the sentence around them was a claim about a clinical case
;;; that has not produced them since v0.13. This is the paper's copy of
;;; PROMPT-DOES-NOT-SELL-CONSTRUCTED-MASSES-AS-CONSULTATIONS.
;;; ------------------------------------------------------------------

(deftest paper-quotes-the-real-constructed-pair ()
  (destructuring-bind (mass k)
      (combined (cons '(:pseudomonas) 0.928d0) (cons '(:klebsiella) 0.60d0))
    (check-phrase (format nil "K = ~,3F" k) "the constructed pair's conflict")
    (check-figure "the constructed pair's margin" (candidates:margin mass))))

(deftest paper-does-not-sell-constructed-masses-as-consultations ()
  (dolist (label '("burn-ICU case" "burn ICU case" "case elsewhere in this project runs"))
    (is (not (paper-says-p label))
        (format nil "docs/Neomycin.md has reattached the clinical label ~S to a ~
                     constructed mass pair -- see culture-1b, which runs K = 0.207" label)))
  (check-phrase "not a consultation" "that the constructed pair is not a consultation"))

;;; ------------------------------------------------------------------
;;; Guard 9 -- the therapy dial has as many settings as the paper says.
;;;
;;; The roster is explicit rather than derived: nothing in the image publishes the
;;; set of legal objectives, and inferring it from *OBJECTIVE*'s docstring would put
;;; a guard's subject inside a comment. So it is a maintained list, checked in both
;;; directions -- every objective here must WORK, and the paper's spelled-out count
;;; must match the length. A fourth objective therefore fails here first.
;;; ------------------------------------------------------------------

(defparameter +therapy-objectives+ '(:lexicographic :spectrum-sparing :stewardship)
  "Every objective the exact solver accepts. Adding one means adding it here, and
   updating the count docs/Neomycin.md states.")

(deftest paper-describes-every-objective-the-solver-has ()
  (check-spelled-count "settings" (length +therapy-objectives+)
                       "how many settings the objective dial has")
  ;; Each one must still produce a regimen -- an objective the solver has stopped
  ;; accepting would leave the paper describing a dial that does not turn.
  (dolist (objective +therapy-objectives+)
    (let ((therapy:*objective* objective))
      (let ((rec (solve-with :exact '((:streptococcus-pyogenes . 0.85d0))
                             therapy:*therapy-kb*)))
        (is (regimen-drugs rec)
            (format nil "the ~A objective no longer returns a regimen" objective))))))

(deftest paper-quotes-the-real-objective-divergence ()
  ;; The paper's one concrete claim about the dials: on a group A strep, breadth and
  ;; stewardship disagree, and neither answer is the other's. It is the whole argument
  ;; for there being three settings rather than two, and it rests on authored tiers
  ;; that a KB edit could silently reconcile.
  (flet ((regimen-for (objective)
           (let ((therapy:*objective* objective))
             (regimen-drugs (solve-with :exact '((:streptococcus-pyogenes . 0.85d0))
                                        therapy:*therapy-kb*)))))
    (let ((narrow (regimen-for :spectrum-sparing))
          (cheap (regimen-for :stewardship)))
      (is (not (equal narrow cheap))
          (format nil "docs/Neomycin.md says the narrow-spectrum and stewardship ~
                       dials disagree on a group A strep; both now return ~S" narrow))
      ;; Both drugs are named in ONE sentence, so pin the sentence rather than the two
      ;; names. Either name alone appears elsewhere in the section -- vancomycin twice
      ;; over -- and a guard satisfied by the other mention would not notice the claim
      ;; itself going false.
      (when (and (= 1 (length narrow)) (= 1 (length cheap)))
        (check-phrase (format nil "setting returns ~(~A~) where the stewardship ~
                                   setting returns ~(~A~)"
                              (first narrow) (first cheap))
                      "which agent each dial returns for a group A strep")))))

;;; ------------------------------------------------------------------
;;; Guard 10 -- the paper's links go somewhere.
;;;
;;; "What to Read Next" is nine relative links, and a renamed document breaks them
;;; silently. The docs/attic boundary (docs/attic/README.md) makes this live: a file
;;; moved to the attic keeps its name and stops being authority for anything.
;;; ------------------------------------------------------------------

(defun paper-relative-links (text)
  "Every ](PATH) whose PATH is a relative file reference, deduplicated."
  (let ((acc '()) (start 0))
    (loop
      (let ((open (search "](" text :start2 start)))
        (unless open (return (remove-duplicates (nreverse acc) :test #'string=)))
        (let ((close (position #\) text :start (+ open 2))))
          (unless close (return (remove-duplicates (nreverse acc) :test #'string=)))
          (let ((path (subseq text (+ open 2) close)))
            (when (and (plusp (length path))
                       (char= (char path 0) #\.))
              (push path acc)))
          (setf start (1+ close)))))))

(deftest paper-links-resolve ()
  (let ((links (paper-relative-links (paper-text))))
    (is (plusp (length links)) "docs/Neomycin.md still carries relative links")
    (dolist (path links)
      (let ((full (merge-pathnames path (asdf:system-relative-pathname "neomycin" "docs/"))))
        (is (probe-file full)
            (format nil "docs/Neomycin.md links to ~S, which does not exist" path))))))

;;; ------------------------------------------------------------------
;;; Guard 11 -- and its table of contents goes somewhere too.
;;;
;;; GitHub slugs a heading by lowercasing it and dropping punctuation, so an anchor
;;; can be perfectly well-formed and still land nowhere -- and a dead in-page link is
;;; invisible to every other check here.
;;; ------------------------------------------------------------------

(defun github-slug (heading)
  "HEADING as GitHub would slug it: lowercased, punctuation dropped, spaces hyphenated."
  (let ((out (make-string-output-stream)))
    (loop for ch across (string-downcase (string-trim " " heading))
          do (cond ((or (alphanumericp ch) (char= ch #\-)) (write-char ch out))
                   ((char= ch #\Space) (write-char #\- out))))
    (get-output-stream-string out)))

(defun paper-headings (text)
  "The slug of every `## ' heading in TEXT."
  (let ((acc '()) (start 0))
    (loop
      (let ((line-end (or (position #\Newline text :start start) (length text))))
        (let ((line (subseq text start line-end)))
          (when (and (> (length line) 3) (string= "## " (subseq line 0 3)))
            (push (github-slug (subseq line 3)) acc)))
        (when (>= line-end (length text)) (return (nreverse acc)))
        (setf start (1+ line-end))))))

(defun paper-anchors (text)
  "Every ](#anchor) in TEXT."
  (let ((acc '()) (start 0))
    (loop
      (let ((open (search "](#" text :start2 start)))
        (unless open (return (nreverse acc)))
        (let ((close (position #\) text :start (+ open 3))))
          (unless close (return (nreverse acc)))
          (push (subseq text (+ open 3) close) acc)
          (setf start (1+ close)))))))

(deftest paper-table-of-contents-resolves ()
  (let* ((text (paper-text))
         (headings (paper-headings text))
         (anchors (paper-anchors text)))
    (is (plusp (length anchors)) "docs/Neomycin.md still has a table of contents")
    (dolist (anchor anchors)
      (is (member anchor headings :test #'string=)
          (format nil "docs/Neomycin.md's table of contents links to #~A, which ~
                       matches no heading. GitHub slugs headings lowercase." anchor)))))

;;; ------------------------------------------------------------------
;;; Guard 12 -- the suite size the paper cites.
;;;
;;; The TEST count is checkable and the ASSERTION count is not: every test is
;;; registered before RUN-ALL begins, but the assertion tally is mid-flight while
;;; this runs. claude-md-tests.lisp declines to guard either, and CLAUDE.md hedges
;;; both with a "~" for exactly that reason. The paper does not hedge -- it cites
;;; them as evidence of rigour, in the section headed "Real Versus Schematic" --
;;; so the half that can be pinned is pinned.
;;; ------------------------------------------------------------------

(deftest paper-states-the-real-test-count ()
  (check-phrase (format nil "across ~D tests" (length *tests*))
                "the number of tests in the suite"))
;;; ------------------------------------------------------------------
;;; Guard 13 -- EVERY figure in the paper is one the engine can produce.
;;;
;;; The other figure guards ask "is this number still stated?". This one asks the
;;; question from the other end -- "where did this number come from?" -- and it is
;;; the only one that catches a STALE figure sitting beside a corrected one. That is
;;; not a hypothetical: the paper stated its rule count three times and updated two
;;; of them, and a falsification pass over the guards above found five more places
;;; where changing one occurrence of a figure left another to satisfy the search.
;;;
;;; It is bin/release-check.py's check 3 -- "every number quoted must appear in a
;;; payload received earlier" -- turned on the document instead of the transcript,
;;; and CLAUDE.md calls that the check that matters for the same reason: it catches
;;; recall-from-memory structurally, and nothing else in the stack can.
;;;
;;; The admissible set is everything the engine can hand a reader: every declared
;;; rule belief, every graded focal mass, and every bel / pl / conflict / margin the
;;; four scenarios the paper narrates actually produce. Anything else must be
;;; exempted BY NAME, with a reason, and the exemptions are checked in both
;;; directions like *CLAUDE-MD-NOT-SYMBOLS*.
;;; ------------------------------------------------------------------

(defparameter +paper-not-engine-figures+
  '(("1.0"   . "the unit bound, written as prose -- \"approaches 1.0\", \"below 1.0\" \
-- rather than read off any consultation")
    ;; The certainty-factor worked example, which is arithmetic the paper performs in
    ;; prose to explain a scheme neomycin's corpus no longer uses. Both were admitted
    ;; by ACCIDENT before the precision split -- the contradiction case's e-coli
    ;; plausibility is 0.7576, which rounds to "0.76" at two places.
    ("0.36"  . "the certainty-factor worked example: 0.6 of the 0.6 doubt remaining")
    ("0.76"  . "the certainty-factor worked example's result: 0.4 combined with 0.6")
    ("0.613" . "pseudomonas BEFORE graded answers -- quoted as superseded, and \
recorded as such in docs/clinician-scenarios.md's Scenario 1 note"))
  "Figures docs/Neomycin.md quotes that no engine reading produces, each with why.

   A figure here MUST NOT become producible without someone noticing: if the corpus
   grows a rule that makes 0.613 a live number again, the sentence calling it a
   superseded value has quietly become ambiguous, and that is worth stopping for.")

(defun paper-figures (text)
  "Every decimal figure written in TEXT.

   The integer part must be a single digit, which is what every belief, mass, bel,
   pl, conflict and margin in this document looks like. That constraint is doing
   real work: it steps over `10.1128' in a DOI and `4th ed.' in a citation without
   needing to know what a citation is."
  (let ((acc '()) (i 0) (n (length text)))
    (loop while (< i n)
          do (let ((ch (char text i)))
               (if (and (digit-char-p ch)
                        (or (zerop i)
                            (not (or (alphanumericp (char text (1- i)))
                                     (char= (char text (1- i)) #\.))))
                        (< (1+ i) n) (char= (char text (1+ i)) #\.)
                        (< (+ i 2) n) (digit-char-p (char text (+ i 2))))
                   (let ((k (+ i 2)))
                     (loop while (and (< k n) (digit-char-p (char text k))) do (incf k))
                     ;; A further `.digit' makes this a version string, not a figure.
                     (unless (and (< k n) (char= (char text k) #\.)
                                  (< (1+ k) n) (digit-char-p (char text (1+ k))))
                       (pushnew (subseq text i k) acc :test #'string=))
                     (setf i k))
                   (incf i))))
    (nreverse acc)))

(defun renderings-of (value from to)
  "VALUE as the paper might write it, at FROM to TO decimal places."
  (loop for places from from to to collect (format nil "~,vF" places value)))

(defun engine-figures ()
  "Every figure the compiled corpus and the paper's four scenarios can produce,
   AT THE PRECISION THAT KIND OF FIGURE IS WRITTEN.

   The precision split is doing the work here, and it is not a technicality. A rule's
   declared weight is authored to one or two places and the paper writes it that way
   -- `:belief 0.4', `at 0.70'. A reading is computed and the paper quotes three.
   Pooling them would make \"0.500\" admissible because some rule declares 0.5, and a
   reading that drifted TO 0.500 would then be waved through: measured, on a
   deliberately corrupted copy, before the split was introduced. Two of the paper's
   stale figures had a legitimate twin of the other kind, which is exactly how a
   number survives a partial update."
  (let ((acc (make-hash-table :test #'equal)))
    (flet ((admit (value from to)
             (dolist (s (renderings-of value from to)) (setf (gethash s acc) t))))
      ;; What the rules DECLARE -- authored, and written to one or two places.
      (dolist (rule (domain-rules))
        (let ((belief (lisa:rule-belief rule)))
          (when (realp belief) (admit (abs belief) 1 2)))
        (dolist (pair (neomycin:rule-grading rule)) (admit (car pair) 1 2)))
      ;; What the scenarios the paper narrates RETURN -- computed, and quoted to three.
      (dolist (scenario '(lisa-user::culture-1 lisa-user::paper-contradiction-case
                          lisa-user::paper-agreement-case lisa-user::paper-convergent-case))
        (let ((mass (candidates-run scenario)))
          (admit (candidates:margin mass) 3 4)
          (admit (candidates-conflict scenario) 3 4)
          (dolist (rule (neomycin:catalogue-rules))
            (dolist (organism (neomycin:rule-answer rule))
              (admit (candidates:bel mass organism) 3 4)
              (admit (candidates:pl mass organism) 3 4)))))
      ;; And the constructed pair. Its INPUTS are stated alongside its outputs and are
      ;; masses the paper chose rather than weights any rule declares, so they are
      ;; admitted at the precision they are written.
      (destructuring-bind (mass k)
          (combined (cons '(:pseudomonas) 0.928d0) (cons '(:klebsiella) 0.60d0))
        (admit 0.928d0 2 4) (admit 0.60d0 2 4)
        (admit k 3 4) (admit (candidates:margin mass) 3 4)))
    acc))

(deftest paper-quotes-no-figure-the-engine-cannot-produce ()
  (let ((admissible (engine-figures))
        (quoted (paper-figures (paper-text))))
    (is (> (length quoted) 20)
        (format nil "docs/Neomycin.md quotes only ~D figures -- PAPER-FIGURES has ~
                     probably stopped recognising them, and a guard that checks ~
                     nothing passes" (length quoted)))
    (dolist (figure quoted)
      (is (or (gethash figure admissible)
              (assoc figure +paper-not-engine-figures+ :test #'string=))
          (format nil "docs/Neomycin.md quotes ~A, which no rule declares and no ~
                       scenario in the paper produces. Either it is stale, or it ~
                       belongs in +PAPER-NOT-ENGINE-FIGURES+ with a reason."
                  figure)))))

(deftest paper-figure-exemptions-are-still-needed ()
  ;; Both directions, as claude-md-tests.lisp does for its symbol exemptions: an
  ;; exemption for a figure the engine now produces has become a lie about where the
  ;; number came from, and one for a figure the paper no longer quotes is clutter
  ;; that reads as policy.
  (let ((admissible (engine-figures))
        (quoted (paper-figures (paper-text))))
    (dolist (entry +paper-not-engine-figures+)
      (destructuring-bind (figure . reason) entry
        (is (not (gethash figure admissible))
            (format nil "~A is exempted from the figure guard as ~S, but the engine ~
                         now produces it" figure reason))
        (is (member figure quoted :test #'string=)
            (format nil "~A is exempted from the figure guard, but docs/Neomycin.md ~
                         no longer quotes it" figure))))))
