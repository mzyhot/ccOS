# ccOS 2.0

A desktop and compact touch interface for advanced CC: Tweaked computers. ccOS includes a categorized tool catalog, stereo audio, printer/disk integration, configurable clocks and an OpenRouter agent with native operating-system tools.

## Install

1. Copy the single root **setup.lua** onto an advanced computer (drag it onto the computer GUI or place it in its ComputerCraft computer folder).
2. Run `setup`.
3. Follow the five setup pages: profile, time zone, clock/appearance, optional OpenRouter connection, and finish.
4. ccOS preserves an existing startup script as `startup.before-ccos.lua` (numbered backups if needed), then automatically restarts into the OS.

`setup.lua` contains all **24** source files and libraries. It installs the modules into `/ccos`, verifies file contents, and then starts `/ccos/setup.lua`. No third-party Lua package downloads are required. `dist/setup.lua` is the same installer; `dist/install.lua` is a compatibility copy.

Reinstallation skips identical files and preserves configuration, notes, tool data and the saved key. Changed code is staged before replacement and restored if installation fails. Setup checks free space before making changes. Legacy `/aurora/config.cfg` preferences and tool data are imported when there is no ccOS configuration; the old installation and user files are retained. Theme/wallpaper names are migrated. Existing startup scripts are kept.

To repeat only the configuration wizard later, run `/ccos/setup.lua`. To start manually, run `/ccos/kernel.lua`.

## Screens and navigation

- **Computer:** windowed desktop, categorized Start menu, command palette, terminals, text input and AI chat. Labels have dark backplates for readability over wallpaper.
- **Largest advanced monitor:** compact `picture` mode. A one-row header and playback bar surround the tool workspace. Categories occupy a slim sidebar; tiny monitors use a category switcher. The old “Big Screen” heading is gone.
- **Other monitors:** information panels for time, playback, notifications and hardware.

Monitor categories: **Favorites, Files, Time, Media, Math, Text, Developer, System, Games, AI**. The catalog has 62 visible entries, including 45 new utilities. Monitor controls use taps and pagination. Tools that require typing, or more space than the monitor provides, open on the computer. No text entry fields are shown on the monitor. Fullscreen monitor apps have a close button and a Tools button.

Music, files, printers, speakers, settings and agent activity are shared across screens. Files on the monitor opens folders with one tap, previews text up to 32 KB and prints previews. Restart and shutdown use a confirmation tap.

Change monitor roles in computer **Settings > Screens**, the **Displays** tool, or a terminal:

```text
screen monitor_0 picture
screen monitor_0 mirror
screen monitor_0 desktop
screen monitor_0 panel
screen monitor_0 off
screen monitor_0 picture 1
```

`mirror` is a live centred copy of the computer, with touch-to-click mapping. `desktop` is a separate windowed desktop. Automatic scale is available in Settings.

## New utilities

| Category | Utilities |
| --- | --- |
| Files | Notes, Checklist, Journal, Bookmarks, Disk manager, Storage analyzer, Backups |
| Time | Calendar, World clocks, Focus timer, Stopwatch, Countdown |
| Math | Unit converter, Percentages, Base converter, Random numbers, Counter |
| Text | Text statistics, Change case, Line tools, Find & replace, URL encoder, Base64 |
| Developer | JSON tools, HTTP inspector, Network monitor, Log viewer |
| System | Redstone, Analog signals, Bundled signals, Peripherals, Inventories, Energy stores, Fluid tanks, System info, Displays, Theme gallery |
| Media | Speaker test, Metronome |
| Games | Dice, Coin flip, Lights Out, Memory pairs, Tic-tac-toe, Guess the number |

The original Files, Music, Piano, Clock, Calculator, Print Center, Tasks, Settings, Editor, Paint, Terminal, Lua and Worm remain available, along with Notifications, Devices, About and AI Agent. Notes and journals are ordinary files in `/notes`. Persistent tool data is in `/ccos/data`. User backups live under `/ccos/backups/user`; restoring makes a backup of the current data first.

## Time display

Configure time during setup, in **Settings > Clock & panel**, or in the monitor's **Settings** view.

- 12-hour and 24-hour formats.
- Hour padding is off by default: `1:00 AM` or `1:00`, rather than `01:00`.
- Optional leading zero and seconds.
- Local/server time, UTC, fixed UTC offsets from -12:00 through +14:00 (15-minute controls), and named zones.
- Named zones: America/Chicago, New_York, Denver and Los_Angeles; Europe/London and Berlin; Asia/Kolkata and Tokyo; Australia/Sydney. US, European and Sydney daylight-saving transitions are calculated by the shared clock module.

