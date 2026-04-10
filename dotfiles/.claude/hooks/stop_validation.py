#!/usr/bin/env python3
"""Stop hook: format check (blocking) + unpushed commits reminder (non-blocking)."""
import json
import pathlib
import subprocess
import sys

def _find_repo_root() -> pathlib.Path:
    """Find the main repo root, works from worktrees and nested repos."""
    # Prefer __file__-based resolution — always correct when the script lives
    # in <repo>/.claude/hooks/.  This avoids bugs when CWD is inside a nested
    # git repo (e.g. docs/research/) where git rev-parse returns the wrong root.
    file_root = pathlib.Path(__file__).resolve().parents[2]
    if (file_root / "tools" / "format.sh").exists():
        return file_root

    # Fallback: git rev-parse (useful inside worktrees where __file__ might
    # resolve through a symlink to the main repo while the worktree is elsewhere).
    try:
        git_common = subprocess.run(
            ["git", "rev-parse", "--git-common-dir"],
            capture_output=True, text=True, timeout=5,
        )
        if git_common.returncode == 0:
            git_dir = pathlib.Path(git_common.stdout.strip())
            if not git_dir.is_absolute():
                git_dir = pathlib.Path.cwd() / git_dir
            candidate = git_dir.resolve().parent
            # Sanity check: the detected root must contain format.sh
            if (candidate / "tools" / "format.sh").exists():
                return candidate
    except (subprocess.TimeoutExpired, OSError):
        pass
    return file_root


REPO_ROOT = _find_repo_root()
FORMAT_EXTS = {".cpp", ".h", ".cc", ".cxx", ".cmake"}

data = json.load(sys.stdin)

# Guard against recursive invocation — stop hooks can trigger stop events
if data.get("stop_hook_active", False):
    sys.exit(0)

# Skip if no C/C++ or CMake files were modified this session
try:
    git_status = subprocess.run(
        ["git", "status", "--porcelain"],
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
        timeout=10,
    )
except subprocess.TimeoutExpired:
    git_status = None

needs_check = git_status is None or any(
    (p := pathlib.Path(line[3:].strip())).suffix in FORMAT_EXTS
    or p.name == "CMakeLists.txt"
    for line in git_status.stdout.splitlines()
    if len(line) > 3
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
    # Auto-fix: run format, then re-check
    subprocess.run(
        ["tools/format.sh", "format"],
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
        timeout=60,
    )
    try:
        recheck = subprocess.run(
            ["tools/format.sh", "check"],
            capture_output=True,
            text=True,
            cwd=REPO_ROOT,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        recheck = None

    if recheck is None or recheck.returncode != 0:
        parts = ["Format check failed even after auto-fix. Please investigate manually."]
        src = recheck or result
        if src.stdout.strip():
            parts.append(src.stdout[-2000:].strip())
        if src.stderr.strip():
            parts.append(src.stderr[-2000:].strip())
        print(json.dumps({"decision": "block", "reason": "\n".join(parts)}))

# --- Unpushed commits reminder ---
try:
    # Count commits ahead of upstream
    rev_list = subprocess.run(
        ["git", "rev-list", "@{u}..HEAD", "--count"],
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
        timeout=5,
    )
    if rev_list.returncode == 0:
        count = int(rev_list.stdout.strip())
        if count > 0:
            branch = subprocess.run(
                ["git", "branch", "--show-current"],
                capture_output=True,
                text=True,
                cwd=REPO_ROOT,
                timeout=5,
            )
            branch_name = branch.stdout.strip() if branch.returncode == 0 else "<unknown>"
            print(json.dumps({
                "decision": "allow",
                "reason": f"Reminder: you have {count} unpushed commit(s) on branch '{branch_name}'. Push when ready.",
            }))
except (subprocess.TimeoutExpired, OSError, ValueError):
    pass  # No upstream, detached HEAD, or other git issue — skip silently

sys.exit(0)
