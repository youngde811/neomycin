# docs/attic — the record of what neomycin used to be

Every document here describes a mechanism **the system no longer has**. They are kept
because the divergence is one of the project's actual findings, not an embarrassment to
be tidied away: neomycin arrived at its current representation by discovering, one
problem at a time, that the previous one could not say what a clinician needed said.
This directory is the evidence for that story, and the primary source for the drift
taxonomy the paper is meant to carry.

**Nothing here is authority for how the system behaves today.** For that, read
`CLAUDE.md`, the corpus itself (`neomycin/rules/`), and the live documents one level up
in `docs/`. Where a live document cites one of these, it is citing the *measurement* or
the *argument*, never the mechanism.

Files are **left as written**, with a banner added at the top. Editing the numbers
inside a design document or a captured session would falsify a record — the same rule
`neomycin/clinician-samples/README.md` follows for transcripts.

## What each one is evidence of

### The declared shared frame — shipped v0.9/v0.10, deleted at v0.11

The belief representation before the current one. Organisms shared a single declared
frame of discernment, which had to be kept in step with the rulebase. It was replaced by
Dempster-Shafer over an **open** frame (`src/belief-systems/candidates/`), where Θ is
never enumerated and nothing declares anything.

- `shared-frame-design.md` — the proposal, and the decision record (D1–D5).
- `shared-frame-phase0-results.md` — the measurements. **Still load-bearing as an
  argument**: they showed no combination operator fixed the ranking problem, and that
  the real variable was focal-set WIDTH. That finding is why graded answers exist.
- `frame-algebra-spike.lisp`, `focal-width-audit.lisp` — throwaway measurement tools.
  They will not run against the current tree.
- `slice-d-focal-width.md` — the focal-width audit and what it changed.
- `belief-conditional-audit.md` — the audit that started the whole line of work, by
  asking which question a rule's belief actually answers.

### Chaining and the organism-class — never in the current corpus

A rule's conclusion used to feed another rule, composing belief multiplicatively through
an intermediate `organism-class`. **Nothing chains now** and there is no class: a genus
IS a candidates set, and answers combine by intersection.

- `chaining-belief-spike.md` — belief propagation through the class intermediate.
- `chaining-belief-spike-open-questions-approach.txt` — David's answers to its open
  questions.
- `gram-positive-cluster-design.md` — the gram-positive expansion, designed as chained
  clusters and lettered slices.

### Disconfirming rules and negative belief — gone at v0.11

Rules used to argue *against* an organism, carrying a negative belief. The corpus now
has none: a rule states the SET its evidence narrows to, and exclusion is what remains
after answers intersect.

- `sibling-cross-disconfirmation-design.md` — cross-disconfirmation among the
  enterobacteriaceae siblings, with signed magnitudes.

### The narrows-to conversion — the working files

The v0.11 conversion that produced the current corpus. Kept for the argument; the
shipped rules in `neomycin/rules/` are the authority.

- `narrows-to-gram-pos-sketch.md` — the design sketch.
- `narrows-to-spike.lisp`, `narrows-to-rules.lisp`, `narrows-to-rules-gram-neg.lisp` —
  throwaway spike rules, in no ASDF system.

### Superseded plans, prototypes and captures

- `ds-grounded-beliefs-design.md` — **deferred and never implemented**; branch deleted.
  Its standalone finding (some illustrative beliefs may encode a sensitivity rather
  than a posterior) has not been actioned.
- `belief-system-prototype.lisp` — the first simplified Dempster-Shafer prototype.
- `next-steps-llm-integration.md` — planning; shipped or superseded throughout. It
  mentions an `ExampleRulebases.md` that was deleted when this attic was created.
- `README-orig.md` — the v0.6.0 project README. Superseded by the repo-root `README.md`.
- `therapy-phase-thoughts.md` — early thinking, before the therapy phase was designed.
- `sample-session.md`, `sample-session-ds-conflict.md` — pre-v0.9.0 driver transcripts.
  The belief figures, rule shapes and narration all predate v0.11.

## The boundary

A document lives **up one level in `docs/`** if it is cited as authority for current
behaviour — by `CLAUDE.md`, by live code, or by the test suite. It lives **here** if the
mechanism it describes is gone. Age is not the test: `docs/base-rate-investigation.md`
and `docs/corpus-expansion-sketch.md` are older than several files in this directory and
are both still normative — the latter defines the artifact-lineage tags that
`neomycin/test/provenance-tests.lisp` enforces.
