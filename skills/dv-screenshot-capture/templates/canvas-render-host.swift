// canvas-render-host.swift
//
// Reference `main.swift` content for the SnapshotHost SPM executable that the
// apple-canvas adapter scaffolds into per-project `tools/SnapshotHost/Sources/SnapshotHost/`.
//
// This file is illustrative — the apple-canvas adapter copies it (and the surrounding
// Package.swift / PreviewBridge.swift) into the target project on first run, RENAMING
// it to `main.swift` so it picks up implicit top-level `@main` semantics inside the
// SPM executable target context.
//
// CLI contract (matches references/apple-canvas.md § CLI contract):
//
//   swift run SnapshotHost
//     --view <ModuleName.TypeName>          # required; key into PreviewBridge.viewRegistry
//     --output <path>                       # required; absolute path to PNG destination
//     [--size 393x852]                      # default 393×852 (iPhone artboard)
//     [--scheme light|dark]                 # default light
//
// Exit codes:
//   0 — success
//   1 — argument parse error (missing required / malformed)
//   2 — view-key not found in PreviewBridge.viewRegistry
//   3 — render failed (ImageRenderer returned nil)
//   4 — write failed (disk/permissions)

import Foundation
import SwiftUI

// MARK: - Entry
//
// Drop-in template. When the scaffolder copies this into a project, it is renamed
// to `main.swift` so the call below executes at module top-level. Until then, this
// file stands alone as a reference — every declaration lives inside `SnapshotHostMain`
// so SourceKit can analyze it without an SPM target context.

@MainActor
enum SnapshotHostMain {

    // MARK: CLI argument parsing

    struct CLIArgs {
        var view: String
        var output: String
        var size: CGSize = CGSize(width: 393, height: 852)   // iPhone artboard
        var scheme: ColorScheme = .light
    }

    enum CLIError: Error {
        case missingFlag(String)
        case malformedSize(String)
        case malformedScheme(String)
    }

    static func parseArgs(_ argv: [String]) throws -> CLIArgs {
        var view: String?
        var output: String?
        var size: CGSize = CGSize(width: 393, height: 852)
        var scheme: ColorScheme = .light

        var i = 1
        while i < argv.count {
            let flag = argv[i]
            let next = (i + 1 < argv.count) ? argv[i + 1] : nil
            switch flag {
            case "--view":
                view = next
                i += 2
            case "--output":
                output = next
                i += 2
            case "--size":
                guard let s = next else { throw CLIError.missingFlag("--size value") }
                let parts = s.split(separator: "x").map(String.init)
                guard parts.count == 2,
                      let w = Double(parts[0]),
                      let h = Double(parts[1]) else {
                    throw CLIError.malformedSize(s)
                }
                size = CGSize(width: w, height: h)
                i += 2
            case "--scheme":
                guard let s = next else { throw CLIError.missingFlag("--scheme value") }
                switch s {
                case "light": scheme = .light
                case "dark":  scheme = .dark
                default:      throw CLIError.malformedScheme(s)
                }
                i += 2
            default:
                // Unknown flag — ignore (forward-compat with future flags from adapter).
                i += 1
            }
        }

        guard let v = view   else { throw CLIError.missingFlag("--view") }
        guard let o = output else { throw CLIError.missingFlag("--output") }
        return CLIArgs(view: v, output: o, size: size, scheme: scheme)
    }

    // MARK: Render

