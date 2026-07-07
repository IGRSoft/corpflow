// Metrics.swift — frozen BenchmarkRecord schema, key-for-key port of
// benchmark/lib/metrics.py.
//
// On-disk JSON MUST stay byte-compatible with the Python `json.dumps(indent=2,
// sort_keys=False)` output so existing benchmark/results/history.json still
// decodes and newly written records stay diff-comparable. To achieve that this
// file uses `OrderedJSON` (a tiny ordered JSON value/serializer below) rather
// than `JSONEncoder` — Foundation's encoder cannot guarantee key order or emit
// Python-style pretty-printing, and Codable's `encodeNil` on optionals is
// awkward to make positional. Ordered emission + explicit nulls are the whole
// contract here (AR deltas D1/D2/D4).
//
// AR deltas implemented:
//   D1 — Tokens ALWAYS emits all 5 keys (in,out,total,cache_read,cache_creation),
//        value-or-null. Only `stages` and `live_partial` are omit-when-empty.
//   D2 — StageAttribution flat shape (stage,fresh_in,cache_creation,cache_read,
//        out,cost_usd) + optional additive `coverage` object appended AFTER
//        cost_usd, encoded ONLY when present (produced by BenchmarkLive in live).
//   D4 — PathMetrics carries a trailing nullable `app_path` (repo-relative).

import Foundation

public enum Mode: String, Sendable, Codable {
    case deterministic
    case live
}

// MARK: - Ordered JSON value + serializer (Python json.dumps(indent=2) parity)

/// A minimal ordered JSON value used for byte-stable serialization. Object keys
/// preserve insertion order (Python `sort_keys=False`). Numbers are emitted the
/// way Python's `json` module emits them (ints without a decimal, floats via
/// `repr`-equivalent shortest round-trip — Swift's `Double` description matches
/// Python's `repr` for the values we emit, including trailing-zero artifacts).
public indirect enum JSONValue: Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    /// Ordered object: array of (key, value) pairs, insertion-ordered.
    case object([(String, JSONValue)])

    /// Serialize with Python `json.dumps(indent=2, sort_keys=False)` semantics.
    public func serialized(indent: Int = 2) -> String {
        var out = ""
        write(into: &out, level: 0, indent: indent)
        return out
    }

    private func write(into out: inout String, level: Int, indent: Int) {
        let pad = String(repeating: " ", count: indent * (level + 1))
        let closePad = String(repeating: " ", count: indent * level)
        switch self {
        case .null:
            out += "null"
        case .bool(let b):
            out += b ? "true" : "false"
        case .int(let i):
            out += String(i)
        case .double(let d):
            out += Self.pyFloat(d)
        case .string(let s):
            out += Self.encodeString(s)
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "[\n"
            for (idx, item) in items.enumerated() {
                out += pad
                item.write(into: &out, level: level + 1, indent: indent)
                out += idx == items.count - 1 ? "\n" : ",\n"
            }
            out += closePad + "]"
        case .object(let pairs):
            if pairs.isEmpty { out += "{}"; return }
            out += "{\n"
            for (idx, pair) in pairs.enumerated() {
                out += pad + Self.encodeString(pair.0) + ": "
                pair.1.write(into: &out, level: level + 1, indent: indent)
                out += idx == pairs.count - 1 ? "\n" : ",\n"
            }
            out += closePad + "}"
        }
    }

    /// Match Python's float repr: integers-valued floats keep `.0`, others use
    /// the shortest round-trippable form (Swift `Double.description` == Python
    /// `repr` for IEEE-754 doubles).
    static func pyFloat(_ d: Double) -> String {
        if d == d.rounded() && d.isFinite && abs(d) < 1e16 {
            return String(format: "%.1f", d)
        }
        return d.description
    }

    static func encodeString(_ s: String) -> String {
        // Python json escapes the standard control set and " and \.
        var r = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": r += "\\\""
            case "\\": r += "\\\\"
            case "\n": r += "\\n"
            case "\r": r += "\\r"
            case "\t": r += "\\t"
            default:
                if scalar.value < 0x20 {
                    r += String(format: "\\u%04x", scalar.value)
                } else {
                    r.unicodeScalars.append(scalar)
                }
            }
        }
        r += "\""
        return r
    }
}

