#!/usr/bin/env bash
# IG validation of real ETL output.
#
# Exports every resource the ETL wrote into Blaze, verbatim, and validates each
# against the published MIABIS-on-FHIR implementation guide package. Validating
# the IG's own examples — which the IG repository already does — says nothing
# about what the ETL emits; this closes that gap.
#
# It is the check that would have caught MoF-library's four validation defects,
# all of which were detectable the whole time: the ValueSet URL in
# Coding.system failing the required DetailedSampleTypeVS binding, the empty
# Condition.stage failing base FHIR con-1 on every Condition written, the
# organisational_capabilities typo, and BASE_URL prepended to an already
# absolute gender code system. They survived because nobody validated output.
#
# Expects an already-synced MIABIS Blaze. Run after trigger-sync-and-wait.sh.
#
#   BLAZE=http://localhost:5432/fhir ./validate-etl-output.sh
set -uo pipefail

BLAZE="${BLAZE:-http://localhost:5432/fhir}"
IG_PACKAGE="${IG_PACKAGE:-https://fhir.miabis.bbmri-eric.eu/package.tgz}"
VALIDATOR="${VALIDATOR:-validator_cli.jar}"
TYPES="${TYPES:-Patient Specimen Observation Condition Organization}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> exporting ETL output from ${BLAZE}"
total=0
for t in $TYPES; do
    n=$(curl -sS "${BLAZE}/${t}?_count=1000" | python3 "$(dirname "$0")/export-from-blaze.py" "$WORK" "$t")
    printf '    %-14s %s\n' "$t" "$n"
    total=$((total + n))
done

if [[ "$total" -eq 0 ]]; then
    echo "ERROR: no resources exported — did the sync run?" >&2
    exit 1
fi
echo "    ${total} resources"

if [[ ! -f "$VALIDATOR" ]]; then
    echo "==> downloading validator"
    wget -q https://github.com/hapifhir/org.hl7.fhir.core/releases/latest/download/validator_cli.jar -O "$VALIDATOR" || exit 1
fi

echo "==> validating against ${IG_PACKAGE}"
out="$WORK/validator.out"
java -jar "$VALIDATOR" -version 4.0.1 -ig "$IG_PACKAGE" "$WORK"/*.json > "$out" 2>&1
rc=$?

errors=$(grep -c "^\s*Error @" "$out" 2>/dev/null || true)
[[ -z "$errors" ]] && errors=0

echo ""
grep -E "^\s*(Error|Warning) @" "$out" | sed 's/^/    /' | head -40
unresolved=$(grep -c "has not been checked because it could not be found" "$out" 2>/dev/null || true)
[[ -z "$unresolved" ]] && unresolved=0
if [[ "$unresolved" -gt 0 ]]; then
    echo "    NOTE — ${unresolved} resource(s) claim a profile the IG does not define, so they"
    echo "           were validated against base FHIR only. Conformance was not actually checked."
    grep "has not been checked because it could not be found" "$out" \
        | sed -E "s/.*Profile reference '([^']*)'.*/             \1/" | sort -u
    echo ""
    [[ "${STRICT_UNRESOLVED:-0}" == "1" ]] && { echo "    FAIL — STRICT_UNRESOLVED is set"; exit 1; }
fi

echo ""
if [[ "$errors" -gt 0 ]]; then
    echo "    FAIL — ${errors} validation error(s) across ${total} resources"
    echo ""
    echo "    Full validator output:"
    sed 's/^/      /' "$out" | tail -40
    exit 1
fi
echo "    ok — ${total} resources, 0 errors (validator exit ${rc})"
