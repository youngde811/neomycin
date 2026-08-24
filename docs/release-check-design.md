# The transcript-assertion harness — design, and what it cannot do

`bin/release-check.py`. Added at v0.15.0, replacing a manual read-the-transcript ritual.

## 1. The problem it exists for

neomycin has four layers and each is tested in isolation:

| layer | tested by |
|---|---|
| the engine and the belief algebra | `neomycin/test/` (the suite) |
| the HTTP bridge | `bin/test-*.sh` |
| the prompt and tool schemas, against the corpus | `prompt-tests.lisp` |
| **the model's narration** | **nothing, until now** |

Everything the clinician actually reads is produced by the last layer, and the failures
found there have all had one shape: **a number or a name the model produced from memory
rather than from a payload.** Three `tools.json` descriptions went stale while the suite
stayed green. A worked example in the system prompt quoted `K = 0.38` for a year after
the real figure moved. A coverage threshold recalibrated at v0.11 was still being
narrated at its old value.

None of those is catchable by testing a layer. They are only visible in the *join*
between what the engine returned and what the model said about it — which is exactly
what a transcript contains.

Reading transcripts by hand does catch them; it caught most of the above. But it does
not scale, and its yield depends on how carefully somebody happens to read that day.

## 2. Why assertions and not an LLM judge

An LLM judge would be the obvious reach, and it is the wrong tool here. The failures are
**referential**, not stylistic: did this number come from somewhere, or was it invented?
That is a set-membership question over the transcript, and set membership is something
string processing answers exactly and a judge answers approximately.

A judge would also reintroduce the failure mode being tested. The whole point is that
model output is not self-certifying.

## 3. The four checks

Run over each `## Assistant` block, with fenced code stripped — a payload echoed back is
not a claim.

### 3.1 Rule names

Every token shaped like a rule name (`...-narrows-to-...`) must exist in the compiled
corpus, read live from `GET /rules`.

Cheap and total: the corpus is the authority, and a rule the model half-remembers from
an earlier release fails immediately.

### 3.2 Test names

Every microbiology test named must appear in `summary.parameters` — the corpus's input
vocabulary, computed from rule premises.

The failure this prevents is specific and expensive: **a clinician sent to the bench for
a result that can never be entered.** A test absent from `summary.parameters` is inert —
assertable, accepted, and read by nothing — and the assertion returns success, so
nothing anywhere reports that the answer was ignored.

This is the weakest of the four, and §5 says why.

### 3.3 Numbers — the one that matters

**Every number quoted must appear in a payload received earlier in the same transcript**,
or in what the clinician said.

Matching is by rounding: a literal with *d* decimals matches any allowed value that
rounds to it at *d* places, so quoting `0.23219512` as `0.23` passes, as it should.
Percentages are matched in both directions, since a narrator may render `0.405` as
`40.5%`. The allowed set is harvested from every tool call and result — including
numbers inside strings, so a citation's `40.5%` counts — plus the **length** of every
array, because "17 organisms" is a legitimate reading of a 17-element list.

Exclusions are deliberately narrow: values above 1000 and bare small integers, which are
list positions and counts rather than belief claims.

**This check catches recall-from-memory structurally.** Pointed at a v0.12-era
transcript it flags `0.613` and `0.806` on sight — precisely the stale figures narrated
to a clinician at the time. No other check in the stack can see that class of defect,
because at every other layer those numbers were correct *once*.

### 3.4 Phrasing

No claim that something "argued against" or was "ruled out". Nothing in this corpus
argues against anything — exclusion is what remains after answers are intersected — so
saying otherwise describes a mechanism that does not exist.

**Negations are exempt**, and getting that right matters: *"nothing argued against it"*
is the phrasing the system prompt explicitly asks for. A check that punished the correct
answer would be worse than no check.

## 4. It found a bug in itself

On its first full run, two scenarios failed on the integers 48/57 and 49/39. They were
the transcript's own footer — `*Ended 2026-08-24T13:48:57*` — which sits after the last
heading and was being folded into the final `## Assistant` block.

Recorded because it is the same lesson the harness exists to enforce: **a check is only
as good as what it looks at**, and this one had to be tested before it could be trusted.
All four checks are negative-tested by injecting a real fault into a real transcript.

## 5. What it CANNOT catch — read this before trusting it

The harness verifies that names and numbers are **referenced** rather than invented. It
does not verify that they are used **correctly**, and the gap is wide:

- **Misattribution.** Quoting Klebsiella's belief for Pseudomonas passes every check:
  the number is in a payload, the names are real.
- **A right number in a wrong claim.** *"E. coli at 0.28, so it is confirmed"* passes.
  0.28 is real; "confirmed" is nonsense.
- **Invented mechanisms.** This is the important one. Earlier in the v0.14 work the
  model saw a rule missing from the trace and explained it as *subsumption* — a real
  mechanism, wrongly applied, describing something that had not happened. **It used no
  fabricated names and no fabricated numbers, so this harness would not have flagged
  it.** It was caught by a person reading carefully, and the fix was a prompt guard
  ("never explain the payload with a mechanism you cannot see in it") rather than a
  test.
- **Omissions.** Failing to state the corpus bound, or to say the beliefs are
  illustrative, is invisible here. A caveat not given leaves no trace.
- **Tests outside the lexicon.** §3.2 works from a curated list of plausible
  microbiology tests, so it catches an *oxidase* but not a test nobody thought to list.
  The list is in the file and is meant to grow.

**So this replaces the mechanical half of the manual check, not the judgement half.**
Reading a release transcript is still worth doing; it is just no longer the only thing
standing between a stale number and a clinician.

## 6. Scenarios

Four, chosen for the paths where narration has actually gone wrong rather than to cover
the corpus:

| scenario | why |
|---|---|
| `burn-icu` | competing epidemiology, two graded answers leaning opposite ways |
| `redundant-context` | a rule deliberately absent from the argument (evidence groups) |
| `therapy` | the solver, its dials, and `below_threshold` reporting |
| `bench-discrimination` | a case that genuinely identifies, for contrast |

Adding a scenario is adding a dict entry. The bar for a new one is that it exercises a
narration path the others do not.

## 7. Operating it

A **release gate, not a commit hook**: it costs API calls and is non-deterministic, so
it runs at the cadence of the manual check it replaces.

```bash
./bin/release-check.py                    # all scenarios
./bin/release-check.py --scenario therapy # one
./bin/release-check.py --keep             # keep transcripts under ./sessions/
./bin/release-check.py --transcript FILE  # re-check a saved transcript, no API calls
```

`--transcript` is how to iterate on a failure: run once, then re-check the saved file
for free while fixing the prompt.

## 8. Relation to the drift taxonomy

This is the fourth entry in a pattern the project keeps finding, and the reason the
taxonomy is worth writing up:

- **a check that cannot fail** — a guard keyed to a retired naming convention; a smoke
  test carrying a literal count; a regression test whose fixture drifted off the
  condition it tested
- **a claim nothing verifies** — transcribed thresholds, counts, worked figures
- **a relative quantity read as absolute** — conflict `K` read as reliability
- **silence indistinguishable from an answer** — inert vocabulary; a fact filed against
  the wrong context so its rule never fires

The narration layer was an instance of the second: a large surface of claims, verified
by nothing. This harness verifies the part of it that is mechanically checkable, and
§5 is an honest statement of the part that still is not.
