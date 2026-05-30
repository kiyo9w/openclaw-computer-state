import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

var activeArgs = CommandLine.arguments
var responseFD: Int32? = nil

struct JSON {
    static func sanitize(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, child) in dict {
                out[key] = sanitize(child)
            }
            return out
        }
        if let array = value as? [Any] {
            return array.map { sanitize($0) }
        }
        if let bool = value as? Bool {
            return bool
        }
        if let double = value as? Double {
            return double.isFinite ? double : 0
        }
        if let float = value as? Float {
            return float.isFinite ? float : 0
        }
        if let number = value as? NSNumber {
            let double = number.doubleValue
            if !double.isFinite {
                return 0
            }
            if floor(double) == double {
                return Int64(double)
            }
            return double
        }
        return value
    }

    static func print(_ value: [String: Any]) {
        let safeValue = sanitize(value)
        if let data = try? JSONSerialization.data(withJSONObject: safeValue, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            if let fd = responseFD {
                _ = text.withCString { write(fd, $0, strlen($0)) }
                _ = "\n".withCString { write(fd, $0, strlen($0)) }
            } else {
                Swift.print(text)
            }
        } else {
            Swift.print("{\"ok\":false,\"error\":\"json_encode_failed\"}")
        }
    }
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    JSON.print(["ok": false, "error": message])
    exit(code)
}

func argValue(_ name: String, default defaultValue: String? = nil) -> String? {
    let args = activeArgs
    guard let index = args.firstIndex(of: name), index + 1 < args.count else {
        return defaultValue
    }
    return args[index + 1]
}

func require(_ name: String) -> String {
    guard let value = argValue(name), !value.isEmpty else {
        fail("missing \(name)")
    }
    return value
}

func defaultScreenshotPath() -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let dir = "\(home)/OpenClawTools"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return "\(dir)/maccontrol-screenshot.png"
}

func screenshot() {
    let path = argValue("--out", default: defaultScreenshotPath())!
    var arguments = ["-x", path]
    if let windowId = argValue("--window-id") {
        arguments = ["-x", "-l", windowId, path]
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = arguments
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        fail("screencapture_launch_failed: \(error.localizedDescription)")
    }
    guard process.terminationStatus == 0 else {
        fail("screen_capture_failed_or_permission_denied")
    }
    guard let image = NSImage(contentsOfFile: path) else {
        fail("screen_capture_file_missing")
    }
    var payload: [String: Any] = ["ok": true, "path": path, "width": image.size.width, "height": image.size.height]
    if let windowId = argValue("--window-id") {
        payload["windowId"] = Int(windowId) ?? 0
    }
    JSON.print(payload)
}

func pointFromArgs() -> CGPoint {
    guard let x = Double(require("--x")), let y = Double(require("--y")) else {
        fail("invalid_coordinates")
    }
    return CGPoint(x: x, y: y)
}

func click() {
    let point = pointFromArgs()
    let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
    let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
    let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
    move?.post(tap: .cghidEventTap)
    usleep(60_000)
    down?.post(tap: .cghidEventTap)
    usleep(60_000)
    up?.post(tap: .cghidEventTap)
    JSON.print(["ok": true, "x": point.x, "y": point.y])
}

func moveMouse() {
    let point = pointFromArgs()
    let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
    event?.post(tap: .cghidEventTap)
    JSON.print(["ok": true, "x": point.x, "y": point.y])
}

func scroll() {
    let dx = Int32(argValue("--dx", default: "0")!) ?? 0
    let dy = Int32(argValue("--dy", default: "0")!) ?? 0
    guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else {
        fail("scroll_event_failed")
    }
    event.post(tap: .cghidEventTap)
    JSON.print(["ok": true, "dx": dx, "dy": dy])
}

