// GenLib.swift — shared helpers for the two deterministic generators, port of
// benchmark/lib/genlib.py adapted to the Swift TTT fixture.
//
// Owns: locating PLUGIN_ROOT / ttt-template, copying the template into a per-side
// workdir (staged or single-shot), running the generated app's Swift Testing
// suite (parsing REAL test_count/pass_fail), counting REAL loc_produced (*.swift),
// and building a PathMetrics from measured values. Never imports BenchmarkLive.
//
// AR contract deltas honored here:
//   - locCount counts *.swift, EXCLUDING .build/ and .swiftpm/ (was *.py).
//   - runAppTests: pass_fail from the exit code ONLY (never parse success text);
//     test_count from the Swift Testing summary regex `Test run with (\d+) test`.
//   - staged copy = one stage per Sources/TicTacToeKit/<subdir> + executable +
//     Tests (was one-per-.py). stage_count is a process-overhead signal; the
//     exact count is NOT a contract (assert >1 WITH, ==1 WITHOUT).

import Foundation

public enum GenLib {
    // MARK: path anchoring

    /// Repo root. Resolved from the running binary's location when possible,
    /// else from an explicit override (tests inject a temp template).
    public static func pluginRoot(from benchmarkDir: String) -> String {
        (benchmarkDir as NSString).deletingLastPathComponent
    }

    // MARK: monotonic timer

    /// Monotonic wall-clock timer. `elapsed` is seconds since `start()`.
    public final class Timer {
        private var t0: UInt64 = 0
        public init() {}
        public func start() { t0 = DispatchTime.now().uptimeNanoseconds }
        public var elapsed: Double {
            Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000_000
        }
        /// Time a closure, returning (result, elapsedSeconds).
        public static func measure<T>(_ body: () throws -> T) rethrows -> (T, Double) {
            let t = Timer(); t.start()
            let r = try body()
            return (r, t.elapsed)
        }
    }

    // MARK: template copy

    static let ignoredDirNames: Set<String> = [".build", ".swiftpm", "__pycache__"]