Desktop, monitor, panels, Clock, world clocks, notification timestamps and print-job times share the same clock policy. Named zones use current recurring DST rules; this is a bundled set of zones, not a full historical IANA database. Fixed offsets cover other regions.

```text
timezone America/Chicago
timezone UTC
timezone fixed 330
```

## AI Agent

Use **Alt+A**, **F1**, the AI tray button, Start menu, command palette or monitor's AI category. `ai` opens it; `ai <task>` starts a task. The computer has a chat composer. The monitor offers touch tasks, status, activity and action review, without a typing field.

Add your key during setup, in **Settings > AI Agent**, or **AI Agent > Settings**. The key is masked during entry and stored locally in `/ccos/private/openrouter.cfg`, separate from public preferences and user-data backups. ccOS excludes it from model messages and redacts it from agent output/logs. CraftOS programs share the computer's trust environment; this is not an encrypted vault or a sandbox for arbitrary Lua programs.

The model id is configurable; the initial selection is `openrouter/auto`. Use an OpenRouter model that supports tools. HTTP must be enabled and the computer must be able to reach `https://openrouter.ai`. The app reports authentication, model, HTTP and timeout failures.

The agent's native tools can:

- List, search and read files; create directories; write, append and edit files; copy, move and reversibly trash files.
- Verify new file content before committing it and keep previous file versions under `/ccos/backups/agent`.
- Open apps, run shell commands/Lua programs in real windows, read window output and manage windows/processes.
- Inspect and change validated OS settings, time policy, screen roles/scales and desktop/monitor favorites.
- Control audio, print files, inspect peripherals, call their methods, read/set redstone and post notifications.

Review changes is enabled initially. Every mutation can be allowed or denied from the computer or monitor; full arguments are scrollable before approval. Turning review off enables autonomous changes. Stop cancels pending work. Request tokens and the per-task step limit are adjustable. The activity view and `/ccos/logs/agent.log` record results, including declines. Task text and requested file/tool results are sent to OpenRouter; the key is used only in the authorization header. Chat history is kept for the current OS session.

The implementation follows [OpenRouter client tool calling](https://openrouter.ai/docs/guides/features/tool-calling), [chat completions](https://openrouter.ai/docs/api/api-reference/chat/create-a-chat-completion), and [CC: Tweaked's asynchronous HTTP API](https://tweaked.cc/module/http.html). API/model access still depends on your key, account and selected provider.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| Alt+Space | Command palette |
| Alt+A / F1 | AI Agent |
| Alt+S | Start menu |
| Alt+T / Alt+F | Terminal / Files |
| Alt+Tab | Cycle computer windows |
| Alt+Enter / Alt+Up | Maximize |
| Alt+Left / Alt+Right | Snap left/right |
| Alt+Down / Alt+Q | Minimize / close |
| Alt+M | Move window to next desktop |

Terminals keep the ccOS commands for apps, files, audio, printing, themes, screens, hardware and power. Run `help` to list them. Existing `aurora` API programs have a compatibility alias while ccOS is running.

## Project layout

```text
setup.lua                  standalone bundled installer
src/ccos/setup.lua         first-run wizard
src/ccos/kernel.lua        screens, windows, processes, input, API and commands
src/ccos/lib/catalog.lua   categories and tool metadata
src/ccos/lib/suite.lua     the 45 utility implementations
src/ccos/lib/agent.lua     OpenRouter tool loop and OS operations
src/ccos/lib/time.lua      shared timezone/DST/display policy
src/ccos/lib/json.lua      bundled JSON codec
src/ccos/lib/picture.lua   compact monitor workspace
src/ccos/lib/ui.lua        common app toolkit
src/ccos/lib/gfx.lua       terminal graphics and icons
src/ccos/lib/audio.lua     shared stereo audio engine
src/ccos/apps/             desktop and fullscreen apps
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

The check runner compiles every Lua source and runs 30 core assertions, 42 tool behavior assertions and 23 simulated runtime scenarios. Coverage includes all utility rendering, actual tool controls/persistence, timezone and DST boundaries, Start and mirror input, different monitor sizes, agent multi-round tool use, action approval/denial, cancellation, late responses, authentication errors, malformed arguments, setup/restart, offline setup, reinstall, low space and rollback. Installer tests compare every installed file to source.

OpenRouter requests are mocked in tests; no real API key or paid inference is used. Rendering is based on terminal cell captures, not a real Minecraft client. A Minecraft/live-provider check remains necessary on the target computer.
