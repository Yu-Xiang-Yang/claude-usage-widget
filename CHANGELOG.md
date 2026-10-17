# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [semantic versioning](https://semver.org/).

## [1.1.1] - 2026-10-17

### Added

- **Background** option in the context menu (Standard, Dense, Solid): a tint over the glass that darkens the card and makes it more opaque.

### Changed

- The default card is darker and more opaque (Dense). Standard restores the previous look.

## [1.1.0] - 2026-10-13

### Added

- `scripts/install.sh` (checksum- and signature-verified installer) and an "Install with Claude" section in the README: the repository link can be sent to Claude, which installs the widget.
- Clicking the widget opens the Claude app (claude.ai when the app is not installed); the **On Click** menu switches it to the claude.ai usage page or to no action.
- Refresh button in the header of every size class (previously only the large class had one).
- Pointing at a heatmap day shows its date, tokens, messages and cost immediately and highlights the cell; the delayed system tooltip was removed.

### Changed

- A pointer movement of less than 4 pt is a click and no longer moves or snaps the widget.
- The card dims briefly while it is pressed, so a click is visible even when Claude is already in front.

### Fixed

- Clicks and drags were ignored over text, heatmap cells and filled areas (only parts of the card responded). Clicking and dragging is now handled by one gesture on the whole card; the refresh button and the sign-in link keep their own action.

## [1.0.1] - 2026-10-13

### Added

- Application icon (a usage gauge with a four-point star), shown in Finder, Launchpad, Spotlight and the Login Items list.

## [1.0.0] - 2026-10-13

### Added

- Desktop widget with four size classes (small, medium, large, extra large) that follow the measured geometry of macOS system widgets: card size, 27 pt corner radius, 180 pt grid snapping, Liquid Glass material on macOS 26.
- 5-hour and weekly plan limits (percentage, reset countdown, local usage inside the window) and per-model weekly limits, read through an embedded claude.ai sign-in.
- GitHub-style activity heatmap (tokens or messages per day) with a persistent per-day history.
- Today, 7-day and 30-day totals, today's token composition, model split and estimated cost.
- English and Chinese interface, switchable from the context menu.
- Launch at login through the system login item, universal (Apple silicon and Intel) release build.
