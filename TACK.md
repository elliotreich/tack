# Tack — Technical & Product Specification v1.0

**An open-source, Apple-native successor to the Post-it® App**
Working codename: **Tack** (`app.tack.*`)
Platforms: macOS 15+, iOS 18+, iPadOS 18+, visionOS 2+ (stretch)
Language: Swift 6 (strict concurrency), SwiftUI-first with AppKit/UIKit escape hatches
License: **AGPL-3.0** for the app + **Apache-2.0** for the file format, sync protocol, and SDKs
Status: Draft for implementation
Date: 2026-08-03

---

## 0. Executive summary

3M's Post-it® App is being wound down. Its core loop — *photograph a wall of paper sticky notes → get discrete, movable, editable digital notes → arrange them → push them somewhere useful* — has no clean open-source equivalent. Everything adjacent is either a heavyweight SaaS whiteboard (Miro, Mural, FigJam, Lucidspark) that charges per seat and locks data in a server, or a local note app with no camera-to-note pipeline.

**Tack** rebuilds that loop, local-first and offline-capable, and then goes past it in three directions the original never covered:

1. **Real OS integration.** Post-it's widget was a static home-screen picture. Tack ships interactive WidgetKit widgets on macOS desktop + Notification Center, iOS home/lock screen, StandBy, Control Center controls, App Intents/Shortcuts, and Spotlight indexing.
2. **A whiteboard worth staying in.** Infinite canvas, frames, connectors, ink, real-time multi-peer collaboration over CRDT, versioned history. Target: beats FigJam/Miro on *speed and offline*, matches them on *core canvas features*, deliberately does not chase their template marketplaces.
3. **Export is a first-class contract, not a feature.** An open, documented, plain-text-friendly file format (`.tack`, a zipped bundle) plus lossless-as-possible exporters/importers to Miro, FigJam, Excalidraw, Lucidspark, Trello, Obsidian Canvas, tldraw, Markdown, CSV, PDF, PPTX, and OPML. Importer for legacy `.postit` bundles is a **P0 launch blocker**.

Guiding principle: **your notes are files on your disk.** Cloud is optional and swappable. If Tack is abandoned in ten years the way Post-it's app was, your data is still readable with `unzip` and a JSON parser.

---

## 1. Baseline: what the Post-it® App does today

Taken from post-it.com/app and the official FAQ. This is the **parity floor** — v1.0 ships all of it unless explicitly marked.