func drag() {
    guard let x1 = Double(require("--x1")),
          let y1 = Double(require("--y1")),
          let x2 = Double(require("--x2")),
          let y2 = Double(require("--y2")) else {
        fail("invalid_drag_coordinates")
    }
    let from = CGPoint(x: x1, y: y1)
    let to = CGPoint(x: x2, y: y2)
    let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: from, mouseButton: .left)
    let move = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: to, mouseButton: .left)
    let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: to, mouseButton: .left)
    down?.post(tap: .cghidEventTap)
    usleep(100_000)
    move?.post(tap: .cghidEventTap)
    usleep(100_000)
    up?.post(tap: .cghidEventTap)
    JSON.print(["ok": true, "x1": x1, "y1": y1, "x2": x2, "y2": y2])
}

func appleScript() {
    let source = require("--script")
    let timeoutMs = Int(argValue("--timeout-ms", default: "10000")!) ?? 10000
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", source]
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err
    do {
        try process.run()
    } catch {
        fail("osascript_launch_failed: \(error.localizedDescription)")
    }
    let deadline = DispatchTime.now() + .milliseconds(max(timeoutMs, 100))
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        process.waitUntilExit()
        done.signal()
    }
    if done.wait(timeout: deadline) == .timedOut {
        process.terminate()
        JSON.print(["ok": false, "status": -1, "stdout": "", "stderr": "osascript_timeout"])
        return
    }
    let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    JSON.print(["ok": process.terminationStatus == 0, "status": process.terminationStatus, "stdout": stdout, "stderr": stderr])
}

func setClipboard(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
}

func getClipboard() -> String {
    NSPasteboard.general.string(forType: .string) ?? ""
}

func keyCode(_ key: String) -> CGKeyCode {
    let table: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
        "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
        "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
        "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
        "`": 50, "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
        "esc": 53, "left": 123, "right": 124, "down": 125, "up": 126
    ]
    guard let code = table[key.lowercased()] else {
        fail("unsupported_key: \(key)")
    }
    return code
}

func flagsFromArgs(_ tokens: [String]) -> CGEventFlags {
    var flags = CGEventFlags()
    for token in tokens {
        switch token.lowercased() {
        case "cmd", "command", "meta": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "ctrl", "control": flags.insert(.maskControl)
        case "opt", "option", "alt": flags.insert(.maskAlternate)
        default: break
        }
    }
    return flags
}

func pressKey(_ key: String, flags: CGEventFlags = []) {
    let code = keyCode(key)
    let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
    let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
    down?.flags = flags
    up?.flags = flags
    down?.post(tap: .cghidEventTap)
    usleep(50_000)
    up?.post(tap: .cghidEventTap)
}

func hotkey() {
    let combo = require("--keys").split(separator: "+").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    guard let key = combo.last, !key.isEmpty else {
        fail("invalid_hotkey")
    }
    let flags = flagsFromArgs(Array(combo.dropLast()))
    pressKey(key, flags: flags)
    JSON.print(["ok": true, "keys": combo.joined(separator: "+")])
}

func keyState() {
    let key = require("--key")
    let code = keyCode(key)
    let pressed = CGEventSource.keyState(.combinedSessionState, key: code)
    JSON.print(["ok": true, "key": key, "pressed": pressed])
}

func typeTextCore(_ text: String) {
    let previous = getClipboard()
    setClipboard(text)
    usleep(80_000)
    pressKey("v", flags: .maskCommand)
    usleep(80_000)
    setClipboard(previous)
}

func typeText() {
    let text = require("--text")
    typeTextCore(text)
    JSON.print(["ok": true, "chars": text.count])
}

func clipboard() {
    let mode = argValue("--mode", default: "get")!
    if mode == "set" {
        let text = require("--text")
        setClipboard(text)
        JSON.print(["ok": true, "chars": text.count])
    } else {
        JSON.print(["ok": true, "text": getClipboard()])
    }
}

func check() {
    let prompt = argValue("--prompt", default: "false") == "true"
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
    let accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
    JSON.print([
        "ok": true,
        "accessibilityTrusted": accessibilityTrusted,
        "bundleIdentifier": Bundle.main.bundleIdentifier ?? "unknown"
    ])
}

func runProcess(_ executable: String, _ arguments: [String]) -> (Int32, String, String) {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = stdout
    process.standardError = stderr
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return (127, "", error.localizedDescription)
    }
    let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (process.terminationStatus, out, err)
}