    private static func copyTree(from src: String, to dest: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: dest, withIntermediateDirectories: true)
        for name in (try? fm.contentsOfDirectory(atPath: src)) ?? [] {
            if ignoredDirNames.contains(name) || name.hasSuffix(".pyc") { continue }
            let s = (src as NSString).appendingPathComponent(name)
            let d = (dest as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: s, isDirectory: &isDir)
            if isDir.boolValue {
                try copyTree(from: s, to: d)
            } else {
                try? fm.removeItem(atPath: d)
                try fm.copyItem(atPath: s, toPath: d)
            }
        }
    }

    /// WITHOUT path: copy the whole template in ONE operation. Returns op count (1).
    @discardableResult
    public static func copyTemplateSingleShot(templateDir: String, dest: String) throws -> Int {
        let fm = FileManager.default
        try fm.removeItemIfExists(atPath: dest)
        try copyTree(from: templateDir, to: dest)
        return 1
    }

    /// WITH path: materialize the template as N discrete staged operations.
    /// One stage per Sources/TicTacToeKit/<subdir> + one for the executable +
    /// one for Package.swift + one for Tests. Returns the staged-op count.
    @discardableResult
    public static func copyTemplateStaged(templateDir: String, dest: String) throws -> Int {
        let fm = FileManager.default
        try fm.removeItemIfExists(atPath: dest)
        try fm.createDirectory(atPath: dest, withIntermediateDirectories: true)
        var stages = 0

        // Stage 1: Package.swift (+ any top-level manifest files).
        let manifest = (templateDir as NSString).appendingPathComponent("Package.swift")
        if fm.fileExists(atPath: manifest) {
            try fm.copyItem(atPath: manifest,
                            toPath: (dest as NSString).appendingPathComponent("Package.swift"))
            stages += 1
        }

        // Stage 2..N: one stage per Sources/TicTacToeKit/<subdir>, then the exe.
        let kitSrc = templateDir + "/Sources/TicTacToeKit"
        let kitDst = dest + "/Sources/TicTacToeKit"
        if fm.fileExists(atPath: kitSrc) {
            let subdirs = ((try? fm.contentsOfDirectory(atPath: kitSrc)) ?? []).sorted()
            for sub in subdirs {
                if ignoredDirNames.contains(sub) { continue }
                let s = (kitSrc as NSString).appendingPathComponent(sub)
                let d = (kitDst as NSString).appendingPathComponent(sub)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: s, isDirectory: &isDir)
                if isDir.boolValue {
                    try copyTree(from: s, to: d)
                } else {
                    try fm.createDirectory(atPath: kitDst, withIntermediateDirectories: true)
                    try fm.copyItem(atPath: s, toPath: d)
                }
                stages += 1
            }
        }

        // Executable target stage.
        let exeSrc = templateDir + "/Sources/tictactoe"
        if fm.fileExists(atPath: exeSrc) {
            try copyTree(from: exeSrc, to: dest + "/Sources/tictactoe")
            stages += 1
        }

        // Final stage: Tests dir.
        let testsSrc = (templateDir as NSString).appendingPathComponent("Tests")
        if fm.fileExists(atPath: testsSrc) {
            try copyTree(from: testsSrc, to: (dest as NSString).appendingPathComponent("Tests"))
            stages += 1
        }

        return stages
    }

    // MARK: measurement

    /// REAL loc_produced: non-blank, non-pure-comment lines across all generated
    /// *.swift files (excluding .build/.swiftpm).
    public static func countLOC(appDir: String) -> Int {
        var total = 0
        let fm = FileManager.default
        guard let e = fm.enumerator(atPath: appDir) else { return 0 }
        for case let rel as String in e {
            if rel.contains(".build/") || rel.contains(".swiftpm/") { continue }
            guard rel.hasSuffix(".swift") else { continue }
            let full = (appDir as NSString).appendingPathComponent(rel)
            guard let text = try? String(contentsOfFile: full, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let s = line.trimmingCharacters(in: .whitespaces)
                if !s.isEmpty && !s.hasPrefix("//") { total += 1 }
            }
        }
        return total
    }

    /// Run the generated app's Swift Testing suite. Returns (test_count, pass_fail).
    /// test_count parsed from the Swift Testing summary line
    /// `Test run with N test(s) ...`; pass_fail from the EXIT CODE only.
    ///
    /// OI-1 (P1): the nested `swift test` materializes a ~150MB `.build/` cache
    /// INSIDE `appDir`. Nothing downstream reads it (loc counts *.swift and skips
    /// `.build/`; metrics reference only `appDir`/Package.swift), so it is the
    /// ephemeral heavy artifact. A `defer` sweeps it on EVERY exit path (normal
    /// return OR a thrown parse error), scoped strictly to `appDir/.build` so the
    /// caller's measured app copy and any `--workdir`/`--record` path survive
    /// (R3). This bounds residue to the app sources, not the build cache — the
    /// two ENOSPC-killed live attempts were this cache accumulating across runs.
    public static func runAppTests(appDir: String) -> (testCount: Int, passFail: String) {
        let buildDir = (appDir as NSString).appendingPathComponent(".build")
        defer { try? FileManager.default.removeItemIfExists(atPath: buildDir) }
        let result = Subprocess.run(
            ["swift", "test", "--package-path", appDir],
            cwd: appDir
        )
        let combined = result.stdout + result.stderr
        let count = parseTestCount(combined)
        let passFail = result.exitCode == 0 ? "pass" : "fail"
        return (count, passFail)
    }

    /// Parse the Swift Testing suite size from a run log. Matches lines like
    /// "Test run with 27 tests" / "✔ Test run with 1 test passed". Falls back to
    /// XCTest-style "Executed N tests" if present. 0 when unparseable.
    public static func parseTestCount(_ log: String) -> Int {
        // Swift Testing: "Test run with N test(s)"
        if let n = firstMatchInt(log, pattern: #"Test run with (\d+) test"#) { return n }
        // XCTest fallback: "Executed N tests"
        if let n = firstMatchInt(log, pattern: #"Executed (\d+) test"#) { return n }
        return 0
    }

    private static func firstMatchInt(_ text: String, pattern: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return Int(text[r])
    }

    /// Build a PathMetrics from measured values (tokens null in deterministic).
    public static func buildPathMetrics(
        appDir: String, pluginRoot: String, stageCount: Int, estimateComplexityScore: Int,
        costUSD: Double?, wallClockS: Double
    ) -> PathMetrics {
        let (testCount, passFail) = runAppTests(appDir: appDir)
        let loc = countLOC(appDir: appDir)
        // Repo-relative app_path so committed history never leaks an absolute path.
        let appPath = relativePath(appDir, from: pluginRoot)
        return PathMetrics(
            tokens: Tokens(input: nil, output: nil, total: nil),
            costUSD: costUSD,
            wallClockS: (wallClockS * 10000).rounded() / 10000,
            locProduced: loc,
            testCount: testCount,
            coveragePct: 0.0,
            estimateComplexityScore: estimateComplexityScore,
            stageCount: stageCount,
            passFail: passFail,
            appPath: appPath
        )
    }

    static func relativePath(_ path: String, from base: String) -> String {
        let p = (path as NSString).standardizingPath
        let b = (base as NSString).standardizingPath
        if p.hasPrefix(b + "/") { return String(p.dropFirst(b.count + 1)) }
        return p
    }
}

// MARK: - Subprocess helper (shared by GenLib / Generators / bench-*)

public struct Subprocess {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    /// Run `argv` synchronously, capturing stdout/stderr. `input` is fed on stdin.
    @discardableResult
    public static func run(_ argv: [String], cwd: String? = nil, input: String? = nil,
                           env: [String: String]? = nil) -> Subprocess {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = argv
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        if let env { process.environment = env }

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let inPipe = Pipe()
        if input != nil {
            process.standardInput = inPipe
        } else {
            // Never inherit the caller's stdin: in nested/headless contexts an
            // inherited tty/pipe stdin can block a child (claude auth status,
            // estimate-calc.py, …) forever. No input => explicit EOF.
            process.standardInput = FileHandle.nullDevice
        }

        // Drain pipes on background queues to avoid deadlock on large output.
        // Lock-protected boxes keep the closure captures Sendable-safe.
        let outBox = DataBox(), errBox = DataBox()
        let group = DispatchGroup()
        let q = DispatchQueue(label: "subprocess.drain", attributes: .concurrent)
        do {
            try process.run()
        } catch {
            return Subprocess(exitCode: 127, stdout: "", stderr: "spawn failed: \(error)")
        }
        if let input {
            inPipe.fileHandleForWriting.write(Data(input.utf8))
            try? inPipe.fileHandleForWriting.close()
        }
        group.enter()
        q.async { outBox.store(outPipe.fileHandleForReading.readDataToEndOfFile()); group.leave() }
        group.enter()
        q.async { errBox.store(errPipe.fileHandleForReading.readDataToEndOfFile()); group.leave() }
        process.waitUntilExit()
        group.wait()
        return Subprocess(
            exitCode: process.terminationStatus,
            stdout: String(decoding: outBox.value, as: UTF8.self),
            stderr: String(decoding: errBox.value, as: UTF8.self)
        )
    }
}

/// Thread-safe byte buffer for pipe draining (avoids captured-var mutation in
/// concurrently-executing code).
private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func store(_ d: Data) { lock.lock(); data = d; lock.unlock() }
    var value: Data { lock.lock(); defer { lock.unlock() }; return data }
}
