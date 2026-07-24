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
assert len(r["items_to_treat"]) == 3, "expected 3 items to treat (pseudomonas, enterobacteriaceae, klebsiella)"
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
echo "=== Therapy smoke test PASSED ==="