func appControl() {
    let action = argValue("--action", default: "list")!
    if action == "list" {
        let apps = NSWorkspace.shared.runningApplications.map { app in
            [
                "pid": app.processIdentifier,
                "name": app.localizedName ?? "",
                "bundleIdentifier": app.bundleIdentifier ?? "",
                "active": app.isActive,
                "hidden": app.isHidden
            ] as [String: Any]
        }
        JSON.print(["ok": true, "apps": apps])
        return
    }

    let name = argValue("--name")
    let bundleId = argValue("--bundle-id")
    if action == "open" {
        if let bundleId {
            let (status, out, err) = runProcess("/usr/bin/open", ["-b", bundleId])
            JSON.print(["ok": status == 0, "status": status, "stdout": out, "stderr": err])
            return
        }
        guard let name else { fail("missing --name or --bundle-id") }
        let (status, out, err) = runProcess("/usr/bin/open", ["-a", name])
        JSON.print(["ok": status == 0, "status": status, "stdout": out, "stderr": err])
        return
    }

    let matches = NSWorkspace.shared.runningApplications.filter { app in
        if let bundleId, app.bundleIdentifier == bundleId { return true }
        if let name, (app.localizedName ?? "").localizedCaseInsensitiveContains(name) { return true }
        return false
    }
    guard let app = matches.first else {
        fail("app_not_running")
    }

    if action == "focus" {
        let ok = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        JSON.print(["ok": ok, "pid": app.processIdentifier, "name": app.localizedName ?? "", "bundleIdentifier": app.bundleIdentifier ?? ""])
    } else if action == "quit" {
        let ok = app.terminate()
        JSON.print(["ok": ok, "pid": app.processIdentifier, "name": app.localizedName ?? "", "bundleIdentifier": app.bundleIdentifier ?? ""])
    } else {
        fail("unknown_app_action: \(action)")
    }
}

func windowsList() {
    guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        fail("window_list_failed")
    }
    let windows = info.compactMap { item -> [String: Any]? in
        let layer = item[kCGWindowLayer as String] as? Int ?? 0
        if layer != 0 { return nil }
        var row: [String: Any] = [
            "id": item[kCGWindowNumber as String] ?? 0,
            "owner": item[kCGWindowOwnerName as String] ?? "",
            "pid": item[kCGWindowOwnerPID as String] ?? 0,
            "title": item[kCGWindowName as String] ?? ""
        ]
        if let bounds = item[kCGWindowBounds as String] as? [String: Any] {
            row["bounds"] = bounds
        }
        return row
    }
    JSON.print(["ok": true, "windows": windows])
}

func processControl() {
    let action = argValue("--action", default: "list")!
    if action == "list" {
        let (status, out, err) = runProcess("/bin/ps", ["-axo", "pid=,comm="])
        let processes = out.split(separator: "\n").compactMap { line -> [String: Any]? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let firstSpace = trimmed.firstIndex(of: " ") else { return nil }
            let pidText = trimmed[..<firstSpace].trimmingCharacters(in: .whitespaces)
            let command = trimmed[firstSpace...].trimmingCharacters(in: .whitespaces)
            return ["pid": Int(pidText) ?? 0, "command": command]
        }
        JSON.print(["ok": status == 0, "status": status, "stderr": err, "processes": processes])
    } else if action == "kill" {
        guard let pid = Int32(require("--pid")) else {
            fail("invalid_pid")
        }
        let signal = Int32(argValue("--signal", default: "15")!) ?? SIGTERM
        let result = Darwin.kill(pid, signal)
        JSON.print(["ok": result == 0, "pid": pid, "signal": signal])
    } else {
        fail("unknown_process_action: \(action)")
    }
}

func fileControl() {
    let action = argValue("--action", default: "open")!
    let path = require("--path")
    let url = URL(fileURLWithPath: path)
    if action == "open" {
        let ok = NSWorkspace.shared.open(url)
        JSON.print(["ok": ok, "path": path])
    } else if action == "reveal" {
        NSWorkspace.shared.activateFileViewerSelecting([url])
        JSON.print(["ok": true, "path": path])
    } else {
        fail("unknown_file_action: \(action)")
    }
}

