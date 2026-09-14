# roblox-studio-capture

A workaround for a real bug: MCP-based Roblox Studio automation (`robloxstudio-mcp`, and
possibly others) returns a **solid magenta screenshot** while a playtest is running — even
though the game is rendering completely normally on screen. Confirmed side by side: the
MCP's own `capture_screenshot` returned uniform magenta at the exact instant this tool's
`shot` command, capturing the same window, returned the full, correct 3D render.

If you're building a Roblox game with an AI coding agent (Claude Code or otherwise) through
an MCP server, and its screenshot tool goes solid-color the moment you start a playtest —
this is for you.

## Why it happens (best understanding so far)

Edit mode capture usually works fine; it's specifically the Play/Test path that breaks —
this points at the MCP server's internal capture mechanism rather than Roblox itself, since
the same window's content is visibly correct to a human, and to the OS, the whole time. If
you can confirm the exact root cause, please open an issue or a PR against the section below
— this repo would rather host one accurate paragraph than three guesses.

## The fix

Ask **macOS** for the window's actual pixels, bypassing the MCP server's capture path
entirely:

- Enumerate on-screen windows via the low-level Window Server list
  (`CGWindowListCopyWindowInfo`) to find the Roblox-owned window and its **window ID**.
- Capture that specific window with `screencapture -l<windowID>`, which reads its
  compositor backing store directly — regardless of which process owns it or whether
  it's occluded by something else.

Deliberately **not** used:
- `screencapture -R x,y,w,h` (a screen-*coordinate* region capture) — it grabs whatever is
  physically on screen at those coordinates on the *currently active* virtual desktop. If
  Roblox's window lives on a different Space, you silently capture the wrong app. This
  happened once while building this tool: a region capture caught a terminal window instead
  of Roblox Studio, purely because Studio was on another Space at the time.
- AppleScript / System Events window queries — they need macOS **Accessibility**
  permission, a bigger ask than necessary and an easy wall to hit (`osascript is not
  allowed assistive access`). Window-ID capture needs only **Screen Recording** permission,
  which most development machines already have granted to their terminal app.

## Requirements

- macOS (uses CoreGraphics/Quartz APIs specific to it).
- Swift (ships with Xcode Command Line Tools: `xcode-select --install` if `swift` isn't
  found).
- Screen Recording permission for whatever runs the command — System Settings → Privacy &
  Security → Screen Recording. If a capture comes back solid **black**, this is the reason;
  see Troubleshooting.

No other dependencies. It's a single Swift file that shells out to the `screencapture`
binary already on every Mac.

## Usage

Standalone, no Claude Code required:

```bash
# List every on-screen window whose owner name contains "Roblox" (the default pattern):
swift bin/roblox_studio_capture.swift list

# Machine-readable:
swift bin/roblox_studio_capture.swift list --json

# Capture the largest matching window (the common case — toolbars/dialogs are always
# smaller than an actual viewport or Studio's own main window):
swift bin/roblox_studio_capture.swift shot --output /tmp/studio.png

# More than one Roblox-owned window (e.g. Studio itself, plus a separate RobloxPlayer
# process from a multiplayer test)? List first, then target one explicitly:
swift bin/roblox_studio_capture.swift list
swift bin/roblox_studio_capture.swift shot --id 15936 --output /tmp/client.png

# Machine-readable capture result (path + which window got picked):
swift bin/roblox_studio_capture.swift shot --json
```

`shot` with no arguments auto-picks the largest on-screen window whose owner name contains
"Roblox" and writes a timestamped PNG under `$TMPDIR`, printing the path.

### As a Claude Code plugin

```
/plugin marketplace add JoaquinSantarcangelo/roblox-studio-capture
/plugin install roblox-studio-capture@roblox-studio-capture
```

This installs a skill (`skills/roblox-studio-capture/SKILL.md`) that Claude Code loads and
can invoke automatically the moment it notices an MCP screenshot tool returning a suspicious
uniform-color image during a Roblox playtest — no manual invocation needed once installed.

## Troubleshooting

**Solid black instead of magenta or real content.** macOS's own "permission denied" signal,
not a bug here. Grant Screen Recording permission to whatever application actually runs your
shell commands (Terminal, iTerm, your IDE's integrated terminal, etc.), then retry — most
terminals pick it up immediately; a few need a restart after granting.

**"No matching windows found."** Roblox Studio/Player might not be running, or its window
title/owner doesn't contain "Roblox". Run `list --pattern ""` to see every on-screen window
and adjust `--pattern`.

**The wrong window gets captured.** Run `list` to see every candidate with its window ID and
size, then pass the right one explicitly with `shot --id <n>`.

## Contributing

Issues and PRs welcome — especially a confirmed root cause for the underlying MCP bug, a
Windows/Linux equivalent (this is macOS-only today), or reports that this also fixes the
same symptom against other Roblox MCP servers.

## License

MIT — see [LICENSE](LICENSE).
