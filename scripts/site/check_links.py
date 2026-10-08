#!/usr/bin/env python3
"""Validate the deployed static artifact, including nested tool entry pages."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote
import sys

ROOT = Path(__file__).resolve().parents[2]
DIST = ROOT / 'dist/site'
BASE = '/psz-godot/'


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key in ('href', 'src') and value:
                self.links.append(value)


def main():
    errors = []
    pages = list(DIST.rglob('*.html'))
    if not pages:
        errors.append('No static output; run npm run build first.')
    for page in pages:
        parser = Links()
        parser.feed(page.read_text())
        for link in parser.links:
            url = urlsplit(link)
            if url.scheme or url.netloc or not url.path:
                continue
            if url.path.startswith('/'):
                if not url.path.startswith(BASE):
                    errors.append(f'{page.relative_to(DIST)}: missing project base: {link}')
                    continue
                target = DIST / unquote(url.path[len(BASE):])
            else:
                target = page.parent / unquote(url.path)
            if not target.is_file() and not (target / 'index.html').is_file():
                errors.append(f'{page.relative_to(DIST)}: missing target: {link}')
    for removed in ('api/report', 'reports', 'server'):
        if (DIST / removed).exists():
            errors.append(f'Dynamic feature still published: {removed}')
    for error in sorted(set(errors)):
        print(error)
    print(f'{len(pages)} static pages; {len(set(errors))} link errors.')
    return bool(errors)


if __name__ == '__main__':
    sys.exit(main())
