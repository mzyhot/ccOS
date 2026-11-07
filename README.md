# ccOS 3.0

A Windows 8.1-style touch OS for CC: Tweaked. **Big Picture** is the only shell: Start tiles, full-screen apps, PC settings and message bands, on the main monitor or on the computer itself. Pocket computers get a compact launcher. ccOS includes a categorized tool catalog, stereo audio, printer/disk integration, configurable clocks and an OpenRouter agent with native operating-system tools.

ccOS 3.0 removes the windowed desktop, Full Sync mirroring, the taskbar, the Start menu and the command palette. Existing installs update in place: desktop and Full Sync monitors switch to Big Picture, and the computer becomes their keyboard.

## Install

Run this on an advanced CC: Tweaked computer or either type of pocket computer:

```text
wget run https://raw.githubusercontent.com/mzyhot/ccOS/main/setup.lua
```

Or copy the single root **setup.lua** onto the computer:

1. Place **setup.lua** in the computer's files.
2. Run `setup`.
3. Follow the five setup pages: profile, time zone, clock and Start colour, optional OpenRouter connection, and finish.
4. ccOS preserves an existing startup script as `startup.before-ccos.lua` (numbered backups if needed), then automatically restarts into the OS.

`setup.lua` contains all **34** runtime files and libraries. It installs the modules into `/ccos`, verifies file contents, and then starts `/ccos/setup.lua`. No third-party Lua package downloads are required. `dist/setup.lua` is the same installer; `dist/install.lua` is a compatibility copy.

Reinstallation skips identical files and preserves configuration, notes, tool data and the saved key. Changed code is staged before replacement and restored if installation fails. Setup checks free space before making changes. Legacy `/aurora/config.cfg` preferences and tool data are imported when there is no ccOS configuration; the old installation and user files are retained. Desktop-era screen roles migrate to Big Picture. Existing startup scripts are kept.

To repeat only the configuration wizard later, run `/ccos/setup.lua`. To start manually, run `/ccos/kernel.lua`.

## Screens and navigation

