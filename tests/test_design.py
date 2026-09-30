"""The design system (MIDI Editor/lib/theme.lua, docs/design.md) is the only
place that decides how the editor looks.

UI files may not draw raw ImGui widgets, push styles, move the cursor by hand
or write colours: they use the theme's components and tokens. The theme's text
colours must stay readable on its surfaces. The layout audit in REAPER
(tests/reaper/layout_test.lua) checks what this cannot: overlap and alignment.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / 'MIDI Editor/lib'
THEME = LIB / 'theme.lua'

# Widgets, styling and manual layout belong to theme.lua. Everything else in
# ImGui (input state, popups, menus, windows, draw lists) stays available.
FORBIDDEN = {
    r'ImGui\.(Button|SmallButton|ArrowButton|InvisibleButton|ImageButton)\(': 'a ui: control (button, toggle, primary, arrow, region)',
    r'ImGui\.(Checkbox|RadioButton)\(': 'ui:switch',
    r'ImGui\.(BeginCombo|EndCombo|Combo|ListBox|BeginListBox)\(': 'ui:combo with ui:option',
    r'ImGui\.Selectable\(': 'ui:option or ui:list_row',
    r'ImGui\.(Slider|VSlider|Input|Drag|Color)\w*\(': 'ui:slider_int, ui:slider_double, ui:input_text, ui:input_int',
    r'ImGui\.(Text|TextColored|TextWrapped|TextDisabled|BulletText|LabelText)\(': 'ui:text, ui:muted, ui:faint, ui:colored, ui:wrapped, ui:warning, ui:heading, ui:label',
    r'ImGui\.(BeginChild|EndChild|BeginGroup|EndGroup)\(': 'ui:panel or ui:column',
    r'ImGui\.(Dummy|Spacing|NewLine|Indent|Unindent|AlignTextToFramePadding)\(': 'ui:gap, ui:indent, ui:label',
    r'ImGui\.(SetNextItemWidth|PushItemWidth|PopItemWidth)\(': 'a size token on the ui: control',
    r'ImGui\.(SetCursorPos|SetCursorPosX|SetCursorPosY|SetCursorScreenPos)\(': 'ui:right_align, ui:center, ui:middle, ui:indent',
    r'ImGui\.SameLine\(ctx,': 'ui:same_line or ui:right_align (no pixel offsets)',
    r'ImGui\.(PushStyleColor|PopStyleColor|PushStyleVar|PopStyleVar|PushFont|PopFont)\(': 'a theme component or token',
    r'0x[0-9A-Fa-f]{6,}': 'a colour token in theme.lua (T.color or T.clips)',
}


def ui_files():
    return [p for p in sorted(LIB.glob('*.lua')) if p != THEME and 'ImGui.' in p.read_text(encoding='utf-8')]


class DesignSystem(unittest.TestCase):
    def test_ui_files_use_the_design_system(self):
        self.assertTrue(ui_files())
        problems = []
        for path in ui_files():
            for number, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
                code = line.split('--', 1)[0]
                for pattern, use in FORBIDDEN.items():
                    if re.search(pattern, code):
                        problems.append(f'{path.name}:{number}: use {use}\n    {line.strip()}')
        self.assertEqual(problems, [], '\n' + '\n'.join(problems))

    def test_one_theme_per_window(self):
        # One ui instance, so the layout audit sees every control in the window.
        makers = [p.name for p in LIB.glob('*.lua') if "theme.lua').new(" in p.read_text(encoding='utf-8')]
        self.assertEqual(makers, ['editor.lua'], 'pass the editor\'s ui to panels instead of creating another')

    def test_design_doc_names_every_component(self):
        doc = (ROOT / 'docs/design.md').read_text(encoding='utf-8')
        components = re.findall(r'^\s*function ui:(\w+)', THEME.read_text(encoding='utf-8'), re.M)
        missing = [c for c in components if f'ui:{c}' not in doc]
        self.assertEqual(missing, [], 'document these components in docs/design.md')

    def test_text_is_readable(self):
        try:
            from lupa import LuaRuntime
        except ImportError:
            self.skipTest('requires lupa (see requirements-dev.txt)')
        theme = LuaRuntime().eval(f'dofile([[{THEME.as_posix()}]])')
        color, contrast = theme.color, theme.contrast
        # WCAG: 4.5:1 for text people read, 3:1 for headings, hints and axis labels.
        for text, minimum in (('text', 7), ('muted', 4.5), ('faint', 3), ('accent_text', 4.5)):
            for surface in ('well', 'bg', 'panel', 'raised'):
                with self.subTest(text=text, on=surface):
                    self.assertGreaterEqual(contrast(color[text], color[surface]), minimum)
        with self.subTest(text='on_accent', on='accent'):
            self.assertGreaterEqual(contrast(color.on_accent, color.accent), 4.5)


if __name__ == '__main__':
    unittest.main()
