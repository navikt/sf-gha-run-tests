#!/bin/bash
set -Eeuo pipefail

trap 'status=$?; printf "ERROR: %s:%s: command failed (exit %s)\n" "${BASH_SOURCE[0]}" "$LINENO" "$status" >&2; exit "$status"' ERR

: "${TARGET_ORG:?TARGET_ORG must be set}"
: "${REQUIRED_CODE_COVERAGE:?REQUIRED_CODE_COVERAGE must be set}"

command -v sf >/dev/null
command -v jq >/dev/null

jq -en --arg threshold "$REQUIRED_CODE_COVERAGE" '
  $threshold | tonumber | select(. >= 0 and . <= 100)
' > /dev/null

is_code_covered=false
code_coverage=0
code_coverage_text="## Code Coverage"$'\n\n'
is_test_success=false
sf_exit=0
step_summary="# Test Summary"$'\n\n'

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p test-run
rm -f -- test-run/test-run.json test-run/results.json \
  test-run/summary.md test-run/step-summary.md \
  test-run/coverage/coverage-summary.json test-run/coverage/text.txt

echo "Target org: $TARGET_ORG"
echo "Required code coverage: $REQUIRED_CODE_COVERAGE"

sf project deploy start \
  --target-org "$TARGET_ORG" \
  --dry-run \
  --test-level RunRelevantTests \
  --coverage-formatters json-summary \
  --coverage-formatters text \
  --results-dir test-run \
  --source-dir force-app \
  --json > test-run/test-run.json || sf_exit=$?

if [[ "$sf_exit" -ne 0 ]]; then
  echo "::error::Test run failed with exit code $sf_exit"
  bash "$script_dir/create-error-summary.sh"
  step_summary+="$(< test-run/summary.md)"
  step_summary+=$'\n\n'
else
  is_test_success=true
fi

if [[ -f test-run/coverage/coverage-summary.json ]]; then
  code_coverage=$(jq -er '
    .total.lines.pct
    | select(type == "number")
    | select(. >= 0 and . <= 100)
  ' test-run/coverage/coverage-summary.json)

  # Round down the code coverage to the nearest integer for comparison
  is_code_covered=$(jq -n \
    --argjson coverage "$code_coverage" \
    --arg threshold "$REQUIRED_CODE_COVERAGE" \
    '($coverage | floor) >= ($threshold | tonumber | floor)')
  if [[ "$is_code_covered" == true ]]; then
    code_coverage_text+="Code coverage criteria met."
  else
    code_coverage_text+="Code coverage criteria not met."
  fi
  code_coverage_text+=$'\n\n'
  code_coverage_text+="Required code coverage: $REQUIRED_CODE_COVERAGE%  "
  code_coverage_text+=$'\n'
  code_coverage_text+="Actual code coverage: $code_coverage%"
  code_coverage_text+=$'\n\n'
else
  echo "::warning::Unable to retrieve test coverage"
fi

if [[ -f test-run/coverage/text.txt ]]; then
  code_coverage_text+=$'```text\n'
  code_coverage_text+="$(< test-run/coverage/text.txt)"
  code_coverage_text+=$'\n```'
else
  echo "::warning::Coverage summary not found."
fi

step_summary+="$code_coverage_text"

printf '%s\n' "$step_summary" > test-run/step-summary.md

jq -n \
  --argjson code_coverage "$code_coverage" \
  --argjson is_code_covered "$is_code_covered" \
  --argjson is_test_success "$is_test_success" \
  '{
    code_coverage: $code_coverage,
    is_code_covered: $is_code_covered,
    is_test_success: $is_test_success
  }' > test-run/results.json

jq -e '
  (type == "object") and
  (.code_coverage | type == "number") and
  (.code_coverage >= 0 and .code_coverage <= 100) and
  (.is_code_covered | type == "boolean") and
  (.is_test_success | type == "boolean")
' test-run/results.json > /dev/null

echo "Sf exit code: $sf_exit"
echo "Code coverage: $code_coverage"
echo "Is code covered: $is_code_covered"
echo "Is test success: $is_test_success"