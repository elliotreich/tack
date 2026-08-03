# Tack

Tack is an open-source, local-first successor to the Post-it app. The product direction is specified in [`TACK.md`](../../../0_inbox/TACK.md).

This first implementation slice is deliberately narrow and real:

- native SwiftUI macOS app;
- on-device image capture path using Vision rectangle detection and OCR;
- optionally open a `.postit` archive and copy its board into a `.tack` directory package;
- preserve captured note images, OCR text, colors, groups, positions, rotation, and provenance;
- move notes on a canvas, search note/group text, edit note text, add/delete notes;
- validate and migrate boards from the command line with `tackkit`.

## Build

```bash
swift test
swift build -c release
```

The local Post-it fixture test is skipped automatically if the installed Post-it container is absent. With the fixture present, it verifies the installed 2025 board imports as 383 notes across 53 groups. Import is compatibility tooling; new boards and image captures are the primary workflow.

## CLI

```bash
swift run tackkit convert legacy.postit Board.tack
swift run tackkit convert legacy.postit Board.tack --retain-captures
swift run tackkit validate Board.tack
swift run tackkit capture wall.jpg Board.tack
```

## Native app bundle

```bash
./scripts/build-app.sh
open build/Tack.app
```

The app defaults to `~/Documents/Tack` for imported and newly saved boards. It does not delete, rewrite, or move the source `.postit` archive.
