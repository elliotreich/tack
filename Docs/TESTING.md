# Testing Tack

Automated checks run with:

```bash
swift test --enable-code-coverage
./scripts/build-app.sh
```

The optional full legacy regression test runs when `TACK_LEGACY_FIXTURE` points to the installed `.postit` archive. The portable fixture is always included so CI tests the importer without personal data.

For a local smoke test after the automated suite passes:

1. Open a blank board, create a note, double-click inside it, type text, and confirm autosave survives quitting and reopening.
2. Select text in the note and try font, size, bold, italic, and each visual color swatch. Confirm the selected note changes without changing neighboring notes.
3. Drag, zoom, and pan the board beyond the initial viewport. Create notes in separated areas and confirm the canvas does not impose a visible outer edge.
4. Select a note, choose `Pin to desktop widget`, add Tack's `Pinned Note` widget from the macOS widget gallery, then edit the note and confirm the widget updates. Repeat with a captured note and confirm its image also appears in the widget.
5. Import or capture a board, confirm OCR/images/groups appear, export Markdown and CSV, and open the exported files in another app.
6. Run `tackkit validate` on a copied `.tack` package and confirm it reports `missing_images=0`. Temporarily remove a referenced image from the copy and confirm validation fails clearly.

These checks are intentionally separate from the automated tests because widget placement, accessibility, visual editing, and App Group behavior require a real macOS session.
