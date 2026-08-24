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
    (:belief 0.7
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf / StatPearls, Gram Staining, NBK562156"
                             "NCBI Bookshelf / StatPearls, Gram-Positive Bacteria, NBK470553")
                  :belief-basis :illustrative
                  :note "The Gram stain partitions bacteria into two mutually exclusive cell-wall categories. Stated as what a gram-negative result establishes; the gram-positives are excluded by intersection."))
  (organism (id ?o))
  (gram (value neg) (of ?o))
  =>
  (assert (candidates (value '(:e-coli :klebsiella :salmonella :enterobacter
                               :serratia :proteus :pseudomonas :bacteroides))
                      (of ?o))))

(defrule gram-positive-narrows-to-gram-positives
    (:belief 0.7
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf / StatPearls, Gram Staining, NBK562156"
                             "NCBI Bookshelf / StatPearls, Gram-Positive Bacteria, NBK470553")
                  :belief-basis :illustrative
                  :note "The mirror image: a gram-positive stain narrows to the gram-positive organisms the corpus models."))
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
    (:belief 0.8
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Enterobacteriaceae), NBK8035"
                             "NCBI Bookshelf / StatPearls, Enterobacter Infections, NBK559296"
                             "NCBI Bookshelf, Medical Microbiology 4th ed. ch.20 (Anaerobes: General Characteristics), NBK7638"
                             "NCBI Bookshelf, Medical Microbiology 4th ed. ch.20 (Anaerobic Gram-Negative Bacilli, Finegold), NBK8438")
                  :belief-basis :illustrative
                  :note "An aerobic gram-negative rod is one of the seven the corpus models -- the six Enterobacteriaceae and Pseudomonas. Bacteroides is excluded because it is an obligate anaerobe. MERGED from two rules that were THE SAME CLAIM seen from opposite sides, both already 0.8: a class rule naming the family, and a ruling-out rule excluding the anaerobe. The reified :enterobacteriaceae class disappears with the merge, and with it the last belief carried over from a retired rule."))
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
;;;
;;; ------------------------------------------------------------------
;;; AUTHORING POLICY: WHAT TO DO WHEN THE EVIDENCE DOES NOT SETTLE IT
;;; ------------------------------------------------------------------
;;; Absence from an answer IS exclusion. So every organism a rule leaves out is a
;;; positive claim that the finding rules it out, and the burden is asymmetric:
;;;
;;;   EXCLUDING an organism requires evidence. INCLUDING one requires none.
;;;
;;; An author who does not know whether a marker is consistent with an organism has
;;; two conservative moves, and never has to guess:
;;;
;;;   WIDEN THE ANSWER -- keep the organism in. A wider answer is a WEAKER claim, and
;;;   Dempster-Shafer is built to carry exactly that: "one of these, the evidence does
;;;   not say which". This is why Serratia sits in both lactose answers (slow, variable
;;;   reactor), Proteus in the indole answer (mirabilis -, vulgaris +), Bacteroides in
;;;   the indole answer (the B. fragilis group splits down the middle), and Pseudomonas
;;;   among the urease producers (72% positive). In every case a marker that is
;;;   variable FOR an organism cannot be used to exclude it.
;;;
;;;   NARROW THE PREMISES -- gate the rule to the context where the marker means
;;;   something, so it never fires where its answer would be incomplete. This is why
;;;   every lactose-reading rule requires aerobic growth: the reading presupposes
;;;   MacConkey, so rather than decide whether Bacteroides ferments lactose, the rule
;;;   declines to see anaerobes at all.
;;;
;;; Prefer narrowing when a marker is only MEANINGFUL in a context; prefer widening
;;; when it is meaningful everywhere but UNRELIABLE for some organism. What is not
;;; allowed is excluding on a hunch, because under this representation a hunch left out
;;; of an answer is indistinguishable from a finding.
;;;
;;; NEOMYCIN/TEST/PROPERTY-TESTS.LISP ENFORCES THE WIDENING HALF: *variable-markers*
;;; records, with citations, which organisms a marker cannot exclude, and no rule
;;; reading that marker may leave one out.

