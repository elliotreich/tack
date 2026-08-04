# Tack product brief

Tack is an open-source, Apple-native successor to the Post-it app: photograph a wall of paper notes, turn the result into discrete editable notes, and keep arranging them on a local-first whiteboard after the capture is gone.

## Product goals

- Preserve the paper-to-board loop with on-device rectangle detection, OCR, note images, colors, positions, rotation, and capture provenance.
- Make the board a real infinite-style canvas where people can create digital notes without a corresponding physical note.
- Keep captured and digital notes in the same model so both can be selected, edited, moved, searched, filtered, grouped, and exported.
- Keep data local and inspectable in a documented `.tack` package with no account requirement.
- Provide native Mac integration first: keyboard controls, widgets, Quick Look, Spotlight, Shortcuts, and later iPhone/iPad support.

## Deliberate non-goals for the current alpha

Frames, connectors, ink, undo/history, collaboration, cloud sync, App Intents, Spotlight indexing, and iOS/iPadOS are planned layers rather than claims about the current implementation.

## Compatibility

Legacy `.postit` import is compatibility tooling and a regression path. It is not a requirement that the app reproduce the old app's storage or branding. Tack is independent of 3M and does not use Post-it trade dress.
