#!/usr/bin/env python3
"""Validate project-wide Godot doc comments for every named GDScript function."""

from __future__ import annotations

import re
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOTS = (PROJECT_ROOT / "scripts", PROJECT_ROOT / "tests")
FUNC_START = re.compile(r"^(?P<indent>\s*)(?:static\s+)?func\s+(?P<name>[A-Za-z0-9_]+)\s*\(")
FUNC_END = re.compile(r"\)\s*(?:->\s*(?P<return>[^:]+))?\s*:\s*$")
PARAM_NAME = re.compile(r"^(?P<name>[A-Za-z_][A-Za-z0-9_]*)")
CHINESE_TEXT = re.compile(r"[\u3400-\u9fff]")


def split_parameters(source: str) -> list[str]:
    """Split a GDScript parameter list without breaking nested default values.

    Args:
        source: Text between the function signature's outer parentheses.

    Returns:
        Individual non-empty parameter declarations.
    """
    result: list[str] = []
    start = 0
    depth = 0
    quote = ""
    escaped = False
    for index, character in enumerate(source):
        if quote:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == quote:
                quote = ""
            continue
        if character in "\"'":
            quote = character
        elif character in "([{":
            depth += 1
        elif character in ")]}":
            depth -= 1
        elif character == "," and depth == 0:
            value = source[start:index].strip()
            if value:
                result.append(value)
            start = index + 1
    value = source[start:].strip()
    if value:
        result.append(value)
    return result


def preceding_doc_block(lines: list[str], function_line: int) -> list[str]:
    """Return the contiguous `##` block above a function and its annotations.

    Args:
        lines: Complete source file split into lines.
        function_line: Zero-based line containing the `func` keyword.

    Returns:
        Documentation lines without indentation.
    """
    cursor = function_line - 1
    while cursor >= 0 and lines[cursor].lstrip().startswith("@"):
        cursor -= 1
    block: list[str] = []
    while cursor >= 0 and lines[cursor].lstrip().startswith("##"):
        block.append(lines[cursor].lstrip()[2:].strip())
        cursor -= 1
    block.reverse()
    return block


def inspect_file(path: Path) -> list[str]:
    """Inspect one GDScript and return human-readable contract violations.

    Args:
        path: GDScript file inside the project.

    Returns:
        Validation error messages prefixed with project-relative locations.
    """
    lines = path.read_text(encoding="utf-8").splitlines()
    errors: list[str] = []
    index = 0
    while index < len(lines):
        match = FUNC_START.match(lines[index])
        if not match:
            index += 1
            continue
        signature_lines = [lines[index].strip()]
        end_index = index
        while end_index < len(lines) and not FUNC_END.search(signature_lines[-1]):
            end_index += 1
            if end_index >= len(lines):
                break
            signature_lines.append(lines[end_index].strip())
        signature = " ".join(signature_lines)
        end_match = FUNC_END.search(signature)
        location = f"{path.relative_to(PROJECT_ROOT).as_posix()}:{index + 1}"
        docs = preceding_doc_block(lines, index)
        if not docs or not any(value for value in docs if not value.startswith(("[param ", "返回", "设计："))):
            errors.append(f"{location}: missing responsibility `##` documentation")
            index = max(index + 1, end_index + 1)
            continue
        for value in docs:
            if not CHINESE_TEXT.search(value):
                errors.append(f"{location}: function documentation must be written in Chinese: {value}")
        open_paren = signature.find("(")
        close_paren = signature.rfind(")")
        parameters = split_parameters(signature[open_paren + 1 : close_paren])
        for parameter in parameters:
            parameter_match = PARAM_NAME.match(parameter)
            if parameter_match and not any(
                f"[param {parameter_match.group('name')}]" in line for line in docs
            ):
                errors.append(
                    f"{location}: missing `[param {parameter_match.group('name')}]` documentation"
                )
        return_type = end_match.group("return").strip() if end_match and end_match.group("return") else ""
        if return_type and return_type != "void" and not any(line.startswith("返回") for line in docs):
            errors.append(f"{location}: non-void function missing `返回...` documentation")
        index = max(index + 1, end_index + 1)
    return errors


def main() -> int:
    """Validate every production and test GDScript under the configured roots.

    Returns:
        Zero when all functions satisfy the contract, otherwise one.
    """
    paths = sorted(path for root in SOURCE_ROOTS for path in root.rglob("*.gd"))
    errors = [error for path in paths for error in inspect_file(path)]
    if errors:
        print("GDScript documentation check failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print(f"GDScript documentation check passed: {len(paths)} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