// MARK: - Loosely-typed JSON parser (for decode + round-trip)

/// A tiny recursive-descent JSON parser producing `JSONValue`, preserving object
/// key order and distinguishing Int from Double. Used so decode/round-trip does
/// not depend on Foundation's `JSONSerialization` number typing (which promotes
/// everything to NSNumber and loses the int/float distinction we need for
/// byte-stable re-emission).
public enum JSONParser {
    public enum ParseError: Error { case malformed(String) }

    public static func parse(_ text: String) throws -> JSONValue {
        let scalars = Array(text.unicodeScalars)
        var i = 0
        skipWS(scalars, &i)
        let v = try parseValue(scalars, &i)
        skipWS(scalars, &i)
        if i != scalars.count { throw ParseError.malformed("trailing content") }
        return v
    }

    private static func skipWS(_ s: [Unicode.Scalar], _ i: inout Int) {
        while i < s.count, s[i] == " " || s[i] == "\n" || s[i] == "\t" || s[i] == "\r" { i += 1 }
    }

    private static func parseValue(_ s: [Unicode.Scalar], _ i: inout Int) throws -> JSONValue {
        guard i < s.count else { throw ParseError.malformed("eof") }
        switch s[i] {
        case "{": return try parseObject(s, &i)
        case "[": return try parseArray(s, &i)
        case "\"": return .string(try parseString(s, &i))
        case "t", "f": return try parseBool(s, &i)
        case "n": try expect(s, &i, "null"); return .null
        default: return try parseNumber(s, &i)
        }
    }

    private static func parseObject(_ s: [Unicode.Scalar], _ i: inout Int) throws -> JSONValue {
        i += 1 // {
        var pairs: [(String, JSONValue)] = []
        skipWS(s, &i)
        if i < s.count, s[i] == "}" { i += 1; return .object(pairs) }
        while true {
            skipWS(s, &i)
            let key = try parseString(s, &i)
            skipWS(s, &i)
            guard i < s.count, s[i] == ":" else { throw ParseError.malformed("expected :") }
            i += 1
            skipWS(s, &i)
            let val = try parseValue(s, &i)
            pairs.append((key, val))
            skipWS(s, &i)
            guard i < s.count else { throw ParseError.malformed("eof in object") }
            if s[i] == "," { i += 1; continue }
            if s[i] == "}" { i += 1; break }
            throw ParseError.malformed("expected , or }")
        }
        return .object(pairs)
    }

    private static func parseArray(_ s: [Unicode.Scalar], _ i: inout Int) throws -> JSONValue {
        i += 1 // [
        var items: [JSONValue] = []
        skipWS(s, &i)
        if i < s.count, s[i] == "]" { i += 1; return .array(items) }
        while true {
            skipWS(s, &i)
            items.append(try parseValue(s, &i))
            skipWS(s, &i)
            guard i < s.count else { throw ParseError.malformed("eof in array") }
            if s[i] == "," { i += 1; continue }
            if s[i] == "]" { i += 1; break }
            throw ParseError.malformed("expected , or ]")
        }
        return .array(items)
    }

    private static func parseString(_ s: [Unicode.Scalar], _ i: inout Int) throws -> String {
        guard i < s.count, s[i] == "\"" else { throw ParseError.malformed("expected string") }
        i += 1
        var out = String.UnicodeScalarView()
        while i < s.count {
            let c = s[i]; i += 1
            if c == "\"" { return String(out) }
            if c == "\\" {
                guard i < s.count else { throw ParseError.malformed("eof in escape") }
                let e = s[i]; i += 1
                switch e {
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                case "/": out.append("/")
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "b": out.append("\u{08}")
                case "f": out.append("\u{0C}")
                case "u":
                    let hex = String(String.UnicodeScalarView(s[i..<min(i + 4, s.count)]))
                    i += 4
                    if let code = UInt32(hex, radix: 16), let sc = Unicode.Scalar(code) {
                        out.append(sc)
                    }
                default: throw ParseError.malformed("bad escape")
                }
            } else {
                out.append(c)
            }
        }
        throw ParseError.malformed("unterminated string")
    }

    private static func parseBool(_ s: [Unicode.Scalar], _ i: inout Int) throws -> JSONValue {
        if s[i] == "t" { try expect(s, &i, "true"); return .bool(true) }
        try expect(s, &i, "false"); return .bool(false)
    }

