"""Write index.xml, the ReaPack repository index.

Run after bumping `@version` in the Open script, commit, then tag the commit
`v<version>` and push the tag: the index points at files under that tag.
"""
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote
from xml.sax.saxutils import escape
import re

ROOT = Path(__file__).resolve().parents[1]
CATEGORY = 'MIDI Editor'
MAIN = 'Fluent MIDI Editor - Open.lua'
ACTIONS = ['Fluent MIDI Editor - Set as default editor.lua',
           'Fluent MIDI Editor - Restore default editor.lua']
REPO = 'onliner10/fluent-midi-editor'


def main():
    folder = ROOT / CATEGORY
    header = (folder / MAIN).read_text(encoding='utf-8')
    version = re.search(r'^-- @version (\S+)', header, re.M).group(1)
    base = f'https://raw.githubusercontent.com/{REPO}/v{version}/{quote(CATEGORY)}/'

    def source(path, attrs):
        return f'        <source {attrs}>{escape(base + quote(path))}</source>'

    sources = [source(MAIN, 'main="main"')]
    sources += [source(name, f'main="main" file="{escape(name)}"') for name in ACTIONS]
    sources += [source(f'lib/{p.name}', f'file="lib/{p.name}"')
                for p in sorted((folder / 'lib').glob('*.lua'))]
    now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    xml = '\n'.join([
        '<?xml version="1.0" encoding="utf-8"?>',
        '<index version="1" name="Fluent MIDI Editor">',
        f'  <category name="{CATEGORY}">',
        f'    <reapack name="{MAIN}" type="script" desc="Fluent MIDI Editor">',
        '      <metadata>',
        f'        <link rel="website">https://github.com/{REPO}</link>',
        '      </metadata>',
        f'      <version name="{version}" author="onliner10" time="{now}">',
        f'        <changelog><![CDATA[See https://github.com/{REPO}/releases]]></changelog>',
        *sources,
        '      </version>',
        '    </reapack>',
        '  </category>',
        '</index>',
        ''])
    (ROOT / 'index.xml').write_text(xml, encoding='utf-8', newline='\n')
    print(f'index.xml: {version}, {len(sources)} files')


if __name__ == '__main__':
    main()
