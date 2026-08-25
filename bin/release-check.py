#!/usr/bin/env python3
"""Release gate: run scripted consultations and ASSERT over the captured transcript.

The suite, bin/*.sh and prompt-tests.lisp each test ONE layer, and none of them puts
the model in the loop. That gap is how three tools.json descriptions went stale while
the suite stayed green, how a worked example in the system prompt quoted K = 0.38 for a
year after the real figure moved, and how a stale coverage threshold was narrated to a
clinician. Every one of those was a number or a name the model produced from memory
rather than from a payload.

Reading a transcript by hand catches those. It caught several. But it is slow, it does
not scale, and whether it happens depends on how carefully somebody reads. This makes it
mechanical.

FOUR CHECKS, all string processing over the transcript. No LLM judge:

  1. RULE NAMES  -- every rule name the assistant quotes exists in the compiled corpus.
  2. TEST NAMES  -- every microbiology test it names is one the corpus can actually
                    hear, and it never recommends an INERT value as a next step.
  3. NUMBERS     -- every number it quotes appears in a payload it received EARLIER in
                    the same transcript (or in what the clinician said). This is the one
                    that matters: it catches recall-from-memory structurally, and
                    nothing else in the stack can.
  4. PHRASING    -- no claim that a rule "argued against" or "ruled out" an organism.
                    Nothing in this corpus argues against anything, and saying so
                    describes a mechanism that does not exist.

WHY A RELEASE GATE AND NOT A COMMIT HOOK: it costs API calls and is non-deterministic.
Run it at the same cadence as the manual check it replaces -- before tagging.

    ./bin/release-check.py                 # all scenarios
    ./bin/release-check.py --scenario burn-icu
    ./bin/release-check.py --keep          # keep transcripts for inspection

Requires a running bridge (see CLAUDE.md "Build & Load") and a configured LLM backend
(see "Running the Clinician Driver"). Exits non-zero if any check fails.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

BRIDGE = os.environ.get("LISA_BRIDGE_URL", "http://localhost:8090")
REPO = Path(__file__).resolve().parent.parent
DRIVER = REPO / "src" / "llm" / "claude" / "driver.py"


# ----------------------------------------------------------------------------
# Scenarios. Each is a list of clinician turns fed to the driver on stdin.
#
# Chosen to cover the paths where narration has actually gone wrong before, not to
# cover the corpus: identification with competing epidemiology, a case where the honest
# answer is "not discriminated", therapy with its dials, and the redundant-evidence
# case where a rule is deliberately absent from the argument.
# ----------------------------------------------------------------------------

SCENARIOS = {
    "burn-icu": [
        "A patient with serious burns and a compromised immune system has an aerobic "
        "gram-negative rod growing in a blood culture. Please run inference and give me "
        "the differential.",
        "Why is that the leading answer, and how confident should I be? Quote the actual "
        "belief figures.",
    ],
    "redundant-context": [
        "Patient on chemotherapy, immunocompromised, and neutropenic. Blood culture: "
        "aerobic gram-negative rods. No biochemistry yet. Run inference and give me the "
        "differential.",
        "Did the neutropenia change anything?",
    ],
    "therapy": [
        "62-year-old, two weeks inpatient on chemo with a central line, new fevers. "
        "Blood culture: gram-negative rods, aerobic. No allergies. What is this and what "
        "should I treat with?",
        "Is there a narrower agent?",
    ],
    "bench-discrimination": [
        "Aerobic gram-negative rods in the blood. Biochemicals are back - lactose "
        "fermenter, indole positive. What is it?",
        "What would you treat with?",
    ],
}


# ----------------------------------------------------------------------------
# Transcript parsing
# ----------------------------------------------------------------------------

SECTION = re.compile(r"^(#{2,3}) (.+?)$", re.M)
FENCE = re.compile(r"```json\n(.*?)\n```", re.S)


def parse_transcript(text):
    """[(kind, name, body), ...] in order.

    kind is 'clinician' | 'assistant' | 'call' | 'result' | 'other'. For calls and
    results the body is the parsed JSON (or None if it did not parse); otherwise it is
    the raw markdown between this heading and the next.
    """
    # The transcript's own footer ("*Ended <ISO timestamp>*") sits after the last
    # heading, so it would otherwise be read as part of the final Assistant block and
    # its timestamp digits flagged as invented numbers. Cut it before parsing rather
    # than filtering timestamps later -- it is scaffolding, not anything the model said.
    footer = re.search(r"\n---\n\n\*Ended [^*]*\*", text)
    if footer:
        text = text[:footer.start()]

    events, marks = [], list(SECTION.finditer(text))
    for i, m in enumerate(marks):
        title = m.group(2).strip()
        body = text[m.end():marks[i + 1].start() if i + 1 < len(marks) else len(text)]
        if title == "Clinician":
            events.append(("clinician", None, body))
        elif title == "Assistant":
            events.append(("assistant", None, body))
        elif title.startswith("Tool call:") or title.startswith("Tool result:"):
            kind = "call" if title.startswith("Tool call:") else "result"
            name = title.split("`")[1] if "`" in title else title
            fence = FENCE.search(body)
            payload = None
            if fence:
                try:
                    payload = json.loads(fence.group(1))
                except json.JSONDecodeError:
                    payload = None
            events.append((kind, name, payload))
        else:
            events.append(("other", title, body))
    return events


def strip_code(text):
    """Prose only -- fenced blocks are payload echoes, not the assistant's claims."""
    return re.sub(r"```.*?```", " ", text, flags=re.S)


