"""Executable Lua behavior tests for Fluent MIDI Editor (pip install lupa)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class FluentMidiEditor(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            from lupa import LuaRuntime
        except ImportError:
            raise unittest.SkipTest('Fluent MIDI Editor tests require lupa (see requirements-dev.txt)')
        cls.lua = LuaRuntime(unpack_returned_tuples=True)

    def test_model_and_integration(self):
        count = self.lua.eval('function(path, root) return assert(loadfile(path))(root) end')(
            (ROOT / 'tests/editor_spec.lua').as_posix(), ROOT.as_posix())
        self.assertGreaterEqual(count, 45)

    def test_all_modules_compile(self):
        paths = list((ROOT / 'MIDI Editor/lib').glob('*.lua'))
        paths += list((ROOT / 'MIDI Editor').glob('*.lua'))
        for path in paths:
            with self.subTest(module=path.name):
                self.lua.execute('assert(loadfile(...))', path.as_posix())

    def test_render_cache_and_viewport(self):
        count = self.lua.eval('function(path, root) return assert(loadfile(path))(root) end')(
            (ROOT / 'tests/render_spec.lua').as_posix(), ROOT.as_posix())
        self.assertGreater(count, 24000)

    def test_note_owned_midi(self):
        count = self.lua.eval('function(path, root) return assert(loadfile(path))(root) end')(
            (ROOT / 'tests/mpe_spec.lua').as_posix(), ROOT.as_posix())
        self.assertGreaterEqual(count, 50)

    def test_clip_modulation(self):
        count = self.lua.eval('function(path, root) return assert(loadfile(path))(root) end')(
            (ROOT / 'tests/modulation_spec.lua').as_posix(), ROOT.as_posix())
        self.assertGreater(count, 200)
