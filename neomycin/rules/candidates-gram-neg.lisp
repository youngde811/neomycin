;;; -*- Mode: Lisp -*-
;;;
;;; Part of neomycin's canonical rulebase.
;;;
;;; THE GRAM-NEGATIVE HALF as narrows-to rules: the enterobacteriaceae cluster (9),
;;; the gram-negative identities (5), the 8 ruling-out rules that touch them, and the
;;; neutropenia host factor. 23 rules in, 21 out after two merges.
;;;
;;; This is the harder cluster -- deeper chaining and far more cross-disconfirmation
;;; than the gram-positives -- so it is the real test of whether the shape holds.
;;;
;;; Same rules as the gram-positive file: confirming only, visible RHS asserting a
;;; CANDIDATES fact, belief on that fact, no organism-class, no frame.

(in-package :lisa-user)

;;; ==================================================================
;;; 1. What the stain establishes
;;; ==================================================================
;;; The two gram-stain rules were the corpus's broadest ruling-out rules. As
;;; narrows-to rules they are simply what a Gram stain IS: a partition.

(defrule gram-negative-narrows-to-gram-negatives
    (:belief 0.7)
  (organism (id ?o))
  (gram (value neg) (of ?o))
  =>
  (assert (candidates (value '(:e-coli :klebsiella :salmonella :enterobacter
                               :serratia :proteus :pseudomonas :bacteroides))
                      (of ?o))))

(defrule gram-positive-narrows-to-gram-positives
    (:belief 0.7)
  (organism (id ?o))
  (gram (value pos) (of ?o))
  =>
  (assert (candidates (value '(:staphylococcus-aureus :staphylococcus-epidermidis
                               :staphylococcus-saprophyticus
                               :streptococcus-pneumoniae :streptococcus-pyogenes
                               :streptococcus-agalactiae :streptococcus-viridans
                               :enterococcus-faecalis :enterococcus-faecium))
                      (of ?o))))

;;; MERGE 1, and the neatest one in the corpus.
;;; aerobic-gram-neg-rod-suggests-enterobacteriaceae-class (0.8, widened in slice D to
;;; the seven aerobic gram-negative rods) and aerobic-growth-argues-against-anaerobe
;;; (0.8, excluding bacteroides) are THE SAME CLAIM seen from opposite sides: an
;;; aerobic gram-negative rod is one of the seven, which is exactly "not the anaerobe".
;;; Both were already 0.8, so the merge is clean -- and the reified
;;; :enterobacteriaceae class disappears with it.
(defrule aerobic-gram-neg-rod-narrows-to-aerobic-gram-neg-rods
    (:belief 0.8)
  (organism (id ?o))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  =>
  (assert (candidates (value '(:e-coli :klebsiella :salmonella :enterobacter
                               :serratia :proteus :pseudomonas))
                      (of ?o))))

;;; ==================================================================
;;; 2. What the biochemistry establishes
;;; ==================================================================
;;; Every one of these WAS a ruling-out rule. Each now states what its finding
;;; narrows the answer to; the organisms it used to name are excluded by
;;; intersection instead.