func axString(_ element: AXUIElement, _ attr: CFString) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr, &value) == .success, let value else {
        return nil
    }
    if let string = value as? String {
        return string
    }
    if let number = value as? NSNumber {
        return number.stringValue
    }
    return String(describing: value)
}

func axBool(_ element: AXUIElement, _ attr: CFString) -> Bool? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr, &value) == .success, let value else {
        return nil
    }
    return value as? Bool
}

func axPoint(_ element: AXUIElement, _ attr: CFString) -> CGPoint? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr, &value) == .success, let value else {
        return nil
    }
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    let axValue = value as! AXValue
    var point = CGPoint.zero
    guard AXValueGetValue(axValue, .cgPoint, &point) else {
        return nil
    }
    return point
}

func axSize(_ element: AXUIElement, _ attr: CFString) -> CGSize? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr, &value) == .success, let value else {
        return nil
    }
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    let axValue = value as! AXValue
    var size = CGSize.zero
    guard AXValueGetValue(axValue, .cgSize, &size) else {
        return nil
    }
    return size
}

func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
          let children = value as? [AXUIElement] else {
        return []
    }
    return children
}

func axActions(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success,
          let names = names as? [String] else {
        return []
    }
    return names
}

func targetApplication() -> NSRunningApplication {
    if let pidText = argValue("--pid"), let pid = pid_t(pidText) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            return app
        }
        fail("app_pid_not_found")
    }
    if let bundleId = argValue("--bundle-id") {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
            return app
        }
        fail("app_bundle_not_running")
    }
    if let name = argValue("--name") {
        if let app = NSWorkspace.shared.runningApplications.first(where: { ($0.localizedName ?? "").localizedCaseInsensitiveContains(name) }) {
            return app
        }
        fail("app_name_not_running")
    }
    if let app = NSWorkspace.shared.frontmostApplication {
        return app
    }
    fail("frontmost_app_not_found")
}

func axNode(_ element: AXUIElement, id: Int, depth: Int) -> [String: Any] {
    var row: [String: Any] = [
        "id": id,
        "depth": depth,
        "role": axString(element, kAXRoleAttribute as CFString) ?? "",
        "title": axString(element, kAXTitleAttribute as CFString) ?? "",
        "description": axString(element, kAXDescriptionAttribute as CFString) ?? "",
        "value": axString(element, kAXValueAttribute as CFString) ?? "",
        "actions": axActions(element)
    ]
    if let enabled = axBool(element, kAXEnabledAttribute as CFString) {
        row["enabled"] = enabled
    }
    if let focused = axBool(element, kAXFocusedAttribute as CFString) {
        row["focused"] = focused
    }
    if let position = axPoint(element, kAXPositionAttribute as CFString),
       let size = axSize(element, kAXSizeAttribute as CFString) {
        row["frame"] = ["x": position.x, "y": position.y, "width": size.width, "height": size.height]
    }
    return row
}

func collectAX(_ element: AXUIElement, depth: Int, maxDepth: Int, maxNodes: Int, rows: inout [[String: Any]], nextId: inout Int, elements: inout [Int: AXUIElement]) {
    if rows.count >= maxNodes || depth > maxDepth {
        return
    }
    let id = nextId
    nextId += 1
    rows.append(axNode(element, id: id, depth: depth))
    elements[id] = element
    if depth == maxDepth {
        return
    }
    for child in axChildren(element) {
        collectAX(child, depth: depth + 1, maxDepth: maxDepth, maxNodes: maxNodes, rows: &rows, nextId: &nextId, elements: &elements)
        if rows.count >= maxNodes {
            return
        }
    }
}

func axSnapshot() {
    let maxDepth = Int(argValue("--max-depth", default: "5")!) ?? 5
    let maxNodes = Int(argValue("--max-nodes", default: "250")!) ?? 250
    let (rows, _, app) = axTree(maxDepth: maxDepth, maxNodes: maxNodes)
    JSON.print([
        "ok": true,
        "pid": app.processIdentifier,
        "name": app.localizedName ?? "",
        "bundleIdentifier": app.bundleIdentifier ?? "",
        "maxDepth": maxDepth,
        "maxNodes": maxNodes,
        "truncated": rows.count >= maxNodes,
        "nodes": rows
    ])
}

