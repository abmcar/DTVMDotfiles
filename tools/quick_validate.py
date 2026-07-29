#!/usr/bin/env python3
"""Strict, read-only validation for one portable agent skill."""

from __future__ import annotations

import argparse
import ast
import hashlib
import os
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

try:
    import yaml
except ImportError:
    print(
        "ERROR: PyYAML is required; install a compatible 6.x release",
        file=sys.stderr,
    )
    raise SystemExit(2)


MAX_SKILL_NAME_LENGTH = 64
MAX_DESCRIPTION_LENGTH = 1024
FRONTMATTER_RE = re.compile(r"\A---\r?\n(.*?)\r?\n---(?:\r?\n|\Z)", re.DOTALL)
NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
MARKDOWN_LINK_RE = re.compile(r"!?\[[^\]]*]\(([^)\n]+)\)")
RESOURCE_PATH_RE = re.compile(
    r"(?<![A-Za-z0-9_.-])(?:references|scripts|assets)/[A-Za-z0-9_./-]+"
)
TODO_RE = re.compile(r"\[(?:TODO|PLACEHOLDER)[^\]]*]|(?:TODO|PLACEHOLDER):", re.I)
BRAND_COLOR_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")
ALLOWED_SKILL_ENTRIES = {"SKILL.md", "agents", "assets", "references", "scripts"}
ALLOWED_FRONTMATTER_KEYS = {"name", "description"}
ALLOWED_OPENAI_TOP_LEVEL = {"interface", "dependencies", "policy"}
ALLOWED_INTERFACE_KEYS = {
    "display_name",
    "short_description",
    "icon_small",
    "icon_large",
    "brand_color",
    "default_prompt",
}
REQUIRED_INTERFACE_KEYS = {
    "display_name",
    "short_description",
    "default_prompt",
}
ALLOWED_TOOL_KEYS = {"type", "value", "description", "transport", "url"}
REQUIRED_TOOL_KEYS = {"type", "value", "description"}


class UniqueKeyLoader(yaml.SafeLoader):
    """Reject duplicate mapping keys instead of silently keeping the last."""


def _construct_unique_mapping(
    loader: UniqueKeyLoader, node: yaml.MappingNode, deep: bool = False
) -> dict[object, object]:
    mapping: dict[object, object] = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise yaml.constructor.ConstructorError(
                "while constructing a mapping",
                node.start_mark,
                f"found duplicate key {key!r}",
                key_node.start_mark,
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
    _construct_unique_mapping,
)


def load_yaml(text: str, label: str, errors: list[str]) -> object | None:
    try:
        return yaml.load(text, Loader=UniqueKeyLoader)
    except yaml.YAMLError as error:
        errors.append(f"{label}: invalid YAML: {error}")
        return None


def mapping_node_values(node: yaml.Node | None) -> dict[str, yaml.Node]:
    if not isinstance(node, yaml.MappingNode):
        return {}
    return {
        str(key_node.value): value_node
        for key_node, value_node in node.value
        if isinstance(key_node, yaml.ScalarNode)
    }


def require_quoted_string_nodes(
    node: yaml.Node | None,
    keys: set[str],
    label: str,
    errors: list[str],
) -> None:
    values = mapping_node_values(node)
    for key in sorted(keys & values.keys()):
        value = values[key]
        if not isinstance(value, yaml.ScalarNode) or value.style != '"':
            errors.append(f'{label}.{key}: string value must use double quotes')


def ensure_local_path(
    skill_dir: Path,
    base_dir: Path,
    raw_target: str,
    label: str,
    errors: list[str],
) -> None:
    target = raw_target.strip()
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1]
    elif " " in target:
        target = target.split(maxsplit=1)[0]
    target = unquote(target).split("#", 1)[0]
    if not target:
        return
    parsed = urlsplit(target)
    if parsed.scheme or parsed.netloc or target.startswith("#"):
        return
    candidate = base_dir / target
    try:
        resolved = candidate.resolve(strict=False)
        resolved.relative_to(skill_dir.resolve())
    except (OSError, ValueError):
        errors.append(f"{label}: local path escapes the skill: {raw_target}")
        return
    if not candidate.exists():
        errors.append(f"{label}: missing local resource: {raw_target}")


