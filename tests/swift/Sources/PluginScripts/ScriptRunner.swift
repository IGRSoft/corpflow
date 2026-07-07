// ScriptRunner.swift — subprocess + JSON helpers for shelling python3 to the
// plugin's skill scripts. No network; python3 is a hard host prerequisite
// (AC-1 environment contract, unchanged).

import Foundation

public struct ScriptResult {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    /// stdout parsed as a JSON object (nil when not a dict / not JSON).
    public var json: [String: Any]? {
        guard let data = stdout.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return obj as? [String: Any]
    }
}

public enum ScriptRunner {
    /// Run `python3 <script> <args...>`, capturing stdout/stderr.
    public static func run(script: String, _ args: [String]) -> ScriptResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script] + args
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return ScriptResult(exitCode: 127, stdout: "", stderr: "spawn failed: \(error)")
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ScriptResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self))
    }
}

// MARK: - JSON access helpers

public extension [String: Any] {
    func dict(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }
    func double(_ key: String) -> Double? {
        if let d = self[key] as? Double { return d }
        if let i = self[key] as? Int { return Double(i) }
        return nil
    }
    func int(_ key: String) -> Int? { self[key] as? Int }
    func string(_ key: String) -> String? { self[key] as? String }
    func bool(_ key: String) -> Bool? { self[key] as? Bool }
}
