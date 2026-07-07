// bench-live — live A/B dispatch executable (the ONLY executable linking
// BenchmarkLive).
//
// FROZEN seam argv (run-benchmark.sh --live):
//   bench-live --workdir <run_id> --budget <usd> --record <path>
// NEW (coverage option 2): --stages CODE[,CODE...] — validated against
// STAGE_TABLE, exit 64 on unknown. Optional: --capture json|stream-json
// (default stream-json for per-stage coverage manifests, plan §Coverage-1),
// --benchmark-dir / --prompts-dir overrides.
//
// Exit codes (D5): 0 success, 2 pre-flight budget decline, 3 no credential,
// 4 running-tally breach (partial record WRITTEN first, D6), 64 bad usage.

import BenchmarkKit
import BenchmarkLive
import Foundation

@MainActor func die(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

var workdir: String?
var budget: Double?
var record: String?
var stagesArg: String?
var captureArg = "stream-json"
var benchmarkDirArg: String?
var promptsDirArg: String?

let argv = CommandLine.arguments
var i = 1
while i < argv.count {
    let a = argv[i]
    switch a {
    case "-h", "--help":
        print("bench-live --workdir <run_id> --budget <usd> --record <path> "
            + "[--stages CODE[,CODE...]] [--capture json|stream-json] "
            + "[--benchmark-dir <dir>] [--prompts-dir <dir>]")
        exit(0)
    case "--workdir", "--budget", "--record", "--stages", "--capture",
         "--benchmark-dir", "--prompts-dir":
        guard i + 1 < argv.count else { die("bench-live: \(a) needs a value", code: 64) }
        let v = argv[i + 1]
        i += 2
        switch a {
        case "--workdir": workdir = v
        case "--budget":
            guard let b = Double(v) else {
                die("bench-live: --budget must be a number, got '\(v)'", code: 64)
            }
            budget = b
        case "--record": record = v
        case "--stages": stagesArg = v
        case "--capture": captureArg = v
        case "--benchmark-dir": benchmarkDirArg = v
        default: promptsDirArg = v
        }
        continue
    default:
        die("bench-live: unknown arg '\(a)'", code: 64)
    }
    i += 1
}

guard let workdir, let budget, let record else {
    die("bench-live: --workdir, --budget and --record are required", code: 64)
}

// --stages validation (coverage option 2): unknown code -> exit 64.
var stages = Budget.pipelineStages
if let stagesArg {
    let requested = stagesArg.split(separator: ",").map {
        $0.trimmingCharacters(in: .whitespaces).uppercased()
    }.filter { !$0.isEmpty }
    if requested.isEmpty {
        die("bench-live: --stages needs at least one stage code", code: 64)
    }
    for code in requested where STAGE_TABLE[code] == nil {
        die("bench-live: unknown stage code '\(code)' (valid: "
            + Budget.pipelineStages.joined(separator: ",") + ")", code: 64)
    }
    // Preserve canonical pipeline order regardless of user order.
    stages = Budget.pipelineStages.filter { requested.contains($0) }
}

guard let captureMode = Dispatch.CaptureMode(rawValue: captureArg) else {
    die("bench-live: --capture must be json or stream-json, got '\(captureArg)'", code: 64)
}

// Anchor benchmark dir: explicit flag, else derived from the record path
// (<bench>/results/runs/live/<id>.json), else cwd/benchmark.
let benchmarkDir: String
if let benchmarkDirArg {
    benchmarkDir = benchmarkDirArg
} else {
    let runsMode = (record as NSString).deletingLastPathComponent   // .../runs/<mode>
    let runs = (runsMode as NSString).deletingLastPathComponent     // .../runs
    let results = (runs as NSString).deletingLastPathComponent      // .../results
    let derived = (results as NSString).deletingLastPathComponent   // .../benchmark
    benchmarkDir = FileManager.default.fileExists(atPath: derived + "/live/prompts")
        ? derived
        : FileManager.default.currentDirectoryPath + "/benchmark"
}

do {
    let rc = try Dispatch.dispatch(
        workdir: workdir, budget: budget, recordPath: record,
        promptsDir: promptsDirArg, stages: stages,
        benchmarkDir: benchmarkDir, captureMode: captureMode)
    exit(rc)
} catch {
    die("bench-live: dispatch failed: \(error)", code: 1)
}
