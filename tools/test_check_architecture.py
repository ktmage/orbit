import pathlib
import tempfile
import unittest

from check_architecture import violations


class ArchitectureChecks(unittest.TestCase):
    def check_manifest(self, source):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            package = root / "core/event"
            package.mkdir(parents=True)
            (package / "moon.pkg").write_text(source)
            return list(violations(root))

    def test_import_with_a_comment_still_rejects_another_domain(self):
        errors = self.check_manifest('import // dependency\n{ "ktmage/orbit/core/service", }')
        self.assertEqual(len(errors), 1)
        self.assertIn("core/event -> core/service", errors[0])

    def test_commented_import_does_not_create_a_dependency(self):
        self.assertEqual(self.check_manifest('// import { "ktmage/orbit/core/service", }'), [])

    def test_string_contents_do_not_create_a_dependency(self):
        self.assertEqual(self.check_manifest('description = "import { \\"ktmage/orbit/core/service\\" }"'), [])

    def test_test_only_dependencies_remain_allowed_with_comments(self):
        source = 'import { "ktmage/orbit/core/service", } for // test mode\n"test"'
        self.assertEqual(self.check_manifest(source), [])

    def test_normal_import_after_test_import_is_still_checked(self):
        source = 'import { "ktmage/orbit/core/service", } for "test"\nimport { "ktmage/orbit/core/lifecycle", }'
        self.assertEqual(len(self.check_manifest(source)), 1)


if __name__ == "__main__":
    unittest.main()