def validate_markdown_paths(skill_dir: Path, skill_body: str, errors: list[str]) -> None:
    for markdown_file in sorted(skill_dir.rglob("*.md")):
        if markdown_file.is_symlink():
            continue
        try:
            text = markdown_file.read_text(encoding="utf-8")
        except UnicodeError as error:
            errors.append(f"{markdown_file}: Markdown is not UTF-8: {error}")
            continue
        label = markdown_file.relative_to(skill_dir).as_posix()
        for match in MARKDOWN_LINK_RE.finditer(text):
            ensure_local_path(
                skill_dir,
                markdown_file.parent,
                match.group(1),
                f"{label} link",
                errors,
            )

    for match in RESOURCE_PATH_RE.finditer(skill_body):
        target = match.group(0).rstrip(".,:;")
        ensure_local_path(
            skill_dir,
            skill_dir,
            target,
            "SKILL.md resource reference",
            errors,
        )


def validate_scripts(skill_dir: Path, errors: list[str]) -> None:
    scripts_dir = skill_dir / "scripts"
    if not scripts_dir.exists():
        return
    if not scripts_dir.is_dir() or scripts_dir.is_symlink():
        errors.append("scripts: must be a regular directory")
        return

    for script in sorted(scripts_dir.rglob("*")):
        if script.is_dir():
            continue
        label = script.relative_to(skill_dir).as_posix()
        if "__pycache__" in script.parts or script.suffix in {".pyc", ".pyo"}:
            continue
        if script.is_symlink() or not script.is_file():
            errors.append(f"{label}: scripts must be regular files")
            continue
        relative = script.relative_to(scripts_dir)
        is_test_resource = "tests" in relative.parts
        if not is_test_resource and not os.access(script, os.X_OK):
            errors.append(f"{label}: script is not executable")
        try:
            source = script.read_text(encoding="utf-8")
        except UnicodeError as error:
            errors.append(f"{label}: script is not UTF-8: {error}")
            continue

        suffix = script.suffix.lower()
        first_line = source.splitlines()[0] if source.splitlines() else ""
        if suffix == ".py" or "python" in first_line:
            try:
                ast.parse(source, filename=str(script))
            except SyntaxError as error:
                errors.append(f"{label}: invalid Python syntax: {error}")
        elif suffix in {".sh", ".bash"} or "bash" in first_line or "sh" in first_line:
            result = subprocess.run(
                ["bash", "-n", str(script)],
                capture_output=True,
                text=True,
                check=False,
            )
            if result.returncode:
                detail = result.stderr.strip() or "bash -n failed"
                errors.append(f"{label}: invalid shell syntax: {detail}")
        else:
            errors.append(f"{label}: unsupported executable script type")