    private static func parseNumber(_ s: [Unicode.Scalar], _ i: inout Int) throws -> JSONValue {
        let start = i
        var isDouble = false
        while i < s.count {
            let c = s[i]
            if c == "-" || c == "+" || (c >= "0" && c <= "9") { i += 1 }
            else if c == "." || c == "e" || c == "E" { isDouble = true; i += 1 }
            else { break }
        }
        let str = String(String.UnicodeScalarView(s[start..<i]))
        if isDouble {
            guard let d = Double(str) else { throw ParseError.malformed("bad number") }
            return .double(d)
        }
        if let n = Int(str) { return .int(n) }
        guard let d = Double(str) else { throw ParseError.malformed("bad number") }
        return .double(d)
    }

    private static func expect(_ s: [Unicode.Scalar], _ i: inout Int, _ lit: String) throws {
        for ch in lit.unicodeScalars {
            guard i < s.count, s[i] == ch else { throw ParseError.malformed("expected \(lit)") }
            i += 1
        }
    }
}

// Convenience accessors used by decode paths.
public extension JSONValue {
    var objectPairs: [(String, JSONValue)]? {
        if case .object(let p) = self { return p }
        return nil
    }
    var arrayItems: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
    subscript(_ key: String) -> JSONValue? {
        guard case .object(let pairs) = self else { return nil }
        return pairs.first(where: { $0.0 == key })?.1
    }
    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d) where d == d.rounded(): return Int(d)
        default: return nil
        }
    }
    /// Number as Double (int or double), else nil. `.null`/absent -> nil.
    var doubleValue: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d
        default: return nil
        }
    }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    var isNull: Bool { if case .null = self { return true }; return false }
}

// MARK: - Tokens (D1)

public struct Tokens: Sendable, Equatable {
    public var input: Int?          // JSON "in"
    public var output: Int?         // JSON "out"
    public var total: Int?          // JSON "total" (= fresh in + out; cache separate)
    public var cacheRead: Int?      // JSON "cache_read"
    public var cacheCreation: Int?  // JSON "cache_creation"

    public init(input: Int? = nil, output: Int? = nil, total: Int? = nil,
                cacheRead: Int? = nil, cacheCreation: Int? = nil) {
        self.input = input
        self.output = output
        self.total = total
        self.cacheRead = cacheRead
        self.cacheCreation = cacheCreation
    }

    /// D1: ALL 5 keys always emitted (value or null), in this fixed order.
    public func toJSON() -> JSONValue {
        .object([
            ("in", input.map(JSONValue.int) ?? .null),
            ("out", output.map(JSONValue.int) ?? .null),
            ("total", total.map(JSONValue.int) ?? .null),
            ("cache_read", cacheRead.map(JSONValue.int) ?? .null),
            ("cache_creation", cacheCreation.map(JSONValue.int) ?? .null),
        ])
    }

    /// Decode. Legacy dicts lacking cache keys -> nil (never fabricate).
    public static func fromJSON(_ v: JSONValue?) -> Tokens {
        guard let v else { return Tokens() }
        return Tokens(
            input: v["in"]?.intValue,
            output: v["out"]?.intValue,
            total: v["total"]?.intValue,
            cacheRead: v["cache_read"]?.intValue,
            cacheCreation: v["cache_creation"]?.intValue
        )
    }
}

// MARK: - coverage (D2, additive option-1 field)

/// Per-stage plugin-surface coverage manifest. Whole object is omitted when nil.
public struct StageCoverage: Sendable, Equatable {
    public var agents: [String]
    public var skills: [String]
    public var commands: [String]
    public var toolCalls: Int

    public init(agents: [String], skills: [String], commands: [String], toolCalls: Int) {
        self.agents = agents
        self.skills = skills
        self.commands = commands
        self.toolCalls = toolCalls
    }

    public func toJSON() -> JSONValue {
        .object([
            ("agents", .array(agents.map(JSONValue.string))),
            ("skills", .array(skills.map(JSONValue.string))),
            ("commands", .array(commands.map(JSONValue.string))),
            ("tool_calls", .int(toolCalls)),
        ])
    }

