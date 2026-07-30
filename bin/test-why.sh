#!/usr/bin/env bash

# Smoke-test the WHY/HOW explanation endpoint over HTTP. Asserts the culture-1
# scenario, runs inference, then asks /why for the authoritative belief derivation
# (composition arithmetic + verified provenance) of a chained species (klebsiella)
# and a combined-belief species (pseudomonas).
#
# Prerequisites: the neomycin bridge running on port 8090 (see CLAUDE.md "Build &
# Load"), e.g. (load "neomycin.lisp").

BASE_URL="${LISA_BRIDGE_URL:-http://localhost:8090}"

echo "=== /why smoke test (culture-1) ==="
echo ""

echo "--- Resetting session ---"
curl -s -X POST "$BASE_URL/reset" | python3 -m json.tool
echo ""

echo "--- Asserting culture-1 facts ---"
curl -s -X POST "$BASE_URL/assert-fact" \
  -d '{"fact_type":"compromised-host","entity":"patient-1","value":"t","entity_class":"patient"}' > /dev/null
curl -s -X POST "$BASE_URL/assert-fact" \
  -d '{"fact_type":"burn","entity":"patient-1","value":"serious","entity_class":"patient"}' > /dev/null
curl -s -X POST "$BASE_URL/assert-fact" -d '{"fact_type":"culture-site","value":"blood"}' > /dev/null
curl -s -X POST "$BASE_URL/assert-fact" -d '{"fact_type":"gram","entity":"organism-1","value":"neg"}' > /dev/null
curl -s -X POST "$BASE_URL/assert-fact" -d '{"fact_type":"morphology","entity":"organism-1","value":"rod"}' > /dev/null
curl -s -X POST "$BASE_URL/assert-fact" -d '{"fact_type":"aerobicity","entity":"organism-1","value":"aerobic"}' > /dev/null
echo "asserted."
echo ""

echo "--- Running inference ---"
curl -s -X POST "$BASE_URL/run-inference" | python3 -m json.tool
echo ""

echo "--- /why klebsiella (chained: composes through the enterobacteriaceae class) ---"
curl -s -X POST "$BASE_URL/why" -d '{"organism":"klebsiella"}' | python3 -m json.tool
echo ""

echo "--- /why pseudomonas (combined belief from two rules) ---"
curl -s "$BASE_URL/why?organism=pseudomonas" | python3 -m json.tool
echo ""