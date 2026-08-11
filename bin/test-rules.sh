#!/usr/bin/env bash

# Smoke-test the rule-catalogue endpoint over HTTP. /rules answers what the corpus
# CONTAINS -- rules, beliefs, premises, provenance -- without anything having to
# fire first, which is what lets the LLM's system prompt stop carrying a
# hand-maintained copy of the rulebase.
#
# Unlike the other bin/ scripts this asserts no facts and runs no inference: the
# catalogue is a property of the compiled rulebase, not of working memory.
#
# Prerequisites: the neomycin bridge running on port 8090 (see CLAUDE.md "Build &
# Load"), e.g. (load "neomycin.lisp").

BASE_URL="${LISA_BRIDGE_URL:-http://localhost:8090}"

echo "=== /rules smoke test ==="
echo ""

echo "--- Corpus shape (the summary rides on every response) ---"
curl -s "$BASE_URL/rules?name=__no_such_rule__" | python3 -c "
import json, sys
s = json.load(sys.stdin)['summary']
print('  %d rules: %d confirming, %d disconfirming'
      % (s['total'], s['confirming'], s['disconfirming']))
print('  organism-classes: ' + ', '.join(s['organism_classes']))
print('  identities (%d): ' % len(s['identities']) + ', '.join(s['identities']))
"
echo ""

echo "--- One cluster: staphylococcus (class + species + host factors + discriminators) ---"
curl -s "$BASE_URL/rules?cluster=staphylococcus" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print('  matched %d' % d['matched'])
for r in d['rules']:
    chained = ('  <- ' + r['chained_from']) if 'chained_from' in r else ''
    print('  %+.2f  %s%s' % (r['belief'], r['rule'], chained))
"
echo ""

echo "--- One rule in full (belief + premises + provenance) ---"
curl -s "$BASE_URL/rules?name=enterobacteriaceae-in-compromised-host-suggests-klebsiella" \
  | python3 -c "
import json, sys
print(json.dumps(json.load(sys.stdin)['rules'][0], indent=2))
"
echo ""

echo "--- Every ruling-out rule and what it argues against ---"
curl -s "$BASE_URL/rules?kind=disconfirming" | python3 -c "
import json, sys
for r in json.load(sys.stdin)['rules']:
    print('  %+.2f  %s' % (r['belief'], r['rule']))
    print('          targets: ' + ', '.join(r.get('targets', [])))
"
echo ""

echo "=== done ==="