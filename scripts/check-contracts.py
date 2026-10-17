#!/usr/bin/env python3
"""Check maintained names, module edges, source membership and generated identity."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
EDGES = {
    'DotListPlusCore': set(),
    'DotListPlusApplication': {'DotListPlusCore'},
    'DotListPlusStorage': {'DotListPlusApplication', 'DotListPlusCore'},
    'DotListPlusCloudKit': {'DotListPlusApplication', 'DotListPlusCore'},
    'DotListPlusUI': {'DotListPlusApplication', 'DotListPlusCore'},
}
SDK = {
    'DotListPlusCore': {'Foundation'},
    'DotListPlusApplication': {'Foundation'},
    'DotListPlusStorage': {'Foundation', 'Darwin', 'Glibc'},
    'DotListPlusCloudKit': {'Foundation', 'CloudKit', 'Network'},
    'DotListPlusUI': {'Foundation', 'SwiftUI', 'UniformTypeIdentifiers'},
}
HISTORICAL = {
    'reports/Original Final Version architecture.md',
    'research_notes/Original Final Version architecture/original_rules.md',
    'research_notes/Original Final Version architecture/variants.md',
    'research_notes/Original Final Version architecture/app_mapping.md',
    'docs/superpowers/plans/2026-10-15-icloud-sync.md',
}
# Only the explicit mapping and negative-test/check definitions may name retired declarations.
NAMING_EXCEPTIONS = HISTORICAL | {'docs/naming.md', 'scripts/check-contracts.py', 'scripts/test_contract_checks.py'}
SKIP_DIRS = {'.git', '.build', '.swiftpm', 'DerivedData', 'node_modules', '__pycache__', 'xcuserdata', 'test-results', 'playwright-report'}
OLD = re.compile(r'\b(?:WorkTask|TaskRules|AppState|SelectionRules|SyncView|StoredLists|AccountList|TaskEditor|WorkView|BreakdownView|DotListCore|DotListStorage|DotList|projectId|parentId|prerequisiteIds|groupProgress)\b')
errors = []
def fail(message): errors.append(message)

def files():
    for directory, dirs, names in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in names:
            yield Path(directory) / name

for path in files():
    relative = path.relative_to(ROOT).as_posix()
    if OLD.search(relative) and relative not in NAMING_EXCEPTIONS:
        fail('Retired name in path: ' + relative)
    if path.suffix not in {'.swift', '.md', '.py', '.json', '.yml', '.yaml', '.plist', '.entitlements', '.pbxproj', '.xcscheme'}:
        continue
    text = path.read_text()
    if relative in HISTORICAL and not text.startswith('> Historical reference.'):
        fail('Historical label missing: ' + relative)
    if relative not in NAMING_EXCEPTIONS:
        for index, line in enumerate(text.splitlines(), 1):
            if OLD.search(line) or re.search(r'Dot List(?! Plus)|[Bb]road tasks?', line):
                fail(f'Retired name: {relative}:{index}')
    if relative.startswith('Sources/') and path.suffix == '.swift':
        module = path.relative_to(ROOT).parts[1]
        if module not in EDGES:
            fail('Unexpected module: ' + module)
            continue
        allowed = EDGES[module] | SDK[module]
        for imported in re.findall(r'^\s*(?:@\w+\s+)?import\s+(\w+)', text, re.M):
            if imported not in allowed:
                fail(f'Forbidden import: {module} → {imported} in {relative}')
        if '@testable' in text or '@_exported' in text or '@_implementationOnly' in text:
            fail('Access-control workaround: ' + relative)
        if module in {'DotListPlusCore', 'DotListPlusApplication'}:
            if re.search(r'\b(?:FileManager|FileHandle|Bundle|fopen|rename)\b|(?:Data|String)\s*\(\s*contentsOf\s*:|\.write\s*\(\s*to:', text):
                fail('Filesystem operation in neutral module: ' + relative)
        if module == 'DotListPlusUI' and re.search(r'ListRules\.transition|ListMerge\.merge|JSONLocalStorage|CloudKitSync', text):
            fail('UI bypasses coordinator: ' + relative)
        # Fixture strings are confined to Tests, never production domain aliases.
        if re.search(r'\b(?:tasks|projectId|parentId|prerequisiteIds)\b|\.(?:group|chain|candidates|cursor)\b|(?:struct|enum)\s+(?:Selection|Change|Progress)\b|func\s+view\s*\(', text):
            fail('Retired domain field: ' + relative)

manifest = (ROOT / 'Package.swift').read_text()
actual = {}
for name, dependencies in re.findall(r'\.target\(name:\s*"([^"]+)"(?:,\s*dependencies:\s*\[([^]]*)\])?\)', manifest):
    actual[name] = set(re.findall(r'"([^"]+)"', dependencies))
declaration_count = len(re.findall(r'\.(?:target|executableTarget|binaryTarget|systemLibrary|plugin)\s*\(', manifest))
if actual != EDGES or declaration_count != len(actual):
    fail('Target dependencies differ from approved graph: ' + repr(actual))
if 'Package(name: "DotListPlus"' not in manifest:
    fail('Package name must be DotListPlus')
if set(p.name for p in (ROOT / 'Sources').iterdir() if p.is_dir() and any(p.iterdir())) != set(EDGES):
    fail('Unexpected module directory')

identity = json.loads((ROOT / 'product-identity.json').read_text())
expected = {'displayName': 'Dot List Plus', 'codeName': 'DotListPlus', 'fileName': 'dot-list-plus',
            'bundleID': 'com.vsodem.DotListPlus', 'cloudContainerID': 'iCloud.com.vsodem.DotListPlus',
            'providerID': 'cloudkit.iCloud.com.vsodem.DotListPlus.private.v1', 'cloudZone': 'DotListPlus',
            'localDirectory': 'DotListPlus', 'localFile': 'local-store-v1.json', 'backupFile': 'dot-list-plus-backup.json'}
if identity != expected:
    fail('Product identity differs from approved values')
project = ROOT / 'Apple/DotListPlus.xcodeproj/project.pbxproj'
if project.exists():
    if 'Sources/' in project.read_text():
        fail('Package source membership must use linked products')
app_sources = {p.name for p in (ROOT / 'Apple').rglob('*.swift')}
if app_sources != {'DotListPlusApp.swift', 'PushNotifications.swift'}:
    fail('App source membership must contain only startup and lifecycle glue')
for retired in ['index.html', '.nojekyll', '.github/workflows/playwright.yml', 'Apple/DotList.xcodeproj']:
    if (ROOT / retired).exists(): fail('Retired artifact remains: ' + retired)

result = subprocess.run([sys.executable, str(ROOT / 'scripts/generate-xcode-project.py'), '--check'], capture_output=True, text=True)
if result.returncode:
    fail(result.stdout + result.stderr)
if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
print('Naming, module boundaries, app membership and generated identity pass.')