func axTree(maxDepth: Int? = nil, maxNodes: Int? = nil) -> ([[String: Any]], [Int: AXUIElement], NSRunningApplication) {
    let app = targetApplication()
    let root = AXUIElementCreateApplication(app.processIdentifier)
    let maxDepth = maxDepth ?? (Int(argValue("--max-depth", default: "8")!) ?? 8)
    let maxNodes = maxNodes ?? (Int(argValue("--max-nodes", default: "700")!) ?? 700)
    var rows: [[String: Any]] = []
    var elements: [Int: AXUIElement] = [:]
    var nextId = 1
    collectAX(root, depth: 0, maxDepth: maxDepth, maxNodes: maxNodes, rows: &rows, nextId: &nextId, elements: &elements)
    return (rows, elements, app)
}

func axMatches(query: String, role: String? = nil) -> [(Int, AXUIElement, [String: Any])] {
    let (rows, elements, _) = axTree()
    let queryLower = query.lowercased()
    let roleLower = role?.lowercased()
    var matches: [(Int, AXUIElement, [String: Any])] = []
    for row in rows {
        let id = row["id"] as? Int ?? 0
        let rowRole = (row["role"] as? String ?? "").lowercased()
        if let roleLower, !rowRole.contains(roleLower) {
            continue
        }
        let haystack = [
            row["role"] as? String ?? "",
            row["title"] as? String ?? "",
            row["description"] as? String ?? "",
            row["value"] as? String ?? ""
        ].joined(separator: " ").lowercased()
        if haystack.contains(queryLower), let element = elements[id] {
            matches.append((id, element, row))
        }
    }
    return matches
}

func matchingAXElement(query: String, role: String? = nil) -> (Int, AXUIElement, [String: Any])? {
    axMatches(query: query, role: role).first
}

func axElementById(_ id: Int) -> (Int, AXUIElement, [String: Any])? {
    let (rows, elements, _) = axTree()
    guard let element = elements[id],
          let row = rows.first(where: { ($0["id"] as? Int) == id }) else {
        return nil
    }
    return (id, element, row)
}

func performAXClick(_ match: (Int, AXUIElement, [String: Any])) -> [String: Any] {
    let actions = axActions(match.1)
    if actions.contains(kAXPressAction as String) {
        let result = AXUIElementPerformAction(match.1, kAXPressAction as CFString)
        if result == .success {
            return ["ok": true, "method": "AXPress", "id": match.0, "node": match.2]
        }
    }
    if let frame = match.2["frame"] as? [String: Any],
       let x = numberAsDouble(frame["x"]),
       let y = numberAsDouble(frame["y"]),
       let width = numberAsDouble(frame["width"]),
       let height = numberAsDouble(frame["height"]) {
        let point = CGPoint(x: x + width / 2, y: y + height / 2)
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        usleep(60_000)
        up?.post(tap: .cghidEventTap)
        return ["ok": true, "method": "centerClick", "id": match.0, "x": point.x, "y": point.y, "node": match.2]
    }
    fail("ax_match_not_actionable")
}

func performAXSetValue(_ match: (Int, AXUIElement, [String: Any]), text: String) -> [String: Any] {
    let result = AXUIElementSetAttributeValue(match.1, kAXValueAttribute as CFString, text as CFTypeRef)
    if result == .success {
        return ["ok": true, "method": "AXSetValue", "id": match.0, "chars": text.count, "node": match.2]
    }
    fail("ax_set_value_failed: \(result.rawValue)")
}

func performAXAction(_ match: (Int, AXUIElement, [String: Any]), action: String) -> [String: Any] {
    let actions = axActions(match.1)
    guard actions.contains(action) else {
        fail("ax_action_not_available: \(action)")
    }
    let result = AXUIElementPerformAction(match.1, action as CFString)
    if result == .success {
        return ["ok": true, "method": "AXAction", "action": action, "id": match.0, "node": match.2]
    }
    fail("ax_action_failed: \(result.rawValue)")
}

