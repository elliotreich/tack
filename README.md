# Tack

Tack is a local-first, Apple-native Mac whiteboard intended to replace the useful part of the Post-it app: photograph a wall of physical notes, turn them into discrete editable notes, and keep working with them after the capture is over.

It adds the half that the old capture workflow does not provide: create a new note without a piece of paper, arrange notes on an infinite-style canvas, edit their text and style, change their colors, search and filter them, and pin one to the Mac desktop as a widget.

Tack is an independent open-source project. It is not affiliated with 3M and is not a 1:1 clone of the Post-it app or Apple Freeform.

## What Tack is replacing

Tack is designed around a specific replacement workflow:

1. Photograph, scan, or import a wall of physical notes.
2. Detect the individual notes and transcribe their text on-device.
3. Preserve each note's image, text, color, position, rotation, group, and capture provenance.
4. Continue arranging and editing the result as a living board.

The old Post-it workflow is strongest at the capture step, but it does not provide the durable whiteboard that comes after it. Tack keeps the paper-to-board loop and makes the result useful as an ordinary canvas.

Tack also replaces the need to create a physical note just to get an idea onto the board. Digital notes and captured notes use the same model once they are in Tack, so both kinds can be moved, edited, styled, searched, grouped, exported, or pinned to a widget.

This is a workflow replacement, not a promise to reproduce every private storage detail, screen, or brand element of another product. The optional `.postit` importer exists to make existing boards useful and to keep compatibility testable; it is not the product's center of gravity.

## Product goals

### Preserve the paper-to-board loop

- Capture a photograph, scan, screenshot, or exported wall image.
- Detect note-shaped regions with Vision on the Mac.
- OCR each captured note on-device.
- Keep the original crop, transcription, color, position, rotation, group, and provenance together.

### Make the board useful without paper

- Create a new note on any blank board.
- Double-click inside a note to type directly.
- Change font, size, bold, italic, and note color.
- Move notes around an infinite-style canvas with pan, zoom, search, filters, and groups.

### Keep captured and digital notes together

There should not be one editor for photographed notes and another for typed notes. Once a note is on the board, it should be the same kind of object regardless of where it came from.

### Stay local-first and durable

- No account is required.
- Notes, OCR text, and images remain on the Mac unless the user exports or syncs them.
- Boards are inspectable `.tack` directory packages rather than an opaque database.
- Markdown and CSV exports provide an escape hatch.

### Feel native on Apple platforms

Mac is the first platform. The direction includes keyboard controls, accessibility, drag-and-drop, Quick Look, Spotlight, Shortcuts, widgets, and eventually iPhone and iPad support.

## What works today

- Native SwiftUI Mac app targeting macOS 15.
- Infinite-style panning and zooming canvas with no visible hard outer edge.
- New digital notes on blank boards.
- Double-click inline editing, drag movement, selection, deletion, and autosave.
- Font, size, bold, italic, and visual color-swatch controls.
- Vision rectangle detection and on-device OCR for captured images.
- Captured note images, OCR text, color, group, position, rotation, and provenance.
- Search across note text and groups.
- Filters for all notes, captured notes, text-only notes, and capture groups.
- Markdown and CSV export.
- Optional legacy `.postit` import that never modifies the source archive.
- A `Pinned Note` macOS widget backed by a shared App Group snapshot.
- `tackkit` commands for capture, validation, and compatibility conversion.
- Human-readable `.tack` directory packages documented in [Docs/FORMAT.md](Docs/FORMAT.md).

The repository includes a portable synthetic importer fixture. A private full-board regression can be run locally by setting `TACK_LEGACY_FIXTURE` to a `.postit` archive; personal board data is intentionally not committed.

## What it does not replace yet

Tack is an alpha foundation, not yet a complete replacement for every part of Freeform or a collaborative whiteboard service. These are planned layers:

- Note resizing, richer text, undo, and history.
- Frames, connectors, shapes, canvas-level text, and ink.
- Better capture review, missed-note correction, perspective cleanup, and multi-shot wall stitching.
- PDF, PNG/SVG, and broader open-whiteboard export.
- Quick Look previews, App Intents, Shortcuts actions, and Spotlight indexing.
- iPhone/iPad versions, optional iCloud sync, and peer collaboration.

The current acceptance test is deliberately smaller: a user can open a blank board, add digital notes, capture physical notes into the same board, edit both kinds, pin one to the desktop, and export the result without an account or migration project.

## Why an infinite-style canvas

Tack stores notes in world coordinates and the app already has a camera transform for pan and zoom. The initial finite feeling came from the viewport background and fit behavior, not from a hard data-model boundary. The current canvas therefore grows with the notes instead of treating the initial canvas size as a page edge.

Thousands of notes will eventually require spatial indexing, viewport culling, texture caching, and possibly a Metal-backed renderer. Those are scaling improvements, not reasons to abandon the current `.tack` model.

## Build and run

Requirements: macOS 15 or later, Swift 6, and the Vision framework available on the Mac.

```bash
swift test
./scripts/build-app.sh
open build/Tack.app
```

Boards created or imported through the app default to `~/Documents/Tack`. Tack does not delete, rewrite, or move the source `.postit` archive.

To use the desktop widget, select a note, choose `Pin to desktop widget`, and add Tack's `Pinned Note` widget from the macOS widget gallery. See [Docs/TESTING.md](Docs/TESTING.md) for the manual smoke path and [RELEASE.md](RELEASE.md) for signing and notarization.

## CLI

```bash
swift run tackkit capture wall.jpg Board.tack
swift run tackkit validate Board.tack
swift run tackkit convert legacy.postit Board.tack
swift run tackkit convert legacy.postit Board.tack --retain-captures
```

## Repository guide

- [Docs/PRODUCT.md](Docs/PRODUCT.md) — product position, replacement scope, goals, and boundaries.
- [Docs/FORMAT.md](Docs/FORMAT.md) — `.tack` package structure and compatibility rules.
- [Docs/TESTING.md](Docs/TESTING.md) — automated checks and hands-on Mac test path.
- [RELEASE.md](RELEASE.md) — local archives, Developer ID signing, App Groups, and notarization.
- [CONTRIBUTING.md](CONTRIBUTING.md) — contribution and data-safety rules.
- [CHANGELOG.md](CHANGELOG.md) — version history.

## License and compatibility

The application is licensed under [AGPL-3.0-only](LICENSE). The file format and SDK-facing libraries are licensed under [Apache-2.0](LICENSE-APACHE).

Post-it is a registered trademark of 3M. Tack is an independent project and is not endorsed by or affiliated with 3M.
