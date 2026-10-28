# Testing Tack

Automated checks run with:

```bash
swift test --enable-code-coverage
./scripts/build-app.sh
```

The optional full legacy regression test runs when `TACK_LEGACY_FIXTURE` points to an installed `.postit` archive. It checks that note crops and original capture photos load as required assets. The portable synthetic fixture is always included so CI tests import, text/layout preservation, and capture metadata without personal data.

For a local smoke test after the automated suite passes:

1. Open a blank board, create a note, double-click inside it, type text, and confirm autosave survives quitting and reopening.
2. Open two boards from the saved-board sidebar in separate windows. Confirm each window keeps its own board; reopening the same package focuses its existing window.
3. Edit a note and switch boards before the autosave delay expires. Confirm the old board saves before the switch; also test that a failed save keeps the current board open. Quit and relaunch to confirm the last board reopens.
4. Select text in a note and try font, size, bold, italic, and each visual color swatch. Confirm the selected note changes without changing neighboring notes.
5. Drag, zoom, and pan the board beyond the initial viewport. Create notes in separated areas and confirm the canvas does not impose a visible outer edge.
6. Pin two notes (ideally on different boards), add two Tack `Pinned Note` widgets, and on each use `right-click → Edit Widget → Note` to select a different pinned note. Confirm both appear in the note picker, the two widgets show different notes, edits update the correct widget, and switching boards doesn't change their selections. Repeat with a captured note and confirm its image also appears.
7. Import or capture a board, confirm OCR/images/groups appear, export Markdown and CSV, and open the exported files in another app.
8. Run `tackkit validate` on a copied `.tack` package and confirm it reports `missing_images=0`. Temporarily remove a referenced image from the copy and confirm validation fails clearly.

These checks are intentionally separate from the automated tests because widget placement, accessibility, visual editing, and App Group behavior require a real macOS session.