;;; WAS lactose-fermenter-argues-against-non-fermenters (excluded salmonella, proteus).
;;; Serratia is a slow/variable lactose reactor and is deliberately kept in.
(defrule lactose-fermenter-narrows-to-fermenters
    (:belief 0.7
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Enterobacteriaceae), NBK8035"
                             "NCBI Bookshelf / StatPearls, Proteus mirabilis Infections, NBK442017")
                  :belief-basis :illustrative
                  :note "Lactose fermentation on MacConkey is the standard teaching discriminator. Salmonella and Proteus are characteristic non-fermenters; Serratia is a slow and variable reactor and is deliberately kept in, since the marker is not clean for it. GATED ON AEROBIC GROWTH: the reading presupposes growth on MacConkey, which presupposes aerobic culture, so the rule has no business firing on an anaerobe. Without that premise it fired on a Bacteroides case and answered a set Bacteroides is not in -- excluding, on an aerobic test, an organism that cannot take the test."))
  (organism (id ?o))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (lactose (value fermenter) (of ?o))
  =>
  (assert (candidates (value '(:e-coli :klebsiella :enterobacter :serratia))
                      (of ?o))))

;;; WAS lactose-non-fermenter-argues-against-fermenters. Serratia kept in for the same
;;; reason -- the marker is not clean for it.
(defrule lactose-non-fermenter-narrows-to-non-fermenters
    (:belief 0.6
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Enterobacteriaceae), NBK8035"
                             "NCBI Bookshelf / StatPearls, Escherichia coli Infection, NBK564298")
                  :belief-basis :illustrative
                  :note "The reciprocal. Serratia is kept in for the same reason -- a slow or variable lactose reaction makes the marker unreliable for it in either direction. PSEUDOMONAS IS IN THIS ANSWER: it is the textbook non-lactose-fermenter, the standard contrast to the Enterobacteriaceae. Omitting it was a conversion defect -- the rule this replaced argued AGAINST the fermenters and never had to say what a non-fermenter positively is, so the complement was taken within the Enterobacteriaceae rather than within the gram-negative rods the corpus models. A lactose-negative reading then CONFLICTED with a Pseudomonas case it is in fact consistent with. Also gated on aerobic growth, for the reason given on the fermenter rule."))
  (organism (id ?o))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (lactose (value non-fermenter) (of ?o))
  =>
  (assert (candidates (value '(:salmonella :proteus :serratia :pseudomonas)) (of ?o))))

;;; WAS indole-pos-argues-against-indole-negative-species. Proteus was deliberately
;;; EXCLUDED from that rule's targets because P. mirabilis is indole-negative while
;;; P. vulgaris is indole-positive -- so as a narrows-to claim, proteus stays IN.
;;; The honest scoping survives the rewrite unchanged.
(defrule indole-positive-narrows-to-indole-producers
    (:belief 0.6
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Enterobacteriaceae), NBK8035"
                             "J Clin Microbiol (indole-positive vs indole-negative Klebsiella identification), PMC1594763"
                             "Differences in susceptibilities of species of the Bacteroides fragilis group to several beta-lactam antibiotics: indole production as an indicator of resistance, Antimicrob Agents Chemother, PMC183804")
                  :belief-basis :illustrative
                  :note "Klebsiella, Enterobacter, Salmonella and Serratia are characteristically indole-negative. Proteus stays IN: P. mirabilis is indole-negative while P. vulgaris is indole-positive, so the marker is ambiguous for the genus -- honest scoping the pre-v0.11 rule already made, and which survives the rewrite unchanged. BACTEROIDES STAYS IN FOR THE IDENTICAL REASON, which the pre-v0.11 rule missed because it was reasoning inside the Enterobacteriaceae: indole splits the B. fragilis group down the middle -- B. ovatus, B. thetaiotaomicron and B. uniformis are indole-positive, B. fragilis, B. distasonis and B. vulgatus are indole-negative (PMC183804). The corpus models one generic :bacteroides, so at that resolution the marker cannot exclude it. This costs nothing on an aerobic case: the aerobicity evidence already excludes the anaerobe, and it is that rule's job to, not this one's."))
  (organism (id ?o))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (indole (value positive) (of ?o))
  =>
  (assert (candidates (value '(:e-coli :proteus :bacteroides)) (of ?o))))

;;; WAS urease-pos-argues-against-urease-negative-organism (excluded e-coli, salmonella).
(defrule urease-positive-narrows-to-urease-producers
    (:belief 0.7
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Enterobacteriaceae), NBK8035"
                             "NCBI Bookshelf / StatPearls, Proteus mirabilis Infections, NBK442017"
                             "Interference of Pseudomonas Strains in the Identification of Helicobacter pylori, J Clin Microbiol, PMC86256")
                  :belief-basis :illustrative
                  :note "E. coli and Salmonella are characteristically urease-negative; Proteus is strongly and rapidly urease-positive, with Klebsiella, Enterobacter and Serratia variable. PSEUDOMONAS IS IN THIS ANSWER despite urease not being one of its identifying tests: 72% of P. aeruginosa strains are urease-positive (PMC86256, which reports Pseudomonas giving false-positive rapid urease tests in H. pylori identification for exactly this reason). Keeping a variably-positive organism IN follows the same policy as Serratia in the two lactose answers -- a marker that is unreliable for an organism cannot be used to exclude it, and under this representation absence from an answer IS exclusion."))
  (organism (id ?o))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (urease (value positive) (of ?o))
  =>
  (assert (candidates (value '(:klebsiella :enterobacter :serratia :proteus :pseudomonas))
                      (of ?o))))

;;; MERGE 2, and it fixes an audit finding.
;;; enterobacteriaceae-red-pigment-suggests-serratia was 0.75, justified by "many
;;; clinical isolates are non-pigmented" -- which belief-conditional-audit.md 3.1
;;; identified as the WRONG CONDITIONAL: that is P(pigment | serratia), a sensitivity,
;;; and irrelevant once red pigment has actually been observed.
;;; red-pigment-argues-against-non-serratia already used 0.8. Merged at 0.8, which is
;;; also close to the 0.90 the deferred grounding work estimated.
(defrule red-pigment-narrows-to-serratia
    (:belief 0.8
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("Scientific Reports 2024, Serratia marcescens prodigiosin red pigment, PMC11291754 (doi:10.1038/s41598-024-68747-3)"
                             "Microbiology (Mikrobiologiya) 2015, Pigmentation of Serratia marcescens and prodigiosin, PMID 25916146"
                             "NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Enterobacteriaceae), NBK8035")
                  :belief-basis :illustrative
                  :note "The red pigment prodigiosin is essentially specific to Serratia marcescens among the Enterobacteriaceae. MERGED from a pair that disagreed: the confirming rule was held to 0.75 by 'many clinical isolates are non-pigmented', which docs/belief-conditional-audit.md 3.1 identified as the WRONG CONDITIONAL -- that is P(pigment | serratia), a sensitivity, and irrelevant once red pigment has actually been observed. The excluding rule's 0.8 survives, close to the ~0.90 the deferred grounding work estimated."))
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
    (:belief 0.8
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf / StatPearls, Escherichia coli Infection, NBK564298"
                             "J Clin Microbiol (indole-positive vs indole-negative Klebsiella identification), PMC1594763")
                  :belief-basis :illustrative
                  :note "E. coli is the only major group of Enterobacteriaceae with both lactose utilization and indole production (IMViC ++--). 0.8 rather than higher because K. oxytoca is also lactose-positive and indole-positive."))
  (organism (id ?o))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
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
    (:belief 0.6
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf / StatPearls, Enterobacter Infections, NBK559296"
                             "NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Enterobacteriaceae), NBK8035")
                  :belief-basis :illustrative
                  :note "Motility separates the motile Enterobacter from the non-motile Klebsiella. Serratia is named alongside Enterobacter because it is also motile, indole-negative and a variable lactose reactor -- the corpus records no motility fact that would exclude it, a gap docs/slice-d-focal-width.md flagged, and naming the wider set is the honest reading of what the evidence can actually distinguish."))
  (organism (id ?o))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (lactose (value fermenter) (of ?o))
  (indole (value negative) (of ?o))
  (motility (value motile) (of ?o))
  =>
  (assert (candidates (value '(:enterobacter :serratia)) (of ?o))))

;;; THE RECIPROCAL OF THE UREASE RULE, and its whole value is one exclusion: Proteus.
;;;
;;; The answer names seven of the eight gram-negative rods the corpus models, which
;;; looks useless until you notice that is the honest reading. Proteus is rapidly and
;;; strongly urease-positive, so a negative urease genuinely rules it out. Everything
;;; else stays: E. coli and Salmonella are characteristically negative and belong here
;;; outright; Klebsiella, Enterobacter and Serratia are VARIABLE, and the corpus policy
;;; is that a marker unreliable for an organism cannot exclude it in EITHER direction --
;;; the same reason they appear in the urease-positive answer too; Pseudomonas is 72%
;;; positive (PMC86256), so 28% of strains read negative and it stays; and Bacteroides
;;; is generally urease-negative, so it belongs here more than most.
;;;
;;; NOT GATED ON AEROBIC GROWTH, unlike the lactose pair. A lactose reading presupposes
;;; growth on MacConkey and therefore an aerobe; a urease test does not, and gating it
;;; would silently drop Bacteroides out of an answer it belongs in.
;;;
;;; A seven-of-eight answer with one real exclusion is worth authoring precisely
;;; because the alternative -- what shipped before -- was SILENCE. A clinician reported
;;; a negative urease, the bridge accepted it, and no rule read it; the model then had
;;; to say the panel "hasn't independently triggered any rule". Now it excludes Proteus,
;;; and can say so.
(defrule urease-negative-narrows-to-non-proteus-rods
    (:belief 0.6
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Enterobacteriaceae), NBK8035"
                             "NCBI Bookshelf / StatPearls, Proteus mirabilis Infections, NBK442017"
                             "Interference of Pseudomonas Strains in the Identification of Helicobacter pylori, J Clin Microbiol, PMC86256")
                  :belief-basis :illustrative
                  :note "Proteus is rapidly and strongly urease-positive, so a negative urease excludes it. It excludes nothing else: the variable producers (Klebsiella, Enterobacter, Serratia, and Pseudomonas at 72% positive) stay in under the policy that an unreliable marker cannot exclude, and E. coli, Salmonella and Bacteroides are characteristically negative. 0.6 reflects a real but narrow claim -- one organism removed from eight -- not a weak one."))
  (organism (id ?o))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (urease (value negative) (of ?o))
  =>
  (assert (candidates (value '(:e-coli :salmonella :klebsiella :enterobacter
                               :serratia :pseudomonas :bacteroides))
                      (of ?o))))

