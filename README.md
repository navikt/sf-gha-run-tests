# sf-gha-run-tests

GitHub Action that runs relevant Apex tests for Salesforce code and reports test results and code coverage.

## Prerequisites

- Salesforce CLI (`sf`) and `jq` must be installed.
- Salesforce CLI must be authenticated to the target org. `target-org` must be an alias or another value accepted by the CLI.
- Source code must be in `force-app` in the workspace.
- The action uses its bundled scripts. Run it from the workspace containing `force-app`.

## Usage

```yaml
- name: Run Apex tests
    id: apex-tests
    uses: navikt/sf-gha-run-tests@<tag-or-sha>
    with:
        target-org: my-org
        required-code-coverage: '85'
```

`target-org` is required. `required-code-coverage` is marked as required in the action metadata and has a default value of `85`.

The action runs `sf project deploy start` as a dry run against `force-app`, using the `RunRelevantTests` test level. It collects line coverage in JSON and text formats. Coverage is compared with the threshold as an integer percentage.

Test results and coverage are shown in the GitHub Actions step summary. If the run fails, the action also creates a summary of deployment and test failures. The action sets status outputs but does not itself exit with a failure status when tests fail or coverage is below the threshold. Use the outputs to fail the workflow for either condition:

```yaml
- name: Check test results
    if: steps.apex-tests.outputs.is-test-success != 'true' || steps.apex-tests.outputs.is-code-covered != 'true'
    run: exit 1
```

Unexpected script errors, missing dependencies, invalid coverage data, and invalid inputs fail the action immediately. Required coverage must be a number between `0` and `100`. Missing coverage reports produce `code-coverage=0` and `is-code-covered=false`.

## Outputs

| Output | Description |
| --- | --- |
| `code-coverage` | Line coverage percentage, or `0` if coverage cannot be retrieved. |
| `is-code-covered` | `true` if coverage meets the threshold; otherwise `false`. |
| `is-test-success` | `true` if the Salesforce run succeeds; otherwise `false`. |

## Test Run Files

The action writes Salesforce CLI results to `test-run/` in the workflow workspace. This includes `test-run.json`, coverage reports under `coverage/`, `step-summary.md`, and `summary.md` when the run fails. Generated reports consumed by the script are cleared before each run to prevent stale results.

The script can also run outside GitHub Actions with `TARGET_ORG` and `REQUIRED_CODE_COVERAGE` set. It writes `results.json` containing numeric `code_coverage` and boolean `is_code_covered` and `is_test_success` fields. A handled Salesforce failure is reported through these fields; unexpected script errors exit nonzero.

Later steps in the same job can read these files directly. To use them in another job or download them after the workflow completes, upload the directory as an artifact:

```yaml
- name: Upload test results
    if: always()
    uses: actions/upload-artifact@v4
    with:
        name: salesforce-test-results
        path: test-run/
        if-no-files-found: ignore
```

## Henvendelser

Spørsmål knyttet til koden eller prosjektet kan stilles som issues her på GitHub.

## For NAV-ansatte

Interne henvendelser kan sendes via Slack i kanalen #platforce.
