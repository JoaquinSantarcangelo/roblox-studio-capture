#!/usr/bin/swift
import CoreGraphics
import Foundation

// roblox-studio-capture
//
// Fixes a real, reproduced bug: MCP-based Roblox Studio automation (at least
// robloxstudio-mcp's capture_screenshot / capture_device_matrix, as of 2026) returns a
// SOLID MAGENTA image while a playtest is running, even though the live game is rendering
// correctly on screen the entire time. Confirmed live, side by side: capture_screenshot
// returned uniform magenta at the exact moment this tool's `shot` command captured the
// full, correct 3D render from the same window.
//
// This tool captures the real macOS window instead, via the low-level Window Server list
// (CGWindowListCopyWindowInfo) plus `/usr/sbin/screencapture -l<windowID>`, which reads a
// window's own compositor backing store directly. That sidesteps whatever is broken inside
// the MCP server, and — unlike `screencapture -R`, a screen-COORDINATE capture — it is also
// unaffected by which virtual desktop/Space the window currently lives on (a region capture
// will happily grab whatever else is actually on screen at those coordinates instead, which
// is its own easy way to silently capture the wrong thing).
//
// Needs macOS Screen Recording permission for whatever process invokes this (typically your
// terminal app) — NOT Accessibility, which an AppleScript/System-Events approach would need
// instead. Grant it once via System Settings > Privacy & Security > Screen Recording if a
// capture comes back black.
//
// Usage:
//   swift roblox_studio_capture.swift list [--pattern <substr>] [--json]
//   swift roblox_studio_capture.swift shot [--pattern <substr>] [--id <n>] [--output <path>] [--json]
//
// `list` enumerates on-screen windows whose OWNER name contains <substr> (case-insensitive;
// default "Roblox"), printing id/owner/title/size/area. Use this when more than one
// Roblox-owned window is open — e.g. Studio's own window plus a separate RobloxPlayer
// process from a multiplayer test — and pass the right one explicitly to `shot --id`.
//
// `shot` captures one window as a PNG: an explicit --id if given, otherwise the LARGEST (by
// area) window matching --pattern. In practice that is almost always the right guess, since
// toolbars, dialogs, and menu-bar extras are far smaller than an actual 3D viewport or
// Studio's own main window.

struct Win {
	let id: Int
	let owner: String
	let title: String
	let x: Int
	let y: Int
	let w: Int
	let h: Int
	var area: Int { w * h }
}

func listWindows(matching pattern: String) -> [Win] {
	let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
	guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: AnyObject]] else {
		return []
	}
	var out: [Win] = []
	for info in raw {
		let owner = (info[kCGWindowOwnerName as String] as? String) ?? ""
		guard pattern.isEmpty || owner.localizedCaseInsensitiveContains(pattern) else { continue }
		// Layer 0 is where normal application windows live; menu-bar extras, the dock, and
		// other system chrome sit on other layers and are never what anyone means by "the
		// Roblox window".
		let layer = (info[kCGWindowLayer as String] as? Int) ?? -1
		guard layer == 0 else { continue }
		let title = (info[kCGWindowName as String] as? String) ?? ""
		let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
		let w = Int(bounds["Width"] ?? 0)
		let h = Int(bounds["Height"] ?? 0)
		guard w > 0 && h > 0 else { continue } // skip degenerate/invisible windows
		let id = (info[kCGWindowNumber as String] as? Int) ?? -1
		out.append(Win(
			id: id, owner: owner, title: title,
			x: Int(bounds["X"] ?? 0), y: Int(bounds["Y"] ?? 0), w: w, h: h
		))
	}
	return out.sorted { $0.area > $1.area }
}

func jsonString(_ s: String) -> String {
	var out = "\""
	for ch in s.unicodeScalars {
		switch ch {
		case "\"": out += "\\\""
		case "\\": out += "\\\\"
		case "\n": out += "\\n"
		default:
			if ch.value < 0x20 {
				out += String(format: "\\u%04x", ch.value)
			} else {
				out.unicodeScalars.append(ch)
			}
		}
	}
	out += "\""
	return out
}

func printWinsHuman(_ wins: [Win]) {
	if wins.isEmpty {
		print("No matching windows found.")
		return
	}
	for w in wins {
		print("id=\(w.id)  area=\(w.area)  owner=\(w.owner)  title=\"\(w.title)\"  size=\(w.w)x\(w.h)  pos=\(w.x),\(w.y)")
	}
}