# ----------------------------------------------------------------------------
# Number extraction
# ----------------------------------------------------------------------------

NUMBER = re.compile(r"(?<![\w.])(\d+(?:\.\d+)?)\s*(%?)")


def numbers_in(text):
    """[(literal, value), ...] found in TEXT, with percentages also offered as fractions."""
    out = []
    for lit, pct in NUMBER.findall(text):
        try:
            v = float(lit)
        except ValueError:
            continue
        out.append((lit + ("%" if pct else ""), v))
        if pct:
            out.append((lit + "%", v / 100.0))
    return out


def harvest(payload, sink):
    """Every number reachable in PAYLOAD -- values, numbers inside strings, and the
    LENGTH of every array, since a narrator legitimately says '17 organisms' from a
    17-element list."""
    if isinstance(payload, bool) or payload is None:
        return
    if isinstance(payload, (int, float)):
        sink.add(round(float(payload), 6))
    elif isinstance(payload, str):
        for _, v in numbers_in(payload):
            sink.add(round(v, 6))
    elif isinstance(payload, list):
        sink.add(float(len(payload)))
        for item in payload:
            harvest(item, sink)
    elif isinstance(payload, dict):
        for v in payload.values():
            harvest(v, sink)


def is_supported(literal, value, allowed):
    """True when a quoted number is justified by something already seen.

    Matching is by ROUNDING, because a narrator quoting 0.23219512 as 0.23 is doing
    exactly the right thing. A literal with d decimals matches any allowed value that
    rounds to it at d places.
    """
    decimals = len(literal.split(".")[1].rstrip("%")) if "." in literal else 0
    for a in allowed:
        if round(a, decimals) == round(value, decimals):
            return True
        # a narrator may render a fraction as a percentage, or the reverse
        if round(a * 100, decimals) == round(value, decimals):
            return True
        if round(a / 100, decimals) == round(value, decimals):
            return True
    return False


# ----------------------------------------------------------------------------
# Corpus facts, read from the bridge
# ----------------------------------------------------------------------------

def corpus():
    with urllib.request.urlopen(f"{BRIDGE}/rules", timeout=30) as fh:
        data = json.load(fh)
    summary = data.get("summary", {})
    params = summary.get("parameters", []) or []
    # summary.parameters is the corpus's INPUT vocabulary, computed from rule premises.
    # A parameter absent from it is INERT: assertable, accepted, and read by no rule. So
    # membership here is the whole test -- there is no separate inert list to consult.
    names = {p.get("parameter") for p in params if isinstance(p, dict)}
    # The catalogue is seeded into the ALLOWED set for check 3, and the reasoning is
    # worth stating because it is the one place that check is loosened.
    #
    # The transcript-order rule exists for CONSULTATION-SPECIFIC numbers -- a belief
    # computed for this patient must come from this patient's payload. It does not need
    # to apply to static facts about the corpus: `describe_rules' is callable at any
    # moment and its answer does not depend on the case, so a model stating "46 rules"
    # or a rule's declared belief is quoting something authoritative whether or not it
    # happened to fetch it this turn.
    #
    # This deliberately does NOT extend to the system prompt, which contains worked
    # EXAMPLE figures (0.16, 0.56, 0.90 ...). Allowing those would defeat the check
    # entirely -- reciting a stale example is exactly the defect that motivated it.
    catalogue = set()
    harvest(data, catalogue)
    return {
        "rules": {r["rule"] for r in data.get("rules", []) if isinstance(r, dict)},
        "parameters": {n for n in names if n},
        "catalogue": catalogue,
    }


