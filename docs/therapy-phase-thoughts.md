# My thoughts on our therapy-recommendation phase

---

Scope honesty: neomycin is not intended as a clinical diagnostic tool that would live in the wild. But, in the back of
my mind I wonder if neomycin could become a useful research tool used by physicians and medical researchers to enhance
our war against AMR...

Anything I don't explicity mention in this document I agree with. If we need to discuss anything, let's do it.

## 2. Design principles

Principles 1, 2, 3: agreed.

## 3. Decision #1 - Knowledge representation (KB as data)

### 3.1 Entities

For our initial data, we'll need to devise some reasonable contraindications for certains drugs that are at least
somewhat realistic.

Agreed that Sensitivity under DS should NOT be a boolean.

Agree with other items in this section.

### 3.2 Shape

We should discuss the use of `def*` forms vs. plain tables. I kind of lean towards `def*` forms, as tables can be
non-intuitive to edit. The flip side is additions to the system require some Lisp knowledge (but that might be ok).

OR: the "external table" could be a sqlite database; key/value store (ndbm or Common Lisp package). We can chat about
this one.

### 4.1 Inputs

Agreed on all points.

### 4.3 Phase B — minimal regimen (weighted set cover)

Agreed. But we'll need a dosing recommendation "database", even if it's simulated.

### 4.4 Output — an auditable recommendation object

Agreed.

## 9. Scope and non-goals

Agreed. But we'll some amount of pharmacology data (dosing, interactions, etc), even if that data is a "best guess"
based on viable internet sources.

## 10. Open questions

1. I think an external data file is problematic, unless one has been built that's usable in our work. I think I lean
   toward `def*` forms, but I could be persuaded otherwise.
2. We need at least some source for θ_cover / θ_cover-drug values, even if simulated (but reasonable). I don't see a
   problem with per-session tunable semantics.
3. I'd say we do it right the first time, and combine sensitivities through the belief system.
4. I think the solver should live in a new `neomycin` package. In fact, if possible we should be able to insert new
   implementations without having to change other code. An API for the solver, in other words.
