# Tack product and replacement brief

## Position

Tack is an open-source, Apple-native Mac whiteboard for turning physical notes into a durable, editable board. It is local-first, stores boards in an inspectable `.tack` package, and treats photographed notes and typed notes as the same kind of object after capture.

Tack is intended to replace a workflow, not imitate another product's branding or private implementation.

## What it replaces

The Post-it app made one workflow valuable: photograph a wall of paper notes, detect the notes, read their text, and preserve the result digitally. Tack is meant to be the durable home for that workflow going forward.

The replacement has two parts:

### 1. A paper-wall capture tool

Tack captures an image, detects note-shaped regions with Vision, performs OCR on-device, and records the image crop, text, color, position, rotation, group, and capture provenance. An optional `.postit` importer keeps existing boards usable and provides a compatibility regression path.

### 2. A real board after capture

The old capture workflow is incomplete if the result cannot continue to evolve. Tack therefore adds the Freeform-like part that matters for this product:

- create a note without a physical note;
- double-click and type inside the note;
- change typography and note color;
- move, search, filter, group, and export notes;
- pan and zoom beyond a finite page edge;
- pin a selected note to the Mac desktop as a widget.

Tack is not currently a complete replacement for every Freeform feature, a cloud collaboration service, or a drop-in clone of the Post-it app. The goal is to replace the original personal paper-to-board workflow first, then provide the same durable foundation to other people who used that workflow.

## Product goals

1. **Keep the paper-to-board loop.** A wall photograph should become a useful set of editable notes rather than a dead image.
2. **Make capture optional.** The first note on a board can be typed directly; paper is an input, not a prerequisite.
3. **Use one note model.** Captured and digital notes should share editing, styling, movement, search, grouping, export, and widget behavior.
4. **Make the canvas effectively infinite.** Notes live in world coordinates; the initial viewport is not a page boundary.
5. **Stay local-first.** The user should be able to work without an account, inspect the package, and back it up with ordinary filesystem tools.
6. **Integrate with the Mac.** The app should feel at home beside Finder, the desktop, widgets, keyboard controls, Quick Look, Spotlight, and Shortcuts.
7. **Remain useful outside Tack.** Markdown, CSV, and future open-board exports prevent the board from becoming a new silo.
8. **Ship as a real public package.** Tests, licenses, metadata, CI, release instructions, and security/reporting guidance are part of the product, not cleanup after it.

## Current alpha scope

The current Mac foundation includes:

- a SwiftUI app and WidgetKit extension for macOS 15;
- digital notes with inline editing, typography, colors, movement, search, filters, grouping, deletion, and autosave;
- Vision capture and OCR;
- legacy `.postit` import without modifying the source archive;
- Markdown and CSV export;
- a human-readable `.tack` directory format;
- a pinned-note desktop widget;
- `tackkit` capture, validation, and conversion commands.

## Deliberate next layers

The following are intentionally outside the current alpha rather than hidden requirements:

- note resizing, richer text, undo, and history;
- frames, connectors, shapes, canvas-level text, and ink;
- capture correction, perspective cleanup, and multi-shot wall stitching;
- PDF, PNG/SVG, and broader open-whiteboard export;
- Quick Look, App Intents, Shortcuts actions, and Spotlight indexing;
- iPhone/iPad apps, optional iCloud sync, and collaboration.

## Success condition

The core product is working when a person can:

1. open a blank board;
2. create and edit a digital note;
3. capture or import physical notes into the same board;
4. arrange, search, filter, style, and group both kinds of notes;
5. pin one note to the desktop;
6. export the board without needing an account or a migration project.

## Compatibility and independence

The `.postit` importer is a compatibility feature and test path. It does not modify the source archive, and the project does not depend on reproducing the source app's private storage format forever.

Post-it is a registered trademark of 3M. Tack is independent and does not use Post-it branding or trade dress.
