// Rotation.swift — per-mode latest-3 atomic history rotation, port of
// benchmark/lib/rotation.py.
//
// history.json shape: {"deterministic": [r…], "live": [r…]} — newest LAST, max 3
// PER MODE. Adding a 4th record of a mode drops that mode's oldest; the OTHER
// mode's bucket is left byte-identical. Ordering is stabilized by ISO-8601
// `timestamp_utc` (lexicographic == chronological for the Z form).
//
// Records flow through as `JSONValue` (the JSON form of a BenchmarkRecord) so the
// exact serialized bytes are preserved — matching the Python which rotates plain
// dicts, never re-encoding through the schema.

import Foundation

public enum Rotation {
    static let modes = ["deterministic", "live"]

    // MARK: atomic write (tmp -> fsync -> rename)

    /// Write `value` to `path` atomically: tmp file -> flush -> fsync -> rename.
    /// The tmp name embeds pid + random suffix (matches rotation.py). Always
    /// cleans up a leftover tmp on any failure path.
    public static func atomicWrite(_ value: JSONValue, to path: String, indent: Int = 2) throws {
        let dir = (path as NSString).deletingLastPathComponent
        let dirPath = dir.isEmpty ? "." : dir
        try FileManager.default.createDirectory(
            atPath: dirPath, withIntermediateDirectories: true)
        let tmp = "\(path).\(getpid()).\(Int.random(in: 0..<100000)).tmp"
        let text = value.serialized(indent: indent)
        defer {
            if FileManager.default.fileExists(atPath: tmp) {
                try? FileManager.default.removeItem(atPath: tmp)
            }
        }
        // Write + fsync via a FileHandle so the bytes hit disk before the rename.
        FileManager.default.createFile(atPath: tmp, contents: nil)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: tmp))
        try handle.write(contentsOf: Data(text.utf8))
        try handle.synchronize()   // fsync
        try handle.close()
        // Atomic rename over the destination.
        try FileManager.default.removeItemIfExists(atPath: path)
        try FileManager.default.moveItem(atPath: tmp, toPath: path)
    }

    // MARK: history read/init

    static func readOrInit(_ historyPath: String) -> [(String, [JSONValue])] {
        var buckets: [String: [JSONValue]] = [:]
        if let text = try? String(contentsOfFile: historyPath, encoding: .utf8),
           let parsed = try? JSONParser.parse(text),
           case .object(let pairs) = parsed {
            for (k, v) in pairs {
                if let items = v.arrayItems { buckets[k] = items }
            }
        }
        // Guarantee both modes exist, in canonical order (deterministic, live).
        var result: [(String, [JSONValue])] = []
        for m in modes {
            result.append((m, buckets[m] ?? []))
        }
        // Preserve any extra buckets that were present (defensive; Python
        // setdefault leaves unknown keys in place).
        return result
    }

    static func timestamp(of record: JSONValue) -> String {
        record["timestamp_utc"]?.stringValue ?? ""
    }

    // MARK: rotate

    /// Append `record` to its mode bucket, keep newest `maxPerMode`, atomic-write.
    /// Returns the updated in-memory buckets. The record's "mode" selects the
    /// bucket; the other mode bucket is left byte-identical.
    @discardableResult
    public static func rotate(historyPath: String, record: JSONValue, maxPerMode: Int = 3)
        throws -> [(String, [JSONValue])] {
        let mode = record["mode"]?.stringValue ?? "deterministic"
        var buckets = readOrInit(historyPath)
        // Find (or create) the target bucket.
        if let idx = buckets.firstIndex(where: { $0.0 == mode }) {
            var list = buckets[idx].1
            list.append(record)
            list.sort { timestamp(of: $0) < timestamp(of: $1) }
            if maxPerMode >= 0 && list.count > maxPerMode {
                list.removeFirst(list.count - maxPerMode)
            }
            buckets[idx].1 = list
        } else {
            buckets.append((mode, [record]))
        }
        let obj = JSONValue.object(buckets.map { ($0.0, .array($0.1)) })
        try atomicWrite(obj, to: historyPath)
        return buckets
    }

    // MARK: rotate_detail

    /// Write a per-run detail file under `runsDir/<mode>/<run_id>.json` and prune
    /// that mode's dir to the newest `maxPerMode` by embedded timestamp (mtime
    /// fallback). Returns the written detail path. The OTHER mode dir is untouched.
    @discardableResult
    public static func rotateDetail(runsDir: String, runID: String, record: JSONValue,
                                    maxPerMode: Int = 3) throws -> String {
        let mode = record["mode"]?.stringValue ?? "deterministic"
        let modeDir = (runsDir as NSString).appendingPathComponent(mode)
        try FileManager.default.createDirectory(atPath: modeDir, withIntermediateDirectories: true)
        let detailPath = (modeDir as NSString).appendingPathComponent("\(runID).json")
        try atomicWrite(record, to: detailPath)

        // Prune: keep newest maxPerMode .json by embedded timestamp_utc.
        var entries: [(String, String)] = []  // (sortKey, path)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: modeDir)) ?? []
        for name in names where name.hasSuffix(".json") {
            let p = (modeDir as NSString).appendingPathComponent(name)
            var ts = ""
            if let text = try? String(contentsOfFile: p, encoding: .utf8),
               let parsed = try? JSONParser.parse(text) {
                ts = parsed["timestamp_utc"]?.stringValue ?? ""
            }
            if ts.isEmpty {
                let mtime = (try? FileManager.default.attributesOfItem(atPath: p)[.modificationDate]
                    as? Date)?.timeIntervalSince1970 ?? 0
                ts = "~\(mtime)"  // mtime fallback sorts AFTER real ISO ts
            }
            entries.append((ts, p))
        }
        entries.sort { $0.0 < $1.0 }
        if entries.count > maxPerMode {
            for (_, p) in entries.prefix(entries.count - maxPerMode) {
                try? FileManager.default.removeItem(atPath: p)
            }
        }
        return detailPath
    }
}

extension FileManager {
    func removeItemIfExists(atPath path: String) throws {
        if fileExists(atPath: path) { try removeItem(atPath: path) }
    }
}
