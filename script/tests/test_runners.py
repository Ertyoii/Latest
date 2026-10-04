import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1]
UI_SUITES = [
    "ComponentAppearanceTest", "MainWindowAppearanceTest",
    "SidebarInteractionTest", "SidebarAppearanceTest", "ToolbarInteractionTest",
    "InstallHelperInteractionTest", "ReleaseNotesWebViewTest", "UpdateActionInteractionTest",
]


class RunnerArgumentsTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.script = self.root / "script"
        self.script.mkdir()
        (self.script / "tests").mkdir()
        for name in ("test.sh", "build_and_run.sh"):
            shutil.copy2(SCRIPTS / name, self.script / name)
        checker = self.script / "check_structure.sh"
        checker.write_text("#!/bin/bash\nexit 0\n")
        checker.chmod(0o755)
        commands = self.root / "bin"
        commands.mkdir()
        self.calls = self.root / "calls"
        self.arguments = self.root / "arguments"
        self.lane = self.root / "lane"
        for name in ("xcodebuild", "pkill", "rm", "mkdir"):
            command = commands / name
            command.write_text(
                '#!/bin/bash\nprintf "%s\\n" "$0" >> "$CALLS"\n'
                'printf "%s\\n" "$@" > "$ARGUMENTS"\n'
                'printf "%s:%s\\n" "$TEST_RUNNER_LATEST_UI_TESTS" "$LATEST_UI_TESTS" > "$LANE"\n')
            command.chmod(0o755)
        self.environment = dict(os.environ, PATH=str(commands) + ":" + os.environ["PATH"],
                                CALLS=str(self.calls), ARGUMENTS=str(self.arguments),
                                LANE=str(self.lane), LATEST_UI_TESTS="1")

    def run_script(self, name, *arguments):
        return subprocess.run([str(self.script / name), *arguments], env=self.environment,
                              capture_output=True, text=True, timeout=5)

    def test_build_help_and_invalid_arguments_have_no_side_effects(self):
        for arguments, status in ((["--help"], 0), (["typo"], 2),
                                  (["run", "--unknown"], 2), (["run", "--signed", "extra"], 2)):
            with self.subTest(arguments=arguments):
                result = self.run_script("build_and_run.sh", *arguments)
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertFalse(self.calls.exists(), "Validation must precede build/kill/delete")

    def test_ui_skip_filter_preserves_the_ui_suite_selection(self):
        result = self.run_script("test.sh", "--ui", "-skip-testing:Latest Tests/Example")
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = self.arguments.read_text().splitlines()
        self.assertIn("-skip-testing:Latest Tests/Example", arguments)
        self.assertEqual([arg for arg in arguments if arg.startswith("-only-testing:")],
                         [f"-only-testing:Latest Tests/{suite}" for suite in UI_SUITES])
        self.assertEqual(self.lane.read_text().strip(), "1:1")

    def test_explicit_selection_and_other_lanes_are_preserved(self):
        for arguments, expected in (
            ([], []), (["--all"], []),
            (["--ui", "-only-testing:Latest Tests/Example"], ["-only-testing:Latest Tests/Example"]),
        ):
            with self.subTest(arguments=arguments):
                result = self.run_script("test.sh", *arguments)
                self.assertEqual(result.returncode, 0, result.stderr)
                received = self.arguments.read_text().splitlines()
                self.assertEqual([arg for arg in received if arg.startswith("-only-testing:")], expected)
                self.assertIn("-skip-testing:Latest Tests/AppPerformanceTest", received)
                background = not arguments
                self.assertEqual(self.lane.read_text().strip(), "0:0" if background else "1:1")
                for suite in UI_SUITES:
                    self.assertEqual(f"-skip-testing:Latest Tests/{suite}" in received, background)


if __name__ == "__main__":
    unittest.main()
