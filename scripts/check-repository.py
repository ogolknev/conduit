#!/usr/bin/env python3
"""Check maintained Markdown links and the always-loaded agent context budget."""
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]


def main():
    errors = []
    words = len((ROOT / 'AGENTS.md').read_text().split())
    if words >= 400:
        errors.append(f'AGENTS.md has {words} words; keep it below 400')
    documents = sorted(set(ROOT.glob('*.md')) | set((ROOT / 'docs').rglob('*.md')) |
                       set((ROOT / '.agents').rglob('SKILL.md')) |
                       set((ROOT / '.github').glob('*.md')))
    for path in documents:
        text = path.read_text()
        # Command examples are not documentation links.
        text = re.sub(r'^```[^\n]*\n.*?^```[^\n]*$', '', text, flags=re.M | re.S)
        refs = re.findall(r'\]\(([^\s)]+)(?:\s+[^)]*)?\)', text)
        refs += re.findall(r'(?:src|srcset)="([^"]+)"', text)
        for ref in refs:
            parsed = urlsplit(ref)
            if parsed.scheme or parsed.netloc or not parsed.path:
                continue
            target = path.parent / unquote(parsed.path)
            if not target.exists():
                errors.append(f'{path.relative_to(ROOT)}: missing {ref}')
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    print(f'Checked {len(documents)} documents; AGENTS.md uses {words}/399 words')
    return 0


if __name__ == '__main__':
    sys.exit(main())