    public static func fromJSON(_ v: JSONValue?) -> StageCoverage? {
        guard let v, case .object = v else { return nil }
        let agents = (v["agents"]?.arrayItems ?? []).compactMap(\.stringValue)
        let skills = (v["skills"]?.arrayItems ?? []).compactMap(\.stringValue)
        let commands = (v["commands"]?.arrayItems ?? []).compactMap(\.stringValue)
        let toolCalls = v["tool_calls"]?.intValue ?? 0
        return StageCoverage(agents: agents, skills: skills, commands: commands, toolCalls: toolCalls)
    }
}

// MARK: - StageAttribution (D2)

public struct StageAttribution: Sendable, Equatable {
    public var stage: String
    public var freshIn: Int?
    public var cacheCreation: Int?
    public var cacheRead: Int?
    public var out: Int?
    public var costUSD: Double?
    /// NEW additive option-1 field; encoded ONLY when present (after cost_usd).
    public var coverage: StageCoverage?

    public init(stage: String, freshIn: Int?, cacheCreation: Int?, cacheRead: Int?,
                out: Int?, costUSD: Double?, coverage: StageCoverage? = nil) {
        self.stage = stage
        self.freshIn = freshIn
        self.cacheCreation = cacheCreation
        self.cacheRead = cacheRead
        self.out = out
        self.costUSD = costUSD
        self.coverage = coverage
    }

    public func toJSON() -> JSONValue {
        var pairs: [(String, JSONValue)] = [
            ("stage", .string(stage)),
            ("fresh_in", freshIn.map(JSONValue.int) ?? .null),
            ("cache_creation", cacheCreation.map(JSONValue.int) ?? .null),
            ("cache_read", cacheRead.map(JSONValue.int) ?? .null),
            ("out", out.map(JSONValue.int) ?? .null),
            ("cost_usd", costUSD.map(JSONValue.double) ?? .null),
        ]
        if let coverage {
            pairs.append(("coverage", coverage.toJSON()))
        }
        return .object(pairs)
    }

    public static func fromJSON(_ v: JSONValue) -> StageAttribution {
        StageAttribution(
            stage: v["stage"]?.stringValue ?? "",
            freshIn: v["fresh_in"]?.intValue,
            cacheCreation: v["cache_creation"]?.intValue,
            cacheRead: v["cache_read"]?.intValue,
            out: v["out"]?.intValue,
            costUSD: v["cost_usd"]?.doubleValue,
            coverage: StageCoverage.fromJSON(v["coverage"])
        )
    }
}

// MARK: - PathMetrics (D4)

public struct PathMetrics: Sendable, Equatable {
    public var tokens: Tokens
    public var costUSD: Double?
    public var wallClockS: Double
    public var locProduced: Int
    public var testCount: Int
    public var coveragePct: Double
    public var estimateComplexityScore: Int
    public var stageCount: Int
    public var passFail: String   // "pass" | "fail"
    public var appPath: String?   // repo-relative; null for live/no-app (D4)

    public init(tokens: Tokens, costUSD: Double?, wallClockS: Double, locProduced: Int,
                testCount: Int, coveragePct: Double, estimateComplexityScore: Int,
                stageCount: Int, passFail: String, appPath: String? = nil) {
        self.tokens = tokens
        self.costUSD = costUSD
        self.wallClockS = wallClockS
        self.locProduced = locProduced
        self.testCount = testCount
        self.coveragePct = coveragePct
        self.estimateComplexityScore = estimateComplexityScore
        self.stageCount = stageCount
        self.passFail = passFail
        self.appPath = appPath
    }

    public func toJSON() -> JSONValue {
        .object([
            ("tokens", tokens.toJSON()),
            ("cost_usd", costUSD.map(JSONValue.double) ?? .null),
            ("wall_clock_s", .double(wallClockS)),
            ("loc_produced", .int(locProduced)),
            ("test_count", .int(testCount)),
            ("coverage_pct", .double(coveragePct)),
            ("estimate_complexity_score", .int(estimateComplexityScore)),
            ("stage_count", .int(stageCount)),
            ("pass_fail", .string(passFail)),
            ("app_path", appPath.map(JSONValue.string) ?? .null),
        ])
    }