def validate_openai_yaml(
    skill_dir: Path,
    skill_name: str,
    require_openai_yaml: bool,
    errors: list[str],
) -> None:
    path = skill_dir / "agents" / "openai.yaml"
    if not path.exists():
        if require_openai_yaml:
            errors.append("agents/openai.yaml: required for an active skill")
        return
    if path.is_symlink() or not path.is_file():
        errors.append("agents/openai.yaml: must be a regular file")
        return
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeError as error:
        errors.append(f"agents/openai.yaml: not UTF-8: {error}")
        return

    data = load_yaml(text, "agents/openai.yaml", errors)
    if not isinstance(data, dict):
        if data is not None:
            errors.append("agents/openai.yaml: top level must be a mapping")
        return
    unexpected = set(data) - ALLOWED_OPENAI_TOP_LEVEL
    if unexpected:
        errors.append(
            "agents/openai.yaml: unexpected top-level keys: "
            + ", ".join(sorted(map(str, unexpected)))
        )

    try:
        root_node = yaml.compose(text, Loader=UniqueKeyLoader)
    except yaml.YAMLError:
        root_node = None
    top_nodes = mapping_node_values(root_node)

    interface = data.get("interface")
    if not isinstance(interface, dict):
        errors.append("agents/openai.yaml.interface: required mapping")
    else:
        interface_keys = set(interface)
        missing = REQUIRED_INTERFACE_KEYS - interface_keys
        unexpected = interface_keys - ALLOWED_INTERFACE_KEYS
        if missing:
            errors.append(
                "agents/openai.yaml.interface: missing keys: "
                + ", ".join(sorted(missing))
            )
        if unexpected:
            errors.append(
                "agents/openai.yaml.interface: unexpected keys: "
                + ", ".join(sorted(map(str, unexpected)))
            )
        for key, value in interface.items():
            if not isinstance(value, str) or not value.strip():
                errors.append(f"agents/openai.yaml.interface.{key}: non-empty string required")
        short_description = interface.get("short_description")
        if isinstance(short_description, str) and not 25 <= len(short_description) <= 64:
            errors.append(
                "agents/openai.yaml.interface.short_description: "
                "must contain 25-64 characters"
            )
        default_prompt = interface.get("default_prompt")
        if isinstance(default_prompt, str) and f"${skill_name}" not in default_prompt:
            errors.append(
                "agents/openai.yaml.interface.default_prompt: "
                f"must explicitly mention ${skill_name}"
            )
        brand_color = interface.get("brand_color")
        if isinstance(brand_color, str) and not BRAND_COLOR_RE.fullmatch(brand_color):
            errors.append(
                "agents/openai.yaml.interface.brand_color: expected #RRGGBB"
            )
        for icon_key in ("icon_small", "icon_large"):
            icon_path = interface.get(icon_key)
            if isinstance(icon_path, str):
                if not icon_path.startswith("./assets/"):
                    errors.append(
                        f"agents/openai.yaml.interface.{icon_key}: "
                        "expected a ./assets/ path"
                    )
                ensure_local_path(
                    skill_dir,
                    skill_dir,
                    icon_path,
                    f"agents/openai.yaml.interface.{icon_key}",
                    errors,
                )
        require_quoted_string_nodes(
            top_nodes.get("interface"),
            interface_keys,
            "agents/openai.yaml.interface",
            errors,
        )

    dependencies = data.get("dependencies")
    if dependencies is not None:
        if not isinstance(dependencies, dict) or set(dependencies) != {"tools"}:
            errors.append(
                "agents/openai.yaml.dependencies: only a tools list is supported"
            )
        else:
            tools = dependencies.get("tools")
            if not isinstance(tools, list):
                errors.append("agents/openai.yaml.dependencies.tools: list required")
            else:
                dependencies_node = mapping_node_values(top_nodes.get("dependencies"))
                tools_node = dependencies_node.get("tools")
                item_nodes = (
                    tools_node.value if isinstance(tools_node, yaml.SequenceNode) else []
                )
                for index, tool in enumerate(tools):
                    label = f"agents/openai.yaml.dependencies.tools[{index}]"
                    if not isinstance(tool, dict):
                        errors.append(f"{label}: mapping required")
                        continue
                    keys = set(tool)
                    missing = REQUIRED_TOOL_KEYS - keys
                    unexpected = keys - ALLOWED_TOOL_KEYS
                    if missing:
                        errors.append(f"{label}: missing keys: {', '.join(sorted(missing))}")
                    if unexpected:
                        errors.append(
                            f"{label}: unexpected keys: "
                            + ", ".join(sorted(map(str, unexpected)))
                        )
                    if tool.get("type") != "mcp":
                        errors.append(f"{label}.type: only mcp is supported")
                    for key, value in tool.items():
                        if not isinstance(value, str) or not value.strip():
                            errors.append(f"{label}.{key}: non-empty string required")
                    item_node = item_nodes[index] if index < len(item_nodes) else None
                    require_quoted_string_nodes(item_node, keys, label, errors)

    policy = data.get("policy")
    if policy is not None:
        if not isinstance(policy, dict) or set(policy) != {"allow_implicit_invocation"}:
            errors.append(
                "agents/openai.yaml.policy: only allow_implicit_invocation is supported"
            )
        elif not isinstance(policy.get("allow_implicit_invocation"), bool):
            errors.append(
                "agents/openai.yaml.policy.allow_implicit_invocation: boolean required"
            )


