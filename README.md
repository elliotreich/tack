# Tack

Tack is an open-source, local-first, Apple-native whiteboard and note-capture app.

It starts from the useful part of the Post-it app: photograph a wall of physical notes and turn the result into discrete, movable, editable notes. It also starts from the useful part of Freeform: create notes directly on a canvas, arrange them without a fixed page, and keep the board useful after the original capture is gone.

The public product brief is [Docs/PRODUCT.md](Docs/PRODUCT.md). The implementation is intentionally an alpha foundation rather than the complete future roadmap.

## The product in one sentence

Tack is a personal and shareable infinite canvas where digital notes and captured paper notes are the same kind of object, stored locally in an open format.

## Goals

### 1. Keep the paper-to-board loop

- Capture a photograph, scan, screenshot, or exported wall image.
- Detect individual notes on-device with Vision.
- OCR each captured note and keep the image, transcription, color, position, rotation, and capture provenance.
- Treat legacy `.postit` import as compatibility and regression tooling, not as the reason the app exists.

### 2. Be a real whiteboard

- The canvas has no hard outer edge.
- Notes can be moved, edited, searched, filtered, and grouped.
- A new digital note can be created at any time, even when no physical note or imported board exists.
- Captured and digital notes share the same editing model once they are on the board.
- The board should grow toward frames, connectors, shapes, ink, links, and task semantics without replacing the underlying note model.

### 3. Be local-first

- No account is required.
- Notes, OCR text, and images stay on the device unless the user exports or syncs them.
- Boards are ordinary `.tack` packages that can be inspected and backed up with filesystem tools.
- Autosave should make the safe path the normal path.

### 4. Be a durable replacement, not a clone

- Native Apple behavior on Mac first, followed by iPhone and iPad.
- Keyboard-first controls, accessible note text, drag-and-drop, Quick Look, Spotlight, widgets, and Shortcuts are part of the direction.
- Export is an escape hatch: Markdown, CSV, PDF, PNG/SVG, and open whiteboard formats should remain useful outside Tack.
- The project is unaffiliated with 3M and does not use Post-it branding or trade dress.

## Why infinite canvas is the right model

This is technically manageable at the current stage. Tack already stores notes as world-space rectangles and the UI already has a camera transform (`pan` + `zoom`). The finite feeling came from drawing a 1600×1000 background and fitting the camera to that rectangle, not from a fundamental data-model limitation.

The current implementation removes the visible boundary and fits the camera to the notes that exist. Scaling to thousands of notes is a later renderer problem: spatial indexing, viewport culling, texture caching, and eventually a Metal-backed canvas. It does not require abandoning the current `.tack` model.

## Current macOS implementation

Working now:

- SwiftUI native Mac app and bundled `Tack.app`.
- Infinite-style panning canvas with zoom-to-fit.
- Visible `New note` action and keyboard shortcut.
- Digital notes with double-click inline editing, drag movement, selection, deletion, and autosave.
- Font, size, bold/italic, and visual color-swatch controls for notes.
- A bundled `Pinned Note` macOS widget that follows the note selected with `Pin to desktop widget`.
- Captured notes from an image using Vision rectangle detection and on-device OCR.
- Captured note images, OCR text, colors, groups, positions, rotation, and provenance.
- Search across note text and groups.
- Filters for all notes, captured notes, text-only notes, and capture groups.
- Markdown and CSV export.
- Optional `.postit` importer verified against the installed 2025 board.
- `tackkit` commands for capture, validation, and compatibility conversion.
- Human-readable `.tack` directory packages.

The real wall-capture fixture currently produces 30 captured notes with one group and no missing image assets. The installed 2025 `.postit` fixture imports as 383 notes across 53 groups.

## What is intentionally next

This repository is the native Mac foundation, not the complete M0–M9 specification yet. The next product layers are:

1. Note resizing, richer text, and undo/history.
2. Frames, connectors, shapes, canvas-level text, and ink.
3. Better capture review: missed-note correction, perspective cleanup, and multi-shot wall stitching.
4. Open archive output, stronger round-trip exporters, and Quick Look previews.
5. App Intents, Shortcuts, Spotlight, and interactive widget actions.
6. iOS/iPadOS, optional iCloud sync, and offline peer collaboration.

The acceptance test for the core model is simple: a user can open a blank board, add and arrange digital notes, capture physical notes into the same board, edit both kinds, and export the result without needing a migration project or a cloud account.

## Repository layout

~~~text
Tack/
├── Sources/
│   ├── TackCore/       # Board, note, capture, group, and canvas models
│   ├── TackFormat/     # .tack package read/write and exporters
│   ├── TackCapture/    # Vision segmentation and OCR
│   ├── TackInterop/    # Optional legacy .postit importer
│   ├── TackApp/        # Native SwiftUI Mac app
│   └── TackWidgets/    # Pinned-note WidgetKit extension
├── Tests/              # Portable format, importer, exporter, and widget-store tests
├── Resources/          # Info.plist and app icon
├── Docs/               # Format, product, and release notes
└── scripts/            # App, icon, and release build helpers
~~~

## Build and run

~~~bash
swift test
./scripts/build-app.sh
open build/Tack.app
~~~

Boards created or imported through the app default to `~/Documents/Tack`. Tack does not delete, rewrite, or move the source `.postit` archive.

To use the desktop widget, select a note and choose `Pin to desktop widget` in the inspector or the note's context menu. Then add Tack's `Pinned Note` widget from the macOS widget gallery. macOS requires the user to place a widget through the gallery; Tack publishes the selected note's latest local snapshot for the widget to render.

For a distributable local archive, run `./scripts/build-release.sh`. See [RELEASE.md](RELEASE.md) for Developer ID signing and notarization requirements.

## CLI

~~~bash
swift run tackkit capture wall.jpg Board.tack
swift run tackkit validate Board.tack
swift run tackkit convert legacy.postit Board.tack
swift run tackkit convert legacy.postit Board.tack --retain-captures
~~~

## License and compatibility

The application is licensed under [AGPL-3.0-only](LICENSE). The file format, sync protocol, and SDK-facing libraries are licensed under [Apache-2.0](LICENSE-APACHE).

Post-it is a registered trademark of 3M. Tack is an independent project and is not endorsed by or affiliated with 3M.
