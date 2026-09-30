"""Install path: the ReaPack index, the install guide and the missing-ReaImGui message."""
from pathlib import Path
from urllib.parse import quote, unquote
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))


def key(name):
    from make_index import version_key
    return version_key(name)
INDEX_URL = 'https://github.com/onliner10/fluent-midi-editor/raw/main/index.xml'
GUIDE_URL = 'github.com/onliner10/fluent-midi-editor/blob/main/docs/install.md'


class Install(unittest.TestCase):
    def versions(self):
        index = (ROOT / 'index.xml').read_text(encoding='utf-8')
        return re.findall(r'<version name="([^"]+)"[^>]*>(.*?)</version>', index, re.S)

    def test_every_version_ships_the_editor_from_its_own_tag(self):
        versions = self.versions()
        self.assertTrue(versions)
        for name, body in versions:
            with self.subTest(version=name):
                urls = re.findall(r'<source[^>]*>([^<]+)</source>', body)
                files = {unquote(u.split('/MIDI%20Editor/', 1)[1]) for u in urls}
                self.assertIn('Fluent MIDI Editor - Open.lua', files)
                self.assertIn('lib/editor.lua', files)
                for url in urls:
                    self.assertIn(f'/{quote("v" + name)}/', url)

    def test_index_holds_one_stable_version_and_newer_dev_builds(self):
        names = [name for name, _ in self.versions()]
        stable = [n for n in names if not re.search('[a-zA-Z]', n)]
        self.assertEqual(len(stable), 1, names)
        for name in names:
            if name != stable[0]:
                self.assertRegex(name, r'^\d+\.\d+\.\d+-dev\.\d+$')
                self.assertGreater(key(name), key(stable[0]))

    def test_index_names_the_script_version_once_released(self):
        version = re.search(r'^-- @version (\S+)',
                            (ROOT / 'MIDI Editor/Fluent MIDI Editor - Open.lua').read_text(encoding='utf-8'), re.M).group(1)
        self.assertRegex(version, r'^\d+(\.\d+)*$', 'dev builds are numbered by CI; @version stays plain')
        names = [name for name, _ in self.versions()]
        if version not in names:
            # The dev branch carries the next release; the index is main's.
            for name in names:
                self.assertLess(key(name), key(version), f'{version} is older than published {name}')

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
