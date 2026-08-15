#!/usr/bin/env python3
"""Check that every relative Markdown link in this repository resolves.

Verifies both halves of a link: that `file.md` exists, and that `#fragment`
matches a heading in it. Anchors follow GitHub's rule — lowercase, drop
punctuation, replace each remaining space with a hyphen, without collapsing
runs. That last part matters: a heading with a spaced em dash produces a
double hyphen, and getting it wrong silently yields a link that lands at the
top of the page instead of the section.

Exits non-zero and prints every broken link it finds.
"""
import os
import re
import sys

LINK = re.compile(r'\]\(([^)\s]+)\)')
HEADING = re.compile(r'^#{1,6}\s+(.*?)\s*$', re.M)
FENCE = re.compile(r'^```.*?^```', re.M | re.S)
DROP = re.compile(r'[^\w\s-]', re.U)


def anchor(heading: str) -> str:
    return DROP.sub('', heading.strip().lower()).replace(' ', '-')


def markdown_files(root: str) -> list[str]:
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d != '.git']
        found += [os.path.join(dirpath, f)
                  for f in filenames if f.endswith('.md')]
    return sorted(found)


def main() -> int:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    files = markdown_files(root)
    anchors = {}
    bodies = {}
    for path in files:
        text = open(path, encoding='utf-8').read()
        bodies[path] = FENCE.sub('', text)
        anchors[path] = {anchor(h) for h in HEADING.findall(bodies[path])}

    broken = []
    for path in files:
        for link in LINK.findall(bodies[path]):
            if re.match(r'^[a-z][a-z0-9+.-]*:', link):
                continue
            target_path, _, fragment = link.partition('#')
            target = (os.path.normpath(
                os.path.join(os.path.dirname(path), target_path))
                if target_path else path)
            rel = os.path.relpath(path, root)
            if target_path and not os.path.exists(target):
                broken.append(f'{rel}: no such file: {link}')
            elif fragment and target in anchors \
                    and fragment not in anchors[target]:
                broken.append(f'{rel}: no such heading: {link}')

    for problem in broken:
        print(problem)
    print(f'{len(files)} files, {len(broken)} broken links')
    return 1 if broken else 0


if __name__ == '__main__':
    sys.exit(main())
