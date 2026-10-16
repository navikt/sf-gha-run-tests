#!/bin/bash
jq -r '
  . as $cli
  | ($cli.result // {}) as $result
  | ($result.details // {}) as $details
  | ($details.runTestResult // {}) as $tests
  | (if ($result.success // false) or ($cli.status == 0)
    then "## Salesforce run passed"
    else "## Salesforce run failed"
    end),
  "",
  "- Result: `\($result.status // "No deployment result")`",
  "- Tests: \($tests.numTestsRun // 0) run, \($tests.numFailures // (($tests.failures // []) | length)) failed",
  (if (($details.componentFailures // []) | length) > 0 then
      "",
      "### Component failures",
      "",
      (($details.componentFailures // [])[] |
        "- `\(.fullName // .fileName // "Unknown component")`: \(.problem // .error // "No details")")
    else empty end),
  (if (($tests.failures // []) | length) > 0 then
      "",
      "### Test failures",
      "",
      (($tests.failures // [])[] |
        "- `\(.name // "Unknown test")#\(.methodName // "unknown method")`: \(.message // "No details")")
    else empty end),
  (if ($cli.message // "") != "" then
      "",
      "### CLI message",
      "",
      $cli.message
    else empty end)
' test-run/test-run.json > test-run/summary.md