func findTextRange(value: String, target: String, prefix: String?, suffix: String?) -> NSRange? {
    let nsValue = value as NSString
    var searchStart = 0
    while searchStart <= nsValue.length {
        let searchRange = NSRange(location: searchStart, length: nsValue.length - searchStart)
        let range = nsValue.range(of: target, options: [], range: searchRange)
        if range.location == NSNotFound {
            return nil
        }
        var ok = true
        if let prefix {
            let prefixLen = (prefix as NSString).length
            if range.location < prefixLen {
                ok = false
            } else {
                let actual = nsValue.substring(with: NSRange(location: range.location - prefixLen, length: prefixLen))
                ok = ok && actual == prefix
            }
        }
        if let suffix {
            let suffixLen = (suffix as NSString).length
            if range.location + range.length + suffixLen > nsValue.length {
                ok = false
            } else {
                let actual = nsValue.substring(with: NSRange(location: range.location + range.length, length: suffixLen))
                ok = ok && actual == suffix
            }
        }
        if ok {
            return range
        }
        searchStart = range.location + max(range.length, 1)
    }
    return nil
}

func performAXSelectText(_ match: (Int, AXUIElement, [String: Any]), target: String, prefix: String?, suffix: String?, mode: String) -> [String: Any] {
    guard let value = axString(match.1, kAXValueAttribute as CFString) else {
        fail("ax_value_not_string")
    }
    guard let targetRange = findTextRange(value: value, target: target, prefix: prefix, suffix: suffix) else {
        fail("target_text_not_found")
    }
    let selectedRange: NSRange
    if mode == "before" {
        selectedRange = NSRange(location: targetRange.location, length: 0)
    } else if mode == "after" {
        selectedRange = NSRange(location: targetRange.location + targetRange.length, length: 0)
    } else if mode == "select" {
        selectedRange = targetRange
    } else {
        fail("invalid_select_mode: \(mode)")
    }
    var cfRange = CFRange(location: selectedRange.location, length: selectedRange.length)
    guard let axRange = AXValueCreate(.cfRange, &cfRange) else {
        fail("ax_range_create_failed")
    }
    let result = AXUIElementSetAttributeValue(match.1, kAXSelectedTextRangeAttribute as CFString, axRange)
    if result == .success {
        return [
            "ok": true,
            "method": "AXSelectedTextRange",
            "id": match.0,
            "mode": mode,
            "location": selectedRange.location,
            "length": selectedRange.length,
            "node": match.2
        ]
    }
    fail("ax_select_text_failed: \(result.rawValue)")
}

func numberAsDouble(_ value: Any?) -> Double? {
    if let double = value as? Double {
        return double
    }
    if let int = value as? Int {
        return Double(int)
    }
    if let number = value as? NSNumber {
        return number.doubleValue
    }
    return nil
}

func axFind() {
    let query = require("--query")
    let role = argValue("--role")
    let limit = Int(argValue("--limit", default: "20")!) ?? 20
    let matches = axMatches(query: query, role: role).prefix(limit).map { $0.2 }
    JSON.print(["ok": true, "query": query, "role": role ?? "", "count": matches.count, "matches": Array(matches)])
}

func axClickById() {
    guard let id = Int(require("--id")) else {
        fail("invalid_id")
    }
    guard let match = axElementById(id) else {
        fail("ax_id_not_found")
    }
    JSON.print(performAXClick(match))
}

func axWaitFor() {
    let query = require("--query")
    let role = argValue("--role")
    let timeoutMs = Int(argValue("--timeout-ms", default: "10000")!) ?? 10000
    let intervalMs = Int(argValue("--interval-ms", default: "250")!) ?? 250
    let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
    var attempts = 0
    while Date() < deadline {
        attempts += 1
        if let match = matchingAXElement(query: query, role: role) {
            JSON.print(["ok": true, "query": query, "role": role ?? "", "attempts": attempts, "match": match.2])
            return
        }
        usleep(useconds_t(max(intervalMs, 50) * 1000))
    }
    JSON.print(["ok": false, "error": "timeout", "query": query, "role": role ?? "", "attempts": attempts])
}

