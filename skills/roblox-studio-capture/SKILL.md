---
name: roblox-studio-capture
description: |
  Screenshots the real Roblox Studio or Roblox Player window on macOS by window ID, for
  when an MCP-based Roblox Studio automation tool's own capture command comes back solid
  magenta (or black, or otherwise wrong) during a playtest.
  Use when: capture_screenshot, capture_device_matrix, or any similar MCP tool returns a
  uniform-color image while a Roblox playtest is running, and you need to actually see
  what's on screen — a live 3D scene, a device-simulated viewport, in-game UI, anything
  rendered inside Roblox Studio or a Roblox Player window.
user-invocable: true
---

# roblox-studio-capture

## The problem this solves

At least one popular Roblox Studio MCP server (`robloxstudio-mcp`) has a real, reproducible
bug: its `capture_screenshot` and `capture_device_matrix` tools return a **solid magenta
image** while a playtest is active, even though the actual game is rendering completely
normally on screen the whole time. Confirmed side by side: `capture_screenshot` returned
uniform magenta at the exact moment a window-ID capture of the same window, same instant,
returned the full, correct 3D render — set, UI, everything.

Edit mode (no playtest running) is usually fine; it's specifically the Play/Test path that
breaks. If you hit this with a different MCP server or tool, the same fix likely still
applies — the workaround captures the operating system's own window content and has nothing
to do with any particular MCP implementation.

## The fix

Ask **macOS itself** for the window's pixels instead of trusting whatever the MCP server's
own capture path does internally. Two things make this robust rather than a fragile hack:

- It reads the window via its **window ID** (`CGWindowListCopyWindowInfo` +
  `screencapture -l<id>`), which asks the window server for that window's own compositor
  backing store directly — regardless of which app owns it, whether a playtest spawned a
  separate process, or whether the window is occluded by something else.
- It does **not** use a screen-coordinate region (`screencapture -R`) or AppleScript/System
  Events UI-scripting. A region capture grabs whatever is physically on screen at those
  coordinates on the CURRENTLY ACTIVE virtual desktop — if the Roblox window lives on a
  different Space, you silently capture the wrong app instead (this happened once while
  building this tool: a region capture caught the terminal instead of Roblox Studio, purely
  because Studio was on another Space). System Events/AppleScript window queries need macOS
  **Accessibility** permission, which is a bigger ask and a separate, easy-to-hit wall.
  Window-ID capture needs only **Screen Recording** permission, which most development
  machines already have granted to their terminal app.

## Usage

```bash
# See every on-screen window whose owner name contains "Roblox" (the default pattern):
swift bin/roblox_studio_capture.swift list

# Same, machine-readable:
swift bin/roblox_studio_capture.swift list --json

# Capture the largest matching window (almost always the right guess — toolbars and
# dialogs are far smaller than an actual viewport or Studio's own main window):
swift bin/roblox_studio_capture.swift shot --output /tmp/studio.png

# More than one Roblox-owned window open (e.g. Studio itself plus a separate RobloxPlayer
# process from a multiplayer test)? List first, then target one explicitly:
swift bin/roblox_studio_capture.swift list
swift bin/roblox_studio_capture.swift shot --id 15936 --output /tmp/client.png

# Machine-readable result (path + which window it picked):
swift bin/roblox_studio_capture.swift shot --json
```

No arguments needed for the common case: `shot` alone auto-picks the largest window whose
owner name contains "Roblox" and writes a timestamped PNG under `$TMPDIR`, printing the path.

## When an agent should use this

Reach for this the moment a Roblox Studio MCP screenshot/capture tool returns a suspicious,
perfectly uniform image (check a corner pixel, or downscale to 1×1 and read the average
colour) while a playtest is active. Run `shot`, then read the resulting PNG file directly —
it will show the actual rendered game.

## Troubleshooting

**Capture comes back solid black instead of magenta or real content.** This is macOS's own
"no permission" signal, not a bug in this tool. Grant Screen Recording permission to
whatever application actually runs your shell commands (Terminal, iTerm, your IDE's
integrated terminal, etc.) in **System Settings → Privacy & Security → Screen Recording**,
then retry — no restart needed for most terminals, though some require quitting and
reopening once after the permission is granted.

**"No matching windows found."** Roblox Studio (or Player) might not actually be running,
or its window title/owner doesn't contain "Roblox" for some reason. Run `list --pattern ""`
to see every on-screen window and adjust `--pattern` accordingly.

**Multiple windows match and the wrong one gets picked.** Use `list` to see all candidates
with their window IDs and sizes, then pass the right one explicitly via `shot --id <n>`.
