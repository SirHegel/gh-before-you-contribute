#!/usr/bin/env python3
"""Validate one audit document from standard input against the checked-in schema."""

from __future__ import annotations

import json
from pathlib import Path
import sys

from jsonschema import Draft202012Validator, FormatChecker


def main() -> int:
    if len(sys.argv) != 1:
        print("usage: validate-schema.py", file=sys.stderr)
        return 2

    schema_path = (
        Path(__file__).resolve().parents[1] / "schema" / "audit-v1.schema.json"
    )
    with schema_path.open(encoding="utf-8") as schema_file:
        schema = json.load(schema_file)
    instance = json.load(sys.stdin)

    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    errors = sorted(validator.iter_errors(instance), key=lambda error: list(error.path))
    if not errors:
        return 0

    for error in errors:
        location = ".".join(str(part) for part in error.absolute_path) or "<root>"
        print(f"{location}: {error.message}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