;;; THE RECIPROCAL OF THE MOTILITY PREMISE, which until now only ever appeared inside
;;; conjunctions. Klebsiella is the textbook non-motile member of the family -- the
;;; corpus already says so on MOTILE-LACTOSE-POS-INDOLE-NEG-NARROWS-TO-MOTILE-FERMENTERS
;;; ("motility separates the motile Enterobacter from the non-motile Klebsiella") --
;;; but nothing read a non-motile result.
;;;
;;; E. COLI IS KEPT IN, and this is the judgement call in this rule. E. coli is
;;; flagellated and described as motile, but motility is variably EXPRESSED and a
;;; substantial minority of clinical isolates read non-motile on a standard tube test.
;;; That is the same unreliability the corpus already honours for Serratia on lactose
;;; and Pseudomonas on urease, so the conservative move is to widen the answer rather
;;; than exclude on a marker the organism does not reliably show. Excluding requires
;;; evidence; including requires none.
(defrule non-motile-narrows-to-non-motile-rods
    (:belief 0.6
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Enterobacteriaceae), NBK8035"
                             "NCBI Bookshelf / StatPearls, Klebsiella Pneumonia, NBK519004"
                             "NCBI Bookshelf / StatPearls, Escherichia coli Infection, NBK564298")
                  :belief-basis :illustrative
                  :note "Klebsiella is characteristically non-motile, which is what makes motility the Klebsiella/Enterobacter discriminator this corpus already relies on. Salmonella, Proteus, Serratia, Enterobacter and Pseudomonas are characteristically motile and are excluded. E. coli is kept in because motility, though characteristic, is variably expressed and a substantial minority of isolates test non-motile -- the marker is not clean enough for it to be excluded on. GATED ON AEROBIC GROWTH: motility is read from a growth-based test, and Bacteroides is neither aerobic nor usefully described by it."))
  (organism (id ?o))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (motility (value non-motile) (of ?o))
  =>
  (assert (candidates (value '(:klebsiella :e-coli)) (of ?o))))

;;; Swarming motility plus strong urease is close to Proteus-specific.
(defrule urease-pos-swarming-narrows-to-proteus
    (:belief 0.8
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf / StatPearls, Proteus mirabilis Infections, NBK442017"
                             "Nature Reviews Microbiology 2012 (Armbruster & Mobley), Proteus mirabilis lifestyle, doi:10.1038/nrmicro2890 (PMC3621030)")
                  :belief-basis :illustrative
                  :note "Proteus species show characteristic swarming motility and rapid, strong urease activity; the combination is close to Proteus-specific among the Enterobacteriaceae."))
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
    (:belief 0.4
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.27 (Pseudomonas), NBK8326"
                             "NCBI Bookshelf / StatPearls, Pseudomonas aeruginosa Infections, NBK557831")
                  :belief-basis :illustrative
                  :note "Pseudomonas aeruginosa is a classic cause of bacteraemia in seriously burned patients. GATED ON AEROBIC GROWTH (Category B): without it this rule fired on an ANAEROBIC gram-negative rod and answered {pseudomonas}, an obligate aerobe, in direct contradiction with the bacteroides answer. That was live in culture-2, where it manufactured conflict the driver docstring attributed to the ambiguous Gram stain."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (culture-site (value blood) (of ?c))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (burn (value serious) (of ?p))
  =>
  (assert (candidates (value '(:pseudomonas)) (of ?o))))

(defrule compromised-gram-neg-rod-narrows-to-pseudomonas
    (:belief 0.6
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf / StatPearls, Pseudomonas aeruginosa Infections, NBK557831"
                             "NCBI Bookshelf, Medical Microbiology 4th ed. ch.27 (Pseudomonas), NBK8326")
                  :belief-basis :illustrative
                  :note "Pseudomonas aeruginosa is a major opportunist in the immunocompromised host. GATED ON AEROBIC GROWTH (Category B) for the same reason as the burn rule above -- Pseudomonas is an obligate aerobe, and without the gate this rule contradicted the bacteroides answer on every anaerobe."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (compromised-host (value t) (of ?p))
  =>
  (assert (candidates (value '(:pseudomonas)) (of ?o))))

(defrule hospital-acquired-aerobic-gram-neg-rod-narrows-to-pseudomonas
    (:belief 0.7
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf / StatPearls, Pseudomonas aeruginosa Infections, NBK557831"
                             "NCBI Bookshelf, Medical Microbiology 4th ed. ch.27 (Pseudomonas), NBK8326")
                  :belief-basis :illustrative
                  :note "Pseudomonas aeruginosa is a leading nosocomial pathogen, notably in ICU bacteraemia and ventilator-associated pneumonia."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (hospital-acquired (value t) (of ?p))
  =>
  (assert (candidates (value '(:pseudomonas)) (of ?o))))

(defrule neutropenia-aerobic-gram-neg-rod-narrows-to-pseudomonas
    (:belief 0.5
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("High Rate of Inappropriate Antibiotics in Patients with Hematologic Malignancies and Pseudomonas aeruginosa Bacteremia following International Guideline Recommendations, PMC10434044"
                             "Clinical characteristics and outcomes of Pseudomonas aeruginosa bacteremia in febrile neutropenic children and adolescents, PMC5513208")
                  :belief-basis :illustrative
                  :note "Antipseudomonal cover is standard in febrile neutropenia. NOTE, retained from the pre-v0.11 rule: this is the WEAKEST CITATION IN THE CORPUS -- the sources support empiric coverage rather than the claim that the organism is more likely to be Pseudomonas. Declared honestly rather than quietly strengthened."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (neutropenia (value t) (of ?p))
  =>
  (assert (candidates (value '(:pseudomonas)) (of ?o))))

(defrule anaerobic-gram-neg-rod-in-blood-narrows-to-bacteroides
    (:belief 0.9
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf / StatPearls, Bacteroides Fragilis, NBK553032"
                             "NCBI Bookshelf, Medical Microbiology 4th ed. ch.20 (Anaerobic Gram-Negative Bacilli, Finegold), NBK8438")
                  :belief-basis :illustrative
                  :note "Bacteroides fragilis is the commonest anaerobic gram-negative rod isolated from blood."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (culture-site (value blood) (of ?c))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value anaerobic) (of ?o))
  =>
  (assert (candidates (value '(:bacteroides)) (of ?o))))

(defrule anaerobic-gram-neg-rod-in-abdomen-narrows-to-bacteroides
    (:belief 0.8
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf / StatPearls, Bacteroides Fragilis, NBK553032"
                             "NCBI Bookshelf / StatPearls, Anaerobic Infections, NBK482349"
                             "IDSA/SIS, Complicated Intra-abdominal Infection guideline (Solomkin et al.), Clin Infect Dis 2010;50(2):133")
                  :belief-basis :illustrative
                  :note "Bacteroides species dominate the colonic flora and are the usual anaerobes in intra-abdominal sepsis."))
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
    (:belief 0.6
     :provenance (:origin :paip-subset
                  :evidence ("ASM Clinical Microbiology Reviews 1998 (Podschun & Ullmann), Klebsiella spp. as Nosocomial Pathogens, doi:10.1128/CMR.11.4.589 (PMC88898)"
                             "NCBI Bookshelf / StatPearls, Klebsiella Pneumonia, NBK519004")
                  :belief-basis :illustrative
                  :note "Klebsiella pneumoniae is a leading nosocomial pathogen in immunocompromised inpatients. NOTE: this rule SUBSUMES the compromised-host-only rule below -- its premises are a strict superset -- so when both fire the more specific one stands alone. See neomycin/consensus.lisp."))
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
    (:belief 0.5
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Escherichia, Klebsiella, Enterobacter, Serratia, Citrobacter, Proteus), NBK8035"
                             "NCBI Bookshelf / StatPearls, Klebsiella Pneumonia, NBK519004")
                  :belief-basis :illustrative
                  :note "Klebsiella is a common opportunist in the compromised host. Subsumed by the hospital-acquired rule above when that one also fires."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (compromised-host (value t) (of ?p))
  =>
  (assert (candidates (value '(:klebsiella)) (of ?o))))

(defrule tropical-travel-aerobic-gram-neg-rod-narrows-to-salmonella
    (:belief 0.65
     :provenance (:origin :paip-subset
                  :evidence ("CDC Yellow Book 2026, Typhoid & Paratyphoid Fever, NBK620886"
                             "NCBI Bookshelf / StatPearls, Typhoid Fever, NBK557513")
                  :belief-basis :illustrative
                  :note "Enteric fever is strongly associated with travel to endemic regions."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (recent-travel (value tropical) (of ?p))
  =>
  (assert (candidates (value '(:salmonella)) (of ?o))))

(defrule blood-low-wbc-aerobic-gram-neg-rod-narrows-to-salmonella
    (:belief 0.55
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf / StatPearls, Typhoid Fever, NBK557513")
                  :belief-basis :illustrative
                  :note "Leukopenia is reported in roughly 15-25% of typhoid cases. NOTE, retained: docs/belief-conditional-audit.md 3.3 flagged that figure as P(low WBC | Salmonella), a sensitivity, for a rule that fires ON low WBC -- and 0.55 is derived from neither it nor a posterior. Carried across unchanged rather than silently adjusted; grounding it is separate work."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (culture-site (value blood) (of ?c))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (white-blood-count (value low) (of ?p))
  =>
  (assert (candidates (value '(:salmonella)) (of ?o))))