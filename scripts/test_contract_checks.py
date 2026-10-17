#!/usr/bin/env python3
"""Mutate isolated copies: checks must reject each architectural/naming regression."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class ContractCheckTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ['Sources', 'Apple', 'scripts', 'docs', 'research_notes', 'reports', 'Tests', '.github']:
            shutil.copytree(ROOT / name, self.root / name, ignore=shutil.ignore_patterns('__pycache__', 'xcuserdata'))
        for name in ['Package.swift', 'product-identity.json', 'README.md']:
            shutil.copy2(ROOT / name, self.root / name)

    def run_check(self):
        return subprocess.run(['python3', str(self.root / 'scripts/check-contracts.py')], capture_output=True, text=True)

    def assertRejected(self, message):
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(message, result.stdout + result.stderr)

    def testCleanAndNonWritingGenerator(self):
        before = {p.relative_to(self.root): (p.read_bytes(), p.stat().st_mtime_ns) for p in self.root.rglob('*') if p.is_file()}
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        after = {p.relative_to(self.root): (p.read_bytes(), p.stat().st_mtime_ns) for p in self.root.rglob('*') if p.is_file()}
        self.assertEqual(before, after)

    def testForbiddenImportInNewFile(self):
        (self.root / 'Sources/DotListPlusCore/Forbidden.swift').write_text('import SwiftUI\n')
        self.assertRejected('Forbidden import')

    def testUnapprovedTargetDependency(self):
        path = self.root / 'Package.swift'
        path.write_text(path.read_text().replace('.target(name: "DotListPlusCore")', '.target(name: "DotListPlusCore", dependencies: ["DotListPlusUI"])'))
        self.assertRejected('Target dependencies')

    def testUnapprovedTargetWithPath(self):
        path = self.root / 'Package.swift'
        path.write_text(path.read_text().replace('var targets: [Target] = [', 'var targets: [Target] = [\n.target(name: "Extra", dependencies: ["DotListPlusStorage"], path: "Extra"),'))
        (self.root / 'Extra').mkdir()
        (self.root / 'Extra/Other.swift').write_text('import DotListPlusStorage\n')
        self.assertRejected('Target dependencies')

    def testStaleGeneratedIdentity(self):
        path = self.root / 'Sources/DotListPlusCore/ProductIdentity.swift'
        path.write_text(path.read_text() + '// changed\n')
        self.assertRejected('Stale generated files')

    def testOldNameInNewFileAndPath(self):
        (self.root / 'Sources/DotListPlusCore/WorkTask.swift').write_text('struct WorkTask {}\n')
        self.assertRejected('Retired name')

    def testNewUnapprovedModule(self):
        path = self.root / 'Sources/Surprise'
        path.mkdir()
        (path / 'Other.swift').write_text('import Foundation\n')
        self.assertRejected('Unexpected module')

    def testDirectPackageSourceMembership(self):
        path = self.root / 'Apple/DotListPlus.xcodeproj/project.pbxproj'
        path.write_text(path.read_text().replace('DotListPlusApp.swift', '../Sources/DotListPlusCore/ListState.swift'))
        self.assertRejected('Package source membership')

    def testMissingGeneratedOutputDoesNotCreateDirectories(self):
        path = self.root / 'Apple/DotListPlus.xcodeproj/xcshareddata'
        shutil.rmtree(path)
        result = subprocess.run(['python3', str(self.root / 'scripts/generate-xcode-project.py'), '--check'], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(path.exists())

if __name__ == '__main__':
    unittest.main()
