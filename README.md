# Welcome to Neomycin

> ## ⚠️ NOT FOR CLINICAL USE
> Neomycin is a research artifact. It is not a medical device, a decision aid,
> or a diagnostic tool, and it must never inform a health decision for any
> human or animal. Every certainty number, drug, dose, and susceptibility in it
> is illustrative — chosen to make the reasoning machinery legible, not
> measured from clinical data.

Neomycin is a hybrid symbolic/LLM engine for bacterial identification and therapy
selection, using Claude as a natural-language clinical assistant and
[Lisa](https://github.com/youngde811/Lisa), a production-quality expert system shell
written in Common Lisp. It is strictly a research vehicle.

Neomycin began as a reconstruction of **MYCIN**, the Stanford medical expert system of
the 1970s, rebuilt on a modern Common Lisp production-rule inference engine and fitted
with a conversational front end powered by a large language model. Due to numerous improvements
during the development period, Neomycin is related only distantly to its ancestors.

The system holds a body of medical knowledge as explicit **rules** — statements of the
form *if these findings hold, the organism is one of this set, and here is how strongly
I believe it.* A user describes a case in ordinary English. The language model turns
that description into structured facts, hands them to the inference engine, and then
explains what the engine concluded. The engine does all the reasoning and all the
algebra. The language model does none of it.

That division of labor is the point of the project. The model is good at
language and bad at being auditable. The engine is the reverse. Keeping them
strictly separate produces a system that can be talked to like a person and
inspected like a ledger.

For a detailed look at Neomycin, see the project document [here](docs/Neomycin.md).
