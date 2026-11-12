# Changelog

All notable changes to Tack will be recorded here.

## [Unreleased]

- The build script now reads the Apple Team ID from the signing certificate, so anyone with their own Apple Development identity can build a working app and widget. The App Group is `<TeamID>.app.tack`; official builds are unchanged.
- Rewrote the build instructions for people building Tack themselves and fixed outdated statements about capture and widgets.
- Moved the long-range specification from `TACK.md` to `Docs/SPEC.md` and marked it as a plan.

## [0.1.0] - 2026-08-04

- Added a native local-first Mac board and open `.tack` directory format.
- Added digital notes, infinite-style canvas navigation, capture/OCR, and legacy `.postit` import.
- Added inline editing, typography controls, visual color swatches, and a pinned-note widget target.
- Added portable format, exporter, widget-store, and importer regression tests.
- Added public product, replacement-scope, build, testing, release, security, and contribution documentation.
- Polished the board workspace, empty state, sidebar selection, note treatment, and inspector hierarchy.
