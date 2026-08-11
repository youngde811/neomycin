# Welcome to Neomycin

Neomycin is a hybrid symbolic/LLM engine designed to mimic and extend the capabilities of the original MYCIN expert
system, using Claude as a natural language clinical assistant in front of [Lisa](https://github.com/youngde811/Lisa), a
production-quality expert system shell written in Common Lisp.

> ## ⚠️ NOT FOR CLINICAL USE
> Neomycin is a research artifact. It is not a medical device, a decision aid,
> or a diagnostic tool, and it must never inform a health decision for any
> human or animal. Every certainty number, drug, dose, and susceptibility in it
> is illustrative — chosen to make the reasoning machinery legible, not
> measured from clinical data.

---

## Table of contents

1. [The short version](#the-short-version)
2. [The historical problem Neomycin re-opens](#the-historical-problem-Neomycin-re-opens)
3. [What the project is actually for](#what-the-project-is-actually-for)
4. [The architecture in one pass](#the-architecture-in-one-pass)
5. [The rules engine, for software engineers](#the-rules-engine-for-software-engineers)
6. [Reasoning when you are not sure](#reasoning-when-you-are-not-sure)
7. [The conversation, end to end](#the-conversation-end-to-end)
8. [Answering "why?"](#answering-why)
9. [From identification to treatment](#from-identification-to-treatment)
10. [Why this is interesting as computer science](#why-this-is-interesting-as-computer-science)
11. [What is real and what is schematic](#what-is-real-and-what-is-schematic)
12. [Where to read next](#where-to-read-next)

---

## The short version

Neomycin is a working reconstruction of **MYCIN**, the Stanford medical expert
system of the 1970s, rebuilt on a modern Common Lisp rules engine and fitted
with a conversational front end powered by a large language model.

The system holds a body of medical knowledge as explicit **rules** — statements
of the form *if these findings hold, then this organism is more likely*. A user
describes a case in ordinary English. The language model turns that description
into structured facts, hands them to the rules engine, and then explains what
the engine concluded. The engine does all the reasoning and all the arithmetic.
The language model does none of it.

That division of labor is the point of the project. The model is good at
language and bad at being auditable. The engine is the reverse. Keeping them
strictly separate produces a system that can be talked to like a person and
inspected like a ledger.

---

## The historical problem Neomycin re-opens

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

---

## What the project is actually for

Neomycin is not an attempt to build a better diagnostic tool. It is an
instrument for studying three questions.

**Can a language model serve as the strategic layer of a symbolic system
without contaminating it?** MYCIN decided what to ask next by working backward
from its hypotheses. That is a fine mechanism, but a rigid one. A language model
is unusually good at deciding what to ask next and at conducting a conversation
that feels natural. The open question is whether it can be given that job while
being structurally prevented from touching the reasoning itself.

**What does uncertainty look like when you model ignorance explicitly?**
Certainty factors compress everything into one number, which means *no evidence
either way* and *strong evidence in both directions* end up looking identical.
Dempster-Shafer theory keeps them distinct. Neomycin runs both systems over the
same rules so the difference can be observed rather than argued about.

**What does auditability cost, and what does it buy?** Every conclusion the
system produces can be unwound into the rules that produced it, the arithmetic
that combined them, and the published sources behind each rule's clinical
claim. The system is built so that a narrated explanation is a *quotation* of
that record, not a reconstruction from memory.

The medical domain is a vehicle. The architecture is domain-agnostic: substitute
claims adjudication, underwriting, or equipment fault diagnosis and the shape of
the system is unchanged.

---

## The architecture in one pass

Four components, each with a job it does not share.

**Lisa.** A forward-chaining production rule engine written in Common Lisp,
using the Rete algorithm. It holds working memory and fires rules. Neomycin is a
fork of Lisa that keeps the engine's packages un-renamed: Neomycin *uses* Lisa
rather than absorbing it, though engine-level changes are made when the research
genuinely calls for them.

**The rulebase and belief system.** `neomycin/rules/` holds 50 medical rules in a
controlled vocabulary, grouped by cluster across a handful of files. Underneath sits
a pluggable belief system — either Dempster-Shafer (the default) or certainty
factors — that decides how confidence is represented and combined.

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

## The rules engine, for software engineers

A **rule** pairs a set of conditions with a conclusion. Here is one, lightly
trimmed, from the Neomycin rulebase:

```lisp
(defrule gram-neg-rod-in-burn-patient-suggests-pseudomonas
    (:belief 0.4
     :provenance (:origin :paip-subset
                  :evidence ("NCBI Bookshelf, Medical Microbiology 4th ed. ch.27 ..."
                             "NCBI Bookshelf / StatPearls, Pseudomonas aeruginosa ...")
                  :belief-basis :illustrative
                  :note "Pseudomonas aeruginosa is a leading cause of wound ..."))
  (organism (id ?o) (culture ?c))
  (culture (id ?c) (patient ?p))
  (culture-site (value blood) (of ?c))
  (gram (value neg) (of ?o))
  (morphology (value rod) (of ?o))
  (burn (value serious) (of ?p))
  =>
  (assert (organism-identity (value :pseudomonas) (of ?o))))
```

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

## Reasoning when you are not sure

This section assumes no probability background. The two systems below are both
ways of answering: *given several pieces of imperfect evidence, how confident
should I be?*

### Certainty factors: one number

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

### Dempster-Shafer: two numbers and the gap between them

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

The mechanics are easier than the notation suggests. Picture one unit of belief
divided into three buckets: the part that supports the hypothesis, the part that
opposes it, and the part that has not committed to either. `bel` is the first
bucket. `pl` is the first plus the third. Combining two pieces of evidence means
combining their buckets and renormalizing — and the amount of belief that lands
in contradictory places is called the **conflict**. When conflict is present,
the combined interval visibly widens and drops.

Neomycin restricts the theory to a single hypothesis and its negation, a
standard simplification that keeps combination cheap while remaining faithful
Dempster-Shafer on that frame.

### Why the difference is worth building for

The rulebase contains **confirming** rules, which push belief up, and
**disconfirming** rules, which commit evidence against a hypothesis. Among the
enterobacteriaceae — a family of related bacteria — several disconfirming rules
express *biochemical cross-disconfirmation*: a lab finding that argues for one
sibling species inherently argues against another, because one organism cannot
have both properties.

Here is what that produces in practice. A case is described with three lab
findings: the organism ferments lactose, tests indole-positive, and produces a
red pigment on the plate. Lactose and indole together point to *E. coli*. The
red pigment points to *Serratia*. But the red pigment argues against E. coli,
and the indole result argues against Serratia. The engine reports:

| Organism | belief (floor) | plausibility (ceiling) |
|---|---|---|
| E. coli | 0.26 | 0.41 |
| Serratia | 0.375 | 0.625 |

Notice that both ceilings have fallen below 1.0, which is the signature of
genuine conflicting evidence — in an ordinary case with only confirming
evidence, both would sit at 1.0. Notice also that E. coli's *ceiling* (0.41) is
now beneath Serratia's *floor* (0.375, and rising toward 0.625). The engine has
not quietly averaged the contradiction away. It has made the contradiction
visible in its own arithmetic, and it can say which finding caused it.

Certainty factors, run over the same case, cannot express this. Both systems are
kept in the codebase precisely so the two answers can be laid side by side.

---

## The conversation, end to end

Here is a full consultation, from the user's first sentence to the system's
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

**The model asks the engine to run.** The engine fires every rule whose
conditions are met, propagates belief through the chains, and records what
happened.

**The model reads back what concluded.** For the case above, two candidates:
*pseudomonas* at belief 0.76, and *klebsiella* at belief 0.40. Both have
plausibility 1.0, because nothing in the case argues against either.

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

**Belief composes through chains.** Some conclusions are reached in more than
one step. An aerobic gram-negative rod first establishes the *enterobacteriaceae
family* as an intermediate classification; specific species are then
discriminated within that family by biochemical findings. A species conclusion
therefore inherits its family's uncertainty: if the family is held at 0.8 and
the species rule contributes 0.8, the species lands at 0.64, because you cannot
be more confident in the species than the family it belongs to. The family
itself is never reported as an identity — it is scaffolding, and the system says
so.

---

## Answering "why?"

Explanation was MYCIN's signature capability, and reproducing it faithfully is a
substantial part of this project.

The naive way to explain a language model's answer is to ask the model. That
produces fluent, plausible text with no reliable connection to what actually
happened. Neomycin does something structurally different.

Two records are kept. Each rule carries **provenance**: where the rule came from
(inherited from the historical MYCIN corpus, or added by this project) and which
published sources support its clinical claim, each citation checked
adversarially rather than accepted on the model's say-so. Separately, the engine
records the **derivation** of every belief as it fires — the actual arithmetic
that combined one number with another to produce a third.

The bridge composes both into a single answer. Asked why an organism was
concluded, it returns the composition arithmetic behind that belief, walked
recursively back through any intermediate steps, together with the sources
behind each rule that participated.

When a user asks *why pseudomonas, and how sure are you about 0.76?*, the model
does not answer from memory. It requests the explanation and quotes it: a prior
of 0.400 combined with a 0.600 rule to give 0.760, from these two rules, citing
these sources. And it reports the boundary the record itself encodes — that the
sources verify the *clinical association*, not the *number*, and that the rule
weights are illustrative teaching values rather than measured frequencies.

That last behavior is the one worth dwelling on. The model declines to present a
schematic number as a measured one, because the engine's own record says which
it is. The honesty is a property of the architecture, not of the model's
disposition.

---

## From identification to treatment

Identifying the organism is half a consultation. The other half is deciding what
to treat with, and Neomycin handles it with the same separation of
responsibilities.

Treatment selection is posed as a **covering problem**. Every organism whose
belief clears a threshold must be covered by at least one drug the patient can
actually take. Prescribing fewer drugs is better, because unnecessary
broad-spectrum use drives resistance — so the objective is the smallest set of
drugs that covers everything.

This is a classic set-cover problem, and finding the true optimum is
computationally hard in general. Neomycin uses a **greedy solver**: repeatedly
take the drug that covers the most still-uncovered organisms, with ties broken
deterministically so that the same case always yields the same regimen. Drugs
the patient cannot take are excluded up front, with the reason recorded. Any
organism no available drug can cover is reported as uncovered rather than
quietly dropped. The solver sits behind a small protocol, so an exact solver can
later be added as a correctness check on the greedy one.

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

---

## Why this is interesting as computer science

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

---

## What is real and what is schematic

Being clear about this is part of the project's purpose.

**Real:** the inference engine, the belief algebras and their arithmetic, the
chaining and belief composition, the conflict behavior, the explanation and
provenance records, the therapy solver and its guarantees, the antibiogram
mathematics, and the test suite — roughly 310 assertions across 93 tests,
including every rule fired in isolation and hand-verified golden values for each
scenario under both belief systems.

**Schematic:** the certainty numbers. Every rule weight is a teaching value,
chosen to make the machinery observable, and each is explicitly marked as such
in its own provenance record. The published citations attached to a rule verify
that the clinical association is real; they do not verify the number. Grounding
some of those numbers in real frequency data is active work.

**Also schematic:** the drug knowledge base, its doses, its susceptibilities, and
its contraindications. The rulebase is 50 rules against MYCIN's original 450 —
enough to exercise every mechanism in the architecture, and nowhere near enough
to be clinically meaningful.

---

## Where to read next

| Document | What it covers |
|---|---|
| [`docs/getting-started.md`](docs/getting-started.md) | Building, running, and testing; how to read the output |
| [`docs/runbook.md`](docs/runbook.md) | A guided tour of a full identification consultation |
| [`docs/therapy-demo.md`](docs/therapy-demo.md) | The treatment phase, end to end |
| [`docs/clinician-scenarios.md`](docs/clinician-scenarios.md) | Worked cases exercising the rulebase and the antibiogram overlay |
| [`docs/why-how-provenance-design.md`](docs/why-how-provenance-design.md) | The design of the explanation facility |
| [`docs/antibiogram-overlay-design.md`](docs/antibiogram-overlay-design.md) | The site-local susceptibility mathematics |
| [`docs/rule-catalogue-design.md`](docs/rule-catalogue-design.md) | Why the rulebase is queried rather than described to the model |
| [`docs/demo-runsheet.md`](docs/demo-runsheet.md) | A 15-minute live demonstration script |
| [`CLAUDE.md`](CLAUDE.md) | Build notes and the layout of the codebase |

**References.**

- Shortliffe, E. H. (1976), *Computer-Based Medical Consultations: MYCIN*
- Buchanan, B. G. and Shortliffe, E. H. (1984), *Rule-Based Expert Systems*
- Clancey, W. J. (1987), *Knowledge-Based Tutoring: The GUIDON Program*
- Shafer, G. (1976), *A Mathematical Theory of Evidence*
- Norvig, P. (1992), *Paradigms of Artificial Intelligence Programming*, chapter 16, whose
forward-chaining translation of the MYCIN rules this rulebase follows
