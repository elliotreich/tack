# Changelog

All notable changes to Tack will be recorded here.

## [Unreleased]

- Added `tackkit mcp`, a Model Context Protocol server so AI agents can list, read, search, create, edit, move, group, delete and capture notes, with every change journaled in `ops/agent-journal.jsonl` and reversible with `undo_agent_change`. Also `tackkit list`, `show` and `search`.
- The app now watches the open board and picks up changes other processes write to `board.json`, merging them with unsaved edits; saves merge with on-disk changes instead of overwriting them, under a per-board lock.
- Post-it import now keeps typed text over a note (`noteEditInfo`) and the user's own corrections of a transcription (`userProvidedText`); both were previously replaced by the raw OCR guess or dropped.
- `TACK_CLT_ONLY=1` builds `tackkit` and runs the swift-testing suite on a Mac with only the Command Line Tools.

- The build script now reads the Apple Team ID from the signing certificate, so anyone with their own Apple Development identity can build a working app and widget. The App Group is `<TeamID>.app.tack`; official builds are unchanged.
- Rewrote the build instructions for people building Tack themselves and fixed outdated statements about capture and widgets.
- Added a Download section and the unnotarized GitHub release process.
- Moved the long-range specification from `TACK.md` to `Docs/SPEC.md` and marked it as a plan.

## [0.1.0] - 2026-08-04

- Added a native local-first Mac board and open `.tack` directory format.
- Added digital notes, infinite-style canvas navigation, capture/OCR, and legacy `.postit` import.
- Added inline editing, typography controls, visual color swatches, and a pinned-note widget target.
- Added portable format, exporter, widget-store, and importer regression tests.
- Added public product, replacement-scope, build, testing, release, security, and contribution documentation.
- Polished the board workspace, empty state, sidebar selection, note treatment, and inspector hierarchy.
