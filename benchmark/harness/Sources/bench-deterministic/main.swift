// bench-deterministic — deterministic dual-path benchmark executable.
// Depends ONLY on BenchmarkKit (AC-8 link-level; never links BenchmarkLive).
//
// Exit codes (D5): 0 success, 1 a generated app's tests failed, 64 bad argv.
//
// Argv (frozen seam, mirrors deterministic_run.py):
//   bench-deterministic --workdir <dir> --run-id <id> --timestamp <YYYYmmddTHHMMSSZ>
//     --git-sha <sha> --record <path> --history <path> --runs-dir <dir>
//     [--template <dir>] [--plugin-root <dir>] [--estimate-calc <path>]

import BenchmarkKit
import Foundation

@MainActor func die(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

var args: [String: String] = [:]
var i = 1
let argv = CommandLine.arguments
let flags = ["--workdir", "--run-id", "--timestamp", "--git-sha", "--record",
             "--history", "--runs-dir", "--template", "--plugin-root", "--estimate-calc"]
while i < argv.count {
    let a = argv[i]
    if a == "-h" || a == "--help" {
        print("bench-deterministic --workdir <dir> --run-id <id> --timestamp <ts> --git-sha <sha> --record <path> --history <path> --runs-dir <dir>")
        exit(0)
    }
    if flags.contains(a), i + 1 < argv.count {
        args[a] = argv[i + 1]; i += 2
    } else {
        die("bench-deterministic: unknown or incomplete arg '\(a)'", code: 64)
    }
}

@MainActor func require(_ key: String) -> String {
    guard let v = args[key] else { die("bench-deterministic: missing required \(key)", code: 64) }
    return v
}

let workdir = require("--workdir")
let runID = require("--run-id")
let timestamp = require("--timestamp")
let gitSHA = require("--git-sha")
let record = require("--record")
let history = require("--history")
let runsDir = require("--runs-dir")

// Anchor the template + plugin root + estimate script relative to the record
// path's repo when not explicitly given. The benchmark dir is the parent of
// results/; plugin root is its parent.
let fm = FileManager.default
// Default template: sibling ttt-template of the benchmark dir. Derive the
// benchmark dir from history path (results/history.json) if possible.
@MainActor func defaultBenchmarkDir() -> String {
    // history is typically <bench>/results/history.json
    let resultsDir = (history as NSString).deletingLastPathComponent
    return (resultsDir as NSString).deletingLastPathComponent
}
let benchDir = defaultBenchmarkDir()
let pluginRoot = args["--plugin-root"] ?? (benchDir as NSString).deletingLastPathComponent
let templateDir = args["--template"] ?? (benchDir as NSString).appendingPathComponent("ttt-template")
let estimateCalc = args["--estimate-calc"]
    ?? pluginRoot + "/skills/estimation-methodology/scripts/estimate-calc.py"

do {
    let result = try DeterministicRun.run(
        workdir: workdir, runID: runID, timestamp: timestamp, gitSHA: gitSHA,
        recordPath: record, history: history, runsDir: runsDir,
        templateDir: templateDir, pluginRoot: pluginRoot, estimateCalcPath: estimateCalc)
    let w = result.record.pathWith
    let wo = result.record.pathWithout
    if let w, let wo {
        print("[benchmark] WITH:    loc=\(w.locProduced) tests=\(w.testCount) pass=\(w.passFail) stages=\(w.stageCount) score=\(w.estimateComplexityScore)")
        print("[benchmark] WITHOUT: loc=\(wo.locProduced) tests=\(wo.testCount) pass=\(wo.passFail) stages=\(wo.stageCount) score=\(wo.estimateComplexityScore)")
    }
    print("[benchmark] record:  \(record)")
    print("[benchmark] history: \(history)")
    if result.exitCode != 0 {
        die("[benchmark] FAIL: a generated app's tests did not pass", code: 1)
    }
    exit(0)
} catch {
    die("[benchmark] error: \(error)", code: 1)
}
