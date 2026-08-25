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

## 3. The six checks

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

### 3.5 Ignorance must be `pl - bel`

An organism's ignorance is the width of its interval. That is arithmetic, checkable
without knowing anything about the case, and a stated triple that fails it is
self-contradicting on its face.

It earns a check because the payload invited the error. `ignorance` was emitted at two
scopes under one key — m(Θ) for the whole consultation, and `pl - bel` per hypothesis —
and on 2026-08-24 an organism at `bel 0.91 / pl ~1.0` was narrated as having *"essentially
no residual ignorance (0.002)"*. That 0.002 was the consultation's m(Θ); the organism's own
ignorance was 0.09, which the same sentence had just implied by quoting bel and pl. Every
number was real and in a payload, so **check 3.3 passed it**.

The entity-level key is `theta_mass` now. This check catches the residue — including the
plain arithmetic slip, which no rename prevents.

### 3.6 A margin against nothing

`margin` is the gap between the leading answer and the nearest answer that
**contradicts** it. Often nothing does, and the bridge then reports `margin_against` as
`null`: the leader stands unopposed, and the margin carries its own support rather than
a lead over a rival.

If the most recent payload said `margin_against: null`, the prose may not narrate the
margin as a comparison. Comparative language — *over*, *ahead of*, *runner-up*,
*versus*, *outranks* — within a bounded window of the word `margin` is a failure.

**This is the first structural check.** Checks 3.1–3.3 ask *is this token real*; this one
asks *does the prose claim a relation the payload denies*. It exists because a real
consultation on 2026-08-24 produced:

> with `margin=0.23` (E. coli leading over the runner-up group by a moderate amount)

against a payload whose `leading_answer` was the seven-organism aerobic-gram-negative-rod
**set** and whose `margin_against` was null. Every number in that sentence was real and
appeared in an earlier payload, so **check 3.3 passed it**. The 0.23 was the mass on the
seven-member set — which is the honest headline for that case — recast as a contest
between organisms that the engine had explicitly declined to describe.

Two things had to be fixed alongside it, and they are the more important half:

- **The prompt taught the misreading.** `system-prompt.md` defined `margin` as "how far
  the leading *organism's* belief sits above the *runner-up's*", and separately claimed —
  falsely — that a set-valued leader scores `margin 0` and `K 0`. `LISA::MARGIN`'s own
  docstring says the opposite, and the corpus supplies the counterexample. Both are
  corrected and pinned by `prompt-tests.lisp`.
- **The payload was ambiguous.** `margin_against` was serialized as the JSON *string*
  `"NULL"`, which is truthy in every client language — including the Python this harness
  is written in. It is real JSON `null` now.

**Negated comparisons are exempt**, exactly as in 3.4, and this was not a precaution —
it was a bug the release gate caught on this check's first live run. The corrected
prompt asks the model to *say* there is no rival, and it does: *"no rival to measure a
margin against"*, *"unopposed support, not a lead over a competitor"*, *"no rival to
report a win over"*. Each names the comparison in order to deny it, and the check failed
two scenarios for it. **It was punishing the fix for working.** `rival` is likewise not
in the banned list: *"every rival organism sits at bel 0"* is correct phrasing and
occurs within a sentence of legitimate margin mentions. A check that punished the
correct answer would be worse than no check.

**Not exercised end to end.** No scenario asserts an inert value, so `inert: false` is
all the gate has ever seen; the disclosure obligation is covered by unit tests and not
by the model-in-the-loop run. Worth a scenario.

**What 3.6 does not check.** That the margin is attributed to the leading *answer* rather
than to one member of it, when that is done without comparative language. *"Margin 0.23
for E. coli"*, with a set-valued leader and no rival, still passes. Detecting it needs a
judgement about what the prose is attributing, which is exactly what §5 says this harness
does not do; the prompt carries that rule instead.

## 4. It found a bug in itself

On its first full run, two scenarios failed on the integers 48/57 and 49/39. They were
the transcript's own footer — `*Ended 2026-08-24T13:48:57*` — which sits after the last
heading and was being folded into the final `## Assistant` block.

Recorded because it is the same lesson the harness exists to enforce: **a check is only
as good as what it looks at**, and this one had to be tested before it could be trusted.
All six checks are negative-tested by injecting a real fault into a real transcript.
Check 3.5 needed no injection: it was written against the session that motivated it
and run over both transcripts of 2026-08-24, where it flags the one real defect and
stays silent on the three margin readings that were correct — including the two in
the same session, and the one in the other session where `margin_against` was also
null but the leading answer was a singleton.

## 5. What it CANNOT catch — read this before trusting it

The harness verifies that names and numbers are **referenced** rather than invented. It
does not verify that they are used **correctly**, and the gap is wide:

- **Misattribution.** Quoting Klebsiella's belief for Pseudomonas passes every check:
  the number is in a payload, the names are real. Observed on 2026-08-24: gentamicin's
  susceptibility floor given as `0.62`, which is *ciprofloxacin's*, from the bullet
  above it. Right number, wrong drug, and check 3.3 cannot see the difference.
- **Fact VALUES the corpus cannot hear.** Check 3.2 validates parameter *names* against
  `summary.parameters` and never looks at values, so `age-group: elderly` — asserted
  against a corpus that hears only `neonate` — is invisible to it in both directions.
  **This one is now caught upstream instead**: `/assert-fact` returns `inert` on every
  assertion and the prompt requires disclosing it. Worth noting as the pattern — the fix
  belonged in the bridge, not here. A harness that reads transcripts cannot see a
  distinction the payload never drew.
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

### Reduced-verbosity transcripts

`--transcript` now warns when the captured verbosity is not `full`. At `normal` the
driver keeps results only for conclusions, rule-trace, partial-matches, why and
recommend-therapy; `describe_rules` payloads are elided, so **any figure quoted from the
rule catalogue has nothing to be checked against** and 3.3 passes it silently.

Measured: a hand-run session on 2026-08-24 quoted a rule's belief as `0.8` with no
payload behind it, and passed — `0.8` happened to appear elsewhere. The scenarios this
harness drives itself always run at `full`, so the exposure was confined to exactly the
hand-run sessions one most wants checked, and it was silent about it.


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
