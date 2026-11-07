# ccOS Big Picture and Pocket design

Windows 8.1-style, adapted to native CC terminal cells. Native CC text for body copy; ccOS-drawn teletext art for headings, glyphs and marks. No Windows images, fonts or logos are copied.

One shell: Big Picture runs on the main advanced monitor, or on the computer when no monitor is attached. With a monitor, the computer is its keyboard console (top bar on the Start colour, what the keyboard is typing into, and Start / Apps / AI Agent / PC settings buttons). Pocket computers keep their compact launcher. There is no windowed desktop, Full Sync mirror, taskbar, Start menu or command palette.

Start: light "Start" heading at the left margin; account name, picture, power and search marks at the top right. Tiles on the 8.1 grid: a small unit is sw x sh cells (3x2, 5x3, 6x4 or 8x5) so a medium tile (2x2 units) is square on screen. Every tile leaves a one-teletext-pixel gutter on its right and bottom edge (3px both ways). Groups flow in four-unit column blocks; pages pan by whole blocks with a bottom scrollbar. Pinned group: Clock and Music (wide, live), Files, AI Agent, Settings, Terminal, Calendar (live), then favourites. Notifications shows an unread badge. Apps by category behind the arrow; typing on Start turns it into search results with a white search box at the top right. Power flyout: Shut down, Restart, Exit to CraftOS.

Pages: back circle plus light title; flat lists with 6px or 18px colour squares; AppBar ring buttons for media; two-pane PC settings (list then page when narrow) with toggles, combo boxes, steppers, sliders and buttons, scrolling when long; full-width message bands for confirmations and system dialogs; 8.1 toasts at the top right for notifications; 8.1 Update title bar (back, colour chip, title, clock, minimise, close) over every full-screen app. Apps are single instance. F2 returns to Start; keys go to the app in front.

Pocket: detected from the pocket API, 26x20 layout, two-column launcher, keyboard focus and pagination, full-screen apps, compact native settings. Basic pockets use the same structure in monochrome. F2 returns to Start.

Boot and power: Start-colour background, light "ccOS" (boot), five eased dots on a ring, status label (light face on large screens). Power finishes in 1.6 seconds. No fake progress steps.

Tokens: every screen uses one Metro palette in the semantic slots (bg #1D1D1D, surface #2B2B2B, raised #464646, muted #A6A6A6, text #FFFFFF, tile colours violet/purple/crimson/green/dark green/amber/orange/red/blue). K.T.select is the Start colour and K.T.accent the accent colour, both chosen in PC settings > Personalize.

Verification sizes: 164x38, 79x38, 82x19 and 36x10 monitor cells, 51x19 computer cells (plus layout checks at 82x26, 100x38, 61x26, 164x53, 57x24); 26x20 pocket cells. These replace web-pixel breakpoints in this terminal application.
