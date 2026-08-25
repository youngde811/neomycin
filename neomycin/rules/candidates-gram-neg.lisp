;;; -*- Mode: Lisp -*-
;;;
;;; Part of neomycin's canonical rulebase.
;;;
;;; THE GRAM-NEGATIVE HALF as narrows-to rules: the enterobacteriaceae cluster (9),
;;; the gram-negative identities (5), the 8 ruling-out rules that touch them, and the
;;; neutropenia host factor. 23 rules in, 21 out after two merges.
;;;
;;; This was the harder cluster to convert -- the source rules chained deeper and
;;; cross-disconfirmed far more than the gram-positives -- which is what made it the
;;; real test of whether the shape holds. Neither mechanism survives the conversion:
;;; nothing chains here and nothing argues against anything.
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
    (:belief 0.7
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Enterobacteriaceae), NBK8035"
                             "NCBI Bookshelf / StatPearls, Escherichia coli Infection, NBK564298")
                  :belief-basis :illustrative
                  :note "The reciprocal. Serratia is kept in for the same reason -- a slow or variable lactose reaction makes the marker unreliable for it in either direction. PSEUDOMONAS IS IN THIS ANSWER: it is the textbook non-lactose-fermenter, the standard contrast to the Enterobacteriaceae. Omitting it was a conversion defect -- the rule this replaced argued AGAINST the fermenters and never had to say what a non-fermenter positively is, so the complement was taken within the Enterobacteriaceae rather than within the gram-negative rods the corpus models. A lactose-negative reading then CONFLICTED with a Pseudomonas case it is in fact consistent with. Also gated on aerobic growth, for the reason given on the fermenter rule.

BELIEF RAISED 0.6 -> 0.7 to match the fermenter reading, which it had been discounted against for no stated reason -- the note said only that it was the reciprocal. There is no asymmetry to justify it: the answers are the same size, and the one organism the marker is unreliable for (Serratia) is kept in BOTH for the same reason, so the unreliability is already handled by widening rather than by discounting. This follows the corpus's own precedent in CATALASE-POSITIVE / CATALASE-NEGATIVE, which carry 0.70 in both directions across a three-member and a six-member answer because the test is no more reliable one way than the other. Where a reciprocal pair IS asymmetric here -- novobiocin, bacitracin, optochin -- the note names the asymmetry."))
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
                  :note "The red pigment prodigiosin is essentially specific to Serratia marcescens among the Enterobacteriaceae. MERGED from a pair that disagreed: the confirming rule was held to 0.75 by 'many clinical isolates are non-pigmented', which docs/attic/belief-conditional-audit.md 3.1 identified as the WRONG CONDITIONAL -- that is P(pigment | serratia), a sensitivity, and irrelevant once red pigment has actually been observed. The excluding rule's 0.8 survives, close to the ~0.90 the deferred grounding work estimated."))
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
                  :note "Motility separates the motile Enterobacter from the non-motile Klebsiella. Serratia is named alongside Enterobacter because it is also motile, indole-negative and a variable lactose reactor -- the corpus records no motility fact that would exclude it, a gap docs/attic/slice-d-focal-width.md flagged, and naming the wider set is the honest reading of what the evidence can actually distinguish."))
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
    (:belief 0.7
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Enterobacteriaceae), NBK8035"
                             "NCBI Bookshelf / StatPearls, Proteus mirabilis Infections, NBK442017"
                             "Interference of Pseudomonas Strains in the Identification of Helicobacter pylori, J Clin Microbiol, PMC86256")
                  :belief-basis :illustrative
                  :note "Proteus is rapidly and strongly urease-positive, so a negative urease excludes it. It excludes nothing else: the variable producers (Klebsiella, Enterobacter, Serratia, and Pseudomonas at 72% positive) stay in under the policy that an unreliable marker cannot exclude, and E. coli, Salmonella and Bacteroides are characteristically negative.