- **Largest advanced monitor:** runs Big Picture (see [Big Picture](#big-picture) below). Every app opens full screen there, including Terminal, Editor, Lua, Paint and Worm.
- **Computer with a Big Picture monitor:** the monitor's keyboard. It shows what you are typing into: a prompt's text (API keys are masked), an AI Agent message, the app in front, or app search on Start. Its bottom bar has Start, Apps, AI Agent and PC settings buttons for the monitor.
- **Computer on its own:** with no advanced monitor attached, the computer runs Big Picture itself, with mouse clicks and the keyboard. Unplug the monitor and Big Picture moves to the computer with the same page or app in front; plug it back and the computer becomes the keyboard again.
- **Pocket computer:** automatically detected from the pocket API, with a 26x20 launcher, full-screen apps and compact settings. Advanced pockets support clicks; ordinary pockets work through keyboard navigation in greyscale.
- **Other monitors:** information panels for time, playback, notifications and hardware. Basic (non-colour) monitors are always panels, because they cannot be touched.

Monitor categories: **Favorites, Files, Time, Media, Math, Text, Developer, System, Games, AI**. The catalog has 63 visible entries, including 45 utilities. Apps are single instance: opening one again brings it back with its state. Every full-screen app has an 8.1 Update-style title bar with back, minimise (back to Start, app keeps running) and close. Text prompts on a monitor are typed on the computer.

Music, files, printers, speakers, settings and agent activity are shared across screens. Files opens folders with one tap, previews text up to 32 KB and prints previews. Restart, shut down and exit use a confirmation band.

Change monitor roles in **PC settings > Display**, the **Displays** tool, or a terminal:

```text
screen monitor_0 picture
screen monitor_0 panel
screen monitor_0 off
screen monitor_0 picture 1
```

The last form sets a fixed text scale. **PC settings > Display** also has text size steppers and automatic size for each monitor.

## Big Picture

The Big Picture monitor follows the Windows 8.1 Start screen, adapted to CC terminal cells. No Windows images, fonts or logos are used: the heading face, tile glyphs and marks are drawn by ccOS in teletext pixels.

- **Start:** a light "Start" heading, your account name and picture, then power and search marks at the top right. On a computer with no monitor, Start fills its 51x19 screen. Tiles sit on the 8.1 grid (small, medium = 2x2, wide = 4x2) and are square on screen. Each tile keeps a one-teletext-pixel gutter on its right and bottom edge, so the gaps are 3 screen pixels both ways, like the 10px Start gutter. Glyphs are centred to the pixel above the label.
- **Groups:** a pinned group (Clock, Music, Files, AI Agent, Settings, Terminal, Calendar and your favourites), then one named group per category. Groups flow in column blocks four units wide; the scrollbar at the bottom pans by whole blocks. Its arrows and track are touch targets.
- **Live tiles:** Clock shows the time and date, Music shows the current song, Calendar shows today's date and Notifications shows an unread badge.
- **Apps by category:** the arrow at the bottom left (or the search mark) lists every app under its category, with its tile colour. The up arrow returns to Start.
- **Search:** type on Start, like 8.1. The Apps view becomes search results with an 8.1 search box at the top right; Enter opens the top result, Backspace edits and Escape clears. On a monitor, tap the search box to type the query on the computer.
- **Power:** the power mark opens a Shut down / Restart / Exit to CraftOS flyout. The shutdown screen shows the five-dot ring on the Start colour.
- **Pages:** Music, Files, Devices and Notifications use an 8.1 page header (back circle and light title). Music has an AppBar with Previous, Play/Pause, Next and Stop. Confirmations and system dialogs are full-width message bands. Notifications appear as 8.1 toasts at the top right; tap one to act on it.
- **PC settings:** two panes on wide screens, a list then a page on narrow ones. **Personalize** (Start colour, accent colour, your name, screen saver), **Time and language**, **Sound** (music volume, balance, system sound volume, speaker test), **Display** (each monitor's role and text size, panel paging), **AI Agent** (key, model, review, step limit) and **Update and recovery** (version, update checks, Exit to CraftOS). Long pages scroll.
- **Colour:** every screen uses one flat Metro palette. The Start background follows **Start colour** and buttons, toggles and highlights follow **accent colour**.
- **Boot:** the Start colour, a light "ccOS" and the progress ring, then a welcome for you.

Automatic scale picks a text scale that gives the monitor about 30 rows, so a typical 8x3 monitor runs at 164x38 cells and tiles are crisp. For larger text, set a fixed scale, for example `screen monitor_0 picture 1`. The layout adapts down to 36x10.

## Pocket computers

The same root `setup.lua` detects pocket hardware automatically; no separate download or manual edition choice is needed. Both advanced colour pockets and ordinary monochrome pockets are supported. Other monochrome desktop computers still require an advanced model. Detection uses [CC: Tweaked's pocket API](https://tweaked.cc/module/pocket.html), not the terminal dimensions. Saved preferences cannot force a desktop/pocket hardware identity.

Pocket controls:

- **Arrow keys + Enter:** select and open launcher tiles; select and change settings.
- **Tab on Start:** next category; **Page Up/Down:** move through apps.
- **F2:** return to pocket Start while keeping open apps.
- **Tab inside ccOS apps:** focus visible buttons/controls; **Enter:** activate. The cursor marks focus. Native terminal/editor keys keep their usual behavior.
- **F1 / Alt+A:** AI Agent. **F3 / F4:** allow/deny an agent action.
- **Settings:** time zone, UTC offset, clock format, update checks, OpenRouter key/model, action review, name and power. The pocket footer exposes Home, Settings and Power on touch devices.
- Dialog buttons stack when needed. Arrow keys select a confirmation choice; Enter submits, Escape cancels. This includes the update prompt.

The pocket uses the same files, agent tools, settings, bundled modules, colours and updater as Big Picture. Hardware tools still need their corresponding peripherals; a pocket edition does not create a printer, speaker or monitor. Apps are full-screen within native 26x20 bounds. Other tools remain available by category; some complex views have fewer visible controls at once.

## Power transition

Shut down and restart show a Windows 8.1-style ring of five dots on the Start colour. Boot uses the same ring. The dots gather slowly at the top and spread out through the bottom. Large monitors use the light heading face for the label. The animation runs for about 1.6 real seconds, then powers off or restarts. It covers active monitors and pocket screens. Existing confirmation dialogs remain. Updating through the OS uses the same restart animation; leaving to CraftOS returns directly.

## New utilities

| Category | Utilities |
| --- | --- |
| Files | Notes, Checklist, Journal, Bookmarks, Disk manager, Storage analyzer, Backups |
| Time | Calendar, World clocks, Focus timer, Stopwatch, Countdown |
| Math | Unit converter, Percentages, Base converter, Random numbers, Counter |
| Text | Text statistics, Change case, Line tools, Find & replace, URL encoder, Base64 |
| Developer | JSON tools, HTTP inspector, Network monitor, Log viewer |
| System | Redstone, Analog signals, Bundled signals, Peripherals, Inventories, Energy stores, Fluid tanks, System info, Displays, Colours |
| Media | Speaker test, Metronome |
| Games | Dice, Coin flip, Lights Out, Memory pairs, Tic-tac-toe, Guess the number |

Files, Music, Piano, Clock, Calculator, Print Center, Tasks, PC settings, Editor, Paint, Terminal, Lua and Worm are available, along with Notifications, Devices, About and AI Agent. All of them run full screen in Big Picture. Notes and journals are ordinary files in `/notes`. Persistent tool data is in `/ccos/data`. User backups live under `/ccos/backups/user`; restoring makes a backup of the current data first.

## Time display

Configure time during setup or in **PC settings > Time and language**.

- 12-hour and 24-hour formats.
- Hour padding is off by default: `1:00 AM` or `1:00`, rather than `01:00`.
- Optional leading zero and seconds.
- Local/server time, UTC, fixed UTC offsets from -12:00 through +14:00 (15-minute controls), and named zones.
- Named zones: America/Chicago, New_York, Denver and Los_Angeles; Europe/London and Berlin; Asia/Kolkata and Tokyo; Australia/Sydney. US, European and Sydney daylight-saving transitions are calculated by the shared clock module.

The small clock panel draws AM/PM as a clear native-font label below the large digits. The bitmap M, N and W also have distinct shapes. Notification timestamps reserve their full width before notification text.

Big Picture, panels, Clock, world clocks, notification timestamps and print-job times share the same clock policy. Named zones use current recurring DST rules; this is a bundled set of zones, not a full historical IANA database. Fixed offsets cover other regions.

```text
timezone America/Chicago
timezone UTC
timezone fixed 330
```

## AI Agent

Use **Alt+A**, **F1**, its Start tile, the AI category, or the keyboard console's **AI Agent** button. `ai` opens it; `ai <task>` starts a task. On a monitor, AI Agent offers touch tasks, status, activity and action review, and you type messages on the computer. On a computer with no monitor it has its own chat composer.

Add your key during setup, in **PC settings > AI Agent**, or **AI Agent > Settings**. The key is masked during entry and stored locally in `/ccos/private/openrouter.cfg`, separate from public preferences and user-data backups. ccOS excludes it from model messages and redacts it from agent output/logs. CraftOS programs share the computer's trust environment; this is not an encrypted vault or a sandbox for arbitrary Lua programs.

The initial model is `openrouter/auto`. **AI Agent > Settings > Models** loads OpenRouter's current catalog, filters to models supporting tools, and shows free models first. You can include paid models or enter a model ID. Refreshing the catalog validates subsequent selections against tool-capable models. HTTP must be enabled and the computer must be able to reach `https://openrouter.ai`.

Requests omit the optional `parallel_tool_calls` flag to avoid excluding providers that do not support it. HTTP failures preserve OpenRouter's JSON error message and provider details, with hints for key, credit, routing and rate-limit errors. A 404 can still mean that your account/provider/privacy settings leave no available route; choose another tool-capable model in Models.

AI chat, action review and activity text convert UTF-8 to CC's single-byte terminal font **before** wrapping or clipping. Smart quotes, dashes, ellipses and common symbols have readable replacements; Latin-1 accents use the font's native glyphs. Unsupported characters use `?`, rather than displaying their UTF-8 bytes. Conversation history, tool arguments and file contents keep their original UTF-8. Keyboard input is encoded to UTF-8 for requests, including accented letters and CC input symbols. Legacy single-byte tool output is also encoded before transport. The display mapping follows [CC: Tweaked's terminal character conversion](https://github.com/cc-tweaked/CC-Tweaked/blob/mc-1.21.x/projects/core/src/main/java/dan200/computercraft/core/util/StringUtil.java).

The agent's native tools can:

- List, search and read files; create directories; write, append and edit files; copy, move and reversibly trash files.
- Verify new file content before committing it and keep previous file versions under `/ccos/backups/agent`.
- Open apps, run shell commands/Lua programs in real terminals (they open in the background; Terminal on Start brings them up), read their output and manage apps/processes.
- Inspect and change validated OS settings, time policy, screen roles/scales and the apps pinned to Start.
- Control audio, print files, inspect peripherals, call their methods, read/set redstone and post notifications.

Review changes is enabled initially. Every mutation can be allowed or denied from the computer or monitor; full arguments are scrollable before approval. Turning review off enables autonomous changes. Stop cancels pending work. Request tokens and the per-task step limit are adjustable. The activity view and `/ccos/logs/agent.log` record results, including declines. Task text and requested file/tool results are sent to OpenRouter; the key is used only in the authorization header. Chat history is kept for the current OS session.

The implementation follows [OpenRouter client tool calling](https://openrouter.ai/docs/guides/features/tool-calling), [chat completions](https://openrouter.ai/docs/api/api-reference/chat/create-a-chat-completion), and [CC: Tweaked's asynchronous HTTP API](https://tweaked.cc/module/http.html). API/model access still depends on your key, account and selected provider.

## Updates

Automatic update checks are enabled by default: once after startup, then every six real-life hours while the computer is running. A new release opens **Later / Update & restart**; installation only starts after you choose Update. Enter selects Later. Turn checks off in **PC settings > Update and recovery**. **Check now** checks manually.

Inside ccOS, run `update` to install the latest version and restart, or `update check` to check and prompt. From CraftOS, run the installed `/update.lua`. Existing ccOS 2.x installations can upgrade without repeating setup:

```text
wget run https://raw.githubusercontent.com/mzyhot/ccOS/main/update.lua
```

The background updater pins downloads to the checked GitHub commit, validates every file against `version.json` SHA-256 checksums, checks Lua syntax and disk space, stages replacements, and rolls back a failed commit. If GitHub's ref API is unavailable it uses the main-branch manifest; mismatched files are rejected. Settings, notes, user data, saved keys and startup scripts are preserved. It restarts into the new OS after a successful install. Save open work before accepting an update.

The standalone updater downloads the self-contained setup bundle in update mode, which uses the same transactional installer and skips the setup wizard. Installation and updates require access to `raw.githubusercontent.com`; background checks also use `api.github.com` when available.

## Keyboard

On the computer, whether it runs Big Picture or is the monitor's keyboard:

| Key | Action |
| --- | --- |
| F2 | Back to Start from anywhere |
| F1 / Alt+A | AI Agent |
| Type on Start | Search apps; Enter opens the top result |
| Escape / Backspace | Close a menu, clear search, or back out of a page |
| Left / Right, Page Up / Down | Pan Start, Apps and lists |
| Arrows, Tab, Enter | Choose and press a message band button |
| Ctrl+T | Stop the app in front |

Every other key goes to the app in front, so Terminal, Editor, Lua and Worm work as usual. Terminals keep the ccOS commands for apps, files, audio, printing, colours (`colour start blue`, `colour accent lime`), screens, hardware and power. Run `help` to list them. Existing `aurora` API programs have a compatibility alias while ccOS is running.

## Project layout

```text
setup.lua                  standalone bundled installer
update.lua                 standalone updater / 2.0 upgrade bridge
version.json               release file sizes and SHA-256 hashes
src/ccos/setup.lua         first-run wizard
src/ccos/kernel.lua        screens, app windows, processes, input, API and commands
src/ccos/lib/catalog.lua   categories and tool metadata
src/ccos/lib/suite.lua     the 45 utility implementations
src/ccos/lib/agent.lua     OpenRouter tool loop and OS operations
src/ccos/lib/time.lua      shared timezone/DST/display policy
src/ccos/lib/json.lua      bundled JSON codec
src/ccos/lib/encoding.lua  UTF-8 / terminal display and input boundary
src/ccos/lib/picture.lua   Big Picture pages, PC settings, toasts and message bands
src/ccos/lib/startscreen.lua 8.1 Start tile grid, live tiles, Apps view and search
src/ccos/lib/pocket.lua    portable launcher and fullscreen app shell
src/ccos/lib/device.lua    pocket/desktop hardware detection
src/ccos/lib/power.lua     boot, shutdown and restart progress ring
src/ccos/lib/input.lua     the computer as Big Picture's keyboard console
src/ccos/lib/updater.lua   checks, approval prompt and verified downloads
src/ccos/lib/install.lua   shared transactional file installer
src/ccos/lib/sha256.lua    bundled checksum implementation
src/ccos/lib/ui.lua        common app toolkit
src/ccos/lib/gfx.lua       terminal graphics, icons, Metro face and tile glyphs
src/ccos/lib/audio.lua     shared stereo audio engine
src/ccos/apps/             full-screen apps
```

## Build and verification

Requires Python 3 and Lua on the development computer:

```sh
python3 tools/bundle.py
python3 tools/check.py
cd test
lua harness.lua ../src picture screens.html
python3 ../tools/render.py screens.html shots
```

The check runner compiles every Lua source and runs 142 core assertions, 42 tool behavior assertions and 47 simulated runtime scenarios. Coverage includes all utility rendering on a monitor and on the computer, actual tool controls/persistence, timezone and DST boundaries, different monitor sizes, agent multi-round tool use, action approval/denial, cancellation, late responses, authentication errors, malformed arguments, setup/restart, offline setup, reinstall, low space and rollback. Installer tests compare every installed file to source. Pocket tests cover advanced/basic hardware detection and same-bundle installation, native-size navigation, settings, app button focus, AI approval, preserved updates and power animation. Start-layout checks cover nine monitor sizes from 36x10 to 164x53: tile bounds, overlap, reachability, the group heading row and square (unstretched) medium tiles. Every catalog app has its own tile glyph. Big Picture scenarios run at 164x38, 79x38, 82x19, 51x19 (the computer) and 36x10, through Start paging, live tiles, Apps by category, type-to-search, PC settings toggles, Start and accent colours, display roles, tool title bars, F2, Files, the power band and Exit to CraftOS. Keyboard tests type into a terminal on the monitor and on the computer, check its cursor and single-instance reopening, bridge monitor prompts, AI chat and masked key entry. Screen tests cover unplugging and replugging the monitor with an app open, and migrating desktop and Full Sync configurations. Update tests cover approval, decline, unchanged releases, offline checks, corrupt files, rollback, restart and preserved data. Panel AM/PM labels are checked. OpenRouter tests verify request parameters, provider-error details, filtered model selection, Unicode replies on the monitor, Unicode input transport and preserved Unicode file contents through action review.

OpenRouter requests are mocked in tests; no real API key or paid inference is used. Rendering is based on terminal cell captures, not a real Minecraft client. A Minecraft/live-provider check remains necessary on the target computer.
