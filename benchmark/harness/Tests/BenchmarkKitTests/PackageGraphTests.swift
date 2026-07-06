// PackageGraphTests.swift — AC-8 as a link-level guarantee (AR decision ad4).
//
// The Python AC-8 tripwire was import-graph based (test_live_gate.py failed if
// any benchmark/live/ module entered sys.modules on the deterministic path).
// Swift converts this to a STATIC dependency-graph assertion: parse this
// package's manifest via `swift package dump-package` and assert the
// deterministic executables' dependency closures never name BenchmarkLive.

import Foundation
import Testing
@testable import BenchmarkKit

/// Path to the harness package dir (this file: Tests/BenchmarkKitTests/…).
private let packageDir: String = {
    let f = URL(fileURLWithPath: #filePath)
    return f.deletingLastPathComponent()      // BenchmarkKitTests
        .deletingLastPathComponent()          // Tests
        .deletingLastPathComponent()          // harness
        .path
}()

private struct ManifestTarget {
    var name: String
    var dependencies: [String]
}

/// One memoized dump-package call for the whole suite. Uses an isolated
/// --scratch-path: running dump-package against the package's own .build while
/// `swift test` holds its lock deadlocks (observed live) — the temp scratch
/// dir sidesteps the lock entirely.
private let dumpedTargets: [ManifestTarget] = {
    let scratch = NSTemporaryDirectory() + "dump-package-scratch-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: scratch) }
    let result = Subprocess.run(["swift", "package", "dump-package",
                                 "--package-path", packageDir,
                                 "--scratch-path", scratch])
    guard result.exitCode == 0,
          let parsed = try? JSONParser.parse(result.stdout) else { return [] }
    var targets: [ManifestTarget] = []
    for t in parsed["targets"]?.arrayItems ?? [] {
        let name = t["name"]?.stringValue ?? ""
        var deps: [String] = []
        for d in t["dependencies"]?.arrayItems ?? [] {
            // dependency form: {"byName": ["BenchmarkKit", null]} or {"target": [...]}
            for key in ["byName", "target", "product"] {
                if let arr = d[key]?.arrayItems, let first = arr.first?.stringValue {
                    deps.append(first)
                }
            }
        }
        targets.append(ManifestTarget(name: name, dependencies: deps))
    }
    return targets
}()

private func dumpTargets() throws -> [ManifestTarget] {
    #expect(!dumpedTargets.isEmpty, "dump-package produced no targets")
    return dumpedTargets
}

/// Transitive dependency closure of `target` within the manifest graph.
private func closure(of target: String, in targets: [ManifestTarget]) -> Set<String> {
    var seen = Set<String>()
    var stack = [target]
    let byName = Dictionary(uniqueKeysWithValues: targets.map { ($0.name, $0) })
    while let t = stack.popLast() {
        guard let node = byName[t] else { continue }
        for d in node.dependencies where !seen.contains(d) {
            seen.insert(d)
            stack.append(d)
        }
    }
    return seen
}

@Suite("Package dependency graph (AC-8 link-level)")
struct PackageGraph {
    @Test func benchDeterministicNeverDependsOnBenchmarkLive() throws {
        let targets = try dumpTargets()
        let deps = closure(of: "bench-deterministic", in: targets)
        #expect(deps.contains("BenchmarkKit"))
        #expect(!deps.contains("BenchmarkLive"),
                "AC-8 violated: bench-deterministic links the live world")
    }

    @Test func benchReportNeverDependsOnBenchmarkLive() throws {
        let targets = try dumpTargets()
        let deps = closure(of: "bench-report", in: targets)
        #expect(deps.contains("BenchmarkKit"))
        #expect(!deps.contains("BenchmarkLive"),
                "AC-8 violated: bench-report links the live world")
    }

    @Test func benchmarkKitHasNoDependencies() throws {
        // The deterministic library itself must be leaf (no live, no external).
        let targets = try dumpTargets()
        let kit = targets.first(where: { $0.name == "BenchmarkKit" })
        #expect(kit != nil)
        #expect(kit?.dependencies.isEmpty == true,
                "BenchmarkKit must be dependency-free, got \(kit?.dependencies ?? [])")
    }

    @Test func benchLiveIsTheOnlyExecutableLinkingBenchmarkLive() throws {
        let targets = try dumpTargets()
        let liveLinkers = targets.filter {
            closure(of: $0.name, in: targets).contains("BenchmarkLive")
        }.map(\.name).sorted()
        #expect(liveLinkers == ["BenchmarkLiveTests", "bench-live"],
                "unexpected BenchmarkLive linkers: \(liveLinkers)")
    }
}