    public static func fromJSON(_ v: JSONValue) -> PathMetrics {
        PathMetrics(
            tokens: Tokens.fromJSON(v["tokens"]),
            costUSD: v["cost_usd"]?.doubleValue,
            wallClockS: v["wall_clock_s"]?.doubleValue ?? 0,
            locProduced: v["loc_produced"]?.intValue ?? 0,
            testCount: v["test_count"]?.intValue ?? 0,
            coveragePct: v["coverage_pct"]?.doubleValue ?? 0,
            estimateComplexityScore: v["estimate_complexity_score"]?.intValue ?? 0,
            stageCount: v["stage_count"]?.intValue ?? 0,
            passFail: v["pass_fail"]?.stringValue ?? "",
            appPath: v["app_path"]?.stringValue
        )
    }
}

// MARK: - MetricDelta

public struct MetricDelta: Sendable, Equatable {
    public var with: Double?     // JSON "with"
    public var without: Double?
    public var delta: Double?

    public init(with: Double?, without: Double?, delta: Double?) {
        self.with = with
        self.without = without
        self.delta = delta
    }

    /// Preserve int-ness on emit: whole-valued numbers serialize as ints (Python
    /// stores ints as ints in the comparison block, e.g. delta 4).
    private static func num(_ d: Double?) -> JSONValue {
        guard let d else { return .null }
        if d == d.rounded() && abs(d) < 1e16 { return .int(Int(d)) }
        return .double(d)
    }

    public func toJSON() -> JSONValue {
        .object([
            ("with", Self.num(with)),
            ("without", Self.num(without)),
            ("delta", Self.num(delta)),
        ])
    }

    public static func fromJSON(_ v: JSONValue) -> MetricDelta {
        MetricDelta(with: v["with"]?.doubleValue, without: v["without"]?.doubleValue,
                    delta: v["delta"]?.doubleValue)
    }

    /// Delta = with - without, or nil when either side nil.
    public static func of(_ withV: Double?, _ withoutV: Double?) -> MetricDelta {
        guard let w = withV, let wo = withoutV else {
            return MetricDelta(with: withV, without: withoutV, delta: nil)
        }
        return MetricDelta(with: w, without: wo, delta: w - wo)
    }
}

// MARK: - BenchmarkRecord

public struct BenchmarkRecord: Sendable, Equatable {
    public var runID: String
    public var timestampUTC: String
    public var mode: Mode
    public var gitSHA: String
    public var budgetUSD: Double?
    public var paths: [(String, PathMetrics)]        // ordered: with, without
    public var comparison: [(String, MetricDelta)]   // ordered insertion
    public var livePartial: Bool
    public var stages: [StageAttribution]

    public init(runID: String, timestampUTC: String, mode: Mode, gitSHA: String,
                budgetUSD: Double?, paths: [(String, PathMetrics)],
                comparison: [(String, MetricDelta)], livePartial: Bool = false,
                stages: [StageAttribution] = []) {
        self.runID = runID
        self.timestampUTC = timestampUTC
        self.mode = mode
        self.gitSHA = gitSHA
        self.budgetUSD = budgetUSD
        self.paths = paths
        self.comparison = comparison
        self.livePartial = livePartial
        self.stages = stages
    }

    public static func == (lhs: BenchmarkRecord, rhs: BenchmarkRecord) -> Bool {
        lhs.runID == rhs.runID && lhs.timestampUTC == rhs.timestampUTC && lhs.mode == rhs.mode
            && lhs.gitSHA == rhs.gitSHA && lhs.budgetUSD == rhs.budgetUSD
            && lhs.paths.map(\.0) == rhs.paths.map(\.0)
            && lhs.paths.map(\.1) == rhs.paths.map(\.1)
            && lhs.comparison.map(\.0) == rhs.comparison.map(\.0)
            && lhs.comparison.map(\.1) == rhs.comparison.map(\.1)
            && lhs.livePartial == rhs.livePartial && lhs.stages == rhs.stages
    }

