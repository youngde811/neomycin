# Welcome to Neomycin

> ## ⚠️ NOT FOR CLINICAL USE
> Neomycin is a research artifact. It is not a medical device, a decision aid,
> or a diagnostic tool, and it must never inform a health decision for any
> human or animal. Every certainty number, drug, dose, and susceptibility in it
> is illustrative — chosen to make the reasoning machinery legible, not
> measured from clinical data.

Neomycin is a hybrid symbolic/LLM engine for bacterial identification and therapy
selection: Claude as a natural-language clinical assistant in front of
[Lisa](https://github.com/youngde811/Lisa), a production-quality expert system shell
written in Common Lisp.

---

## Table of contents

1. [Introduction](#Introduction)
2. [The Historical Problem Neomycin Re-Opens](#The-Historical-Problem-Neomycin-Re-Opens)
3. [Project Purpose](#Project-Purpose)
4. [What Neomycin Is](#What-Neomycin-Is)
5. [The Architecture](#The-Architecture)
6. [The Symbolic Inference Engine](#The-Symbolic-Inference-Engine)
7. [Reasoning When You Are Not Sure](#Reasoning-When-You-Are-Not-Sure)
8. [The Conversation](#The-Conversation)
9. [Answering "Why?"](#Answering-Why)
10. [From Identification to Treatment](#From-Identification-to-Treatment)
11. [Neomycin is Actually Interesting](#Neomycin-is-Actually-Interesting)
12. [Real Versus Schematic](#Real-Versus-Schematic)
13. [What to Read Next](#What-to-Read-Next)

## Introduction

Neomycin began as a reconstruction of **MYCIN**, the Stanford medical expert system of
the 1970s, rebuilt on a modern Common Lisp rules engine and fitted with a conversational
front end powered by a large language model. It is no longer a reconstruction of it.

The system holds a body of medical knowledge as explicit **rules** — statements of the
form *if these findings hold, the organism is one of this set, and here is how strongly
I believe it.* A user describes a case in ordinary English. The language model turns
that description into structured facts, hands them to the rules engine, and then
explains what the engine concluded. The engine does all the reasoning and all the
arithmetic. The language model does none of it.

That division of labor is the point of the project. The model is good at
language and bad at being auditable. The engine is the reverse. Keeping them
strictly separate produces a system that can be talked to like a person and
inspected like a ledger.

## The Historical Problem Neomycin Re-Opens

**MYCIN** (Shortliffe, 1976) diagnosed bacterial infections of the blood and
recommended antibiotics. It was one of the first programs to perform at the
level of a human specialist in a narrow domain, and it did so by encoding
roughly 450 rules elicited from infectious-disease physicians.

Two things about MYCIN mattered more than its diagnoses.

**It could explain itself.** A physician could ask *why are you asking me this?*
or *how did you reach that conclusion?* and receive the actual chain of rules
that produced the answer. Explanation was not a feature bolted on afterward; it
fell out of the fact that the reasoning was made of inspectable parts.

**It reasoned under uncertainty.** Medicine rarely offers certainty, so MYCIN
attached a number to every conclusion — a *certainty factor* — and combined
those numbers as evidence accumulated.

MYCIN was never deployed. The reasons were partly practical (a mainframe login
was an absurd way to consult about a patient in 1976) and partly institutional.
Its architecture, however, was extracted into **EMYCIN** — "Essential MYCIN" —
a shell that separated the reasoning machinery from the medical content so the
same machinery could host other domains.

A few years later, William Clancey went further with a system called **NEOMYCIN**.
He observed that MYCIN's rules mixed two very different kinds of knowledge:
*what is true about the world* (gram-negative rods in burn patients suggest
pseudomonas) and *how a good diagnostician proceeds* (establish the broad
category first, then discriminate within it). Tangled together, neither could be
taught, reused, or reasoned about. Clancey pulled them apart.

This project takes its name from that separation, because that separation is its
whole architecture — with one substitution. Where Clancey wrote the diagnostic
strategy as an explicit second body of rules, Neomycin lets a language model
play that role.

## Project Purpose

Neomycin is not an attempt to build a better diagnostic tool. It is an
instrument for studying three questions.

**Can a language model serve as the strategic layer of a symbolic system
without contaminating it?** MYCIN decided what to ask next by working backward
from its hypotheses. That is a fine mechanism, but a rigid one. A language model
is unusually good at deciding what to ask next and at conducting a conversation
that feels natural. The open question is whether it can be given that job while
being structurally prevented from touching the reasoning itself.

**What does uncertainty look like when you model ignorance explicitly?**
Certainty factors compress everything into one number, so *no evidence either way* and
*strong evidence in both directions* end up looking identical. Dempster-Shafer keeps
them distinct, and Neomycin's rules are written for it: a rule states the **set** its
evidence narrows to, and what it declines to claim stays visible as ignorance.

> Neomycin once ran certainty factors and Dempster-Shafer over the same rules for
> comparison. It no longer can: a rule's answer is now a *set*, and certainty factors
> have no set algebra to reason over one. Both remain in the Lisa substrate for Lisa's
> own examples. The three-way comparison is reproducible on the `v0.10.0` tag and not
> after it — an honest casualty of the representation getting better.

**What does auditability cost, and what does it buy?** Every conclusion can be unwound
into the rules that produced it, what each of them answered, and the published sources
behind each rule's clinical claim. The system is built so that a narrated explanation is
a *quotation* of that record, not a reconstruction from memory. There is no arithmetic
chaining one belief through another to quote, because the representation has none.

The medical domain is a vehicle. The architecture is domain-agnostic: substitute
claims adjudication, underwriting, or equipment fault diagnosis and the shape of
the system is unchanged.

## What Neomycin Is

Neomycin began as a MYCIN/EMYCIN reconstruction and is no longer one. The divergence was not a
goal; it accumulated, one representational problem at a time, and it is now large enough
that comparing results against MYCIN's would be a category error. **This is not a claim
that Neomycin is better.** It answers different questions, and it answers them about a
corpus a fraction of MYCIN's size.

What changed, and why:

- **A rule states the SET its evidence narrows to**, not "this organism is more likely".
  Exclusion is never authored — it falls out when answers are intersected and nothing is
  left. There are no ruling-out rules and no negative beliefs anywhere in the corpus.
- **Epidemiological rules GRADE their answers.** A burn does not make Pseudomonas
  certain and Klebsiella impossible; it makes Pseudomonas likelier while excluding
  nothing. That is a mass function over several sets, and no single set can express it.
- **Dempster-Shafer over an open frame.** The set of possible organisms is never
  enumerated, so a pathogen the corpus cannot name keeps its plausibility instead of
  being silently excluded by omission.
- **No organism classes and no chaining.** A genus is a set, not a thing, and no belief
  is the product of two others.
- **A therapy phase MYCIN's illustration did not have**: an exact minimum-set-cover
  solver over a schematic drug knowledge base, with explicit policy dials and an opt-in
  site-local antibiogram overlay.
- **An LLM strategy layer with enforced separation.** The model conducts the interview
  and narrates; machinery — provenance records, `/why`, a queryable rule catalogue,
  guards over the prompt — makes it structurally hard for it to reason instead.

The rulebase is 46 rules against MYCIN's roughly 450, and every belief in it is a
schematic teaching figure. `:origin :paip-subset` on a rule still means what it says —
this association was inherited from the PAIP/EMYCIN illustration — but it does not make
the historical treatment of that rule authoritative.

## The Architecture

Four components, each with a job it does not share.

**Lisa.** A forward-chaining production rule engine written in Common Lisp,
using the Rete algorithm. It holds working memory and fires rules. Neomycin is a
fork of Lisa that keeps the engine's packages un-renamed: Neomycin *uses* Lisa
rather than absorbing it, though engine-level changes are made when the research
genuinely calls for them.

**The rulebase and belief system.** `neomycin/rules/` holds 44 medical rules in a
controlled vocabulary, grouped by cluster across a handful of files. Every one of them
is *confirming*: it states the set of organisms its evidence narrows the answer to.
Underneath sits a pluggable belief system — Dempster-Shafer over an open frame is
Neomycin's, and certainty factors and a per-hypothesis Dempster-Shafer remain in the
Lisa substrate for its own examples.

**The bridge.** A small HTTP service that runs inside the same Lisp image as the
engine. It exposes the engine's capabilities as a handful of web endpoints:
assert a fact, run inference, retrieve conclusions, retrieve the rule trace, ask
which rules are close to firing, ask why a conclusion holds, request a therapy
recommendation, and reset the session. The bridge is deliberately thin. It
validates and translates; it does not reason. Its purpose is to make the Lisp
image reachable from a process that is not Lisp — in practice, a Python client —
without either side needing to know much about the other.

**The driver.** A Python program that connects a Claude model to the bridge
using tool-use. The model is given a description of the bridge's capabilities
and the engine's fact vocabulary, and is permitted to call those capabilities as
tools. Everything the model learns about the case comes back through those
calls.

The important structural property is that the model has no path to the answer
except through the engine. It cannot compute a belief, because there is no tool
that lets it write one; it can only assert facts, ask the engine to run, and
read what came back.

---

## The Symbolic Inference Engine

A **rule** pairs a set of conditions with a conclusion. Here is one (slightly elided) from the Neomycin rulebase:

```lisp
(defrule burn-blood-aerobic-gram-neg-rod-narrows-to-opportunist-rods
    (:belief 0.4
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.27 (Pseudomonas), NBK8326"
                             "NCBI Bookshelf / StatPearls, Pseudomonas aeruginosa Infections, NBK557831"
                             "Highly Drug-Resistant Pathogens Implicated in Burn-Associated Bacteremia, PMC4128596"
                             "Gram-Negative Bacilli Blood Stream Infection in Patients with Severe Burns: a 9-Year Cohort, PMC11476612")
                  :belief-basis :illustrative
                  :note "Pseudomonas aeruginosa is a classic cause of bacteraemia in seriously burned patients, but it is not the only one..."))
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
```

The conclusion is worth a second look, because it is not what most rule engines
assert. The rule does **not** say "this is Pseudomonas". It says *"one of these four
organisms, and here is how my confidence is spread across them"* — 0.20 on
Pseudomonas, 0.07 on Klebsiella, 0.05 on Enterobacter, 0.08 on E-Coli, Proteus and Serratia.
A burn makes Pseudomonas likelier. It does not make Klebsiella impossible.

The clauses in the middle are patterns matched against **working memory**, the
set of facts asserted so far. The `?o`, `?c`, and `?p` are variables: they bind
to whatever satisfies the first pattern and must then match consistently
throughout, which is how the rule insists that the blood culture, the organism
growing in it, and the burned patient are all the same case rather than three
unrelated facts. The final clause asserts a new fact.

The `:belief 0.4` says how much this rule's firing should move confidence in its
conclusion. The `:provenance` block records where the rule came from and which
published sources support the clinical association, and marks the belief value
itself as illustrative — a machine-readable field that the explanation facility
later reads back.

**Forward chaining** means the engine works from facts toward conclusions. When
a new fact arrives, the engine finds every rule whose conditions are now
satisfied and fires it, which may assert further facts, which may satisfy
further rules. It runs until nothing more can fire. This is the opposite of
MYCIN's original approach, which started from a hypothesis and worked backward
looking for supporting facts.

**Rete** is the algorithm that makes forward chaining efficient. The naive
implementation re-tests every rule against every fact on every cycle, which is
quadratic and unusable at scale. Rete instead compiles the rules into a network
that stores partial matches — the intermediate state of every rule that is
partway to firing. Asserting a fact updates only the affected parts of that
network. The engine trades memory for time, and the payoff is that the cost of
adding a fact is proportional to what that fact actually affects.

That stored partial-match state turns out to have a second use, and it is the
one Neomycin cares about most. Because the network already knows which rules are
one condition short of firing, the engine can be asked directly: *what single
additional fact would let something new conclude?* That question is what
`/partial-matches` answers, and it is how a forward-chaining engine recovers the
goal-directed behavior — knowing what to ask next — that MYCIN got from backward
chaining. It is not a workaround. It is the same information, read off a
structure that already existed.

Rules are given descriptive names, as in the example above, so that a trace of
what fired reads as clinical prose rather than as a list of identifiers. That
matters when the trace is going to be narrated back to a person.

---

## Reasoning When You Are Not Sure

This section assumes no probability background. The two systems below are both
ways of answering: *given several pieces of imperfect evidence, how confident
should I be?*

### Certainty factors: A Single Number

MYCIN's original scheme attaches a single number between −1 and +1 to each
hypothesis. Positive means the evidence supports it; negative means the evidence
argues against it; zero means nothing is known.

The interesting part is how two independent confirmations combine. Suppose one
rule contributes 0.4 and another contributes 0.6. The result is not 1.0, and it
is not their average. It is **0.76**, and the reasoning is intuitive: after the
first rule you are 0.4 convinced, so 0.6 of your doubt remains. The second rule
claims 0.6 of what is left, which is 0.36. Add that to the 0.4 you already had
and you get 0.76. Each new piece of evidence takes a bite out of the remaining
doubt, so confidence approaches 1.0 without ever arriving.

The scheme's weakness is that one number cannot say two different things. A
hypothesis about which nothing is known and a hypothesis with strong evidence on
both sides both land near zero, and the system cannot distinguish them. In
medicine that distinction is exactly the one you want.

### Dempster-Shafer: Two Numbers and the Gap Between Them

Dempster-Shafer theory replaces the single number with a pair, written
`[bel, pl]`.

- **`bel`** — short for *belief* — is the evidence that positively commits to the
  hypothesis. Read it as a floor: *at least this much supports it.*
- **`pl`** — short for *plausibility* — is one minus the evidence committed
  against the hypothesis. Read it as a ceiling: *at most this much room is left
  for it to be true.*
- The gap between them, `pl − bel`, is **ignorance**: evidence that has not been
  committed either way, or simply evidence you do not have.

A hypothesis nobody has said anything about sits at `[0, 1]` — a floor of zero,
a ceiling of one, and complete ignorance in between. That is a genuinely
different statement from "the evidence balances out," and it is the distinction
certainty factors cannot make.

The mechanics are easier than the notation suggests, and in neomycin they rest on a
single idea: **a rule states the set of organisms its evidence narrows the answer to.**
The Gram stain says "one of these eight". The aerobic result says "one of these seven".
The burn and the compromised host say "Pseudomonas". Each of those is an answer, with a
weight, and answers combine by **intersection** — the organisms that survive are the
ones in every answer.

That single mechanism does all the work, including the work that looks like it needs
something else:

- **Exclusion is never written down.** `{pyogenes, agalactiae}` intersected with
  `{pneumoniae}` is empty, and that emptiness *is* the ruling-out. No rule ever argues
  against an organism, and no rule can.
- **A genus is just a set.** "Is this a staphylococcus?" is a question about
  {aureus, epidermidis, saprophyticus}, answered directly. Nothing chains, and no
  belief is the product of two others.
- **Belief committed to one organism is belief unavailable to its rivals**, so evidence
  for one lowers the ceiling on the others automatically. An organism nobody has
  mentioned can still be effectively excluded.
- **Belief that lands on an impossible combination is the conflict**, `K` — and it is
  reported with a companion, the **margin**, because `K` alone does not mean what it
  looks like it means. Two answers naming different organisms are incompatible
  *totally*, so `K` counts how much rival evidence was **overruled**, and it therefore
  climbs as the winning side strengthens. A high `K` can describe a case that is
  perfectly clear-cut. The margin — how far the leading answer sits above the nearest
  answer that contradicts it — is what says whether the disagreement resolved.

The frame is **open**. The system never enumerates every organism that exists — only
the sets its rules actually name. So the question *"could this be something you don't
model?"* has a real answer rather than an embarrassed silence: it is the belief that
has not been committed anywhere, and the system will quote it.

### Why the Difference is Worth Building

Here is a case with three lab findings: the organism ferments lactose, tests
indole-positive, and produces a red pigment on the plate. Lactose and indole together
point to *E. coli*. Red pigment points to *Serratia*. One organism cannot be both.

Nothing in the rulebase says so. There is no rule anywhere that argues against E. coli
or against Serratia — the corpus contains no such rule and cannot express one. The
findings simply give answers that do not overlap, and the arithmetic does the rest:

| Organism | belief (floor) | plausibility (ceiling) |
|---|---|---|
| E. coli | 0.670 | 0.758 |
| Serratia | 0.242 | 0.303 |

with **conflict `K` = 0.736** and a **margin of 0.427**.

Read the ceilings first. Both have fallen well below 1.0, which is the signature of
genuine contradiction; in an ordinary case where the evidence agrees, both would sit at
1.0. E. coli leads because three answers admit it and only one admits Serratia. But
**nearly three quarters of the belief in this case landed on a combination that cannot
be true**, and the two specific answers driving it — `{e-coli}` at 0.80 and
`{serratia}` at 0.80 — are *equally* strong and cannot both hold. The right thing to
tell a clinician is not "E. coli, 67%"; it is that the bench results contradict each
other and should be repeated.

The margin is what licenses reading it that way, and it is worth seeing the contrast.
A burn-ICU case elsewhere in this project runs `K = 0.557` — comparably high — with a
margin of **0.740**, and there the answer is simply Pseudomonas: one specific answer at
0.93 against a rival at 0.60, decisively overruled. Same shape of number, opposite
meaning. Here the margin is 0.427 and the two specific answers are tied, so the high
`K` is what it appears to be. **Neither figure is interpretable alone**; the pair is.

That is the property worth building for. A system that reports its own inputs disagree
is more useful than one that smooths the disagreement into a confident-looking average
— and here the disagreement is not a special feature bolted on, but a consequence of
representing an answer as a set.

Contrast the case where the evidence *agrees*: a chain-forming gram-positive coccus,
alpha-hemolytic, optochin-sensitive. Three answers, each nested inside the last, all
naming *S. pneumoniae*. It reaches `bel 0.963` with `pl 1.000` and **`K` = 0** — higher
than any single rule's own weight, purely because independent evidence converged. Same
machinery, opposite reading.

---

## The Conversation

Here is a hypothetical consultation, from the user's first sentence to the system's
answer. The user types into a prompt; nothing else is involved.

**A person describes a case in ordinary English.** For example: a patient with
serious burns and a compromised immune system has an aerobic gram-negative rod
growing in a three-day-old blood culture, and what organism is this?

**The model translates that into structured facts.** It has been told the exact
fact vocabulary the engine understands — which attributes exist, which values
are legal, which entities facts attach to — and it maps the free text onto that
vocabulary. Severe burns become a fact about the patient. Gram-negative and
rod-shaped become facts about the organism. Each is submitted individually
through the bridge, and the bridge validates it before it enters working memory.
Malformed facts are rejected there, not silently absorbed.

**The model asks the engine to run.** The engine fires every rule whose conditions are
met, each one asserting the set of organisms its evidence narrows the answer to, and
records which rules said what.

**The model reads back what concluded.** For the case above, a three-way
differential: *E. coli* at belief 0.232 with plausibility 0.564, *pseudomonas* at
0.176 / 0.468, and *klebsiella* at 0.165 / 0.458. Nothing reaches plausibility 1.0,
because belief supporting one organism is belief the others cannot also have — and
nothing has been *excluded* either, because the only evidence so far is a stain and
two facts about the patient. A further 0.234 sits on the *set* of seven aerobic
gram-negative rods without naming a member: the honest statement that the family is
better established than any species in it, and often the right headline. `K` = 0.180
records the belief that went to combinations which cannot all hold.

The reading a clinician should take from this is that **the culture has not been
discriminated yet.** A burn raises Pseudomonas and an immunocompromised host raises
E. coli, and the engine says both — but epidemiology ranks organisms, it does not
identify one. A lactose or indole result would. An earlier version of this rulebase
returned pseudomonas at 0.613 here and looked far more decisive; it reached that
number by asserting that a burn made Klebsiella, E. coli, Enterobacter, Serratia and
Proteus *impossible*, which is not true and is not what burn-unit surveillance data
say. The smaller numbers are the more honest ones.

**The model narrates the result.** It reports the differential, the beliefs, and
the reasoning — all of it read from the engine rather than composed.

Three details in that flow deserve emphasis.

**The model conducts an interview, not a form.** If the case description leaves
out something the engine needs, the model asks for it in natural language. It
decides what to ask by consulting the engine's partial-match state — the rules
that are one fact short of firing — so its questions are the ones that would
actually change a conclusion. This is the clinician's-assistant role: the model
manages the dialogue, notices what is missing, asks in ordinary language, and
keeps the conversation coherent across turns. What it never does is decide
anything about the case.

**Uncertainty in the input is carried, not flattened.** A person who says "I
think the stain was gram-positive" is not making the same claim as one who says
"the stain was gram-positive." The model attaches a reduced confidence to the
asserted fact, and the engine's belief arithmetic carries that reduction through
to every conclusion downstream.

**Evidence of different sharpness combines without any of it being scaffolding.** An
aerobic gram-negative rod answers "one of these seven". A lactose result narrows to four
of them. Indole narrows to two. The combination that names *E. coli* answers with one.
Those are four answers at four resolutions, and because each set contains E. coli they
*agree* — they reinforce to 0.884, higher than any single rule's own weight, with
conflict zero.

The coarse answers are conclusions in their own right, not way-stations. "One of these
seven, the evidence does not say which" is frequently the most honest thing the system
can report, and it is reported rather than discarded on the way to a species. Nothing
chains, nothing is scaffolding, and no belief is the product of two others.

## Answering "Why?"

Explanation was MYCIN's signature capability, and reproducing it faithfully is a
substantial part of this project.

The naive way to explain a language model's answer is to ask the model. That
produces fluent, plausible text with no reliable connection to what actually
happened. Neomycin does something structurally different.

Two records are kept. Each rule carries **provenance**: where the rule came from
(inherited from the historical MYCIN corpus, or added by this project) and which
published sources support its clinical claim, each citation checked
adversarially rather than accepted on the model's say-so. Separately, the engine
records which rules produced each answer as they fire.

The bridge composes both into a single answer: the **argument**. Asked why an organism
stands where it does, it returns every answer given about that culture — the set each
one narrowed to, its weight, the rules that said it, and their sources — together with
what those answers intersect to.

It also returns the answers that do **not** admit the organism, and that is the
load-bearing part. Since nothing in this corpus argues against anything, an organism can
only lose ground because other evidence pointed somewhere else. An explanation showing
only the supporting answers would leave a reader to assume an objection that does not
exist.

So when a user asks *why Klebsiella, and how sure are you?*, the model does not answer
from memory. It requests the argument and reads it aloud: three answers admit Klebsiella
— the Gram stain narrowing to eight organisms at 0.70, the aerobic rod finding to seven
at 0.80, the compromised-host rule to Klebsiella alone at 0.50 — and together they leave
Klebsiella. What holds it down is the burn and blood-culture evidence answering
"Pseudomonas" at 0.76, which does not include Klebsiella. Nothing argued against it.
There is no arithmetic composing one belief through another to quote, because nothing
chains. And it reports the boundary the record itself encodes — that the
sources verify the *clinical association*, not the *number*, and that the rule
weights are illustrative teaching values rather than measured frequencies.

That last behavior is the one worth dwelling on. The model declines to present a
schematic number as a measured one, because the engine's own record says which
it is. The honesty is a property of the architecture, not of the model's
disposition.

## From Identification to Treatment

Identifying the organism is half a consultation. The other half is deciding what
to treat with, and Neomycin handles it with the same separation of
responsibilities.

Treatment selection is posed as a **covering problem**. Every organism whose
belief clears a threshold must be covered by at least one drug the patient can
actually take, and the regimen should use as few drugs as possible.

This is a classic set-cover problem. Finding the true optimum is computationally
hard in general, but not at this scale — eleven drugs and a handful of organisms —
so Neomycin searches **exhaustively**: it finds every smallest regimen that covers
the case, then picks among them by a stated rule. Drugs the patient cannot take are
excluded up front, with the reason recorded. Any organism no available drug can
cover is reported as uncovered rather than quietly dropped. A greedy solver is kept
alongside, and the test suite checks the two agree.

**Fewest drugs is not the same as narrowest drugs**, and the difference turned out to
matter more than we expected. Using fewer drugs is good; reaching for a
broad-spectrum agent when a narrow one would do is the thing that drives resistance.
Those are separate goals, and an early version of this system conflated them: its
code claimed to practise antimicrobial stewardship while actually optimising drug
count alone. Because the broadest agents also carry the best coverage numbers, that
objective reached for a last-line carbapenem almost every time — and, in a recorded
session, told a clinician who asked for something narrower that no narrower option
existed. Five did.

So the choice is now a **dial you can turn**, alongside the ones for the belief
system and for how much certainty to demand. One setting reproduces the original
behaviour, honestly labelled. The other prefers narrow-spectrum agents. The same case
under both settings gives two defensible answers, and the system reports what each
one gave up: the narrower agent usually has a lower, and less certain, chance of
working.

The dial is also allowed to be visibly wrong. On one case the narrow-spectrum setting
picks a *reserve* antibiotic — the kind held back precisely so it keeps working —
because it can see how broad a drug is but not how precious. That could have been
quietly patched. It wasn't, because a research instrument that shows you where its
reasoning runs out is worth more than one tidied until it looks authoritative.

Every regimen also lists **what it did not choose**: the other drugs that would have
covered the case, and the other equally small regimens that lost on the tiebreak. A
recommendation that shows only its winner invites the reader to assume there was no
alternative, which is how the false answer above came to be given in the first place.

Susceptibilities — how well a given drug works against a given organism — are
themselves belief-valued, not booleans, and they can be refined by a **site-local
antibiogram**: the record of how many isolates on this particular ward actually
proved susceptible to this drug.

That refinement is where a small amount of statistics earns its place, and it
can be stated in words. Suppose the local lab tested 10 isolates and 7 were
susceptible. The optimistic reading is 7 in 10. The pessimistic reading is also
7 in 10. But you have only tested 10 — so imagine a couple of additional tests
whose outcomes you never saw. A pessimist assumes those unseen tests all failed;
an optimist assumes they all succeeded. Those two assumptions give you a floor
and a ceiling, and the gap between them is exactly the ignorance that comes from
a small sample. Test 500 isolates instead of 10 and the two imagined extra tests
barely move either bound, so the interval tightens on its own. No separate
confidence machinery is needed: sample size and ignorance are the same quantity.

The local interval is then pooled with the curated figure from the knowledge
base, so local resistance can pull coverage down and solid local data can
promote a drug the curated knowledge base was unsure about. Every susceptibility
carries its own provenance — where the number came from, and how many isolates
stand behind it — so the model can narrate that too.

The rule that governs the whole phase is the same one that governs
identification: the solver chooses the drugs, and the model explains the choice.
The model never picks a drug.

## Neomycin is Actually Interesting

Set the medicine aside. What remains is a pattern with three properties that are
hard to get at the same time.

**A natural-language interface over a system of record that stays authoritative.**
Most attempts to put a language model in front of a decision system end up
letting the model make decisions, because the boundary is a matter of prompting
and prompting is not a boundary. Here the boundary is structural: the model's
only available actions are to submit facts, invoke the engine, and read results.
There is no tool through which it could score a hypothesis, so it cannot, and no
amount of clever prompting changes that.

**Explanation that is a quotation rather than a reconstruction.** The system does
not ask the model to explain the answer. It asks the engine for the derivation
and has the model read it aloud. The difference matters most in exactly the
settings where explanation is legally or ethically required, because a
reconstructed explanation can be fluent and wrong in ways nobody can detect from
the text.

**Uncertainty that stays legible instead of collapsing.** Conflicting evidence
produces a visibly wider, lower interval rather than a confident-looking average.
A system that can tell you *its own inputs disagree* is more useful than one
that smooths the disagreement away, and it is the kind of signal that any serious
adjudication process wants surfaced.

There is also a historical argument. Expert systems were declared a dead end,
and the reasons given were real: knowledge acquisition was expensive, and the
interfaces were unusable. Both of those failures were about the *human edges* of
the system — getting knowledge in, and getting explanations out — not about the
inference core, which worked. Language models are unusually good at exactly
those edges. Neomycin is a test of the resulting hypothesis: that the symbolic
core was never the problem, and that pairing it with a model that handles the
edges produces something neither approach reaches alone. The engine keeps the
model honest, and the model makes the engine usable.

## Real Versus Schematic

Being clear about this is part of the project's purpose.

**Real:** the inference engine, the belief algebra and its arithmetic, the set
intersection and the conflict behavior, the explanation and provenance records, the
therapy solver and its guarantees, the antibiogram mathematics, the release gate that
checks the model's narration against the payloads it was actually given
(`bin/release-check.py` — every quoted number must appear in something the engine
returned), and the test suite —
roughly 1589 assertions across 197 tests, including every rule fired in isolation,
hand-verified golden values for each scenario, and corpus-wide invariants checked by
introspecting the compiled rulebase so that a new rule is covered the moment it is
written.

**Schematic:** the certainty numbers. Every rule weight is a teaching value, chosen to
make the machinery observable, and each is explicitly marked as such in its own
provenance record. The published citations attached to a rule verify that the clinical
association is real; they do not verify the number.

> Grounding those numbers in real frequency data is **deliberately not being done.**
> Illustrative is the honest state, and stating it loudly is better than a set of
> numbers that look measured and are not. What *has* been done is narrower and worth
> distinguishing: making the numbers consistent **with each other**, so that (for
> instance) a rule cannot commit less than a more general rule it displaces. That is a
> coherence property, not a calibration claim.

**Also schematic:** the drug knowledge base, its doses, its susceptibilities, and its
contraindications. The rulebase is 46 rules against MYCIN's original 450 — enough to
exercise every mechanism in the architecture, and nowhere near enough to be clinically
meaningful. It can name **17 organisms**; a real differential is not 17 organisms wide.

**Redundant evidence, and why one rule can speak for several.** Four of the
gram-negative epidemiological rules rest on the same underlying statistics — they are
one fact reported four times, under four labels. Combining them would count that fact
repeatedly: a patient who was both immunocompromised and neutropenic saw the leading
organism's belief inflated *and* the reported conflict inflated, between two rules that
agreed. They are now declared as a single **evidence group**, and only the most
committed member contributes; the rest are dropped before combination and are absent
from the explanation as well as the arithmetic. Contexts that genuinely differ — a burn,
a tropical journey — carry their own distributions, are in no group, and still combine
normally. Measured and analysed in `docs/base-rate-investigation.md`.

This is worth reading as an instance of a general problem rather than a local fix:
Dempster's rule assumes the evidence you combine is independent, and a knowledge base
assembled from overlapping literature will quietly violate that. The corpus now declares
the dependence rather than hoping it does not matter, and two invariants check the
declaration from both directions.

---

## What to Read Next

| Document | What it covers |
|---|---|
| [`getting-started.md`](./getting-started.md) | Building, running, and testing; how to read the output |
| [`runbook.md`](./runbook.md) | A guided tour of a full identification consultation |
| [`therapy-demo.md`](./therapy-demo.md) | The treatment phase, end to end |
| [`clinician-scenarios.md`](./clinician-scenarios.md) | Worked cases exercising the rulebase and the antibiogram overlay |
| [`why-how-provenance-design.md`](./why-how-provenance-design.md) | The design of the explanation facility |
| [`antibiogram-overlay-design.md`](./antibiogram-overlay-design.md) | The site-local susceptibility mathematics |
| [`rule-catalogue-design.md`](./rule-catalogue-design.md) | Why the rulebase is queried rather than described to the model |
| [`demo-runsheet.md`](./demo-runsheet.md) | A 15-minute live demonstration script |
| [`CLAUDE.md`](../CLAUDE.md) | Build notes and the layout of the codebase |

**References.**

- Shortliffe, E. H. (1976), *Computer-Based Medical Consultations: MYCIN*
- Buchanan, B. G. and Shortliffe, E. H. (1984), *Rule-Based Expert Systems*
- Clancey, W. J. (1987), *Knowledge-Based Tutoring: The GUIDON Program*
- Shafer, G. (1976), *A Mathematical Theory of Evidence*
- Norvig, P. (1992), *Paradigms of Artificial Intelligence Programming*, chapter 16, whose forward-chaining translation
  of the MYCIN rules this rulebase follows
