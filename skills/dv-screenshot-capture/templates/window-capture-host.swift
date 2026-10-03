// WindowCaptureHost — copied by scripts/macos-window-capture.sh into
// <ctx>/tools/WindowCaptureHost/<task>.<run>/Sources/WindowCaptureHost/, next to CaptureRoot.swift,
// which must define `@MainActor func captureRoot() -> some View`.
//
// The real root view runs in a real NSWindow and is driven by mouse events delivered through
// NSWindow.sendEvent. Everything stays in-process and the PNG comes from cacheDisplay, not a
// screen grab, so no Screen Recording, Accessibility or event-posting grant is needed.
//
// argv:  <out-dir> <width> <height> <timeout-seconds>
// stdin: one step per line
//   click <x> <y>   points from the window's top-left, title bar included
//   wait <seconds>
//   shot <name>     writes <out-dir>/<name>.png at 1x, so a PNG pixel is a click point
// Exit: 0 every step ran, 3 a step failed or the timeout fired, 64 bad argv.

import AppKit
import SwiftUI

// SwiftUI dims prominent controls in a non-key window; a harness window never becomes key when
// the process lacks activation rights, and the evidence should show the active appearance.
final class CaptureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var isKeyWindow: Bool { true }
}

@main
@MainActor
enum WindowCaptureHost {
    static var window: CaptureWindow!
    static var outDir = URL(fileURLWithPath: ".")
    static var failed = false

    static func main() {
        let args = CommandLine.arguments
        guard args.count == 5, let width = Double(args[2]), let height = Double(args[3]),
              let limit = Double(args[4]) else {
            FileHandle.standardError.write(Data("usage: WindowCaptureHost <out-dir> <width> <height> <timeout>\n".utf8))
            exit(64)
        }
        outDir = URL(fileURLWithPath: args[1])
        let steps = Array(AnyIterator { readLine() })

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        window = CaptureWindow(contentRect: NSRect(x: 120, y: 120, width: width, height: height),
                               styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "WindowCaptureHost"
        window.contentView = NSHostingView(rootView: captureRoot())
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)

        // A click that opens a modal or a step list that stalls must not hang the DV stage.
        DispatchQueue.main.asyncAfter(deadline: .now() + limit) {
            FileHandle.standardError.write(Data("timeout after \(limit)s\n".utf8))
            exit(3)
        }
        Task { @MainActor in
            await settle(1.0)
            for step in steps { await perform(step) }
            exit(failed ? 3 : 0)
        }
        app.run()
    }

    static func perform(_ line: String) async {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        switch (parts.first, parts.count) {
        case (nil, _), (.some("#"), _):
            return
        case ("click", 3):
            guard let x = Double(parts[1]), let y = Double(parts[2]) else { return reject(line) }
            click(x: x, yFromTop: y)
            await settle(0.35)
        case ("wait", 2):
            guard let seconds = Double(parts[1]) else { return reject(line) }
            await settle(seconds)
        case ("shot", 2):
            capture(parts[1])
        default:
            reject(line)
        }
    }

    static func reject(_ line: String) {
        FileHandle.standardError.write(Data("bad step: \(line)\n".utf8))
        failed = true
    }

    static func settle(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
    }

    static func click(x: Double, yFromTop: Double) {
        // Window coordinates grow upward from the frame's bottom edge; steps use the PNG's frame.
        let point = NSPoint(x: x, y: window.frame.height - yFromTop)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ) else { return reject("click \(x) \(yFromTop)") }
            window.sendEvent(event)
        }
        print("click \(x) \(yFromTop)")
    }

    static func capture(_ name: String) {
        // The theme frame, not the content view, so the title bar is in the shot and the PNG
        // frame equals the click frame.
        guard let view = window.contentView?.superview else { return reject("shot \(name)") }
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return reject("shot \(name)") }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = outDir.appendingPathComponent("\(name).png")
        do {
            guard let data = rep.representation(using: .png, properties: [:]) else {
                return reject("shot \(name)")
            }
            try data.write(to: url)
            print("shot \(name).png \(Int(size.width))x\(Int(size.height))")
        } catch {
            reject("shot \(name): \(error.localizedDescription)")
        }
    }
}