BELIEF RAISED 0.6 -> 0.7, AND THE OLD JUSTIFICATION WITHDRAWN. It read: \"0.6 reflects a real but narrow claim -- one organism removed from eight -- not a weak one.\" That reasons from INFORMATIVENESS where this value means RELIABILITY. A belief is the mass this evidence commits to this answer set -- how sure we are the true organism is in there -- so removing one organism from eight leaves a WIDE answer, which is EASIER to be right about and should carry MORE mass, not less. The old note argued for a low number from a premise that implies a high one.

On the evidence, this is if anything the STRONGER of the two urease readings: Proteus is rapidly and strongly urease-positive, so a negative result excludes it crisply, whereas a positive result is muddy (Pseudomonas 72%, Klebsiella/Enterobacter/Serratia variable). The sharper reading over the wider set was carrying the lower number. Now matched to the positive reading at 0.7, per the CATALASE precedent."))
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
;;;
;;; ------------------------------------------------------------------
;;; CATEGORY B: WHAT EPIDEMIOLOGICAL EVIDENCE CAN AND CANNOT SAY
;;; ------------------------------------------------------------------
;;; Every rule in this section used to answer with a SINGLETON. Under the v0.11
;;; semantics -- absence from an answer IS exclusion -- that made each of them a claim
;;; that the context established the species outright. The literature does not support
;;; one of them at that resolution, and the survey (docs/category-b-resolution-survey.md)
;;; records the check rule by rule.
;;;
;;; The asymmetry that makes this a defect rather than a preference: the AUTHORING
;;; POLICY above already requires that a BENCH marker which is merely variable for an
;;; organism must keep that organism in the answer. Epidemiological association
;;; discriminates far LESS sharply than a bench marker. These rules were answering at
;;; maximum resolution on the thinnest evidence in the corpus.
;;;
;;; THE OPPORTUNIST SET. Four of these rules -- burn, compromised host, hospital
;;; acquired, neutropenia -- now answer with the same six organisms:
;;;
;;;   {e-coli, klebsiella, enterobacter, serratia, proteus, pseudomonas}
;;;
;;; the aerobic seven less Salmonella, which is an enteric pathogen rather than an
;;; opportunist and is the only member any of these contexts has evidence to exclude.
;;; That the four converge is not laziness; it is the finding. Nosocomial and
;;; compromised-host gram-negative bacteraemia is dominated by E. coli and Klebsiella
;;; with Pseudomonas third, and the same handful of organisms recurs across all four
;;; contexts. What changes between them is the RELATIVE likelihood of the members --
;;; which is precisely the quantity an answer SET cannot express. See section 5.
;;;
;;; TWO RULES WERE RETIRED and two were MERGED. See section 5 for both, and for what
;;; the exercise showed about the representation itself.

(defrule burn-blood-aerobic-gram-neg-rod-narrows-to-opportunist-rods
    (:belief 0.4
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.27 (Pseudomonas), NBK8326"
                             "NCBI Bookshelf / StatPearls, Pseudomonas aeruginosa Infections, NBK557831"
                             "Highly Drug-Resistant Pathogens Implicated in Burn-Associated Bacteremia, PMC4128596"
                             "Gram-Negative Bacilli Blood Stream Infection in Patients with Severe Burns: a 9-Year Cohort, PMC11476612")
                  :belief-basis :illustrative
                  :note "Pseudomonas aeruginosa is a classic cause of bacteraemia in seriously burned patients, but it is not the only one and the singleton this rule used to assert was a claim that it was. Burn-associated bacteraemia gives P. aeruginosa 34%, K. pneumoniae 12%, A. baumannii 9% and E. cloacae 8%; a nine-year gram-negative cohort in severe burns gives Pseudomonas 50.7%, A. baumannii 46.4%, Klebsiella 13.8%. Proteus, Serratia and E. coli are all described burn-unit organisms. WIDENED to the opportunist set. Acinetobacter is not modelled by this corpus and needs no naming -- the open frame keeps it plausible as residual ignorance. GATED ON AEROBIC GROWTH: without it this rule fired on an ANAEROBIC gram-negative rod and answered {pseudomonas}, an obligate aerobe, contradicting the bacteroides answer. That was live in culture-2, where it manufactured conflict the driver docstring attributed to the ambiguous Gram stain."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (culture-site (value blood) (of ?c))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (burn (value serious) (of ?p))
  =>
  (assert (candidates (value '((0.20 :pseudomonas)
                               (0.07 :klebsiella)
                               (0.05 :enterobacter)
                               (0.08 :e-coli :proteus :serratia)))
                      (of ?o))))