func healthcheck() {
    var checks: [[String: Any]] = []
    checks.append(["name": "accessibility", "ok": AXIsProcessTrusted()])

    let screenshotPath = defaultScreenshotPath().replacingOccurrences(of: ".png", with: "-healthcheck.png")
    let capture = runProcess("/usr/sbin/screencapture", ["-x", screenshotPath])
    checks.append([
        "name": "screenshot",
        "ok": capture.0 == 0 && FileManager.default.fileExists(atPath: screenshotPath),
        "path": screenshotPath,
        "stderr": capture.2
    ])

    let marker = "maccontrol-healthcheck-\(Int(Date().timeIntervalSince1970))"
    let previousClipboard = getClipboard()
    setClipboard(marker)
    let clipboardOk = getClipboard() == marker
    setClipboard(previousClipboard)
    checks.append(["name": "clipboard", "ok": clipboardOk])

    if let app = NSWorkspace.shared.frontmostApplication {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var rows: [[String: Any]] = []
        var elements: [Int: AXUIElement] = [:]
        var nextId = 1
        collectAX(root, depth: 0, maxDepth: 2, maxNodes: 20, rows: &rows, nextId: &nextId, elements: &elements)
        checks.append(["name": "ax-snapshot", "ok": rows.count > 1, "frontApp": app.localizedName ?? "", "nodes": rows.count])
    } else {
        checks.append(["name": "ax-snapshot", "ok": false, "error": "frontmost_app_not_found"])
    }

    let signing = runProcess("/usr/bin/codesign", ["-dr", "-", Bundle.main.bundlePath])
    checks.append([
        "name": "codesign",
        "ok": (signing.1 + signing.2).contains("identifier \"app.openclaw.maccontrol\""),
        "requirement": signing.1 + signing.2
    ])

    JSON.print(["ok": checks.allSatisfy { ($0["ok"] as? Bool) == true }, "checks": checks])
}

func axClick() {
    let role = argValue("--role")
    let match: (Int, AXUIElement, [String: Any])?
    if let idText = argValue("--id"), let id = Int(idText) {
        match = axElementById(id)
    } else {
        match = matchingAXElement(query: require("--query"), role: role)
    }
    guard let match else { fail("ax_match_not_found") }
    JSON.print(performAXClick(match))
}

func axType() {
    let text = require("--text")
    let role = argValue("--role")
    let match: (Int, AXUIElement, [String: Any])?
    if let idText = argValue("--id"), let id = Int(idText) {
        match = axElementById(id)
    } else {
        match = matchingAXElement(query: require("--query"), role: role)
    }
    guard let match else { fail("ax_match_not_found") }
    let clickResult = performAXClick(match)
    usleep(100_000)
    typeTextCore(text)
    JSON.print(["ok": true, "click": clickResult, "chars": text.count])
}

func axSetValue() {
    let text = require("--text")
    let role = argValue("--role")
    let match: (Int, AXUIElement, [String: Any])?
    if let idText = argValue("--id"), let id = Int(idText) {
        match = axElementById(id)
    } else {
        match = matchingAXElement(query: require("--query"), role: role)
    }
    guard let match else { fail("ax_match_not_found") }
    JSON.print(performAXSetValue(match, text: text))
}

func axAction() {
    let action = require("--action")
    let role = argValue("--role")
    let match: (Int, AXUIElement, [String: Any])?
    if let idText = argValue("--id"), let id = Int(idText) {
        match = axElementById(id)
    } else {
        match = matchingAXElement(query: require("--query"), role: role)
    }
    guard let match else { fail("ax_match_not_found") }
    JSON.print(performAXAction(match, action: action))
}

func axSelectText() {
    let text = require("--text")
    let prefix = argValue("--prefix")
    let suffix = argValue("--suffix")
    let mode = argValue("--mode", default: "select")!
    let role = argValue("--role")
    let match: (Int, AXUIElement, [String: Any])?
    if let idText = argValue("--id"), let id = Int(idText) {
        match = axElementById(id)
    } else {
        match = matchingAXElement(query: require("--query"), role: role)
    }
    guard let match else { fail("ax_match_not_found") }
    JSON.print(performAXSelectText(match, target: text, prefix: prefix, suffix: suffix, mode: mode))
}

