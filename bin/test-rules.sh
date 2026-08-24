#!/usr/bin/env bash

# Smoke-test the rule-catalogue endpoint over HTTP. /rules answers what the corpus
# CONTAINS -- rules, beliefs, the set each one narrows to, premises, provenance --
# without anything having to fire first, which is what lets the LLM's system prompt
# stop carrying a hand-maintained copy of the rulebase.
#
# Unlike the other bin/ scripts this asserts no facts and runs no inference: the
# catalogue is a property of the compiled rulebase, not of working memory.
#
# THIS SCRIPT ASSERTS -- see the note in test-why.sh. The previous version printed
# and exited 0, and so reported nothing when the summary's organism list silently
# went empty.
#
# Prerequisites: the neomycin bridge running on port 8090 (see CLAUDE.md "Build &
# Load"), e.g. (load "neomycin.lisp").

BASE_URL="${LISA_BRIDGE_URL:-http://localhost:8090}"
FAILURES=0

fail() { echo "  FAIL: $*"; FAILURES=$((FAILURES + 1)); }
pass() { echo "  ok: $*"; }

check() {
  local desc="$1" expr="$2" expected="$3"
  local actual
  actual=$(printf '%s' "$BODY" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print($expr)
" 2>/dev/null)
  if [ "$actual" = "$expected" ]; then pass "$desc"; else fail "$desc (got '$actual', want '$expected')"; fi
}

echo "=== /rules smoke test (no inference required) ==="
echo ""

echo "--- Corpus summary ---"
BODY=$(curl -s "$BASE_URL/rules")
printf '%s' "$BODY" | python3 -c "
import json,sys
d=json.load(sys.stdin); s=d['summary']
print('total rules :', s['total'])
print('organisms   :', len(s['organisms']))
print('resolutions :', s['resolutions'])
"
# NOT a literal rule count. This file carried "44" in three places and went red the
# next time a rule was authored -- a smoke test that has to be edited whenever the
# corpus grows is one people learn to ignore. What is actually worth asserting is
# self-consistency, which a real defect breaks and a new rule does not.
TOTAL=$(printf '%s' "$BODY" | python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['total'])")
check "corpus is non-empty"       "d['summary']['total'] > 0"              "True"
check "summary counts the rules it returns" \
                                  "d['summary']['total'] == len(d['rules'])" "True"
check "organisms are listed"      "len(d['summary']['organisms']) > 10"    "True"
# The bug this catches: the summary once reported organism_classes/identities from a
# vocabulary the corpus no longer uses, and every list came back empty while the
# endpoint returned 200.
check "organism list is real"     "'pseudomonas' in d['summary']['organisms']" "True"
check "resolutions account for every rule" \
                                  "sum(int(v) for v in d['summary']['resolutions'].values()) == d['summary']['total']" "True"
check "every rule narrows to >=1" "all(len(r['narrows_to']) >= 1 for r in d['rules'])" "True"
check "every rule has a belief"   "all(0 < r['belief'] <= 1 for r in d['rules'])" "True"
echo ""

echo "--- Rules that can name pseudomonas (?names=) ---"
BODY=$(curl -s "$BASE_URL/rules?names=pseudomonas")
printf '%s' "$BODY" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('matched:', d['matched'])
for r in d['rules']:
    print('  %-52s %.2f  -> {%s}' % (r['rule'], r['belief'], ', '.join(r['narrows_to'])))
"
check "some rules name it"      "d['matched'] > 0" "True"
check "all matches name it"     "all('pseudomonas' in r['narrows_to'] for r in d['rules'])" "True"
# The summary must describe the WHOLE corpus even under a filter -- a filtered count
# here would misreport the shape. Compared against the unfiltered total captured above.
check "summary is unfiltered"   "d['summary']['total']" "$TOTAL"
echo ""

echo "--- One rule in full (?name=) ---"
BODY=$(curl -s "$BASE_URL/rules?name=burn-blood-aerobic-gram-neg-rod-narrows-to-opportunist-rods")
printf '%s' "$BODY" | python3 -m json.tool
check "exactly one match"       "d['matched']" "1"
check "premises are reported"   "len(d['rules'][0]['premises']) > 0" "True"
check "provenance is carried"   "'provenance' in d['rules'][0]" "True"
check "evidence is cited"       "len(d['rules'][0]['provenance']['evidence']) > 0" "True"
echo ""

echo "--- Rules premising on a finding (?premises=) ---"
BODY=$(curl -s "$BASE_URL/rules?premises=neg")
check "gram-neg rules found"    "d['matched'] > 0" "True"
# By PARAMETER as well as by value. This form returned zero rules until a
# release-check consultation asked it and was told, falsely, that no rule reads a
# negative urease. An empty result reads as an empty corpus.
BODY=$(curl -s "$BASE_URL/rules?premises=urease")
check "premises= accepts a parameter name" "d['matched'] > 0" "True"
check "and returns BOTH polarities" \
  "len({v for r in d['rules'] for p in r['premises'] if p['class']=='urease' for v in p['values']}) == 2" "True"
echo ""

if [ "$FAILURES" -eq 0 ]; then
  echo "PASS: /rules smoke test"
  exit 0
else
  echo "FAIL: /rules smoke test -- $FAILURES check(s) failed"
  exit 1
fi