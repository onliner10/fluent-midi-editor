# Install Fluent MIDI Editor

About 5 minutes, no coding. You need **REAPER 7** or newer.

There are three things to install, always in this order:

| | What | Why |
| :- | :- | :- |
| 1 | **ReaPack** | REAPER's package manager. It installs and updates scripts for you. |
| 2 | **Fluent MIDI Editor** | The editor itself. |
| 3 | **ReaImGui** | A free extension the editor draws its window with. **Without it the editor cannot open.** |

Then **restart REAPER once**. That step is the one people miss.

> Already have ReaPack? Skip to [step 2](#2-add-the-fluent-midi-editor-repository).
> Already have ReaImGui? Skip that part of step 3. Everything else is the same.

---

## 1. Install ReaPack

Check first: does REAPER's top menu have **Extensions → ReaPack**? If so, go to step 2.

If not:

1. Download ReaPack for your system from **<https://reapack.com>** (the *Download* section: Windows `x64`, macOS `arm64` for Apple Silicon or `x86_64` for Intel, Linux `x86_64`).
2. In REAPER: **Options → Show REAPER resource path in explorer/finder…**
3. Open the **UserPlugins** folder and put the downloaded file in it. Do not rename it.
4. **Close REAPER completely and open it again.**

You should now see **Extensions → ReaPack** in the menu.

## 2. Add the Fluent MIDI Editor repository

1. **Extensions → ReaPack → Import repositories…**
2. Paste this line into the box and click **OK**:

   ```
   https://github.com/onliner10/fluent-midi-editor/raw/main/index.xml
   ```

Nothing dramatic happens, and that is fine. ReaPack quietly adds a repository called *Fluent MIDI Editor* to its list.

## 3. Install the editor and ReaImGui

1. **Extensions → ReaPack → Browse packages…**
2. In the **Filter** box type `Fluent`. One package appears: **Fluent MIDI Editor** (*Script*, by onliner10).
   **Right-click it → Install.** The **Apply** button at the bottom becomes clickable.
3. Change the filter to `ReaImGui`. Ten or so results appear. You want this one:

   **ReaImGui: ReaScript binding for Dear ImGui**, type *Extension*, author **cfillion**.

   **Right-click it → Install.** (Many of the other results are unrelated scripts that merely use ReaImGui. Do not install those.)
   *Already installed? Then* **Uninstall** *is clickable in that menu and* **Install** *is not. Leave it alone.*
4. Click **Apply**. A *Transaction report* window lists what was installed:
   both **Fluent MIDI Editor** and **ReaImGui** should be there. Close it.
5. REAPER also says *"One or more native REAPER extensions were installed. These newly installed files won't be loaded until REAPER is restarted."*
   That is ReaImGui. **Close REAPER completely and open it again.**

## 4. Open the editor

1. Click a **MIDI clip** in your project to select it. Select several to edit them together.
2. Open the Actions list: press **`?`** (Shift + /), or **Actions → Show action list…**
3. Type `Fluent` in the filter. Select **Script: Fluent MIDI Editor - Open.lua** and press **Run**.

The Fluent MIDI Editor window opens with your clip's notes. Congratulations, you are done.

### Give it a shortcut (recommended)

Opening it from the list every time is tedious. In that same Actions window select
**Script: Fluent MIDI Editor - Open.lua**, click **Add…** under *Shortcuts for selected action*,
press the key you want and confirm. Any free key works. Pick one you can hit with a clip selected.

### Make double-click open it (optional)

Run **Script: Fluent MIDI Editor - Set as default editor.lua** once. Double-clicking a MIDI clip
then opens this editor instead of REAPER's. **Restore default editor** undoes it. Both are also in the
editor's **Options** menu. Skip this if you like keeping REAPER's own editor on double-click.

---

## It did not work? Find your symptom

**A message says "The editor needs the ReaImGui extension" (or "Install ReaImGui").**
Almost always one of two things:
- You installed ReaImGui but **did not restart REAPER**. Close it completely, open it, and run the action again. This fixes most cases.
- ReaImGui is not installed yet. Do step 3 again and make sure you pick **ReaImGui: ReaScript binding for Dear ImGui** by *cfillion*.

To check: **Extensions → ReaPack → Browse packages…**, filter `ReaImGui`, right-click that package. If **Uninstall** is clickable, it is installed.

**There is no Extensions → ReaPack menu.**
ReaPack is not loaded. Redo step 1. The file must be directly inside the `UserPlugins` folder (not a subfolder, not the Downloads folder), and REAPER must be restarted after copying it.

**Browse packages shows no "Fluent MIDI Editor".**
The repository is not imported or not synchronised yet. Do step 2 again, then **Extensions → ReaPack → Synchronize packages**. Make sure the pasted line has no spaces or line breaks and ends in `index.xml`.
If there is an error about the download, check your internet connection and that a firewall, VPN or antivirus is not blocking ReaPack.

**I cannot find the action in the Actions list.**
Type `Fluent` in the filter (not `Fluent MIDI`, and no quotes) and make sure **Section** at the top is **Main**.
If the list is still empty, ReaPack did not install the script: open Browse packages and check *Fluent MIDI Editor* is installed.

**The editor opens but it is empty.**
Select a **MIDI clip** first (click it in the arrange view), then run the action again. If the editor is already open,
running the action again just brings it to the front and loads the selected clips.

**Still stuck?**
[Open an issue](https://github.com/onliner10/fluent-midi-editor/issues) and tell us: your operating system, your REAPER version (**Help → About REAPER**), and the exact message you see (a screenshot is perfect). This is a beta and we want to know what breaks.

---

## Updating

**Extensions → ReaPack → Synchronize packages** fetches new versions, then open **Browse packages…** to see what changed. Your projects and shortcuts are untouched. If ReaPack says a native extension was
updated, restart REAPER.

## Trying development builds

New features and fixes arrive first as **dev builds**, before they are released to
everyone. They may be unstable. To try them:

1. **Extensions → ReaPack → Browse packages…**, filter `Fluent`.
2. Right-click **Fluent MIDI Editor** → **Enable pre-releases (bleeding-edge)**.
3. Right-click it again → **Update to v…** (the version ending in `-dev.<n>`), then **Apply**.

ReaPack then installs the newest build, stable or dev, for this package only.
Versions like `0.11.0-dev.3` are dev builds; `0.11.0` is the release they lead to.
To go back, untick **Enable pre-releases (bleeding-edge)** in the same menu: ReaPack
offers the stable version again at the next release, or right-click → **Versions**
to pick it now.

If **Extensions → ReaPack → Manage repositories… → Options… → Enable pre-releases
globally (bleeding edge)** is ticked, you already get dev builds of every package,
including this one.

## Uninstalling

**Extensions → ReaPack → Browse packages…**, filter `Fluent`, right-click the package → **Uninstall**, then **Apply**.
Repeats that the editor made are ordinary REAPER clips and stay in your projects.

## Without ReaPack (manual install)

Only if you cannot use ReaPack. You will not get automatic updates.

1. Install **ReaImGui** yourself: download the file for your system from its
   [releases page](https://github.com/cfillion/reaimgui/releases) (Windows `reaper_imgui-x64.dll`,
   macOS `reaper_imgui-arm64.dylib` or `-x86_64.dylib`, Linux `reaper_imgui-x86_64.so`), put it in REAPER's
   **UserPlugins** folder, and also put [`imgui.lua`](https://github.com/cfillion/reaimgui/blob/master/shims/imgui.lua)
   into `Scripts/ReaTeam Extensions/API/` in the resource folder.
2. Download this repository (green **Code** button → *Download ZIP*) and copy the `MIDI Editor` folder into
   REAPER's `Scripts` folder. The three `Fluent MIDI Editor - *.lua` files must stay next to the `lib` folder.
3. Restart REAPER. In the Actions list click **New action… → Load ReaScript…** and pick
   `Fluent MIDI Editor - Open.lua`. Do the same for the two default-editor scripts if you want them.