# The tests a clinician might reasonably be told to order. Anything here that is NOT in
# summary.parameters is a test the corpus cannot hear, and recommending it sends someone
# to the bench for a result that can never be entered.
KNOWN_TESTS = {
    "lactose", "indole", "motility", "urease", "pigment", "catalase", "coagulase",
    "hemolysis", "optochin", "bacitracin", "novobiocin", "bile-esculin",
    "salt-tolerance", "arabinose", "sorbitol", "oxidase", "citrate", "dnase",
    "coagulase-negative", "germ-tube", "maldi-tof", "gram", "morphology", "aerobicity",
}


# ----------------------------------------------------------------------------
# Checks
# ----------------------------------------------------------------------------

RULE_TOKEN = re.compile(r"\b([a-z][a-z0-9]*(?:-[a-z0-9]+){2,})\b")
BANNED = [
    (re.compile(r"(?<!no )(?<!nothing )(?<!never )(?<!not )\bargu\w+ against\b", re.I),
     "claims something argued against an organism"),
    (re.compile(r"(?<!not )(?<!never )\brul\w+ out\b", re.I),
     "claims an organism was ruled out"),
]
# \w+n't catches hasn't / haven't / wasn't / doesn't and the rest in one alternative.
# Spelling them individually is how "the evidence hasn't ruled out salmonella" -- correct
# phrasing the prompt asks for -- was flagged as a violation on the first gated release.
# A margin with nothing to measure against. `margin' is the gap between the leading
# answer and the nearest answer that CONTRADICTS it -- and when nothing does, the
# bridge reports no rival and margin carries the leader's own support instead. That
# reading was got wrong in a clinician session on 2026-08-24: a payload with
# `margin_against' unset and a SEVEN-ORGANISM leading answer was narrated as "margin
# 0.23 (E. coli leading over the runner-up group)", inventing a rival the payload had
# explicitly declined to name and reassigning the leader from the set to one member.
#
# Every number in that sentence was real and appeared in the payload, so check (3)
# passed it. This is the structural version of the same idea: not "is the number
# there" but "does the prose claim a comparison the payload says does not exist".
#
# `rival' is deliberately NOT in this list. "Every rival organism sits at bel 0" is
# correct phrasing and appears within a sentence of a legitimate margin mention.
MARGIN_MENTION = re.compile(r"\bmargins?\b", re.I)
COMPARATIVE = re.compile(
    r"\b(over|ahead of|versus|vs\.?|runner[-\s]?up|out(?:ranks|paces)|"
    r"beats?|lead(?:s|ing)? over|in front of)\b", re.I)

# How far either side of a `margin' mention to look for comparative language. Bounded
# rather than sentence-scoped on purpose: "E. coli" defeats every sentence splitter
# worth writing, and the phrase that matters sits within a clause of the number.
MARGIN_BACK, MARGIN_FORWARD = 40, 120


def margin_contexts(payload):
    """Every (margin_against, leading_answer) a payload states, at any depth.

    /conclusions carries one per organism entity; /why carries one at top level.
    """
    found = []

    def walk(node):
        if isinstance(node, dict):
            if "margin_against" in node:
                found.append((node.get("margin_against"),
                              node.get("leading_answer")))
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    walk(payload)
    return found


def no_rival(margin_against):
    """True when the payload says nothing contradicts the leading answer.

    Accepts the legacy string sentinel as well as real JSON null: transcripts
    captured before the serialization was fixed carry "NULL", and --transcript is
    meant to work on saved files.
    """
    return (margin_against is None
            or (isinstance(margin_against, str)
                and margin_against.strip().upper() == "NULL")
            or margin_against == [])


NEGATION_WINDOW = re.compile(
    r"\b(no|nothing|none|never|not|cannot|\w+n't)\b[^.]{0,60}$", re.I)