    public func toJSON() -> JSONValue {
        var pairs: [(String, JSONValue)] = [
            ("run_id", .string(runID)),
            ("timestamp_utc", .string(timestampUTC)),
            ("mode", .string(mode.rawValue)),
            ("git_sha", .string(gitSHA)),
            ("budget_usd", budgetUSD.map(JSONValue.double) ?? .null),
            ("paths", .object(paths.map { ($0.0, $0.1.toJSON()) })),
            ("comparison", .object(comparison.map { ($0.0, $0.1.toJSON()) })),
        ]
        if livePartial {
            pairs.append(("live_partial", .bool(true)))
        }
        if !stages.isEmpty {
            pairs.append(("stages", .array(stages.map { $0.toJSON() })))
        }
        return .object(pairs)
    }

    public static func fromJSON(_ v: JSONValue) -> BenchmarkRecord {
        let pathsPairs: [(String, PathMetrics)] = (v["paths"]?.objectPairs ?? []).map {
            ($0.0, PathMetrics.fromJSON($0.1))
        }
        let compPairs: [(String, MetricDelta)] = (v["comparison"]?.objectPairs ?? []).map {
            ($0.0, MetricDelta.fromJSON($0.1))
        }
        let stages = (v["stages"]?.arrayItems ?? []).map { StageAttribution.fromJSON($0) }
        return BenchmarkRecord(
            runID: v["run_id"]?.stringValue ?? "",
            timestampUTC: v["timestamp_utc"]?.stringValue ?? "",
            mode: Mode(rawValue: v["mode"]?.stringValue ?? "deterministic") ?? .deterministic,
            gitSHA: v["git_sha"]?.stringValue ?? "",
            budgetUSD: v["budget_usd"]?.doubleValue,
            paths: pathsPairs,
            comparison: compPairs,
            livePartial: v["live_partial"]?.boolValue ?? false,
            stages: stages
        )
    }

    public var pathWith: PathMetrics? { paths.first(where: { $0.0 == "with" })?.1 }
    public var pathWithout: PathMetrics? { paths.first(where: { $0.0 == "without" })?.1 }
}

// MARK: - comparison builder / record factory / JSON I/O

/// Numeric comparison metrics present in both modes.
public let deterministicComparisonKeys = [
    "loc_produced", "test_count", "coverage_pct", "wall_clock_s",
    "estimate_complexity_score", "stage_count",
]

public func buildComparison(with: PathMetrics, without: PathMetrics, mode: Mode)
    -> [(String, MetricDelta)] {
    func metric(_ key: String, _ p: PathMetrics) -> Double? {
        switch key {
        case "loc_produced": return Double(p.locProduced)
        case "test_count": return Double(p.testCount)
        case "coverage_pct": return p.coveragePct
        case "wall_clock_s": return p.wallClockS
        case "estimate_complexity_score": return Double(p.estimateComplexityScore)
        case "stage_count": return Double(p.stageCount)
        default: return nil
        }
    }
    var comp: [(String, MetricDelta)] = []
    for key in deterministicComparisonKeys {
        comp.append((key, MetricDelta.of(metric(key, with), metric(key, without))))
    }
    if mode == .live {
        comp.append(("tokens_total", MetricDelta.of(with.tokens.total.map(Double.init),
                                                     without.tokens.total.map(Double.init))))
        comp.append(("cost_usd", MetricDelta.of(with.costUSD, without.costUSD)))
    }
    return comp
}

public func makeRecord(runID: String, timestampUTC: String, mode: Mode, gitSHA: String,
                       budgetUSD: Double?, with: PathMetrics, without: PathMetrics,
                       livePartial: Bool = false, stages: [StageAttribution] = [])
    -> BenchmarkRecord {
    BenchmarkRecord(
        runID: runID, timestampUTC: timestampUTC, mode: mode, gitSHA: gitSHA,
        budgetUSD: budgetUSD,
        paths: [("with", with), ("without", without)],
        comparison: buildComparison(with: with, without: without, mode: mode),
        livePartial: livePartial, stages: stages
    )
}

public func dumps(_ record: BenchmarkRecord, indent: Int = 2) -> String {
    record.toJSON().serialized(indent: indent)
}

public func loads(_ text: String) throws -> BenchmarkRecord {
    BenchmarkRecord.fromJSON(try JSONParser.parse(text))
}

public func writeRecord(_ record: BenchmarkRecord, to path: String) throws {
    try dumps(record).write(toFile: path, atomically: true, encoding: .utf8)
}

public func readRecord(from path: String) throws -> BenchmarkRecord {
    try loads(String(contentsOfFile: path, encoding: .utf8))
}
