# Tack file format v0.1

The first Tack implementation uses the document-package form of the format: a directory whose name ends in `.tack`. It is deliberately readable with ordinary filesystem tools. A future archive writer may zip the same entries without changing `board.json`.

```text
Board.tack/
├── manifest.json
├── board.json
├── media/
│   ├── notes/<note-id>.jpg
│   └── captures/<legacy-capture-files>
└── ops/
```

`board.json` is authoritative for the materialized board. JSON is pretty-printed with stable sorted keys and ISO-8601 dates. Note coordinates are unbounded world coordinates; the app does not treat `canvas.width` and `canvas.height` as a hard edge. They remain layout/export hints for v0.1 and preserve compatibility with captured boards.

Unknown future keys are not currently re-emitted by the Swift decoder; this is an explicit v0.1 limitation to remove before publishing the format as a compatibility contract.

The legacy `.postit` importer preserves:

- board title;
- note text from the legacy sheet OCR field;
- note image crops;
- note color, size, position, rotation, and capture provenance;
- cluster/group names and membership;
- OCR confidence where present;
- optional original capture photos when `tackkit convert --retain-captures` is used.

No source archive is modified. Imported packages are newly created under the user's Tack folder.