def check_transcript(path, facts):
    events = parse_transcript(path.read_text(encoding="utf-8"))
    allowed = set(facts["catalogue"])
    failures = []
    # The margin context most recently PUT IN FRONT of the model. Same ordering
    # discipline as check (3): what the assistant may say is bounded by what it has
    # already been shown.
    margin_seen = []

    for kind, name, body in events:
        if kind in ("result", "call"):
            if body is not None:
                harvest(body, allowed)
                ctx = margin_contexts(body)
                if ctx:
                    margin_seen = ctx
            continue
        if kind == "clinician":
            for _, v in numbers_in(body):
                allowed.add(round(v, 6))
            continue
        if kind != "assistant":
            continue

        prose = strip_code(body)

        # (1) rule names
        for token in RULE_TOKEN.findall(prose):
            if "narrows-to" in token and token not in facts["rules"]:
                failures.append(("rule-name", f"quotes rule `{token}`, which is not in "
                                              f"the compiled corpus"))

        # (2) test names
        for token in set(RULE_TOKEN.findall(prose)) | set(re.findall(r"\b[a-z]{4,}\b", prose)):
            if token in KNOWN_TESTS and token not in facts["parameters"]:
                failures.append(("test-name", f"names the test `{token}`, which is not "
                                              f"in summary.parameters -- the corpus "
                                              f"cannot hear it"))

        # (3) numbers
        for literal, value in numbers_in(prose):
            if value > 1000 or (value.is_integer() and value <= 31 and "." not in literal):
                continue  # years, small counts, list positions -- not belief claims
            if not is_supported(literal, value, allowed):
                failures.append(("number", f"quotes {literal}, which appears in no "
                                           f"payload received earlier in this transcript"))

        # (4) phrasing
        for pattern, why in BANNED:
            for m in pattern.finditer(prose):
                before = prose[max(0, m.start() - 80):m.start()]
                if NEGATION_WINDOW.search(before):
                    continue  # "nothing argued against it" is the CORRECT phrasing
                snippet = prose[max(0, m.start() - 40):m.end() + 40].replace("\n", " ")
                failures.append(("phrasing", f"{why}: ...{snippet.strip()}..."))

        # (5) margin against nothing
        if margin_seen and all(no_rival(ma) for ma, _ in margin_seen):
            for m in MARGIN_MENTION.finditer(prose):
                window = prose[max(0, m.start() - MARGIN_BACK):
                               m.end() + MARGIN_FORWARD]
                hit = COMPARATIVE.search(window)
                if hit:
                    snippet = window.replace("\n", " ").strip()
                    failures.append((
                        "margin",
                        f"narrates the margin as a comparison (`{hit.group(0)}') when "
                        f"the payload named no contradicting answer -- "
                        f"`margin_against' was null: ...{snippet}..."))

    return failures


# ----------------------------------------------------------------------------
# Driving
# ----------------------------------------------------------------------------

def run_scenario(name, turns, outdir, python):
    transcript = outdir / f"{name}.md"
    proc = subprocess.run(
        [python, str(DRIVER), "--plain", "--transcript",
         "--transcript-dir", str(outdir),
         "--transcript-file", f"{name}.md",
         "--transcript-verbosity", "full"],
        input="\n".join(turns) + "\n",
        text=True, capture_output=True, timeout=900,
    )
    if not transcript.exists():
        raise RuntimeError(
            f"no transcript written for {name}\n--- driver stderr ---\n{proc.stderr[-2000:]}")
    return transcript


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--scenario", action="append",
                    help="run only this scenario (repeatable)")
    ap.add_argument("--keep", action="store_true",
                    help="keep transcripts instead of using a temp dir")
    ap.add_argument("--python", default=sys.executable,
                    help="interpreter for the driver (default: this one)")
    ap.add_argument("--transcript", metavar="PATH",
                    help="check an EXISTING transcript instead of running the driver")
    args = ap.parse_args()

    try:
        facts = corpus()
    except Exception as exc:
        print(f"FAIL: cannot reach the bridge at {BRIDGE} ({exc})", file=sys.stderr)
        print("      start it first -- see CLAUDE.md 'Build & Load'", file=sys.stderr)
        return 2
    print(f"corpus: {len(facts['rules'])} rules, {len(facts['parameters'])} parameters\n")

    if args.transcript:
        pairs = [(Path(args.transcript).stem, Path(args.transcript))]
    else:
        wanted = args.scenario or list(SCENARIOS)
        unknown = [s for s in wanted if s not in SCENARIOS]
        if unknown:
            print(f"unknown scenario(s): {', '.join(unknown)}", file=sys.stderr)
            return 2
        outdir = Path("./sessions/release-check") if args.keep else \
            Path(tempfile.mkdtemp(prefix="neomycin-release-"))
        outdir.mkdir(parents=True, exist_ok=True)
        pairs = []
        for name in wanted:
            print(f"running {name} ...", flush=True)
            pairs.append((name, run_scenario(name, SCENARIOS[name], outdir, args.python)))
        print()

    total = 0
    for name, path in pairs:
        failures = check_transcript(path, facts)
        total += len(failures)
        if failures:
            print(f"FAIL {name}  ({len(failures)} problem(s))")
            for kind, message in failures:
                print(f"    [{kind}] {message}")
        else:
            print(f"ok   {name}")
        if args.keep or failures:
            print(f"     transcript: {path}")

    print()
    if total:
        print(f"RELEASE CHECK FAILED -- {total} problem(s)")
        print("Each is something the model told a clinician that the engine did not say.")
        return 1
    print("RELEASE CHECK PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
