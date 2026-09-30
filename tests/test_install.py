"""Install path: the ReaPack index, the install guide and the missing-ReaImGui message."""
from pathlib import Path
from urllib.parse import unquote
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
INDEX_URL = 'https://github.com/onliner10/fluent-midi-editor/raw/main/index.xml'
GUIDE_URL = 'github.com/onliner10/fluent-midi-editor/blob/main/docs/install.md'


class Install(unittest.TestCase):
    def test_index_lists_every_shipped_file(self):
        index = (ROOT / 'index.xml').read_text(encoding='utf-8')
        listed = {unquote(u.split('/MIDI%20Editor/', 1)[1])
                  for u in re.findall(r'<source[^>]*>([^<]+)</source>', index)}
        shipped = {p.relative_to(ROOT / 'MIDI Editor').as_posix()
                   for p in (ROOT / 'MIDI Editor').rglob('*.lua')}
        self.assertEqual(listed, shipped)

    def test_index_tag_matches_script_version(self):
        version = re.search(r'^-- @version (\S+)',
                            (ROOT / 'MIDI Editor/Fluent MIDI Editor - Open.lua').read_text(encoding='utf-8'), re.M).group(1)
        index = (ROOT / 'index.xml').read_text(encoding='utf-8')
        self.assertIn(f'<version name="{version}"', index)
        self.assertIn(f'/v{version}/', index)

    def test_docs_use_the_real_repository_url(self):
        for name in ('README.md', 'docs/install.md'):
            with self.subTest(file=name):
                self.assertIn(INDEX_URL, (ROOT / name).read_text(encoding='utf-8'))

    def test_guide_covers_the_steps_people_miss(self):
        guide = (ROOT / 'docs/install.md').read_text(encoding='utf-8')
        for needle in ('Import repositories', 'Browse packages', 'ReaImGui: ReaScript binding for Dear ImGui',
                       'cfillion', 'Close REAPER completely', 'Fluent MIDI Editor - Open.lua'):
            with self.subTest(needle=needle):
                self.assertIn(needle, guide)
        self.assertIn('docs/install.md', (ROOT / 'README.md').read_text(encoding='utf-8'))

    def test_missing_reaimgui_says_restart_and_links_the_guide(self):
        try:
            from lupa import LuaRuntime
        except ImportError:
            self.skipTest('requires lupa (see requirements-dev.txt)')
        lua = LuaRuntime(unpack_returned_tuples=True)
        script = (ROOT / 'MIDI Editor/Fluent MIDI Editor - Open.lua').as_posix()
        shown, = lua.eval('''function(path)
          local shown = {}
          reaper = {
            GetSelectedMediaItem = function() return nil end,
            GetExtState = function() return '' end,
            time_precise = function() return 100 end,
            MB = function(text, title) shown[#shown + 1] = text .. '\\n' .. title end,
          }
          assert(loadfile(path))()
          return shown
        end''')(script), 
        self.assertEqual(len(shown), 1)
        text = shown[1]
        self.assertIn('ReaImGui', text)
        self.assertIn('Restart REAPER', text)
        self.assertIn(GUIDE_URL, text)


if __name__ == '__main__':
    unittest.main()