| # | Post-it® capability | Detail |
|---|---|---|
| B1 | **Capture** | Photograph physical notes; app segments each note into a discrete digital object. Marketing claims up to 200 notes per capture; FAQ says ≥50 on all devices, camera-dependent, more notes = lower per-note resolution. |
| B2 | Capture assist | Hints overlay, viewfinder gridlines, minimum-distance enforcement (won't shoot if too far), manual tap to add missed notes from the original capture image. |
| B3 | Note geometry | All square Post-it shapes, 3 in and up; ≥1/8 in gap recommended; overlapping notes need manual assist. No panoramic photo import. |
| B4 | **Boards** | A board holds many captures; each capture lands as its own group. |
| B5 | Groups | Notes can be grouped, moved, re-grouped, merged across sessions. |
| B6 | Grid View | Board browser / library. |
| B7 | Board View | Freeform arrangement + snap-to-grid organize. |
| B8 | Note Editor | Type text, draw with markers (multiple marker colors), change note color independently of ink color, resize note. |
| B9 | Edit captured notes | Captured (photographic) notes are editable like digital ones. |
| B10 | **Handwriting transcription** | OCR handwriting on a note into editable text. |
| B11 | Combine boards | Merge multiple sessions/projects into one board. |
| B12 | **Export / share** | PowerPoint, Excel, PDF, Dropbox, Trello, Miro, Lucidspark, text message, save image to camera roll (per-note), `.postit` file export. |
| B13 | Sync | iCloud sync across iPhone/iPad/Mac; `.postit` documents live in a `Post-it` folder in iCloud Drive or On My iPhone. |
| B14 | Brainstorming Session | Invite others to contribute notes to your board during a workshop. |
| B15 | Widget | Static home-screen widget showing selected notes. |
| B16 | Store view | Commerce surface for buying physical pads. **Not replicated.** |
| B17 | Platform reach | iOS/iPadOS 13.4+, macOS 10.15+, Android 8+, ChromeOS. |

### 1.1 Known deficiencies of the baseline (the "what I'd change" list)

These drive the v1 differentiators in §3.

- **D1** Capture only understands *square* notes ≥3 in. No support for rectangular/lined/Super Sticky XL/arrow flags/tabs/index cards/whiteboard-drawn rectangles.
- **D2** Resolution collapses as note count rises; no multi-shot stitching or high-res re-capture of a single note.
- **D3** No panorama or multi-photo wall stitching — you either lose resolution or manually manage separate captures.
- **D4** Board is a *grid*, not an infinite canvas. No connectors, no frames/columns, no shapes, no freeform ink between notes.
- **D5** No search across boards. No tags, no colors-as-semantics, no filters, no saved views.
- **D6** No versioning, no undo history beyond session, no recovery of deleted boards.
- **D7** Widget is static and read-only.
- **D8** No Shortcuts/App Intents, no URL scheme, no CLI, no automation of any kind.
- **D9** Export is one-directional and lossy; nothing round-trips back in. No open format spec.
- **D10** Collaboration is a proprietary ad-hoc session, cloud-mediated, no offline peer mode, no presence, no comments.
- **D11** Android/Chromebook data has no backup path at all (per FAQ).
- **D12** No keyboard-first operation on Mac; the Mac app is a phone app's habits on a desktop.
- **D13** No accessibility story for note content (photographic notes are images to VoiceOver).
- **D14** No links between notes, no backlinks, no task semantics (due dates, assignees, checkboxes).
- **D15** No Apple Pencil pressure/tilt fidelity, no Scribble, no hover.

---

## 2. Product goals & non-goals

### 2.1 Goals
- **G1 Parity**: every B-row above (minus B16, B17-Android) works on day one.
- **G2 Local-first**: full functionality with the network off, forever, with no account.
- **G3 Open data**: format spec published, versioned, and independently implementable; a `tackkit` CLI proves it.
- **G4 OS-native**: feel like an Apple system app — widgets, intents, drag-and-drop, Quick Look, Spotlight, Handoff, Universal Clipboard, Stage Manager, multi-window.
- **G5 Escape velocity**: exporting to a competitor must be one command and must not degrade the work.
- **G6 Performance**: 10,000 notes on one canvas at 120 fps ProMotion on M-series; 2,000 notes at 60 fps on iPhone 13.

### 2.2 Non-goals (v1)
- Android / Web clients (see §14 roadmap — the format and sync protocol are designed so a third party *can* build them).
- Template marketplace, video calls, voting timers, "workshop facilitation suite" feature bloat.
- AI note-generation. AI is used only for *perception* (segmentation, OCR, cleanup) and *optional* clustering, all on-device.
- Enterprise SSO/SCIM. Self-hosted sync only.

### 2.3 Success metrics
| Metric | Target |
|---|---|
| Capture accuracy (well-lit wall, 40 square notes, 1/8 in gaps) | ≥98% notes correctly segmented, ≤1 false positive |
| Capture accuracy (mixed shapes, overlapping, angled 30°) | ≥90% |
| Handwriting OCR word accuracy (clear print, marker) | ≥92% |
| Time from launching app to first note on canvas | ≤3 s cold |
| Canvas frame time, 5k notes, M1 | ≤8.3 ms p95 |
| Round-trip fidelity `.tack` → Excalidraw → `.tack` | ≥95% of properties preserved |
| Cold sync of 500-note board over CloudKit | ≤10 s |

---

## 3. Differentiators (the "better than the paid alternatives" bets)

| ID | Bet | Why it wins |
|---|---|---|
| X1 | **Any-shape capture.** Segmentation trained/tuned for squares, rectangles, XL, lined, tabs, flags, index cards, and hand-drawn whiteboard boxes. Per-note re-shoot at full sensor resolution. | Kills D1/D2. Nobody else does the paper→digital step well. |
| X2 | **Wall stitching.** Sweep-capture multiple overlapping frames; homography-stitch into one high-res composite before segmentation. Notes keep true relative positions. | Kills D3. Captures a whole 12-ft wall at readable resolution. |
| X3 | **Infinite canvas + frames + connectors + ink**, GPU-rendered. | Kills D4. Turns the parity floor into an actual whiteboard. |
| X4 | **Everything is searchable text.** OCR runs on every captured note at import; text is stored alongside the pixels, indexed in Spotlight + in-app full-text search with filters (color, tag, board, date, author, has-task). | Kills D5/D13 at once — searchable *and* accessible. |
| X5 | **Interactive widgets everywhere.** Add a note, check off a task, cycle boards, all from the widget. macOS desktop + Notification Center, iOS home/lock/StandBy, Control Center control, Live Activity for active brainstorm sessions. | Kills D7. This is the single most-requested Post-it feature. |
| X6 | **Automation surface.** 20+ App Intents, Shortcuts actions, `tack://` URL scheme, AppleScript/JXA dictionary on macOS, and a `tackkit` CLI (SwiftPM executable) for CI/scripting. | Kills D8. |
| X7 | **Bidirectional interop.** Importers *and* exporters. `.postit` legacy import at launch. | Kills D9/D11. |
| X8 | **Peer-to-peer offline collaboration** over Multipeer Connectivity + CRDT, plus optional relay. A room full of people on airplane-mode Wi-Fi can co-edit. | Kills D10. Miro cannot do this. |
| X9 | **Keyboard-first Mac app.** Command palette (⌘K), vim-ish canvas navigation option, every action bindable, full menu bar, multi-window, tabs. | Kills D12. |
| X10 | **Time travel.** Append-only op log → scrub board history, restore deleted notes, diff two points in time. | Kills D6. |
| X11 | **Note semantics.** Optional checkbox/task state, due date, assignee, tags, and typed links between notes (renders as connector). Tasks surface in widgets and Reminders (opt-in two-way). | Kills D14. |
| X12 | **Pencil fidelity.** PencilKit with pressure/tilt/azimuth, Scribble, double-tap/squeeze tool switching, hover preview on iPad Pro M-series. | Kills D15. |

---

## 4. System architecture

### 4.1 Module map (SwiftPM, one workspace, multi-target)

```
Tack/
├── Packages/
│   ├── TackCore/            # Domain model, CRDT, op log, command bus. No UI. No Apple UI frameworks.
│   ├── TackFormat/          # .tack read/write, schema versioning, migration. Apache-2.0.
│   ├── TackCapture/         # Vision/CoreImage pipeline: detect → rectify → segment → OCR → color-classify
│   ├── TackCanvas/          # Renderer: Metal + SwiftUI Canvas fallback, hit-testing, spatial index
│   ├── TackSync/            # CloudKit engine, Multipeer engine, optional WebSocket relay client
│   ├── TackInterop/         # Importers/exporters (postit, excalidraw, miro, figjam, trello, md, csv, pptx, pdf, opml, tldraw, obsidian)
│   ├── TackIntents/         # App Intents definitions shared by app + widgets + Shortcuts
│   ├── TackUI/              # Shared SwiftUI components, design tokens, theming
│   └── TackTestKit/         # Golden fixtures, synthetic board generator, snapshot helpers
├── Apps/
│   ├── Tack-iOS/            # iOS + iPadOS
│   ├── Tack-macOS/          # Mac (native AppKit-hosted SwiftUI, not Catalyst)
│   └── Tack-visionOS/       # stretch
├── Extensions/
│   ├── TackWidgets/         # WidgetKit (all platforms)
│   ├── TackControls/        # Control Center / Lock Screen controls (iOS 18 ControlWidget)
│   ├── TackShareExt/        # Share sheet target: images, text, URLs → note
│   ├── TackQuickLook/       # .tack thumbnails + previews in Finder/Files
│   └── TackSpotlight/       # CSSearchableIndex delegate
├── Tools/
│   └── tackkit/             # CLI: convert, validate, merge, ocr, render, diff
└── Docs/
    ├── FORMAT.md  SYNC.md  INTENTS.md  CONTRIBUTING.md  ADR/
```

**Rule:** `TackCore` and `TackFormat` must compile on Linux (Foundation-only) so `tackkit` and any future server run headless. Enforced in CI.

### 4.2 Layering

```
        ┌───────────────────────────────────────────┐
        │ Views (SwiftUI) · Widgets · Intents · CLI │
        └───────────────┬───────────────────────────┘
                        │ commands / queries
        ┌───────────────▼───────────────────────────┐
        │ CommandBus  — validates, wraps in ops,    │
        │ pushes to op log, emits undo entries      │
        └───────────────┬───────────────────────────┘
        ┌───────────────▼───────────────────────────┐
        │ DocumentActor (Swift actor, per board)    │
        │  · CRDT state  · derived indices          │
        └──────┬─────────────────────┬──────────────┘
               │                     │
     ┌─────────▼────────┐   ┌────────▼─────────┐
     │ Persistence      │   │ SyncEngines      │
     │ (.tack bundle,   │   │ CloudKit / MPC / │
     │  SQLite index)   │   │ relay            │
     └──────────────────┘   └──────────────────┘
```

- One `DocumentActor` per open board. All mutations funnel through it. Swift 6 strict concurrency; model types are `Sendable` value types.
- UI observes via `@Observable` projections; the canvas subscribes to a dirty-rect stream, not to whole-model diffs.

### 4.3 Rendering

- **Primary:** custom Metal renderer. Notes are instanced quads; text and ink render to per-note textures cached in an LRU atlas (4096×4096 pages). Photographic notes are mip-mapped and streamed.
- **Culling:** R-tree spatial index over note AABBs; only visible + 1-screen-margin tiles drawn.
- **LOD:** ≥1.0 scale → full text/ink; 0.35–1.0 → cached raster; <0.35 → solid color chip with a 2-line text "gist" glyph run; <0.1 → color-only density map.
- **Fallback:** SwiftUI `Canvas` path for widgets, thumbnails, visionOS, and any device where Metal init fails. Must produce pixel-comparable output (snapshot-tested).
- Ink is stored as PencilKit `PKDrawing` **and** as a normalized stroke list in the format (so non-Apple readers can render it).

---

## 5. Data model

### 5.1 Entities

```swift
struct Board: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    var created: Date
    var modified: Date
    var canvas: CanvasSettings        // background, grid, units, infinite bounds
    var items: [ItemID: Item]         // notes, frames, connectors, shapes, ink, media, text
    var groups: [Group]               // legacy-compatible grouping (B5), incl. capture provenance
    var captures: [Capture]           // source photos + segmentation metadata
    var tags: [Tag]
    var views: [SavedView]            // named camera + filter states
    var comments: [Comment]
    var schemaVersion: SemVer
}

enum Item: Codable, Sendable {
    case note(Note)
    case frame(Frame)           // named region; acts as column/swimlane; can auto-layout children
    case connector(Connector)   // typed edge between two anchors, with label + routing
    case shape(Shape)           // rect/ellipse/diamond/arrow/line
    case ink(InkItem)
    case media(MediaItem)       // image, PDF page, file link
    case text(TextItem)         // canvas-level text, not a sticky
}

struct Note: Codable, Sendable {
    let id: ItemID
    var frame: Rect             // position + size in canvas points
    var rotation: Angle         // captured notes keep real-world tilt
    var z: FractionalIndex
    var stock: NoteStock        // physical archetype: square3, square3Lined, rect4x6, xl, tab, flag, indexCard, custom
    var paper: PaperStyle       // fill color (P3), lined/plain, edge treatment, shadow, curl
    var content: NoteContent
    var text: RichText?         // authoritative text (typed OR transcribed)
    var transcription: Transcription?   // OCR result + confidence + engine + accepted/pending
    var task: TaskState?        // isTask, done, due, assignee, priority   (X11)
    var tagIDs: [TagID]
    var links: [NoteLink]       // typed relations to other items/URLs/files
    var provenance: Provenance? // captureID, cropRect in source image, homography, timestamp, device
    var accessibilityLabel: String?     // auto-filled from text/OCR
}

enum NoteContent: Codable, Sendable {
    case digital(text: RichText?, drawing: InkData?)
    case captured(image: AssetRef, cleaned: AssetRef?, drawing: InkData?, text: RichText?)
    case hybrid(base: AssetRef, overlays: [Overlay])
}
```

Key decisions:
- **Captured notes are never "just images."** Every captured note carries OCR text, a detected paper color, and an editable ink layer on top (satisfies B9 and X4).
- **Rotation is preserved** from the wall. Optional "straighten all" command.
- **z-order uses fractional indexing** (LSEQ-style strings) so concurrent reorders never conflict.
- **Groups (B5) survive** as a first-class concept *and* map onto Frames when the user wants layout behavior. Every Capture auto-creates a Group (B4 parity).

### 5.2 CRDT design

- Document = **op-based CRDT** over an append-only log. Each op: `{opID: (lamport, actorID), parent: [opIDs], payload}`.
- Registers (position, size, color, text): **LWW with actor-ID tiebreak**, except:
  - **Text**: RGA/Yjs-style sequence CRDT per rich-text field (concurrent typing on the same note merges).
  - **Ink**: strokes are immutable, add-only set; erase = tombstone op referencing stroke IDs.
  - **z-order**: fractional index (no conflict possible).
  - **Set membership** (tags, group children): OR-Set.
- **Move semantics**: notes moved concurrently by two people → LWW; but a "move into frame" op is modeled as parent-change with a cycle check to avoid the classic tree-move anomaly (Kleppmann move-op algorithm).
- Compaction: log is snapshotted every N ops (default 2,000) or on close; history retained for time-travel (X10) with configurable retention (default: all ops, since a 10k-note board's log is ~single-digit MB).

### 5.3 Undo

Per-actor selective undo derived from the op log (invert op, append as new op). Undo stack is per *window*, not per document, on macOS. ⌘Z depth: unlimited within session, 500 ops persisted.

---

## 6. File format: `.tack`

**Spec lives in `Docs/FORMAT.md`, licensed Apache-2.0, versioned independently of the app.**

`.tack` is a **zip archive** (stored, not deflated, for the media dir) with a UTI `app.tack.board`, conforming to `public.composite-content`. Also usable as a macOS/iOS document package (`NSFileWrapper`) so iCloud Drive syncs it file-by-file rather than as a monolith.

```
Board Name.tack/
├── manifest.json          # schema version, app version, board id, counts, checksums
├── board.json             # full materialized state (human-readable, stable key order, pretty-printed)
├── ops/
│   ├── 000001.oplog       # binary-framed CBOR op batches (append-only)
│   └── snapshot-000042.json
├── media/
│   ├── captures/<uuid>.heic        # original capture photos (optional, user can strip)
│   ├── notes/<uuid>.png            # per-note rectified crops
│   └── attachments/…
├── ink/<uuid>.pkdrawing            # Apple ink blobs (optional; strokes also in board.json)
├── thumbnail.png                   # 1024px board preview for Quick Look / Grid View
└── LICENSE-DATA.txt                # user's own content; no rights claimed
```

Rules:
1. `board.json` alone must be sufficient to reconstruct a visually faithful board (media referenced by relative path, missing media renders as placeholder).
2. Unknown keys must be **preserved on round-trip** by any conforming implementation (forward compatibility).
3. Schema is JSON Schema + a generated Swift `Codable` layer; both checked into the repo.
4. A `--flat` export writes a single `board.tack.json` with base64 media for pasteboard/gist use.

**Pasteboard**: dragging notes exports, in order of preference: `app.tack.items` (JSON), `public.png` (rendered), `public.utf8-plain-text` (bulleted text), `public.rtf`. Dropping the reverse. This makes Tack a good citizen with every other app on the system.

**Legacy `.postit` import (P0)**: reverse-engineer the bundle (it is a document package containing images + a plist/JSON manifest). Importer must: preserve board name, note positions, groups (one per capture), note colors, note images, and any transcribed text. Ship a `tackkit convert legacy.postit out.tack` path so users can bulk-migrate from a folder without opening the app. Include a **"Rescue my Post-it boards"** first-run flow that scans iCloud Drive/`On My iPhone` for the `Post-it` folder (documented in the Post-it FAQ) and offers bulk import.

---

## 7. Capture pipeline (`TackCapture`)

This is the hardest and most differentiating subsystem. It must beat 3M's, not match it.

### 7.1 Stages

```
[AVCapture / PhotoPicker / Continuity Camera / drag-drop file]
   → 0. Source normalization (HEIC/JPEG/RAW/PDF page/panorama-allowed)
   → 1. Scene rectification      (VNDetectRectangles + perspective homography, or ARKit plane if available)
   → 2. Multi-frame stitching    (optional; feature match + bundle adjust)  [X2]
   → 3. Illumination flattening  (CoreImage: divide-by-blur, white balance to paper white)
   → 4. Note segmentation        (see 7.2)
   → 5. Per-note rectify + crop  (rotate to upright, keep original angle in metadata)
   → 6. Paper color classification (quantize to known stock palette + free color)
   → 7. Stock classification     (square3 / rect / XL / tab / flag / lined / index card)
   → 8. Content extraction       (ink/text separation, background removal → clean transparent PNG)
   → 9. OCR                      (VNRecognizeTextRequest .accurate, custom words, handwriting)
   → 10. Emit Notes + Group + Capture record
```

### 7.2 Segmentation strategy (layered, fail-soft)

1. **Classical first** (fast, explainable, no model download):
   - Convert to Lab, compute chroma saliency (sticky notes are saturated against neutral walls).
   - Adaptive threshold + morphological open/close → contours.
   - Filter contours by: area within [minNoteArea, 0.4 × frame], aspect ratio in known stock ratios ±12%, convexity ≥0.9, quadrilateral fit residual below tolerance.
   - Merge/split heuristics for touching notes: watershed on distance transform when two quads share an edge.
2. **Learned refinement** (bundled Core ML, ~8 MB, quantized):
   - A small instance-segmentation model (YOLO-seg or U-Net + connected components) trained on synthetic + community-donated wall photos. Runs on Neural Engine. Used to (a) recover notes classical missed, (b) split overlaps (D1/B3 gap), (c) reject false positives (posters, laptops, hands).
   - Ensemble: union of classical + learned proposals, NMS with IoU 0.4, confidence-weighted.
3. **Human-in-the-loop** (parity with B2 "add a missed note", but better):
   - Capture Preview shows every proposal with a checkmark; tap to toggle.
   - **Tap anywhere on the photo** to add a note: the app flood-fills from that point and snaps to the nearest quad; drag handles to adjust.
   - **Lasso** for irregular content.
   - Rejected/added proposals feed an **opt-in, local-only** correction store; users may export corrections as an anonymized training contribution (explicit consent, no images uploaded without review).

### 7.3 Capture UX requirements

- Live viewfinder overlay draws detected quads in real time at ≥15 fps (downsampled 640px pipeline) with a running count: *"37 notes detected."*
- **Quality gates with guidance, never a hard block** (fixes the "why can't I take a photo" FAQ frustration): if too far / too dark / too much motion blur / too oblique, show the hint *and* let the user shoot anyway with a warning badge.
- Gridlines and hints individually toggleable in Settings (B2 parity).
- **Sweep mode (X2)**: guided pan; app captures frames on overlap thresholds, shows a stitch progress ribbon, then segments the composite.
- **Re-shoot single note**: from any captured note, "Retake" opens a tight viewfinder; the new high-res crop replaces the pixels while keeping ID, position, text, tags (fixes D2).
- Import from Photos, Files, Continuity Camera, scanner, AirDrop, Share Extension, and **panorama images are allowed** (explicitly fixing a Post-it limitation).
- Batch: process a folder of 50 photos into one board, each photo = one Group.
- All processing on-device. No image leaves the device. Stated in-app and in the README.

### 7.4 OCR / transcription (B10, X4)

- `VNRecognizeTextRequest`, `.accurate`, `automaticallyDetectsLanguage`, plus per-board custom vocabulary (project nouns, names) built from existing board text.
- Handwriting: Vision's handwriting support, plus a preprocessing pass (stroke thinning, deskew per text line).
- Result stored with **per-line confidence**. UI shows low-confidence words with a dotted underline; tap to fix. "Accept all transcriptions" bulk action.
- Transcription is **additive**: the photo stays; text becomes searchable, accessible, and exportable. User can switch a note to "text-only view" which re-renders the note as a digital sticky with the transcribed text in a handwriting-ish or clean face.
- Runs in background on a `TaskGroup` with QoS `.utility`; board is usable immediately, text fills in.

---

## 8. Board & canvas features

### 8.1 Parity-level (B4–B9, B11)
- Grid View library with board thumbnails, folders, sort (modified/created/name/size), search, favorites, recently deleted (30-day).
- Board View: freeform drag, multi-select (marquee, shift-click, ⌘A), align/distribute, snap to grid & to other notes, "Organize" (tidy into grid, preserving group adjacency), resize notes with aspect-lock for known stocks.
- Note editor: type (rich text: bold/italic/underline/strike, 3 sizes, alignment, bullets/numbering, checkboxes), draw (marker/pen/highlighter/eraser, ≥12 ink colors + custom), note color independent of ink color, full stock palette + custom P3 colors.
- Combine boards: `Board ▸ Merge…` picks N boards, offers layout strategy (side-by-side frames / interleave / keep groups).

### 8.2 Beyond-parity (X3, X10, X11)
- **Infinite canvas**, zoom 2%–6400%, momentum pan, pinch/trackpad/Pencil/scroll-wheel, zoom-to-fit, zoom-to-selection, minimap.
- **Frames**: named rectangles that own their children. Modes: *free*, *stack* (auto-column), *grid*, *kanban* (children get a status = frame name). Frames are the export unit for PPTX slides and Trello lists.
- **Connectors**: elbow/curved/straight, arrowheads, labels, typed (`blocks`, `relates`, `causes`, custom). Auto-route around obstacles; re-route on move.
- **Shapes & text** for structure: rect, ellipse, diamond, line, arrow, freeform text.
- **Ink on canvas** (not just in notes), infinite, PencilKit-backed.
- **Clustering assist** (on-device, optional): embed note text with a small sentence model, k-means/HDBSCAN, propose groupings the user can accept/reject. Never auto-applies.
- **Filters & saved views**: filter by tag/color/author/task-state/date; matching notes highlight, others dim. Save camera+filter as a named view; views are shareable and exportable as PDF pages.
- **Comments & mentions** anchored to items or canvas points; resolve/unresolve; badge counts.
- **History scrubber**: timeline at the bottom; drag to any point; "Restore this version" forks or overwrites. Diff mode highlights added/moved/deleted since a chosen point.
- **Presentation mode**: ordered frame sequence, arrow-key advance, laser pointer, presenter display on Mac, AirPlay-friendly.
- **Templates as plain `.tack` files** in a user folder — retro, 2×2, story map, empathy map, sprint board. No marketplace, no accounts.

### 8.3 Mac-specific (X9, D12)
- True multi-window, tabs, Stage Manager–correct sizing, full menu bar with every command, customizable toolbar.
- **Command palette ⌘K** (fuzzy actions, boards, notes, tags).
- Complete keyboard model: `N` new note, `Tab` new sibling, `Return` edit, arrows to move by 1pt / ⇧arrows by grid, `G` group, `F` frame, `C` connector, `/` search, `1–9` note colors, space-drag pan, `Z` zoom-fit.
- Inspector sidebar (⌥⌘I): geometry, color, stock, tags, task, links, provenance, transcription.
- Services menu entry: "New Tack Note from Selection." AppleScript/JXA dictionary. `tack://` URLs everywhere.
- Drag notes out to Finder (creates PNG or `.tack` fragment), drag files in.

---

## 9. Widgets, controls, and OS surfaces (X5 — the flagship requirement)

### 9.1 Shared foundations
- Widgets read through an **App Group** container holding a small, denormalized SQLite "widget mirror" (board summaries, pinned notes, task list), refreshed on document save and on sync merge. Widgets never open a full `.tack` bundle — memory budget is 30 MB on iOS and hard-enforced.
- All widget interactivity uses **App Intents** (`AppIntentTimelineProvider`, `Button(intent:)`, `Toggle(isOn:intent:)`), so the same intents power Shortcuts, Siri, and the CLI. No URL-scheme hacks.
- Rendering uses the SwiftUI fallback renderer (§4.3) so widget output is consistent with the canvas.

### 9.2 macOS
| Surface | Behavior |
|---|---|
| **Desktop widgets** (macOS Sonoma+ on-desktop placement) | Small/Medium/Large/Extra-Large. Extra-Large = a live mini-board: up to 24 notes in true relative layout, tinted correctly, respecting desktop-tint/monochrome modes (must look right when the desktop-tinting effect kicks in — test both). |
| **Notification Center widgets** | Same family; the "Quick Notes" widget with an **Add Note** button, and a **Today's Tasks** widget with working checkboxes. |
| **Menu bar extra** | `NSStatusItem` popover: type a note, ⌘↩ to file it to the default board, recent boards list, capture-from-Continuity-Camera button. Global hotkey (default ⌃⌥Space), user-remappable. |
| **Dock** | Badge = open tasks (opt-in). Dock menu = recent boards + New Note. |
| **Quick Look** | `.tack` previews render the board thumbnail + note count + first N notes; spacebar in Finder just works. |
| **Spotlight** | Every note indexed with `CSSearchableItem` (title = first line, description = text, thumbnail). Opening a result deep-links to the note and flies the camera to it. |
| **Stage Manager / Mission Control / Spaces** | Correct window restoration per board. |

### 9.3 iOS / iPadOS
| Surface | Behavior |
|---|---|
| **Home Screen widgets** | systemSmall (one pinned note or next 3 tasks), systemMedium (board strip + Add button), systemLarge (mini-board, 12–18 notes), and iPad systemExtraLarge (mini-board, up to 30). Interactive: check a task, cycle to next board, add note (opens compose sheet via intent → app), pin/unpin. |
| **Lock Screen widgets** | `accessoryCircular` (open task count), `accessoryRectangular` (top pinned note text), `accessoryInline` (next due task). |
| **StandBy** | Large-format pinned-note display with dimmed night mode; ideal "wall of one note" use. |
| **Control Center controls** (iOS 18 `ControlWidget`) | *New Note*, *Capture Notes* (opens camera straight into capture), *Toggle focus board*. Also assignable to the Action Button and the Lock Screen shortcut slots. |
| **Live Activity** | During a Brainstorming Session: participant count, notes added, time elapsed; Dynamic Island compact = live note counter. |
| **Widget configuration** | `AppIntentConfiguration` — pick board, pick filter (tag/color/tasks), pick density, pick theme. |
| **Interactive refresh** | Timeline reload on document change via `WidgetCenter.shared.reloadTimelines(ofKind:)` from the sync engine and the save pipeline; plus a 15-min cadence floor for time-based content. |
| **Handoff / Universal Clipboard** | Continue a board Mac↔iPad↔iPhone with camera position preserved. |
| **Apple Watch** (stretch) | Complication with pinned note + dictate-a-note. |

### 9.4 Widget acceptance criteria (must pass to ship)
- W1 Adding a note from any widget lands in the target board within 2 s and reflects in the widget within 1 s (or optimistically, immediately).
- W2 Widgets render correctly in Light, Dark, tinted, and monochrome modes; no unreadable text on any note color (auto contrast-adjust text per WCAG 4.5:1 against the note fill).
- W3 Widget memory peak < 28 MB with a 30-note extra-large layout.
- W4 No widget ever shows stale data after a foreground app edit — verified by UI test on device.
- W5 All widget actions are also available as Shortcuts actions with identical parameters (shared intent definitions).

---

## 10. Sync, sharing, collaboration

### 10.1 Tiers (all optional, user picks; default = local files only)
| Tier | Transport | Use |
|---|---|---|
| **T0 Local** | Filesystem | Default. Boards in `~/Documents/Tack` or any folder the user picks (security-scoped bookmarks). |
| **T1 iCloud** | CloudKit private DB + iCloud Drive documents | B13 parity. Ops sync via CKRecords (op batches as CKAssets ≤1 MB), media as CKAssets with lazy download. Conflict-free by construction (CRDT). |
| **T2 Peer** (X8) | Multipeer Connectivity (Bonjour + AWDL) / Network.framework `NWListener` over local Wi-Fi | Offline room collaboration. Host advertises a session; peers join via 6-digit code or QR; ops gossip peer-to-peer; encrypted with a session key derived from the code (SPAKE2). Works with zero internet. |
| **T3 Shared** | CloudKit Sharing (`CKShare`) | Invite by iCloud identity, read/write or read-only links. |
| **T4 Self-host** | `tack-relay`, a ~500-line WebSocket op-relay (Swift on Linux, Docker image, also runnable as a Cloudflare Worker) | For teams that want cross-platform/non-Apple participants later. Relay is dumb: it stores and forwards encrypted op batches, no content access. E2E encryption with per-board key shared out-of-band. |

Protocol documented in `Docs/SYNC.md` (Apache-2.0): op batch framing, causal delivery via version vectors, snapshot negotiation, media transfer, presence heartbeats.

### 10.2 Brainstorming Session (B14, upgraded)
- Host starts a session → QR code + 6-digit code on screen (and on the presentation display).
- Participants join **with or without an account**; a guest can join in read-write for the session lifetime.
- Guests get a simplified "contribute" UI: type/draw/capture → note flies onto the host's board into a per-participant Group.
- Host controls: lock canvas, approve-before-post mode, anonymous mode, timer, dot-voting, "close session" (converts guests to read-only and bakes contributions).
- Presence: cursors with names/colors, follow-me mode, viewport-of-others indicators.
- Everything works entirely over T2 with no internet.

---

## 11. Interoperability (X7) — the escape-hatch contract

### 11.1 Import
| Source | Fidelity target |
|---|---|
| `.postit` (legacy, **P0**) | Boards, notes, images, positions, groups, colors, names, transcriptions |
| Images / PDF / panorama | Via capture pipeline |
| Excalidraw `.excalidraw` | Elements → notes/shapes/connectors/text; near-lossless |
| tldraw `.tldr` | Shapes/notes/arrows/frames |
| Obsidian Canvas `.canvas` | Cards → notes, edges → connectors, embeds → media |
| Miro | Board JSON via REST API (OAuth) — stickies, frames, connectors, images, text |
| FigJam | Via `.fig`-adjacent REST read where available, else clipboard bridge + PNG+CSV pair |
| Trello | JSON export or API: lists → frames, cards → notes, labels → tags, checklists → tasks |
| Lucidspark | Standard export (JSON/CSV) → notes+frames |
| Markdown / OPML / CSV / plain text | Bullets → notes; heading hierarchy → frames; front-matter → tags |
| Reminders / Things / Todoist CSV | Tasks → task-notes |

### 11.2 Export
| Target | Notes |
|---|---|
| `.tack` | Canonical |
| **Excalidraw** | *Recommended lossless-ish open target.* Notes → rectangles w/ text + custom `customData.tack` blob preserving IDs/tags/task so it round-trips back |
| tldraw, Obsidian Canvas | Same custom-data strategy |
| **Miro** | REST API: create board, batch-create `sticky_note`, `frame`, `connector`, `image` items; preserve color mapping; return the board URL |
| **FigJam** | Via clipboard payload (FigJam accepts pasted structured content) + a fallback "PNG + CSV of note text/positions" pair; documented limitations |
| **Lucidspark** | Their import format / API |
| **Trello** | Frames → lists, notes → cards, tags → labels, task state → due/complete, images attached |
| Linear / Jira / GitHub Issues | Selected notes → issues, one-way, with a link written back onto the note (X11 links) |
| **PPTX** | One slide per frame (or one per group), notes rendered as native PowerPoint shapes with real text (not flat images) so they stay editable; images embedded for captured notes |
| **XLSX / CSV** | One row per note: text, color, stock, tags, group/frame, x, y, w, h, task, due, assignee, capture id, created, modified, author |
| **PDF** | Vector, whole board or per-view/per-frame pages; text is selectable (uses transcription); optional appendix listing all note text |
| **Markdown** | Frames → `##`, groups → `###`, notes → bullets, tasks → `- [ ]`; images to a sibling folder; YAML front-matter with board metadata |
| **OPML** | For outliners/mind-mappers |
| **PNG / SVG** | Whole board, selection, or per note, @1x–@4x, transparent or paper background |
| **Reminders / Calendar** | Task-notes → EventKit (opt-in, two-way for completion) |
| Dropbox / Google Drive / any Files provider | Via `UIDocumentPicker`/Files — no bespoke SDKs, no vendor lock |
| iMessage / Share Sheet | B12 parity: share board or note as image/text/`.tack` |

### 11.3 The `tackkit` CLI (X6)
```
tackkit convert in.postit out.tack
tackkit convert board.tack --to excalidraw --out board.excalidraw
tackkit ocr board.tack --language en --accept-above 0.85
tackkit render board.tack --png --scale 2 --out board@2x.png
tackkit merge a.tack b.tack --layout side-by-side --out combined.tack
tackkit diff v1.tack v2.tack --format json
tackkit validate board.tack           # schema conformance; exit 1 on failure
tackkit new --from-markdown plan.md --out plan.tack
```
Runs on macOS and Linux. Used in the repo's own CI to validate every fixture on every commit. This is the proof that the format is genuinely open.

---

## 12. Non-functional requirements

### 12.1 Performance budgets
| Scenario | Budget |
|---|---|
| Cold launch to interactive (Mac, M1) | ≤1.2 s |
| Open 5,000-note board | ≤2.0 s to first frame, ≤4 s fully streamed |
| Pan/zoom frame time, 5k notes | p95 ≤8.3 ms (120 Hz), p99 ≤16 ms |
| Note drag latency (Pencil, iPad Pro) | ≤20 ms photon-to-photon |
| Capture: 40-note photo → notes on board | ≤4 s on A17/M1, ≤8 s on A14 |
| OCR: 40 notes background | ≤15 s, non-blocking |
| Memory, 5k-note board | ≤900 MB Mac, ≤450 MB iPhone (LOD/texture eviction enforced) |
| `.tack` save (incremental) | ≤80 ms, off main thread, atomic |
| Widget timeline build | ≤400 ms |

### 12.2 Accessibility (D13 fixed)
- Every note exposes an accessibility element with label = typed text or transcription, value = task state, traits, and custom actions (edit, move, delete, open).
- VoiceOver canvas navigation: spatial rotor (left-to-right/top-to-bottom), group rotor, "read all notes in frame."
- Full Dynamic Type in editors, sidebars, widgets; canvas text has an independent minimum-size floor and a "large text canvas" mode.
- Contrast: automatic text color per note fill (≥4.5:1); Increase Contrast adds note borders; Differentiate Without Color adds an optional pattern/icon per color category.
- Reduce Motion: no zoom-fly animations, cross-fade instead.
- Full Voice Control and Switch Control support; every action reachable without a pointer.
- Keyboard-only completeness on Mac and iPad (hardware keyboard).
- Localization-ready from day one (en at launch; strings catalogs, RTL layout verified, no baked-in text in art).

### 12.3 Privacy & security
- **Zero telemetry by default.** Optional, opt-in, aggregate-only crash reporting (self-hosted Sentry or none).
- No image, note text, or embedding leaves the device unless the user explicitly syncs/exports.
- CloudKit private DB only. E2E encryption for T4 relay (per-board symmetric key; key never touches the relay).
- Peer sessions: SPAKE2-derived key from the join code, TLS via Network.framework, code rotates each session.
- On-disk: honors FileVault/Data Protection (`.completeUnlessOpen`); optional per-board lock with Face ID/Touch ID.
- Sandboxed, hardened runtime, notarized. Entitlements minimized and documented in `Docs/ENTITLEMENTS.md`.
- Third-party API tokens (Miro/Trello/Lucid) in Keychain, revocable in Settings, scoped minimally.

### 12.4 Reliability
- Atomic writes with a write-ahead op log: a crash mid-edit loses at most the ops since the last flush (flush cadence ≤2 s or 20 ops).
- Corrupt bundle recovery: rebuild `board.json` from `ops/` + media; `tackkit validate --repair`.
- Recently Deleted (30 days) for boards and notes.
- Automatic local versioned backups (last 10 snapshots per board) in Application Support, prunable.

---

## 13. Quality plan

- **Unit**: `TackCore` CRDT properties (commutativity, idempotence, convergence) via SwiftCheck-style randomized op interleaving; 10k-op fuzz runs in CI.
- **Golden fixtures**: a corpus of ~120 wall photos (varied lighting, angles, stocks, densities, whiteboard-drawn boxes, hands in frame) with hand-labeled ground truth; CI reports precision/recall per commit and **fails on regression >1%**.
- **Snapshot tests** for Metal vs SwiftUI renderers (must match within perceptual threshold), for widgets in all size classes × color schemes, and for every exporter.
- **Round-trip tests**: `.tack` → each format → `.tack`, asserting a documented property-preservation ratio per target.
- **Performance tests** in CI on real hardware (self-hosted Mac runner) against §12.1 budgets; regressions fail the build.
- **Sync tests**: simulated 5-peer partition/heal matrices; a "chaos" test that randomly drops/dupes/reorders op batches.
- **Accessibility audit** each release: VoiceOver walkthrough script, Accessibility Inspector zero-warning, contrast checker over the full palette.
- **Device matrix**: iPhone SE3, iPhone 15, iPhone 17 Pro, iPad 10, iPad Pro M4, MacBook Air M1, Mac Studio, external display 5K, Sidecar.

---

## 14. Roadmap

| Milestone | Scope | Rough effort (1–2 devs) |
|---|---|---|
| **M0 Skeleton** | Repo, SwiftPM modules, CI, `TackFormat` v0 + JSON Schema, `tackkit validate`, empty apps | 3 weeks |
| **M1 Canvas** | Metal renderer, notes, drag/select/resize/color, local persistence, undo, Grid View | 6 weeks |
| **M2 Capture** | Full pipeline classical + human-in-loop, capture preview, groups, per-note re-shoot | 6 weeks |
| **M3 Editor & Ink** | Rich text, PencilKit, stocks/palette, OCR + transcription UI, search + Spotlight | 5 weeks |
| **M4 Interop** | `.postit` importer (+rescue flow), Markdown/CSV/PDF/PNG/PPTX/Excalidraw export, `tackkit convert` | 5 weeks |
| **M5 Widgets & Intents** | All §9 surfaces, App Intents, menu bar extra, Quick Look, Shortcuts | 5 weeks |
| **M6 Sync** | T0/T1/T3 (local, CloudKit, CKShare), conflict soak testing | 5 weeks |
| **M7 Whiteboard+** | Frames, connectors, shapes, canvas ink, filters/saved views, history scrubber, presentation mode | 7 weeks |
| **M8 Collaboration** | T2 peer sessions, Brainstorming Session, presence, comments, Live Activity | 6 weeks |
| **M9 Polish → 1.0** | Accessibility audit, localization, performance pass, docs, notarization, App Store + notarized DMG + Homebrew cask | 5 weeks |
| **Post-1.0** | ML segmentation model (X1 stage 2), Miro/Trello/Lucid live APIs, wall stitching (X2), visionOS, `tack-relay` self-host, watchOS, community Android/web via published spec | — |

**MVP definition (what makes it worth switching):** M1–M5. That is: capture, canvas, editor, `.postit` import, exports, and real widgets. Sync and the full whiteboard come next.

---

## 15. Open decisions to settle before M1

| # | Question | Options | Recommendation |
|---|---|---|---|
| Q1 | Renderer | Metal-only vs SwiftUI-only vs hybrid | **Hybrid** — Metal for canvas, SwiftUI for widgets/thumbnails |
| Q2 | Persistence store | Files-only vs SwiftData vs SQLite index over files | **Files (`.tack`) + SQLite derived index.** SwiftData's migration story is too rigid for an open format |
| Q3 | CRDT | Roll our own vs Automerge (Rust FFI) vs Yjs port | **Roll our own** in TackCore (keeps Linux/CLI build pure-Swift, avoids FFI in extensions); revisit if it stalls |
| Q4 | Mac app tech | AppKit-hosted SwiftUI vs Catalyst | **Native Mac** — Catalyst can't deliver X9 |
| Q5 | Distribution | Mac App Store vs direct DMG vs both | **Both** + Homebrew cask; MAS build drops nothing (all entitlements are sandbox-legal) |
| Q6 | License | MIT vs GPL vs AGPL | **AGPL-3.0 app / Apache-2.0 format+protocol** — keeps forks open, keeps the format universally adoptable |
| Q7 | Trademark | Name must not evoke Post-it® | **Tack** or similar; explicitly avoid "Post-it," "sticky-note yellow" as a brand identity, and the canary-yellow-plus-3M trade dress. Add a `NOTICE` disclaiming affiliation with 3M |
| Q8 | Minimum OS | 17 vs 18 | **18** — Control Center controls, latest WidgetKit interactivity, Swift 6 concurrency |

---

## 16. Legal note

Post-it® is a registered trademark of 3M. This project is unaffiliated with and unendorsed by 3M. Do not use the name, the trade dress, or 3M's canary-yellow-in-context branding in the app name, icon, or marketing. Describing compatibility ("imports `.postit` boards") is nominative fair use and is fine; implying endorsement is not. The legacy importer must be built by reading files the user already owns — no circumvention of any protection measure, and ship it as a user-initiated migration tool.

---

*End of specification. Companion documents to be written during M0: `Docs/FORMAT.md`, `Docs/SYNC.md`, `Docs/INTENTS.md`, `Docs/ADR/0001-crdt-choice.md`.*
