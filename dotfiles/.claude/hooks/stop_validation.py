#!/usr/bin/env python3
"""Stop hook: block Claude from finishing until format check passes."""
import json
import pathlib
import subprocess
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
FORMAT_EXTS = {".cpp", ".h", ".cc", ".cxx", ".cmake"}

data = json.load(sys.stdin)

# Guard against recursive invocation — stop hooks can trigger stop events
if data.get("stop_hook_active", False):
    sys.exit(0)

# Skip if no C/C++ or CMake files were modified this session
diff = subprocess.run(
    ["git", "status", "--porcelain"],
    capture_output=True,
    text=True,
    cwd=REPO_ROOT,
)
changed = [line[3:].strip() for line in diff.stdout.splitlines()]
needs_check = any(
    pathlib.Path(f).suffix in FORMAT_EXTS or pathlib.Path(f).name == "CMakeLists.txt"
    for f in changed
)
if not needs_check:
    sys.exit(0)

try:
    result = subprocess.run(
        ["tools/format.sh", "check"],
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
        timeout=60,
    )
except subprocess.TimeoutExpired:
    print(json.dumps({
        "decision": "block",
        "reason": "Format check timed out after 60s. Check for a hung clang-format or cmake-format process.",
    }))
    sys.exit(0)

if result.returncode != 0:
    parts = ["Format check failed. Run `tools/format.sh format` to fix."]
    if result.stdout.strip():
        parts.append(result.stdout[-2000:].strip())
    if result.stderr.strip():
        parts.append(result.stderr[-2000:].strip())
    print(json.dumps({"decision": "block", "reason": "\n".join(parts)}))

sys.exit(0)
