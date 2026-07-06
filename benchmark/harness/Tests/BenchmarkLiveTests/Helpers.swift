// Helpers.swift — shared fakes for the BenchmarkLive suite, port of
// benchmark/tests/live/_helpers.py. No test here ever performs a network or
// LLM call.

import BenchmarkKit
import Foundation
@testable import BenchmarkLive

/// A dispatcher that FAILS LOUDLY if ever called. Proves the default path
/// never dispatches and guards tests that must abort BEFORE a breaching stage.
final class TripwireDispatcher: Dispatching, @unchecked Sendable {
    struct Tripped: Error, CustomStringConvertible {
        let description = "TRIPWIRE: real dispatcher was invoked — no LLM call may happen in tests"
    }
    private(set) var called = false

    func run(argv: [String], promptText: String) throws -> String {
        called = true
        throw Tripped()
    }
}

/// A fake dispatcher returning canned stdout per call. Records every
/// (argv, prompt). NEVER shells out. Once outputs are exhausted it returns
/// "{}" (Layer-1 parse yields no usage -> Layer-3 degradation).
final class RecordingFakeDispatcher: Dispatching, @unchecked Sendable {
    private(set) var calls: [(argv: [String], prompt: String)] = []
    var outputs: [String]

    init(outputs: [String] = []) { self.outputs = outputs }

    func run(argv: [String], promptText: String) throws -> String {
        calls.append((argv, promptText))
        return outputs.isEmpty ? "{}" : outputs.removeFirst()
    }
}

/// A budget-estimate runner yielding a fixed cost via estimate-calc.py-shaped
/// JSON so the REAL parse path is exercised without a subprocess.
func fakeEstimateRunner(_ perStageUSD: Double) -> ([String]) throws -> String {
    { _ in "{\"ai_cost\": {\"usd\": \(perStageUSD)}}" }
}

/// Fake `claude auth status --json` runners.
func loggedOutRunner() -> String { "{\"loggedIn\": false}" }
func loggedInRunner() -> String {
    // Includes identity fields exactly like the real CLI, to prove hasCLILogin
    // never surfaces them past the boolean.
    "{\"loggedIn\": true, \"authMethod\": \"claude.ai\", "
        + "\"email\": \"canary@example.invalid\", \"orgId\": \"org-canary\"}"
}

/// Repo root, resolved from this source file's location.
let liveTestsRepoRoot: String = {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // BenchmarkLiveTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // harness
        .deletingLastPathComponent()   // benchmark
        .deletingLastPathComponent()   // repo root
        .path
}()

/// Make a temp "benchmark dir" with a prompts dir containing minimal stage
/// bodies, so Dispatch.dispatch can run fully injected. Returns
/// (benchmarkDir, promptsDir, recordPath).
func makeLiveSandbox(stages: [String] = Budget.pipelineStages)
    throws -> (benchmarkDir: String, promptsDir: String, recordPath: String) {
    let base = NSTemporaryDirectory() + "live-sandbox-\(UUID().uuidString)"
    let prompts = base + "/live/prompts"
    try FileManager.default.createDirectory(atPath: prompts, withIntermediateDirectories: true)
    for stage in stages {
        try "\(stage.lowercased()) task body\n".write(
            toFile: prompts + "/\(stage.lowercased()).txt", atomically: true, encoding: .utf8)
    }
    return (base, prompts, base + "/rec.json")
}

/// Extract a section body between <<<marker>>> and the next <<<...>>> tag.
/// Mirrors cache-lint.sh extract_section so tests assert the SAME slicing the
/// production lint uses over a captured prompt-log.
func section(_ prompt: String, _ marker: String) -> String {
    var out: [String] = []
    var capturing = false
    for ln in prompt.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
        if ln == marker { capturing = true; continue }
        if capturing && ln.hasPrefix("<<<") && ln.hasSuffix(">>>") { break }
        if capturing { out.append(ln) }
    }
    return out.joined(separator: "\n")
}
