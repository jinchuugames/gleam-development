#!/usr/bin/env python3
"""Copy marked source excerpts into the Go-to-Gleam guide, or check them."""

import argparse
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
GUIDE = ROOT / "docs/go-to-gleam.md"
BLOCK = re.compile(
    r"(<!-- source: ([\w/.-]+)#([\w-]+) -->\n```\w+\n)(.*?)(^```)", re.DOTALL | re.MULTILINE
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    document = GUIDE.read_text()
    count = 0

    def replace(match):
        nonlocal count
        count += 1
        path, label = match.group(2, 3)
        source = (ROOT / path).read_text()
        lines = source.splitlines()
        start = [i for i, line in enumerate(lines) if line.strip() == f"// snippet:{label}"]
        end = [i for i, line in enumerate(lines) if line.strip() == f"// end:{label}"]
        if len(start) != 1 or len(end) != 1 or start[0] >= end[0]:
            raise SystemExit(f"Invalid excerpt markers: {path}#{label}")
        excerpt = "\n".join(lines[start[0] + 1:end[0]]).strip("\n")
        # Nested excerpt markers are source metadata, not part of the example.
        excerpt = re.sub(r"^\s*// (?:snippet|end):[\w-]+\n?", "", excerpt, flags=re.MULTILINE)
        return match.group(1) + excerpt + "\n" + match.group(5)

    updated = BLOCK.sub(replace, document)
    if count == 0 or count != document.count("<!-- source:"):
        raise SystemExit("The guide has missing or malformed source blocks")
    if args.check:
        if updated != document:
            raise SystemExit("Stale guide excerpts. Run python3 scripts/sync-go-to-gleam.py")
        print(f"Guide excerpts match the source: {count}")
    else:
        GUIDE.write_text(updated)
        print(f"Updated guide excerpts: {count}")


if __name__ == "__main__":
    main()
