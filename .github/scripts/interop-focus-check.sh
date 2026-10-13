#!/usr/bin/env bash
# Cross-implementation interop check: fhir-module output -> Blaze -> samply/focus.
#
# Asserts that criteria a researcher would actually send return the counts the
# synced data implies. Every scenario here corresponds to a defect that reached
# production once and was found by hand:
#
#   diagnosis   focus queried Condition while MIABIS puts sample-linked
#               diagnoses on Observation (samply/focus#373, fixed in v0.26.0)
#   sample_kind MoF-library wrote the ValueSet URL into Coding.system where
#               focus declares the CodeSystem (MoF-library#26, fixed in 1.4.0)
#   absent code a control: a criterion matching everything must not pass
#
# Expects an already-synced MIABIS Blaze. Run after trigger-sync-and-wait.sh.
#
#   BLAZE=http://localhost:5432/fhir FOCUS_IMAGE=ghcr.io/samply/focus:main \
#     ./interop-focus-check.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BLAZE="${BLAZE:-http://localhost:5432/fhir}"
FOCUS_IMAGE="${FOCUS_IMAGE:-samply/focus:main}"
PORT="${PORT:-8082}"
APP_ID="focus.proxy1.broker.samply.de"
PASS=0; FAIL=0

run_scenario() {
    local desc="$1" ast="$2" expected="$3"
    local tid ast_b64 body_b64 rf mp

    tid="$(python3 -c 'import uuid; print(uuid.uuid4())')"
    ast_b64="$(printf '%s' "$ast" | base64 -w0)"
    body_b64="$(printf '{"lang":"ast","payload":"%s"}' "$ast_b64" | base64 -w0)"
    rf="$(mktemp)"

    MOCK_TASK_ID="$tid" FOCUS_APP_ID="$APP_ID" BODY_B64="$body_b64" \
        MOCK_PROXY_PORT="$PORT" RESULT_FILE="$rf" \
        python3 "$HERE/interop-mock-proxy.py" &
    mp=$!
    sleep 1

    docker run --rm --network host \
        -e BEAM_PROXY_URL="http://localhost:${PORT}" \
        -e BEAM_APP_ID_LONG="$APP_ID" \
        -e API_KEY=test \
        -e ENDPOINT_URL="${BLAZE}/" \
        -e BLAZE_URL="${BLAZE}/" \
        -e ENDPOINT_TYPE=blaze \
        -e OBFUSCATE=no \
        -e CQL_FLAVOUR=miabis \
        -e PROXY_ID=local.test \
        -e RUST_LOG=error \
        "$FOCUS_IMAGE" >/dev/null 2>&1 &

    wait "$mp" 2>/dev/null || true
    docker ps -q --filter "ancestor=$FOCUS_IMAGE" | xargs -r docker kill >/dev/null 2>&1

    local actual; actual="$(cat "$rf" 2>/dev/null || echo '-1')"; rm -f "$rf"
    if [[ "$actual" == "$expected" ]]; then
        printf '  ok    %-46s count=%s\n' "$desc" "$actual"; PASS=$((PASS+1))
    else
        printf '  FAIL  %-46s expected=%s got=%s\n' "$desc" "$expected" "$actual"; FAIL=$((FAIL+1))
    fi
}

ast_diagnosis() {
    printf '{"ast":{"operand":"OR","children":[{"operand":"AND","children":[{"operand":"OR","children":[{"key":"diagnosis","type":"EQUALS","system":"","value":"%s"}]}]}]},"id":"%s"}' "$1" "$2"
}
ast_sample_kind() {
    printf '{"ast":{"operand":"OR","children":[{"operand":"AND","children":[{"operand":"OR","children":[{"key":"sample_kind","type":"EQUALS","system":"","value":"%s"}]}]}]},"id":"%s"}' "$1" "$2"
}

echo "==> interop: fhir-module -> Blaze -> focus (CQL_FLAVOUR=miabis)"
echo "    blaze=${BLAZE}  focus=${FOCUS_IMAGE}"
echo ""

run_scenario 'empty AST — every donor'            '{"ast":{"operand":"AND","children":[]},"id":"i-0"}' "${EXPECT_ALL:-1}"
run_scenario 'diagnosis C50.9 — on Observation'   "$(ast_diagnosis C50.9 i-1)"  "${EXPECT_C509:-1}"
run_scenario 'diagnosis C61 — on Observation'     "$(ast_diagnosis C61 i-2)"    "${EXPECT_C61:-1}"
run_scenario 'diagnosis C99 — absent, control'    "$(ast_diagnosis C99 i-3)"    "0"
run_scenario 'sample_kind blood-serum'            "$(ast_sample_kind blood-serum i-4)" "${EXPECT_SERUM:-1}"

echo ""
echo "    ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
