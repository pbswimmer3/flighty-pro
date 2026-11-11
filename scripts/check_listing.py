#!/usr/bin/env python3
"""Check docs/store/listing.md field lengths.

Each field is a "### <Field> (<limit>)" heading followed by a ```text fenced block.
Counts characters (Keywords: UTF-8 bytes). Exit 1 if any field is over or missing.
Usage: python scripts/check_listing.py [path]
"""
import re
import sys
from pathlib import Path

DEFAULT = Path(__file__).resolve().parent.parent / "docs" / "store" / "listing.md"
REQUIRED = ["Name", "Subtitle", "Promotional Text", "Description", "Keywords", "What's New"]
HEAD = re.compile(r"^###\s+(.+?)\s*\((?:[^)]*?)(\d[\d,]*)[^)]*\)\s*$")
FENCE = re.compile(r"```text[ \t]*\r?\n(.*?)\r?\n?```", re.S)


def parse(text):
    fields, pos = [], 0
    lines = text.splitlines(keepends=True)
    offs = []
    for ln in lines:
        offs.append(pos)
        pos += len(ln)
    for i, ln in enumerate(lines):
        m = HEAD.match(ln.rstrip("\r\n"))
        if not m:
            continue
        end = len(text)
        for j in range(i + 1, len(lines)):
            if lines[j].startswith("#"):
                end = offs[j]
                break
        fm = FENCE.search(text[offs[i] + len(ln):end])
        if fm:
            fields.append((m.group(1).strip(), int(m.group(2).replace(",", "")), fm.group(1)))
    return fields


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    if not path.exists():
        print(f"ERROR: {path} does not exist yet (listing.md not written).")
        return 1
    fields = parse(path.read_text(encoding="utf-8"))
    if not fields:
        print(f"ERROR: no '### Field (limit)' + ```text blocks found in {path}.")
        return 1
    bad = False
    print(f"{'Field':<24}{'Count':>7}{'Limit':>7}  Status")
    for name, limit, body in fields:
        body = body.replace("\r\n", "\n")
        is_kw = name.lower().startswith("keyword")
        n = len(body.encode("utf-8")) if is_kw else len(body)
        ok = n <= limit
        bad |= not ok
        print(f"{name + (' (bytes)' if is_kw else ''):<24}{n:>7}{limit:>7}  {'OK' if ok else 'OVER'}")
        if re.search("flighty", body, re.I):
            print(f"  WARNING: '{name}' mentions Flighty")
    have = {f[0].lower() for f in fields}
    for req in REQUIRED:
        if req.lower() not in have:
            print(f"MISSING required field: {req}")
            bad = True
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
