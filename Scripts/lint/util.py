import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent

EXTENSIONS_TO_CHECK = set(
    (".h", ".hpp", ".cpp", ".m", ".mm", ".pch", ".swift", ".proto")
)


def get_changed_paths(ref, diff_filter=None):
    filter_args = [f"--diff-filter={diff_filter}"] if diff_filter else []
    output = subprocess.run(
        ["git", "diff", "--name-only", "--no-renames", "-z", *filter_args, ref],
        cwd=REPO_ROOT,
        capture_output=True,
        encoding="utf8",
        check=True,
    ).stdout
    return [path for path in output.split("\0") if path]
