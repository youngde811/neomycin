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

;;; WAS lactose-fermenter-argues-against-non-fermenters (excluded salmonella, proteus).
;;; Serratia is a slow/variable lactose reactor and is deliberately kept in.
(defrule lactose-fermenter-narrows-to-fermenters
    (:belief 0.7
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Enterobacteriaceae), NBK8035"
                             "NCBI Bookshelf / StatPearls, Proteus mirabilis Infections, NBK442017")
                  :belief-basis :illustrative
                  :note "Lactose fermentation on MacConkey is the standard teaching discriminator. Salmonella and Proteus are characteristic non-fermenters; Serratia is a slow and variable reactor and is deliberately kept in, since the marker is not clean for it."))
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
    (:belief 0.6
     :provenance (:origin :neomycin-extrapolation
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.26 (Enterobacteriaceae), NBK8035"
                             "NCBI Bookshelf / StatPearls, Escherichia coli Infection, NBK564298")
                  :belief-basis :illustrative
                  :note "The reciprocal. Serratia is kept in for the same reason -- a slow or variable lactose reaction makes the marker unreliable for it in either direction. PSEUDOMONAS IS IN THIS ANSWER: it is the textbook non-lactose-fermenter, the standard contrast to the Enterobacteriaceae. Omitting it was a conversion defect -- the rule this replaced argued AGAINST the fermenters and never had to say what a non-fermenter positively is, so the complement was taken within the Enterobacteriaceae rather than within the gram-negative rods the corpus models. A lactose-negative reading then CONFLICTED with a Pseudomonas case it is in fact consistent with."))
  (organism (id ?o))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
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
                             "J Clin Microbiol (indole-positive vs indole-negative Klebsiella identification), PMC1594763")
                  :belief-basis :illustrative
                  :note "Klebsiella, Enterobacter, Salmonella and Serratia are characteristically indole-negative. Proteus stays IN: P. mirabilis is indole-negative while P. vulgaris is indole-positive, so the marker is ambiguous for the genus -- honest scoping the pre-v0.11 rule already made, and which survives the rewrite unchanged."))
  (organism (id ?o))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (indole (value positive) (of ?o))
  =>
  (assert (candidates (value '(:e-coli :proteus)) (of ?o))))

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
  (lactose (value fermenter) (of ?o))
  (indole (value negative) (of ?o))
  (motility (value motile) (of ?o))
  =>
  (assert (candidates (value '(:enterobacter :serratia)) (of ?o))))

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
                  :note "Pseudomonas aeruginosa is a classic cause of bacteraemia in seriously burned patients."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (culture-site (value blood) (of ?c))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (burn (value serious) (of ?p))
  =>
  (assert (candidates (value '(:pseudomonas)) (of ?o))))

(defrule compromised-gram-neg-rod-narrows-to-pseudomonas
    (:belief 0.6
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf / StatPearls, Pseudomonas aeruginosa Infections, NBK557831"
                             "NCBI Bookshelf, Medical Microbiology 4th ed. ch.27 (Pseudomonas), NBK8326")
                  :belief-basis :illustrative
                  :note "Pseudomonas aeruginosa is a major opportunist in the immunocompromised host."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
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