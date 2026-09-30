"""Write index.xml, the ReaPack repository index, from the release tags.

The index lists the latest stable version (tag `v<version>`, made from main)
and every newer dev build (tag `v<version>-dev.<n>`, made from the dev branch).
ReaPack treats versions with letters as pre-releases: people get dev builds only
after enabling pre-releases for the package. Each version points at the files
under its own tag, so a tag must exist before the index names it.

Release CI runs this after tagging. Locally: `git fetch --tags`, then run it
from the repository. It works on the repository it is run in, so CI can run a
newer copy of this script in an older checkout of main.
"""
from pathlib import Path
from urllib.parse import quote
from xml.sax.saxutils import escape
import os
import re
import subprocess

CATEGORY = 'MIDI Editor'
MAIN = 'Fluent MIDI Editor - Open.lua'
REPO = 'onliner10/fluent-midi-editor'


def git(*args):
    return subprocess.run(['git', *args], check=True, capture_output=True,
                          text=True, encoding='utf-8', env={**os.environ, 'TZ': 'UTC'}).stdout


def version_key(name):
    """Order versions as ReaPack does: numbers above letters, segment by segment."""
    return [(1, int(s), '') if s.isdigit() else (0, 0, s) for s in re.findall(r'\d+|[a-zA-Z]+', name)] + [(0.5, 0, '')]


def stable(name):
    return not re.search(r'[a-zA-Z]', name)


def published():
    """The versions the index lists: the newest stable one and newer dev builds."""
    names = [t[1:] for t in git('tag', '--list', 'v*').split() if re.match(r'v\d', t)]
    names.sort(key=version_key)
    stables = [n for n in names if stable(n)]
    floor = version_key(stables[-1]) if stables else []
    return [n for n in names if (stables and n == stables[-1]) or (not stable(n) and version_key(n) > floor)]


def entry(version):
    tag = f'v{version}'
    base = f'https://raw.githubusercontent.com/{REPO}/{quote(tag)}/{quote(CATEGORY)}/'
    files = sorted(Path(p).relative_to(CATEGORY).as_posix()
                   for p in git('ls-tree', '-r', '--name-only', tag, '--', CATEGORY).splitlines()
                   if p.endswith('.lua'))
    # Each file's role comes from the Open script's header at that tag.
    header = git('show', f'{tag}:{CATEGORY}/{MAIN}')
    actions = set(re.findall(r'^--\s+\[main\]\s+(.+?)\s*$', header, re.M))
    time = git('log', '-1', '--format=%cd', '--date=format-local:%Y-%m-%dT%H:%M:%SZ', tag).strip()

    def source(path):
        if path == MAIN:
            attrs = 'main="main"'
        elif path in actions:
            attrs = f'main="main" file="{escape(path)}"'
        else:
            attrs = f'file="{escape(path)}"'
        return f'        <source {attrs}>{escape(base + quote(path))}</source>'

    return [f'      <version name="{version}" author="onliner10" time="{time}">',
            f'        <changelog><![CDATA[https://github.com/{REPO}/releases/tag/{tag}]]></changelog>',
            *[source(p) for p in [MAIN] + [f for f in files if f != MAIN]],
            '      </version>']


def main():
    versions = published()
    if not versions:
        raise SystemExit('No release tags. Tag a release first (git fetch --tags).')
    xml = '\n'.join([
        '<?xml version="1.0" encoding="utf-8"?>',
        '<index version="1" name="Fluent MIDI Editor">',
        f'  <category name="{CATEGORY}">',
        f'    <reapack name="{MAIN}" type="script" desc="Fluent MIDI Editor">',
        '      <metadata>',
        f'        <link rel="website">https://github.com/{REPO}</link>',
        '      </metadata>',
        *[line for v in versions for line in entry(v)],
        '    </reapack>',
        '  </category>',
        '</index>',
        ''])
    root = Path(git('rev-parse', '--show-toplevel').strip())
    (root / 'index.xml').write_text(xml, encoding='utf-8', newline='\n')
    print('index.xml: ' + ', '.join(versions))


if __name__ == '__main__':
    main()