func printWinsJSON(_ wins: [Win]) {
	let items = wins.map { w -> String in
		"{\"id\":\(w.id),\"owner\":\(jsonString(w.owner)),\"title\":\(jsonString(w.title))," +
			"\"x\":\(w.x),\"y\":\(w.y),\"width\":\(w.w),\"height\":\(w.h),\"area\":\(w.area)}"
	}
	print("[\(items.joined(separator: ","))]")
}

func fail(_ code: Int32, _ message: String, json: Bool) -> Never {
	if json {
		print("{\"ok\":false,\"error\":\(jsonString(message))}")
	} else {
		FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
	}
	exit(code)
}

// --- argv parsing -----------------------------------------------------------------------

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
	print("""
	roblox-studio-capture — screenshots a Roblox window by its macOS window ID, bypassing
	MCP capture tools that return solid magenta during a playtest.

	Usage:
	  swift roblox_studio_capture.swift list [--pattern <substr>] [--json]
	  swift roblox_studio_capture.swift shot [--pattern <substr>] [--id <n>] [--output <path>] [--json]

	Defaults: --pattern "Roblox", --output a timestamped PNG under $TMPDIR.
	""")
	exit(0)
}
args.removeFirst()

var pattern = "Roblox"
var explicitId: Int? = nil
var outputPath: String? = nil
var asJSON = false

var i = 0
while i < args.count {
	switch args[i] {
	case "--pattern":
		i += 1
		guard i < args.count else { fail(64, "--pattern needs a value", json: asJSON) }
		pattern = args[i]
	case "--id":
		i += 1
		guard i < args.count, let v = Int(args[i]) else {
			fail(64, "--id needs a numeric value", json: asJSON)
		}
		explicitId = v
	case "--output":
		i += 1
		guard i < args.count else { fail(64, "--output needs a value", json: asJSON) }
		outputPath = args[i]
	case "--json":
		asJSON = true
	case "--help", "-h":
		print("See usage: run with no arguments.")
		exit(0)
	default:
		fail(64, "Unknown argument: \(args[i])", json: asJSON)
	}
	i += 1
}

switch command {
case "list":
	let wins = listWindows(matching: pattern)
	if asJSON {
		printWinsJSON(wins)
	} else {
		printWinsHuman(wins)
	}

case "shot":
	let candidates = listWindows(matching: pattern)
	let chosen: Win?
	if let wantedId = explicitId {
		chosen = candidates.first { $0.id == wantedId } ?? listWindows(matching: "").first { $0.id == wantedId }
	} else {
		chosen = candidates.first // listWindows() sorts by area, descending
	}
	guard let win = chosen else {
		let msg = explicitId != nil
			? "No on-screen window with id \(explicitId!)."
			: "No on-screen window matched pattern \(jsonString(pattern)). Run the 'list' command to see what's actually open."
		fail(1, msg, json: asJSON)
	}

	let path = outputPath ?? (NSTemporaryDirectory() + "roblox-capture-\(Int(Date().timeIntervalSince1970)).png")

	let proc = Process()
	proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
	proc.arguments = ["-x", "-t", "png", "-l\(win.id)", path]
	do {
		try proc.run()
		proc.waitUntilExit()
	} catch {
		fail(3, "Failed to launch screencapture: \(error)", json: asJSON)
	}
	guard proc.terminationStatus == 0 else {
		fail(
			3,
			"screencapture exited with status \(proc.terminationStatus). If the image comes back black, macOS Screen Recording permission is likely missing for this terminal — grant it in System Settings > Privacy & Security > Screen Recording and retry.",
			json: asJSON
		)
	}

	if asJSON {
		print(
			"{\"ok\":true,\"path\":\(jsonString(path)),\"window\":{\"id\":\(win.id),\"owner\":\(jsonString(win.owner)),\"title\":\(jsonString(win.title)),\"width\":\(win.w),\"height\":\(win.h)}}"
		)
	} else {
		print("Captured \(win.owner) — \"\(win.title)\" (\(win.w)x\(win.h)) -> \(path)")
	}

default:
	fail(64, "Unknown command \(jsonString(command)). Use 'list' or 'shot'.", json: asJSON)
}
