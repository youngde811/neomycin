#!/usr/bin/env bash

# End-to-end smoke test for the therapy phase (design doc step (c)). Drives the
# live bridge: assert the culture-1 scenario, run inference, then exercise
# POST /recommend-therapy -- once with no patient state, once with a cephalosporin
# allergy -- checking the regimen and the recorded exclusion.
#
# Assumes the bridge is already running (see CLAUDE.md "Build & Load"). Start it,
# then: ./bin/test-therapy.sh
#
# NOT FOR CLINICAL USE -- the pharmacology KB is schematic and illustrative.

set -euo pipefail

BASE_URL="${LISA_BRIDGE_URL:-http://localhost:8090}"
fail() { echo "FAIL: $*" >&2; exit 1; }

echo "=== Therapy phase smoke test (culture-1) ==="

echo "--- Resetting session ---"
curl -sf -X POST "$BASE_URL/reset" >/dev/null

echo "--- Asserting culture-1 findings ---"
assert() {
  curl -sf -X POST "$BASE_URL/assert-fact" -d "$1" >/dev/null \
    || fail "assert-fact failed for: $1"
}
assert '{"fact_type":"compromised-host","entity":"patient-1","value":"t","entity_class":"patient"}'
assert '{"fact_type":"burn","entity":"patient-1","value":"serious","entity_class":"patient"}'
assert '{"fact_type":"culture-site","value":"blood"}'
assert '{"fact_type":"culture-age","value":"3"}'
assert '{"fact_type":"gram","entity":"organism-1","value":"neg"}'
assert '{"fact_type":"morphology","entity":"organism-1","value":"rod"}'
assert '{"fact_type":"aerobicity","entity":"organism-1","value":"aerobic"}'

echo "--- Running inference ---"
curl -sf -X POST "$BASE_URL/run-inference" >/dev/null

echo ""
echo "--- Recommend therapy (no contraindications) ---"
REC=$(curl -sf -X POST "$BASE_URL/recommend-therapy" -d '{"patient":[]}')
echo "$REC" | python3 -m json.tool

# A gram-negative culture must yield at least one drug and leave nothing uncovered.
echo "$REC" | python3 -c '
import sys, json
r = json.load(sys.stdin)
assert len(r["regimen"]) >= 1, "expected a non-empty regimen"
# THIS COUNT HAS MOVED THREE TIMES AND THE HISTORY IS THE WARNING. It read 3 when the
# script was authored (2026-07-20), silently became wrong when the family backstop was
# suppressed (5317e30, 2026-07-29) and stayed wrong for weeks because bin/*.sh lives
# outside asdf:test-system and nothing runs it; it went to 2 deliberately at v0.11,
# when the candidate-set shape made organisms share one unit of belief; and it is 3
# again after Category B, for the opposite reason to the original 3 -- not a family
# backstop, but a real organism the corpus had been wrongly excluding.
treated = sorted(i["organism"] for i in r["items_to_treat"])
# THREE since Category B. Graded answers put e-coli in the differential at 0.232 --
# ahead of both the others -- where the singleton context rules had claimed a burn or
# a compromised host made it impossible. It never was: E. coli is the commonest
# gram-negative bacteraemia isolate there is, and the corpus previously could not say
# so. The regimen is still a single agent, so a wider differential did not widen the
# treatment.
assert treated == ["e-coli", "klebsiella", "pseudomonas"], \
    "expected e-coli, klebsiella and pseudomonas above the gate, got %r" % (treated,)
assert len(r["uncovered"]) == 0, "expected nothing uncovered, got %r" % (r["uncovered"],)
assert "solver" in r and "belief_system" in r, "response should echo solver + belief_system"
print("  OK: %d-drug regimen, %d items treated, none uncovered" % (len(r["regimen"]), len(r["items_to_treat"])))
' || fail "no-contraindication recommendation did not meet expectations"

echo ""
echo "--- Recommend therapy (cephalosporin allergy) ---"
REC2=$(curl -sf -X POST "$BASE_URL/recommend-therapy" -d '{"patient":["allergy-cephalosporin"]}')
echo "$REC2" | python3 -m json.tool

# Ceftazidime must be excluded (with reason), and an alternative must still cover.
echo "$REC2" | python3 -c '
import sys, json
r = json.load(sys.stdin)
excl = [e["drug"] for e in r["excluded"]]
assert "ceftazidime" in excl, "expected ceftazidime among excluded, got %r" % (excl,)
assert all(rx["drug"] != "ceftazidime" for rx in r["regimen"]), "ceftazidime must not be in the regimen"
assert len(r["uncovered"]) == 0, "expected full coverage by an alternative, got %r" % (r["uncovered"],)
print("  OK: ceftazidime excluded, still fully covered by an alternative")
' || fail "contraindication recommendation did not meet expectations"

echo ""
echo "--- Objective dial: same case, two stewardship policies ---"
# The objective is a policy dial (exact-solver-design.md 3.5). Both settings must
# cover the case; spectrum-sparing should reach for a narrower agent, and each
# response must report the OTHER one's pick under alternative_agents -- the payload
# property that makes "is there a narrower option?" answerable (1.1).
LEX=$(curl -sf -X POST "$BASE_URL/recommend-therapy" -d '{"patient":[],"objective":"lexicographic"}')
SPARE=$(curl -sf -X POST "$BASE_URL/recommend-therapy" -d '{"patient":[],"objective":"spectrum-sparing"}')

python3 -c '
import sys, json
lex, spare = json.loads(sys.argv[1]), json.loads(sys.argv[2])
for label, r in (("lexicographic", lex), ("spectrum-sparing", spare)):
    assert r["objective"] == label, "response must echo the objective it used"
    assert len(r["uncovered"]) == 0, "%s left something uncovered: %r" % (label, r["uncovered"])
    assert "alternative_agents" in r, "%s: payload must carry alternative_agents" % label
lex_drugs   = sorted(d["drug"] for d in lex["regimen"])
spare_drugs = sorted(d["drug"] for d in spare["regimen"])
# Each regimen must appear in the other'"'"'s alternatives, so neither can imply it
# was the only option.
lex_alts   = {a["drug"] for a in lex["alternative_agents"]}
spare_alts = {a["drug"] for a in spare["alternative_agents"]}
if lex_drugs != spare_drugs:
    assert set(spare_drugs) & lex_alts, "spectrum-sparing pick absent from default alternatives"
    assert set(lex_drugs) & spare_alts, "default pick absent from spectrum-sparing alternatives"
    print("  OK: objectives diverge (%s vs %s), each listed in the other'"'"'s alternatives"
          % (",".join(lex_drugs), ",".join(spare_drugs)))
else:
    print("  OK: objectives agree on %s (no divergence for this case)" % ",".join(lex_drugs))
' "$LEX" "$SPARE" || fail "objective dial did not meet expectations"

echo ""
echo "--- Rejecting an unknown objective ---"
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE_URL/recommend-therapy" \
       -d '{"objective":"cheapest"}')
[ "$CODE" = "500" ] || fail "an unknown objective should error, got HTTP $CODE"
echo "  OK: unknown objective rejected (HTTP $CODE) rather than silently defaulting"

echo ""
echo "=== Therapy smoke test PASSED ==="