    static func renderPNG(args: CLIArgs) -> Int32 {
        // PreviewBridge is the scaffolded sibling file that exposes
        // `viewRegistry: [String: AnyView]`. See:
        //   templates/SnapshotHost-template/Sources/SnapshotHost/PreviewBridge.swift
        //
        // In a free-floating analysis context (no SPM module), the symbol is
        // unresolved — that is expected. The scaffold builds them together.
        let registry = Self.lookupRegistry()

        guard let view = registry[args.view] else {
            FileHandle.standardError.write(Data("error: view '\(args.view)' not found in PreviewBridge.viewRegistry\n".utf8))
            let keys = registry.keys.sorted().joined(separator: ", ")
            FileHandle.standardError.write(Data("available views: \(keys)\n".utf8))
            return 2
        }

        // Wrap in a fixed-size container so `proposedSize` is deterministic across
        // host/sim runs (mitigates fidelity drift documented in apple-canvas.md).
        // Explicit `\EnvironmentValues.colorScheme` root keeps SourceKit happy in
        // free-floating analysis (no SwiftUI environment context inferred).
        let wrapped = view
            .environment(\EnvironmentValues.colorScheme, args.scheme)
            .frame(width: args.size.width, height: args.size.height)

        let renderer = ImageRenderer(content: wrapped)
        renderer.proposedSize = ProposedViewSize(width: args.size.width, height: args.size.height)
        renderer.scale = 2.0  // 2x render for retina fidelity

        guard let cgImage = renderer.cgImage else {
            FileHandle.standardError.write(Data("error: ImageRenderer.cgImage returned nil\n".utf8))
            return 3
        }

        // Write PNG via CGImageDestination (cross-platform — works on macOS host
        // and iOS Catalyst host). Avoids NSBitmapImageRep so this file compiles
        // identically under both `.macOS(.v13)` and `.iOS(.v16)`.
        let url = URL(fileURLWithPath: args.output)
        #if canImport(ImageIO)
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else {
            FileHandle.standardError.write(Data("error: CGImageDestinationCreateWithURL failed for \(args.output)\n".utf8))
            return 4
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            FileHandle.standardError.write(Data("error: CGImageDestinationFinalize failed for \(args.output)\n".utf8))
            return 4
        }
        #else
        FileHandle.standardError.write(Data("error: ImageIO unavailable on this platform\n".utf8))
        return 4
        #endif

        // Success — print absolute path on stdout for adapter parsing convenience.
        print(args.output)
        return 0
    }

    /// Indirect access to `PreviewBridge.viewRegistry`. Indirection keeps this
    /// reference-template file analyzable standalone. apple-canvas.sh copies it
    /// to main.swift unchanged, so the project copy must be edited by hand to
    /// `return PreviewBridge.viewRegistry` before any --view key resolves.
    static func lookupRegistry() -> [String: AnyView] {
        return [:]
    }

    // MARK: Entry point
    //
    // apple-canvas.sh copies this file to `main.swift` and the call below runs
    // at module top-level. Until then, `runMain()` is a no-op unless invoked
    // explicitly — keeps SourceKit happy without an `@main` conflict.

    static func runMain() async {
        do {
            let args = try parseArgs(CommandLine.arguments)
            let exitCode = renderPNG(args: args)
            exit(exitCode)
        } catch CLIError.missingFlag(let f) {
            FileHandle.standardError.write(Data("error: missing flag \(f)\n".utf8))
            FileHandle.standardError.write(Data("usage: SnapshotHost --view <ModuleName.TypeName> --output <path> [--size WxH] [--scheme light|dark]\n".utf8))
            exit(1)
        } catch CLIError.malformedSize(let s) {
            FileHandle.standardError.write(Data("error: --size must be WxH (e.g. 393x852); got '\(s)'\n".utf8))
            exit(1)
        } catch CLIError.malformedScheme(let s) {
            FileHandle.standardError.write(Data("error: --scheme must be 'light' or 'dark'; got '\(s)'\n".utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }
}

// SCAFFOLDER NOTE — after rename to `main.swift`, append the following two lines
// at module top-level so the executable target has an entry point:
//
//     await SnapshotHostMain.runMain()
//
// Do NOT add `@main` to the enum — the runMain() call above is the explicit form
// and avoids the "main attribute cannot be used in a module that contains
// top-level code" conflict that a free-floating reference file would trigger.
