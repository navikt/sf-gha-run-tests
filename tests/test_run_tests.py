import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]


class RunTestsScriptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sf tests ")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.bin = self.work / "bin"
        self.bin.mkdir()
        sf = self.bin / "sf"
        sf.write_text(
            "#!/bin/bash\n"
            "set -euo pipefail\n"
            'if [[ "${MOCK_COVERAGE:-}" != missing ]]; then\n'
            "  mkdir -p test-run/coverage\n"
            '  printf \'%s\\n\' "$MOCK_COVERAGE" > test-run/coverage/coverage-summary.json\n'
            "  printf 'Coverage report\\n' > test-run/coverage/text.txt\n"
            "fi\n"
            'printf \'{"status":%s,"message":"Mock deployment"}\\n\' "${MOCK_EXIT:-0}"\n'
            'exit "${MOCK_EXIT:-0}"\n'
        )
        sf.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}",
            "TARGET_ORG": "test-org",
            "REQUIRED_CODE_COVERAGE": "85",
            "MOCK_COVERAGE": '{"total":{"lines":{"pct":100}}}',
            "MOCK_EXIT": "0",
        }

    def run_script(self):
        return subprocess.run(
            ["bash", str(ROOT / "scripts/run-tests.sh")],
            cwd=self.work,
            env=self.env,
            capture_output=True,
            text=True,
        )

    def results(self):
        return json.loads((self.work / "test-run/results.json").read_text())

    def test_success(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.results(),
            {"code_coverage": 100, "is_code_covered": True, "is_test_success": True},
        )

    def test_threshold_comparison_preserves_rounding(self):
        self.env["MOCK_COVERAGE"] = '{"total":{"lines":{"pct":85.1}}}'
        self.env["REQUIRED_CODE_COVERAGE"] = "85.9"
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.results()["is_code_covered"])

    def test_below_threshold(self):
        self.env["MOCK_COVERAGE"] = '{"total":{"lines":{"pct":84.9}}}'
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.results()["is_code_covered"])
        self.assertTrue(self.results()["is_test_success"])

    def test_deployment_failure_still_produces_results(self):
        self.env.update(MOCK_EXIT="1", MOCK_COVERAGE="missing")
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.results(),
            {"code_coverage": 0, "is_code_covered": False, "is_test_success": False},
        )
        self.assertIn(
            "Salesforce run failed",
            (self.work / "test-run/step-summary.md").read_text(),
        )

    def test_repeat_run_does_not_reuse_reports(self):
        self.assertEqual(self.run_script().returncode, 0)
        self.env["MOCK_COVERAGE"] = "missing"
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.results()["code_coverage"], 0)
        self.assertFalse(self.results()["is_code_covered"])
        summary = (self.work / "test-run/step-summary.md").read_text()
        self.assertEqual(summary.count("# Test Summary"), 1)
        self.assertNotIn("Coverage report", summary)

    def test_invalid_coverage_fails_without_results(self):
        for coverage in (
            "{}",
            "",
            "invalid",
            '{"total":{"lines":{"pct":null}}}',
            '{"total":{"lines":{"pct":101}}}',
        ):
            with self.subTest(coverage=coverage):
                self.env["MOCK_COVERAGE"] = coverage
                result = self.run_script()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("ERROR:", result.stderr)
                self.assertFalse((self.work / "test-run/results.json").exists())

    def test_invalid_required_coverage(self):
        for threshold in ("", "invalid", "-1", "101"):
            with self.subTest(threshold=threshold):
                self.env["REQUIRED_CODE_COVERAGE"] = threshold
                result = self.run_script()
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(result.stderr)
                self.assertFalse((self.work / "test-run/test-run.json").exists())

    def test_missing_target_org(self):
        self.env.pop("TARGET_ORG")
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("TARGET_ORG must be set", result.stderr)

    def test_missing_dependency(self):
        (self.bin / "sf").unlink()
        self.env["PATH"] = str(self.bin)
        result = subprocess.run(
            ["/bin/bash", str(ROOT / "scripts/run-tests.sh")],
            cwd=self.work,
            env=self.env,
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ERROR:", result.stderr)
        self.assertFalse((self.work / "test-run/results.json").exists())

    def test_report_write_failure(self):
        (self.work / "test-run/step-summary.md").mkdir(parents=True)
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ERROR:", result.stderr)
        self.assertFalse((self.work / "test-run/results.json").exists())

    def test_error_summary_failure(self):
        sf = self.bin / "sf"
        sf.write_text("#!/bin/bash\nprintf 'invalid JSON\\n'\nexit 1\n")
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ERROR:", result.stderr)
        self.assertFalse((self.work / "test-run/results.json").exists())

    def test_action_publishes_outputs(self):
        action = (ROOT / "action.yml").read_text()
        commands = textwrap.dedent(
            action.split("      run: |\n", 1)[1].split("      shell: bash", 1)[0]
        )
        for sf_exit in ("0", "1"):
            with self.subTest(sf_exit=sf_exit):
                output = self.work / "github-output"
                summary = self.work / "github-summary"
                output.write_text("")
                summary.write_text("")
                result = subprocess.run(
                    ["bash", "-e", "-o", "pipefail", "-c", commands],
                    cwd=self.work,
                    env={
                        **self.env,
                        "MOCK_EXIT": sf_exit,
                        "GITHUB_ACTION_PATH": str(ROOT),
                        "GITHUB_OUTPUT": str(output),
                        "GITHUB_STEP_SUMMARY": str(summary),
                    },
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(
                    output.read_text().splitlines(),
                    [
                        "code-coverage=100",
                        "is-code-covered=true",
                        f"is-test-success={'true' if sf_exit == '0' else 'false'}",
                    ],
                )
                self.assertIn("# Test Summary", summary.read_text())


if __name__ == "__main__":
    unittest.main()
