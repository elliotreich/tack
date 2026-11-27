# Tack for agents

Tack boards are plain `.tack` folders, so any program can read them. This page covers the supported ways for AI agents (Claude Code, Codex, any MCP client) to read **and change** them without fighting the running app.

## MCP server: `tackkit mcp`

`tackkit mcp` is a [Model Context Protocol](https://modelcontextprotocol.io) server over stdio. It works on the board packages directly: the Tack app does not have to be open, and when it is, the open window picks up the change within a moment and merges it with anything you were typing.

### Install

```bash
TACK_CLT_ONLY=1 swift build -c release --product tackkit   # TACK_CLT_ONLY only needed without full Xcode
mkdir -p ~/.local/bin
cp "$(TACK_CLT_ONLY=1 swift build -c release --show-bin-path)/tackkit" ~/.local/bin/
```

### Claude Code

```bash
claude mcp add --scope user tack -- ~/.local/bin/tackkit mcp
```

or in a `.mcp.json` / `--mcp-config` file:

```json
{
  "mcpServers": {
    "tack": {
      "command": "/Users/you/.local/bin/tackkit",
      "args": ["mcp"]
    }
  }
}
```

### Codex (`~/.codex/config.toml`)

```toml
[mcp_servers.tack]
command = "/Users/you/.local/bin/tackkit"
args = ["mcp"]
```

### Options

| Flag | Meaning |
|---|---|
| `--root DIR` | Folder of boards the server may see and change (default `~/Documents/Tack`, or `$TACK_ROOT`). Nothing outside it is touched. |
| `--board PATH` | Also allow one specific `.tack` package outside the root. Repeatable. |
| `--read-only` | Only the read tools are listed; nothing can be written. |

## Tools

Read (always available): `list_boards`, `get_board` (outline or full JSON), `search_notes`, `get_note` (includes the absolute path of a photographed note's image, so a vision model can read the handwriting), `export_board` (markdown/csv), `list_agent_changes`.

Write: `create_board`, `rename_board`, `create_notes` (batch; omit x/y and Tack finds free space next to the note's group, or a clear column for a new group), `update_note`, `move_notes`, `group_notes`, `delete_notes`, `capture_image` (on-device Vision detection + OCR of a photo of paper notes), `undo_agent_change`.

Boards can be named by id, title, title prefix, or package path. Colors are `yellow`, `blue`, `green`, `pink`, `white`, `lavender`, `orange`, or `#RRGGBB`. Each board is also an MCP resource (`tack://board/<id>`) whose content is the outline.

Every tool carries MCP annotations (`readOnlyHint`, `destructiveHint`, `idempotentHint`) so clients can auto-approve reads and ask before deletes.

## How concurrent editing stays safe

1. **One lock per board.** Every writer (the app's autosave, `tackkit mcp`, the CLI) takes an advisory `flock` on `/tmp/app.tack.locks/<hash>.lock` around its read-modify-write. The lock file is outside the package so iCloud never syncs it.
2. **Writers re-read before writing.** The MCP server always loads `board.json` fresh inside the lock, applies its change and writes atomically. The app remembers the board as it last saw it on disk; when it saves, it three-way merges (`TackBoardMerge`) with whatever is on disk now instead of overwriting it.
3. **The app watches its board.** A file-system watcher on the open package reloads `board.json` when another process changes it. With no unsaved edits the new board is shown as-is; with unsaved edits the two are merged.
4. **Merge rules.** Per note: a side that did not change it yields to the side that did; if both changed it, the newer `modifiedAt` wins; an edit beats a concurrent delete. Group membership and the pinned note are repaired afterwards.

## The agent journal

Each write through `tackkit mcp` appends one line to `ops/agent-journal.jsonl` inside the package: time, tool, a one-line summary, and the notes (and groups) before and after. `undo_agent_change` uses it to reverse the latest change, and refuses if you have since edited the same notes in the app. The journal keeps the last 500 entries.

## CLI equivalents

```bash
tackkit list
tackkit show "2025"            # outline; --json for the full board
tackkit search burner --in 2025
```

## Not yet

App Intents / Shortcuts actions, a `tack://` URL scheme, and a live "focus this note" channel into the running app are planned; see the pull request that added this page for the list.