;;; MERGED. This rule and COMPROMISED-GRAM-NEG-ROD-NARROWS-TO-PSEUDOMONAS had
;;; BYTE-IDENTICAL premises once the latter was gated on aerobicity, and answered
;;; disjoint singletons -- {klebsiella} against {pseudomonas}. Two rules contradicting
;;; each other on identical evidence is not a differential; it is the corpus disagreeing
;;; with itself, and PROPERTY-NO-TWO-RULES-SHARE-IDENTICAL-PREMISES forbids it the
;;; moment they agree on an answer. They were never two observations. They were one
;;; observation and two citations, each naming the organism its author had in mind.
;;; Merged at 0.6, the higher of the pair, following David's 2026-08-17 precedent.
(defrule compromised-aerobic-gram-neg-rod-narrows-to-opportunist-rods
    (:belief 0.6
     :provenance (:origin :paip-subset
                  :evidence-group :gram-neg-opportunist-base-rate
                  :evidence ("NCBI Bookshelf / StatPearls, Pseudomonas aeruginosa Infections, NBK557831"
                             "NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Escherichia, Klebsiella, Enterobacter, Serratia, Citrobacter, Proteus), NBK8035"
                             "NCBI Bookshelf / StatPearls, Klebsiella Pneumonia, NBK519004"
                             "Epidemiological characteristics and management of Gram-negative bacteraemia in different immunocompromised hosts, PMC12233224"
                             "Pathogenesis of Gram-Negative Bacteremia, Clin Microbiol Rev, doi:10.1128/cmr.00234-20")
                  :belief-basis :illustrative
                  :note "Both Pseudomonas and Klebsiella are major opportunists in the compromised host, and NEITHER leads: E. coli is the most frequently reported organism in gram-negative bacteraemia in solid-tumour patients (47%), and across nosocomial gram-negative bacteraemia generally E. coli runs 40.5% to Klebsiella's 22.5% and Pseudomonas's 10%. A rule naming either alone excludes the leader. MERGED from the pseudomonas and klebsiella rules that shared this premise set exactly; see the comment above. SUBSUMED by the hospital-acquired rule below when that one also fires -- its premises are a strict superset. See neomycin/consensus.lisp. SHARED BASE RATE, DECLARED AS :evidence-group :gram-neg-opportunist-base-rate. This rule's distribution is substantially the same shape as the other gram-negative opportunist context rules (compromised host, hospital-acquired, hospital-acquired-and-compromised, neutropenia) -- e-coli around 0.43 of the commitment, klebsiella 0.27, pseudomonas 0.15 -- because all four rest on the same epidemiology of gram-negative bacteraemia. They are NOT conditionally independent, and Dempster's rule assumes they are: before the group was declared, a patient who was both compromised and neutropenic fired two of them and the engine read agreement as corroboration, inflating the leader's belief ABOVE what either finding alone supports (e-coli 0.28 -> 0.3492) while simultaneously inflating conflict to 0.2096 between two rules that AGREE. Measured in docs/base-rate-investigation.md. ONLY ONE MEMBER OF THE GROUP NOW CONTRIBUTES -- the most committed, ties broken by name -- so the result is exactly what that rule gives alone. A dropped member is absent from the argument as well as the arithmetic."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (compromised-host (value t) (of ?p))
  =>
  (assert (candidates (value '((0.28 :e-coli)
                               (0.16 :klebsiella)
                               (0.08 :pseudomonas)
                               (0.08 :enterobacter :serratia :proteus)))
                      (of ?o))))

(defrule hospital-acquired-aerobic-gram-neg-rod-narrows-to-opportunist-rods
    (:belief 0.7
     :provenance (:origin :paip-subset
                  :evidence-group :gram-neg-opportunist-base-rate
                  :evidence ("NCBI Bookshelf / StatPearls, Pseudomonas aeruginosa Infections, NBK557831"
                             "NCBI Bookshelf, Medical Microbiology 4th ed. ch.27 (Pseudomonas), NBK8326"
                             "Risk factors for mortality in patients with nosocomial Gram-negative rod bacteremia, PubMed 23640443"
                             "Epidemiology and microbiology of nosocomial bloodstream infections: 482 cases, PMC4288947"
                             "NCBI Bookshelf / StatPearls, Central Line-Associated Blood Stream Infections, NBK430891")
                  :belief-basis :illustrative
                  :note "Pseudomonas aeruginosa is a leading nosocomial pathogen, but in nosocomial gram-negative bacteraemia it ranks THIRD: E. coli 40.5%, K. pneumoniae 22.5%, P. aeruginosa 10%, with a second series giving E. coli 25.5% and Klebsiella 11.2%, and NHSN CLABSI data ranking Klebsiella 5.8%, Enterobacter 3.9%, Pseudomonas 3.1%, E. coli 2.7%. This rule carried the HIGHEST belief of the four pseudomonas context rules (0.7) on the organism the surveillance data rank third. WIDENED to the opportunist set; the belief is left where it was, because it now answers a question the evidence supports -- how reliably does a nosocomial aerobic gram-negative rod mean one of these six. SHARED BASE RATE, DECLARED AS :evidence-group :gram-neg-opportunist-base-rate. This rule's distribution is substantially the same shape as the other gram-negative opportunist context rules (compromised host, hospital-acquired, hospital-acquired-and-compromised, neutropenia) -- e-coli around 0.43 of the commitment, klebsiella 0.27, pseudomonas 0.15 -- because all four rest on the same epidemiology of gram-negative bacteraemia. They are NOT conditionally independent, and Dempster's rule assumes they are: before the group was declared, a patient who was both compromised and neutropenic fired two of them and the engine read agreement as corroboration, inflating the leader's belief ABOVE what either finding alone supports (e-coli 0.28 -> 0.3492) while simultaneously inflating conflict to 0.2096 between two rules that AGREE. Measured in docs/base-rate-investigation.md. ONLY ONE MEMBER OF THE GROUP NOW CONTRIBUTES -- the most committed, ties broken by name -- so the result is exactly what that rule gives alone. A dropped member is absent from the argument as well as the arithmetic."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (hospital-acquired (value t) (of ?p))
  =>
  (assert (candidates (value '((0.30 :e-coli)
                               (0.19 :klebsiella)
                               (0.11 :pseudomonas)
                               (0.10 :enterobacter :serratia :proteus)))
                      (of ?o))))

(defrule neutropenia-aerobic-gram-neg-rod-narrows-to-opportunist-rods
    (:belief 0.5
     :provenance (:origin :neomycin-extrapolation
                  :evidence-group :gram-neg-opportunist-base-rate
                  :evidence ("Review of clinical profile and bacterial spectrum and sensitivity patterns of pathogens in febrile neutropenic patients in hematological malignancies, PMC3764750"
                             "Clinical characteristics and outcomes of Pseudomonas aeruginosa bacteremia in febrile neutropenic children and adolescents, PMC5513208"
                             "An eleven-year cohort of bloodstream infections in 552 febrile neutropenic patients, Ann Hematol, doi:10.1007/s00277-020-04144-w")
                  :belief-basis :illustrative
                  :note "THE CLEAREST SINGLE DEFECT THE CATEGORY B SURVEY FOUND, and it was hiding behind an honest note rather than a silent one. The febrile-neutropenia literature states it directly: Pseudomonas aeruginosa is the THIRD most common gram-negative cause of bacteraemia in these patients, after Klebsiella pneumoniae and Escherichia coli -- E. coli 39.5% and K. pneumoniae 23.3% of gram-negative isolates. The rule named the third-place organism as its sole answer.

The retained pre-v0.11 note said this was the WEAKEST CITATION IN THE CORPUS because its sources support empiric coverage rather than a claim about which organism is likelier. That is not a weak conditional; it is NO conditional. Antipseudomonal cover in febrile neutropenia is a THERAPY policy -- neomycin has a therapy phase to express it, and this is the identification corpus. Widening removes the false identification claim; it does not remove the clinical point, which belongs in neomycin/therapy/. SHARED BASE RATE, DECLARED AS :evidence-group :gram-neg-opportunist-base-rate. This rule's distribution is substantially the same shape as the other gram-negative opportunist context rules (compromised host, hospital-acquired, hospital-acquired-and-compromised, neutropenia) -- e-coli around 0.43 of the commitment, klebsiella 0.27, pseudomonas 0.15 -- because all four rest on the same epidemiology of gram-negative bacteraemia. They are NOT conditionally independent, and Dempster's rule assumes they are: before the group was declared, a patient who was both compromised and neutropenic fired two of them and the engine read agreement as corroboration, inflating the leader's belief ABOVE what either finding alone supports (e-coli 0.28 -> 0.3492) while simultaneously inflating conflict to 0.2096 between two rules that AGREE. Measured in docs/base-rate-investigation.md. ONLY ONE MEMBER OF THE GROUP NOW CONTRIBUTES -- the most committed, ties broken by name -- so the result is exactly what that rule gives alone. A dropped member is absent from the argument as well as the arithmetic."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (neutropenia (value t) (of ?p))
  =>
  (assert (candidates (value '((0.20 :e-coli)
                               (0.13 :klebsiella)
                               (0.09 :pseudomonas)
                               (0.08 :enterobacter :serratia :proteus)))
                      (of ?o))))

;;; The two anaerobe rules SURVIVE Category B with their singletons, and the reason is
;;; worth stating rather than enjoying: the corpus models exactly ONE anaerobic
;;; gram-negative rod, so {bacteroides} already IS the whole anaerobic pool. Neither
;;; rule makes a resolution claim at all -- there is nothing either could have excluded.
(defrule anaerobic-gram-neg-rod-in-blood-narrows-to-bacteroides
    (:belief 0.9
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf / StatPearls, Bacteroides Fragilis, NBK553032"
                             "NCBI Bookshelf, Medical Microbiology 4th ed. ch.20 (Anaerobic Gram-Negative Bacilli, Finegold), NBK8438")
                  :belief-basis :illustrative
                  :note "Bacteroides fragilis is the commonest anaerobic gram-negative rod isolated from blood. SURVIVES CATEGORY B, but the narrowness is an artifact of CORPUS COVERAGE rather than of evidence: real anaerobic gram-negative bacteraemia also includes Fusobacterium and Prevotella, which this corpus cannot name. The open frame keeps them plausible as residual ignorance, which is what makes the narrow answer safe -- the same disclosure NOVOBIOCIN-SENSITIVE-NARROWS-TO-EPIDERMIDIS makes for the unmodelled coagulase-negative staphylococci."))
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
                  :note "Bacteroides species dominate the colonic flora and are the usual anaerobes in intra-abdominal sepsis. SURVIVES CATEGORY B on the same terms as the blood rule above, and carries the same disclosure: Fusobacterium and Prevotella are unmodelled, not excluded."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value anaerobic) (of ?o))
  (infection-site (value abdominal) (of ?p))
  =>
  (assert (candidates (value '(:bacteroides)) (of ?o))))

(defrule hospital-acquired-compromised-aerobic-gram-neg-rod-narrows-to-opportunist-rods
    (:belief 0.7
     :provenance (:origin :paip-subset
                  :evidence-group :gram-neg-opportunist-base-rate
                  :evidence ("ASM Clinical Microbiology Reviews 1998 (Podschun & Ullmann), Klebsiella spp. as Nosocomial Pathogens, doi:10.1128/CMR.11.4.589 (PMC88898)"
                             "NCBI Bookshelf / StatPearls, Klebsiella Pneumonia, NBK519004"
                             "Risk factors for mortality in patients with nosocomial Gram-negative rod bacteremia, PubMed 23640443"
                             "Epidemiology and microbiology of nosocomial bloodstream infections: 482 cases, PMC4288947")
                  :belief-basis :illustrative
                  :note "Klebsiella pneumoniae is a leading nosocomial pathogen in immunocompromised inpatients -- a solid SECOND at 22.5% (11.2% in a second series), behind E. coli at 40.5% (25.5%). Naming Klebsiella alone excluded the leader. WIDENED to the opportunist set. This rule SUBSUMES the compromised-host-only rule above -- its premises are a strict superset -- so when both fire the more specific one stands alone, and it now also subsumes the hospital-acquired-only rule, which it did not before: those two answered different singletons, so the specificity policy never engaged between them. See neomycin/consensus.lisp.

BELIEF RAISED 0.6 -> 0.7, FIXING A COHERENCE DEFECT rather than tuning a number. This rule SUBSUMES the hospital-acquired-only rule, which commits 0.7 -- so whenever both fire, the specificity policy DROPS the 0.7 rule and keeps this one. The corpus was therefore committing 0.6 where it would have committed 0.7 on strictly LESS information: learning that a hospital-acquired patient is also immunocompromised made it less sure. That is not a probability error, it is the specificity policy and the belief values disagreeing, and it was the only defect of its kind in the corpus. Invariant 16 now forbids it.

The focal masses were rescaled to the new total in the SAME proportions -- e-coli held at 40% of the commitment, klebsiella 30%, pseudomonas 17%, the remainder 13% -- so the distribution's shape, which the literature decides, is untouched. Only how much the rule commits at all has changed. SHARED BASE RATE, DECLARED AS :evidence-group :gram-neg-opportunist-base-rate. This rule's distribution is substantially the same shape as the other gram-negative opportunist context rules (compromised host, hospital-acquired, hospital-acquired-and-compromised, neutropenia) -- e-coli around 0.43 of the commitment, klebsiella 0.27, pseudomonas 0.15 -- because all four rest on the same epidemiology of gram-negative bacteraemia. They are NOT conditionally independent, and Dempster's rule assumes they are: before the group was declared, a patient who was both compromised and neutropenic fired two of them and the engine read agreement as corroboration, inflating the leader's belief ABOVE what either finding alone supports (e-coli 0.28 -> 0.3492) while simultaneously inflating conflict to 0.2096 between two rules that AGREE. Measured in docs/base-rate-investigation.md. ONLY ONE MEMBER OF THE GROUP NOW CONTRIBUTES -- the most committed, ties broken by name -- so the result is exactly what that rule gives alone. A dropped member is absent from the argument as well as the arithmetic."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (hospital-acquired (value t) (of ?p))
  (compromised-host (value t) (of ?p))
  =>
  (assert (candidates (value '((0.28 :e-coli)
                               (0.21 :klebsiella)
                               (0.12 :pseudomonas)
                               (0.09 :enterobacter :serratia :proteus)))
                      (of ?o))))

;;; The travel rule keeps real content, and it is the only context rule in this section
;;; that does: it points AWAY from the opportunist set and towards the enteric organisms.
(defrule tropical-travel-aerobic-gram-neg-rod-narrows-to-enteric-rods
    (:belief 0.65
     :provenance (:origin :paip-subset
                  :evidence ("CDC Yellow Book 2026, Typhoid & Paratyphoid Fever, NBK620886"
                             "NCBI Bookshelf / StatPearls, Typhoid Fever, NBK557513"
                             "Fever in the Returned Traveler, PMC7152027")
                  :belief-basis :illustrative
                  :note "Enteric fever is strongly associated with travel to endemic regions, and enteric bacteria -- E. coli, Campylobacter, Salmonella, Shigella -- are the commonest bacterial causes of fever from the tropics. WIDENED, but only to the enteric rods: this rule does not fire on fever, it fires on a blood culture ALREADY growing an aerobic gram-negative rod, and conditioned on that, travel to an endemic region genuinely raises Salmonella a long way. What it cannot support is the implied claim that E. coli bacteraemia stops happening because the patient travelled. Pseudomonas, Proteus, Serratia and Enterobacter are left out on the enteric-source reading, which is evidence, not a hunch."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (aerobicity (value aerobic) (of ?o))
  (recent-travel (value tropical) (of ?p))
  =>
  (assert (candidates (value '((0.42 :salmonella)
                               (0.15 :e-coli)
                               (0.08 :klebsiella)))
                      (of ?o))))

;;; ==================================================================
;;; 5. RETIRED: what Category B removed, and why
;;; ==================================================================
;;; BLOOD-LOW-WBC-AEROBIC-GRAM-NEG-ROD-NARROWS-TO-SALMONELLA (was 0.55) is GONE.
;;;
;;; It is the WRONG CONDITIONAL that docs/attic/belief-conditional-audit.md 3.3 predicted,
;;; now confirmed. The rule fired ON a low white count, so it had to answer
;;; P(Salmonella | low WBC, aerobic gram-negative rod in blood). The 15-25% figure its
;;; note cited is P(low WBC | typhoid) -- a SENSITIVITY, and a poor one: leukopenia
;;; occurs in only about 25% of typhoid patients (24.6% in a 191-patient series), and a
;;; normal or raised count is commoner and does not exclude the diagnosis.
;;;
;;; Correcting the conditional does not rescue the rule, which is why it was retired
;;; rather than widened. Leukopenia in gram-negative bacteraemia marks SEVERITY, not
;;; species -- it occurs across E. coli, Klebsiella and Pseudomonas sepsis alike. The
;;; honest widened answer is therefore the whole aerobic set, which adds nothing the
;;; Gram stain did not already say. A rule whose honest answer is "one of the seven"
;;; should not be a rule.
;;;
;;; Sources: PMC9018254 (Laboratory Findings in Typhoid); PubMed 1496717 (The white
;;; cell count in typhoid fever); NBK557513.
;;;
;;; CONSEQUENCE: `white-blood-count' is now INERT -- no rule in the corpus premises on
;;; it. It stays in context.lisp and in the bridge's parameter map because a clinician
;;; may still report it and the record should stay faithful, but it is marked inert in
;;; system-prompt.md and tools.json so the model never solicits it as a discriminating
;;; test. prompt-tests.lisp checks that marking in BOTH directions.
;;;
;;; COMPROMISED-GRAM-NEG-ROD-NARROWS-TO-PSEUDOMONAS (was 0.6) is GONE, merged into
;;; COMPROMISED-AEROBIC-GRAM-NEG-ROD-NARROWS-TO-OPPORTUNIST-RODS above. See the comment
;;; there: once gated on aerobicity its premises were byte-identical to the klebsiella
;;; rule's, and the two answered disjoint singletons.
;;;
;;; ------------------------------------------------------------------
;;; WHAT THIS SECTION SHOWED ABOUT THE REPRESENTATION
;;; ------------------------------------------------------------------
;;; Four of these rules now assert the SAME six-organism answer and differ only in
;;; belief. That is not an authoring failure; it is what the evidence says. Burn,
;;; compromised host, hospital acquisition and neutropenia are all associated with the
;;; same handful of organisms, and what genuinely differs between them is the RELATIVE
;;; likelihood of the members -- Pseudomonas rising in a burn, E. coli leading almost
;;; everywhere else.
;;;
;;; AN ANSWER SET CANNOT EXPRESS THAT. It can only say "one of these", and exclusion is
;;; the only mechanism it has for saying anything sharper. The singletons these rules
;;; used to assert were the representation's only available way to express "Pseudomonas
;;; is likelier here" -- and the price was a false claim that everything else was
;;; impossible. Widening removes the false claim and, with it, the corpus's ability to
;;; rank the members on epidemiological grounds at all.
;;;
;;; That trade is deliberate and is recorded in docs/category-b-resolution-survey.md
;;; section 5. Bench findings still rank organisms, because a bench finding genuinely
;;; does exclude. Epidemiology no longer pretends to.
