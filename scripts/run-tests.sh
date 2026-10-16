#!/bin/bash
is_code_covered=false
code_coverage=0
code_coverage_text="## Code Coverage"$'\n\n'
is_test_success=false
sf_exit=0
step_summary="# Test Summary"$'\n\n'


mkdir -p test-run
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
  bash scripts/create-error-summary.sh
  step_summary+="$(< test-run/summary.md)"
  step_summary+=$'\n\n'
else
  is_test_success=true
fi

if [[ -f test-run/coverage/coverage-summary.json ]]; then
  code_coverage=$(jq -r '.total.lines.pct' test-run/coverage/coverage-summary.json)

  # Round down the code coverage to the nearest integer for comparison
  if (( ${code_coverage%.*} >= ${REQUIRED_CODE_COVERAGE%.*} )); then
    is_code_covered=true

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

echo "Sf exit code: $sf_exit"
echo "Code coverage: $code_coverage"
echo "Is code covered: $is_code_covered"
echo "Is test success: $is_test_success"