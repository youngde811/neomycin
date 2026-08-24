#!/usr/bin/env bash

# Smoke-test the WHY/HOW explanation endpoint over HTTP. Asserts the culture-1
# scenario, runs inference, then asks /why for the authoritative argument behind a
# hypothesis: the answers that admit it, the answers that do not, what they intersect
# to, and the verified provenance of every rule involved.
#
# THIS SCRIPT ASSERTS. An earlier version printed each response through `json.tool`
# and exited 0 whatever came back -- so when /why began returning 404 for every
# organism, the script stayed "green" and said so for as long as nobody read the
# output. A smoke test that cannot fail is not a test. Every check below exits
# non-zero on failure and the script ends with an explicit PASS/FAIL line.
#
# Prerequisites: the neomycin bridge running on port 8090 (see CLAUDE.md "Build &
# Load"), e.g. (load "neomycin.lisp").

BASE_URL="${LISA_BRIDGE_URL:-http://localhost:8090}"
FAILURES=0

fail() { echo "  FAIL: $*"; FAILURES=$((FAILURES + 1)); }
pass() { echo "  ok: $*"; }

# check <description> <jq-ish python expr over $BODY> <expected>
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

echo "=== /why smoke test (culture-1) ==="
echo ""

echo "--- Resetting session ---"
curl -s -X POST "$BASE_URL/reset" > /dev/null

echo "--- Asserting culture-1 facts ---"
curl -s -X POST "$BASE_URL/assert-fact" \
  -d '{"fact_type":"compromised-host","entity":"patient-1","value":"t","entity_class":"patient"}' > /dev/null
curl -s -X POST "$BASE_URL/assert-fact" \
  -d '{"fact_type":"burn","entity":"patient-1","value":"serious","entity_class":"patient"}' > /dev/null
curl -s -X POST "$BASE_URL/assert-fact" -d '{"fact_type":"culture-site","value":"blood"}' > /dev/null
curl -s -X POST "$BASE_URL/assert-fact" -d '{"fact_type":"gram","entity":"organism-1","value":"neg"}' > /dev/null
curl -s -X POST "$BASE_URL/assert-fact" -d '{"fact_type":"morphology","entity":"organism-1","value":"rod"}' > /dev/null
curl -s -X POST "$BASE_URL/assert-fact" -d '{"fact_type":"aerobicity","entity":"organism-1","value":"aerobic"}' > /dev/null
curl -s -X POST "$BASE_URL/run-inference" > /dev/null
echo "asserted, inference run."
echo ""

echo "--- /why klebsiella (admitted by three answers, excluded by one) ---"
CODE=$(curl -s -o /tmp/why-kleb.$$ -w '%{http_code}' "$BASE_URL/why?organism=klebsiella")
BODY=$(cat /tmp/why-kleb.$$); rm -f /tmp/why-kleb.$$
if [ "$CODE" != "200" ]; then fail "/why klebsiella returned HTTP $CODE"; else pass "HTTP 200"; fi
printf '%s' "$BODY" | python3 -m json.tool
check "organism echoed"        "d['organism']"                          "klebsiella"
check "resolved to an entity"  "d['entity']"                            "organism-1"
check "bel is positive"        "d['bel'] > 0"                           "True"
check "pl >= bel"              "d['pl'] >= d['bel']"                    "True"
check "argument is populated"  "len(d['argument']) > 0"                 "True"
check "some answer admits it"  "any(a['admits'] for a in d['argument'])" "True"
check "intersection names it"  "'klebsiella' in d['intersection']"      "True"
check "rules are cited"        "all('rules' in a and len(a['rules'])>0 for a in d['argument'])" "True"
check "provenance is carried"  "any('provenance' in r for a in d['argument'] for r in a['rules'])" "True"
check "narrative is prose"     "len(d['narrative']) > 40"               "True"
echo ""

echo "--- /why pseudomonas (two GRADED answers, each leaning its own way) ---"
CODE=$(curl -s -o /tmp/why-ps.$$ -w '%{http_code}' -X POST "$BASE_URL/why" -d '{"organism":"pseudomonas"}')
BODY=$(cat /tmp/why-ps.$$); rm -f /tmp/why-ps.$$
if [ "$CODE" != "200" ]; then fail "/why pseudomonas returned HTTP $CODE"; else pass "HTTP 200"; fi
printf '%s' "$BODY" | python3 -m json.tool
check "organism echoed"     "d['organism']" "pseudomonas"
# RE-POINTED BY CATEGORY B. This used to assert bel > 0.4 and "two rules cited",
# and both encoded the singleton corpus:
#
#   * bel > 0.4 was reachable only because the burn and compromised-host rules each
#     answered {pseudomonas} FLAT, claiming every other aerobic gram-negative rod was
#     impossible. They now grade, so nothing in culture-1 gets near 0.4 -- correct,
#     because nothing in culture-1 has DISCRIMINATED. Epidemiology leans; it does not
#     identify. The real question the old check was reaching for is whether pseudomonas
#     leads klebsiella, so ask that instead of a magic number.
#   * "two rules cited" held because both rules asserted the SAME set and so landed on
#     one fact. Grading gives them different distributions and therefore separate
#     answers, one rule each.
check "bel is positive"     "d['bel'] > 0" "True"
check "not yet identified"  "d['bel'] < 0.4" "True"
check "grading is reported" "any('grading' in a for a in d['argument'])" "True"
check "focal sets ordered"  "all(a['grading']==sorted(a['grading'],key=lambda g:-g['mass']) for a in d['argument'] if 'grading' in a)" "True"
# The burn evidence must lean pseudomonas -- that is the clinical content the flat
# widening would have thrown away, and the whole reason grading exists.
check "burn leans pseudomonas" "any(a['grading'][0]['organisms']==['pseudomonas'] for a in d['argument'] if 'grading' in a)" "True"
check "narrative states lean"  "'leaning' in d['narrative']" "True"
echo ""

# Pseudomonas must lead klebsiella. Fetched separately so this compares two measured
# figures rather than either against a constant that goes stale.
echo "--- pseudomonas vs klebsiella (a comparison, not a magic number) ---"
PS_BEL=$(curl -s "$BASE_URL/why?organism=pseudomonas" | python3 -c 'import json,sys; print(json.load(sys.stdin)["bel"])')
KL_BEL=$(curl -s "$BASE_URL/why?organism=klebsiella"  | python3 -c 'import json,sys; print(json.load(sys.stdin)["bel"])')
if python3 -c "import sys; sys.exit(0 if $PS_BEL > $KL_BEL else 1)"; then
  pass "pseudomonas ($PS_BEL) beats klebsiella ($KL_BEL)"
else
  fail "pseudomonas ($PS_BEL) should beat klebsiella ($KL_BEL)"
fi
echo ""

echo "--- /why for an organism no rule named (should 404, not 500) ---"
CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/why?organism=nocardia")
if [ "$CODE" = "404" ]; then pass "unnamed organism -> HTTP 404"; else fail "unnamed organism -> HTTP $CODE (want 404)"; fi
echo ""

if [ "$FAILURES" -eq 0 ]; then
  echo "PASS: /why smoke test"
  exit 0
else
  echo "FAIL: /why smoke test -- $FAILURES check(s) failed"
  exit 1
fi