# ccOS Start and Pocket design

Windows 8.1-inspired, adapted to native CC terminal cells. Existing native fonts, K.T semantic colours and generated icons remain. No image/font assets or Windows logos are copied.

Big Picture: full-screen Start heading, flat saturated tiles, mixed tile widths, group/category navigation, live clock/music state, All apps and Full Sync/desktop actions. Monitor has no keyboard composer.

Pocket: detected from the pocket API, 26x20 layout, two-column launcher, keyboard focus and pagination, full-screen apps, compact native settings. Basic pockets use the same structure in monochrome. F2 returns to Start.

Power: solid select-colour background, moving dot ring, native status label, 1.6-second finish. No fake progress steps.

Tokens: K.T.select for Start/power canvas; tile colours from K.T.accent, accent2, green, orange, danger and info; K.T.text labels. One-cell gutters. Native text for headings/body, pixel icons only when enough room. Desktop, Full Sync and stored data retain their existing ownership.

Verification sizes: 82x19, 79x38, 36x10 monitor cells; 26x20 pocket cells. These replace web-pixel breakpoints in this terminal application.