;;; WAS lactose-fermenter-argues-against-non-fermenters (excluded salmonella, proteus).
;;; Serratia is a slow/variable lactose reactor and is deliberately kept in.
(defrule lactose-fermenter-narrows-to-fermenters
    (:belief 0.7)
  (organism (id ?o))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (lactose (value fermenter) (of ?o))
  =>
  (assert (candidates (value '(:e-coli :klebsiella :enterobacter :serratia))
                      (of ?o))))

;;; WAS lactose-non-fermenter-argues-against-fermenters. Serratia kept in for the same
;;; reason -- the marker is not clean for it.
(defrule lactose-non-fermenter-narrows-to-non-fermenters
    (:belief 0.6)
  (organism (id ?o))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (lactose (value non-fermenter) (of ?o))
  =>
  (assert (candidates (value '(:salmonella :proteus :serratia)) (of ?o))))

;;; WAS indole-pos-argues-against-indole-negative-species. Proteus was deliberately
;;; EXCLUDED from that rule's targets because P. mirabilis is indole-negative while
;;; P. vulgaris is indole-positive -- so as a narrows-to claim, proteus stays IN.
;;; The honest scoping survives the rewrite unchanged.
(defrule indole-positive-narrows-to-indole-producers
    (:belief 0.6)
  (organism (id ?o))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (indole (value positive) (of ?o))
  =>
  (assert (candidates (value '(:e-coli :proteus)) (of ?o))))

;;; WAS urease-pos-argues-against-urease-negative-organism (excluded e-coli, salmonella).
(defrule urease-positive-narrows-to-urease-producers
    (:belief 0.7)
  (organism (id ?o))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (urease (value positive) (of ?o))
  =>
  (assert (candidates (value '(:klebsiella :enterobacter :serratia :proteus))
                      (of ?o))))

;;; MERGE 2, and it fixes an audit finding.
;;; enterobacteriaceae-red-pigment-suggests-serratia was 0.75, justified by "many
;;; clinical isolates are non-pigmented" -- which belief-conditional-audit.md 3.1
;;; identified as the WRONG CONDITIONAL: that is P(pigment | serratia), a sensitivity,
;;; and irrelevant once red pigment has actually been observed.
;;; red-pigment-argues-against-non-serratia already used 0.8. Merged at 0.8, which is
;;; also close to the 0.90 the deferred grounding work estimated.
(defrule red-pigment-narrows-to-serratia
    (:belief 0.8)
  (organism (id ?o))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (pigment (value red) (of ?o))
  =>
  (assert (candidates (value '(:serratia)) (of ?o))))

;;; ==================================================================
;;; 3. Discriminating combinations -- narrower claims from more evidence
;;; ==================================================================
;;; These sit UNDER the single-finding rules above as nested sets: lactose+ narrows to
;;; four, and lactose+ with indole+ narrows within that to one. No chaining, no
;;; composition -- just a smaller set from more evidence, which Dempster combines.

;;; The classic IMViC pair. E. coli is the only major Enterobacteriaceae with both
;;; lactose utilization and indole production (K. oxytoca is the near miss).
(defrule lactose-pos-indole-pos-narrows-to-e-coli
    (:belief 0.8)
  (organism (id ?o))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (lactose (value fermenter) (of ?o))
  (indole (value positive) (of ?o))
  =>
  (assert (candidates (value '(:e-coli)) (of ?o))))

;;; Motility separates the motile Enterobacter from the NON-motile Klebsiella. But the
;;; corpus records no motility fact for Klebsiella or Serratia -- slice D flagged this
;;; as a CORPUS GAP -- so the honest set here is Enterobacter AND Serratia, which is
;;; also motile, indole-negative and a variable lactose reactor. Under the old shape
;;; this rule claimed Enterobacter alone; stating the wider set is the shape being
;;; honest about what the corpus can actually distinguish.
(defrule motile-lactose-pos-indole-neg-narrows-to-motile-fermenters
    (:belief 0.6)
  (organism (id ?o))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (lactose (value fermenter) (of ?o))
  (indole (value negative) (of ?o))
  (motility (value motile) (of ?o))
  =>
  (assert (candidates (value '(:enterobacter :serratia)) (of ?o))))

;;; Swarming motility plus strong urease is close to Proteus-specific.
(defrule urease-pos-swarming-narrows-to-proteus
    (:belief 0.8)
  (organism (id ?o))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (urease (value positive) (of ?o))
  (motility (value swarming) (of ?o))
  =>
  (assert (candidates (value '(:proteus)) (of ?o))))

;;; ==================================================================
;;; 4. What the patient and the culture establish
;;; ==================================================================
;;; Context rules narrow to a small set with modest belief. They gate on the bench
;;; findings that would have derived the organism-class, since there is no longer a
;;; class fact to premise on.

(defrule burn-blood-gram-neg-rod-narrows-to-pseudomonas
    (:belief 0.4)
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (culture-site (value blood) (of ?c))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (burn (value serious) (of ?p))
  =>
  (assert (candidates (value '(:pseudomonas)) (of ?o))))

(defrule compromised-gram-neg-rod-narrows-to-pseudomonas
    (:belief 0.6)
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (compromised-host (value t) (of ?p))
  =>
  (assert (candidates (value '(:pseudomonas)) (of ?o))))

(defrule hospital-acquired-aerobic-gram-neg-rod-narrows-to-pseudomonas
    (:belief 0.7)
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (hospital-acquired (value t) (of ?p))
  =>
  (assert (candidates (value '(:pseudomonas)) (of ?o))))

(defrule neutropenia-aerobic-gram-neg-rod-narrows-to-pseudomonas
    (:belief 0.5)
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (neutropenia (value t) (of ?p))
  =>
  (assert (candidates (value '(:pseudomonas)) (of ?o))))

(defrule anaerobic-gram-neg-rod-in-blood-narrows-to-bacteroides
    (:belief 0.9)
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (culture-site (value blood) (of ?c))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value anaerobic) (of ?o))
  =>
  (assert (candidates (value '(:bacteroides)) (of ?o))))

(defrule anaerobic-gram-neg-rod-in-abdomen-narrows-to-bacteroides
    (:belief 0.8)
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value anaerobic) (of ?o))
  (infection-site (value abdominal) (of ?p))
  =>
  (assert (candidates (value '(:bacteroides)) (of ?o))))

;;; The Klebsiella and Salmonella context rules. Each used to premise on the derived
;;; :enterobacteriaceae class; each now gates on the aerobic gram-negative rod finding
;;; that would have derived it.

(defrule hospital-acquired-compromised-aerobic-gram-neg-rod-narrows-to-klebsiella
    (:belief 0.6)
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (hospital-acquired (value t) (of ?p))
  (compromised-host (value t) (of ?p))
  =>
  (assert (candidates (value '(:klebsiella)) (of ?o))))

(defrule compromised-aerobic-gram-neg-rod-narrows-to-klebsiella
    (:belief 0.5)
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (compromised-host (value t) (of ?p))
  =>
  (assert (candidates (value '(:klebsiella)) (of ?o))))

(defrule tropical-travel-aerobic-gram-neg-rod-narrows-to-salmonella
    (:belief 0.65)
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (recent-travel (value tropical) (of ?p))
  =>
  (assert (candidates (value '(:salmonella)) (of ?o))))

(defrule blood-low-wbc-aerobic-gram-neg-rod-narrows-to-salmonella
    (:belief 0.55)
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (culture-site (value blood) (of ?c))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (white-blood-count (value low) (of ?p))
  =>
  (assert (candidates (value '(:salmonella)) (of ?o))))