def validate_skill(skill_dir: Path, require_openai_yaml: bool) -> list[str]:
    errors: list[str] = []
    if not skill_dir.is_dir() or skill_dir.is_symlink():
        return [f"{skill_dir}: skill path must be a regular directory"]

    for entry in sorted(skill_dir.iterdir()):
        if entry.name not in ALLOWED_SKILL_ENTRIES:
            errors.append(f"{entry.name}: unexpected top-level skill entry")
    for path in sorted(skill_dir.rglob("*")):
        if path.is_symlink():
            errors.append(
                f"{path.relative_to(skill_dir).as_posix()}: symlinks are not portable"
            )
        if path.name == "__pycache__" or path.suffix in {".pyc", ".pyo"}:
            errors.append(
                f"{path.relative_to(skill_dir).as_posix()}: generated bytecode is forbidden"
            )

    skill_md = skill_dir / "SKILL.md"
    if not skill_md.is_file() or skill_md.is_symlink():
        errors.append("SKILL.md: required regular file")
        return errors
    try:
        text = skill_md.read_text(encoding="utf-8")
    except UnicodeError as error:
        errors.append(f"SKILL.md: not UTF-8: {error}")
        return errors
    match = FRONTMATTER_RE.match(text)
    if not match:
        errors.append("SKILL.md: missing exact YAML frontmatter")
        return errors

    frontmatter = load_yaml(match.group(1), "SKILL.md frontmatter", errors)
    body = text[match.end() :]
    if not isinstance(frontmatter, dict):
        if frontmatter is not None:
            errors.append("SKILL.md frontmatter: top level must be a mapping")
        return errors
    keys = set(frontmatter)
    missing = ALLOWED_FRONTMATTER_KEYS - keys
    unexpected = keys - ALLOWED_FRONTMATTER_KEYS
    if missing:
        errors.append(
            "SKILL.md frontmatter: missing keys: " + ", ".join(sorted(missing))
        )
    if unexpected:
        errors.append(
            "SKILL.md frontmatter: unexpected keys: "
            + ", ".join(sorted(map(str, unexpected)))
        )

    name = frontmatter.get("name")
    if not isinstance(name, str) or not NAME_RE.fullmatch(name):
        errors.append("SKILL.md frontmatter.name: hyphen-case string required")
        name = skill_dir.name
    elif len(name) > MAX_SKILL_NAME_LENGTH:
        errors.append(
            f"SKILL.md frontmatter.name: exceeds {MAX_SKILL_NAME_LENGTH} characters"
        )
    if name != skill_dir.name:
        errors.append(
            f"SKILL.md frontmatter.name: {name!r} does not match {skill_dir.name!r}"
        )

    description = frontmatter.get("description")
    if not isinstance(description, str) or not description.strip():
        errors.append("SKILL.md frontmatter.description: non-empty string required")
    elif len(description) > MAX_DESCRIPTION_LENGTH:
        errors.append(
            "SKILL.md frontmatter.description: "
            f"exceeds {MAX_DESCRIPTION_LENGTH} characters"
        )
    elif "<" in description or ">" in description:
        errors.append(
            "SKILL.md frontmatter.description: angle brackets are not allowed"
        )

    if not body.strip():
        errors.append("SKILL.md: instruction body is empty")
    elif not re.search(r"^#\s+\S", body, re.MULTILINE):
        errors.append("SKILL.md: instruction body needs an H1 heading")
    if TODO_RE.search(body) or (
        isinstance(description, str) and TODO_RE.search(description)
    ):
        errors.append("SKILL.md: unresolved TODO or placeholder content")

    validate_openai_yaml(skill_dir, name, require_openai_yaml, errors)
    validate_markdown_paths(skill_dir, body, errors)
    validate_scripts(skill_dir, errors)
    return errors


def tree_fingerprint(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        if relative == ".git" or relative.startswith(".git/"):
            continue
        stat_result = path.lstat()
        kind = (
            "link"
            if path.is_symlink()
            else "dir"
            if path.is_dir()
            else "file"
            if path.is_file()
            else "other"
        )
        digest.update(f"{kind}\0{stat_result.st_mode & 0o7777:o}\0{relative}\0".encode())
        if path.is_symlink():
            digest.update(os.readlink(path).encode(errors="surrogateescape"))
        elif path.is_file():
            digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("skill_dir", type=Path)
    parser.add_argument(
        "--require-openai-yaml",
        action="store_true",
        help="Require and validate agents/openai.yaml",
    )
    parser.add_argument(
        "--fingerprint",
        action="store_true",
        help="Print a deterministic tree fingerprint instead of validating",
    )
    args = parser.parse_args()
    skill_dir = args.skill_dir.expanduser().absolute()

    if args.fingerprint:
        if not skill_dir.is_dir():
            print(f"ERROR: directory not found: {skill_dir}", file=sys.stderr)
            return 1
        print(tree_fingerprint(skill_dir))
        return 0

    errors = validate_skill(skill_dir, args.require_openai_yaml)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"OK: {skill_dir.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