func usage() -> Never {
    Swift.print("""
    MacControl primitive desktop controller

    Commands:
      check [--prompt true]
      screenshot [--out PATH] [--window-id ID]
      click --x X --y Y
      move --x X --y Y
      scroll --dx DX --dy DY
      drag --x1 X --y1 Y --x2 X --y2 Y
      applescript --script SOURCE
      type --text TEXT
      hotkey --keys cmd+v
      key-state --key escape
      clipboard [--mode get|set] [--text TEXT]
      app --action list|open|focus|quit [--name NAME|--bundle-id ID]
      windows
      process --action list|kill [--pid PID]
      file --action open|reveal --path PATH
      ax-snapshot [--name APP|--bundle-id ID|--pid PID] [--max-depth N] [--max-nodes N]
      ax-find --query TEXT [--role ROLE] [--limit N]
      ax-click (--query TEXT|--id ID) [--role ROLE] [--name APP|--bundle-id ID|--pid PID]
      ax-type (--query TEXT|--id ID) --text TEXT [--role ROLE] [--name APP|--bundle-id ID|--pid PID]
      ax-set-value (--query TEXT|--id ID) --text TEXT [--role ROLE] [--name APP|--bundle-id ID|--pid PID]
      ax-action (--query TEXT|--id ID) --action ACTION [--role ROLE] [--name APP|--bundle-id ID|--pid PID]
      ax-select-text (--query TEXT|--id ID) --text TEXT [--prefix TEXT] [--suffix TEXT] [--mode select|before|after]
      ax-wait-for --query TEXT [--role ROLE] [--timeout-ms N]
      healthcheck
    """)
    exit(2)
}

func runCommand(_ args: [String]) {
    activeArgs = args
    guard args.count >= 2 else {
        fail("missing_command", code: 2)
    }
    switch args[1] {
    case "check": check()
    case "screenshot": screenshot()
    case "click": click()
    case "move": moveMouse()
    case "scroll": scroll()
    case "drag": drag()
    case "applescript": appleScript()
    case "type": typeText()
    case "hotkey": hotkey()
    case "key-state": keyState()
    case "clipboard": clipboard()
    case "app": appControl()
    case "windows": windowsList()
    case "process": processControl()
    case "file": fileControl()
    case "healthcheck": healthcheck()
    case "ax-snapshot": axSnapshot()
    case "ax-find": axFind()
    case "ax-click": axClick()
    case "ax-type": axType()
    case "ax-set-value": axSetValue()
    case "ax-action": axAction()
    case "ax-select-text": axSelectText()
    case "ax-wait-for": axWaitFor()
    case "help", "--help", "-h": usage()
    default: fail("unknown_command: \(args[1])", code: 2)
    }
}

func serve() -> Never {
    let port = UInt16(argValue("--port", default: "17891")!) ?? 17891
    let server = socket(AF_INET, SOCK_STREAM, 0)
    guard server >= 0 else {
        fail("socket_failed")
    }

    var yes: Int32 = 1
    setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindResult = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(server, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult == 0 else {
        fail("bind_failed_port_\(port)")
    }
    guard listen(server, 8) == 0 else {
        fail("listen_failed")
    }

    JSON.print(["ok": true, "server": "MacControl", "port": port])

    while true {
        let client = accept(server, nil, nil)
        if client < 0 {
            continue
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = read(client, &buffer, buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                continue
            }
            break
        }
        if !data.isEmpty {
            responseFD = client
            if let argv = try? JSONSerialization.jsonObject(with: data) as? [String] {
                runCommand(["MacControl"] + argv)
            } else {
                JSON.print(["ok": false, "error": "invalid_json_argv"])
            }
            responseFD = nil
        }
        close(client)
    }
}

let args = activeArgs
guard args.count >= 2 else {
    usage()
}

if args[1] == "serve" {
    serve()
} else {
    runCommand(args)
}
