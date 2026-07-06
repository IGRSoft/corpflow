// bench-report — render benchmark/results/history.json into result.html.
// Depends ONLY on BenchmarkKit (AC-8 link-level).
//
// Argv: bench-report [--history <path>] [--out <path>] [--plugin-root <dir>]
// Exit codes: 0 success, 64 bad argv.

import BenchmarkKit
import Foundation

@MainActor func die(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

var history: String?
var out: String?
var pluginRoot: String?
var i = 1
let argv = CommandLine.arguments
while i < argv.count {
    switch argv[i] {
    case "-h", "--help":
        print("bench-report [--history <path>] [--out <path>] [--plugin-root <dir>]")
        exit(0)
    case "--history":
        guard i + 1 < argv.count else { die("bench-report: --history needs a value", code: 64) }
        history = argv[i + 1]; i += 2
    case "--out":
        guard i + 1 < argv.count else { die("bench-report: --out needs a value", code: 64) }
        out = argv[i + 1]; i += 2
    case "--plugin-root":
        guard i + 1 < argv.count else { die("bench-report: --plugin-root needs a value", code: 64) }
        pluginRoot = argv[i + 1]; i += 2
    default:
        die("bench-report: unknown arg '\(argv[i])'", code: 64)
    }
}

// Default paths: benchmark/results/{history.json,result.html}. Derive the
// benchmark dir from this binary's location's repo when possible; otherwise the
// caller passes explicit paths (the shell seam always does).
let cwd = FileManager.default.currentDirectoryPath
let historyPath = history ?? cwd + "/benchmark/results/history.json"
let outPath = out ?? cwd + "/benchmark/results/result.html"
let root = pluginRoot ?? cwd

do {
    let written = try Report.buildReport(historyPath: historyPath, outPath: outPath, pluginRoot: root)
    print("[report] wrote \(written)")
    exit(0)
} catch {
    die("[report] error: \(error)", code: 1)
}
