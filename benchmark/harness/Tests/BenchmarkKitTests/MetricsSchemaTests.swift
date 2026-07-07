// MetricsSchemaTests.swift — port of benchmark/tests/with-plugin/
// test_metrics_schema.py (39 tests). AC-6 schema validation.

import Foundation
import Testing
@testable import BenchmarkKit

private func makeTokens(null: Bool) -> Tokens {
    if null { return Tokens(input: nil, output: nil, total: nil) }
    return Tokens(input: 100, output: 200, total: 300,
                  cacheRead: 677604, cacheCreation: 129094)
}

private func makePath(nullTokens: Bool) -> PathMetrics {
    PathMetrics(
        tokens: makeTokens(null: nullTokens),
        costUSD: nullTokens ? nil : 0.42,
        wallClockS: 1.23, locProduced: 275, testCount: 9, coveragePct: 88.5,
        estimateComplexityScore: 15, stageCount: 5, passFail: "pass"
    )
}

private func makeTestRecord(mode: Mode = .deterministic) -> BenchmarkRecord {
    let withP = makePath(nullTokens: mode == .deterministic)
    let withoutP = PathMetrics(
        tokens: makeTokens(null: true), costUSD: nil, wallClockS: 0.5,
        locProduced: 275, testCount: 9, coveragePct: 88.5,
        estimateComplexityScore: 0, stageCount: 1, passFail: "pass"
    )
    return makeRecord(
        runID: "\(mode.rawValue)-test-abc1234", timestampUTC: "2026-01-01T00:00:00Z",
        mode: mode, gitSHA: "abc1234",
        budgetUSD: mode == .deterministic ? nil : 5.0,
        with: withP, without: withoutP
    )
}

@Suite("Required top-level fields")
struct RequiredTopLevelFields {
    let d = makeTestRecord().toJSON()

    @Test func runIDPresentAndString() {
        #expect(d["run_id"]?.stringValue != nil)
    }

    @Test func timestampUTCPresentAndISO() {
        let ts = d["timestamp_utc"]?.stringValue
        #expect(ts != nil)
        #expect(ts?.hasSuffix("Z") == true)
        #expect(ts?.contains("T") == true)
    }

    @Test func modeIsValidLiteral() {
        let mode = d["mode"]?.stringValue
        #expect(mode == "deterministic" || mode == "live")
    }

    @Test func gitSHAPresent() {
        #expect(d["git_sha"]?.stringValue != nil)
    }

    @Test func budgetUSDNullInDeterministic() {
        #expect(d["budget_usd"]?.isNull == true)
    }

    @Test func budgetUSDPopulatedInLive() {
        let live = makeTestRecord(mode: .live).toJSON()
        #expect(live["budget_usd"]?.isNull == false)
        #expect(live["budget_usd"]?.doubleValue == 5.0)
    }
}

@Suite("Paths block")
struct PathsBlock {
    let d = makeTestRecord().toJSON()
    var withP: JSONValue? { d["paths"]?["with"] }
    var withoutP: JSONValue? { d["paths"]?["without"] }

    @Test func pathsHasWithAndWithout() {
        #expect(d["paths"]?["with"] != nil)
        #expect(d["paths"]?["without"] != nil)
    }

    private func checkPath(_ p: JSONValue?) {
        let required = ["tokens", "cost_usd", "wall_clock_s", "loc_produced",
                        "test_count", "coverage_pct", "estimate_complexity_score",
                        "stage_count", "pass_fail"]
        let keys = Set((p?.objectPairs ?? []).map(\.0))
        for r in required {
            #expect(keys.contains(r), "missing field: \(r)")
        }
    }

    @Test func withPathHasAllRequiredFields() { checkPath(withP) }
    @Test func withoutPathHasAllRequiredFields() { checkPath(withoutP) }

    @Test func tokensKeywordShimProducesInOutTotalKeys() {
        for p in [withP, withoutP] {
            let keys = Set((p?["tokens"]?.objectPairs ?? []).map(\.0))
            #expect(keys.contains("in"))
            #expect(keys.contains("out"))
            #expect(keys.contains("total"))
            #expect(!keys.contains("input"))
            #expect(!keys.contains("output"))
        }
    }

    @Test func deterministicTokensAreNull() {
        let t = withP?["tokens"]
        #expect(t?["in"]?.isNull == true)
        #expect(t?["out"]?.isNull == true)
        #expect(t?["total"]?.isNull == true)
    }

    @Test func deterministicCostUSDIsNull() {
        #expect(withP?["cost_usd"]?.isNull == true)
    }

    @Test func liveTokensPopulated() {
        let live = makeTestRecord(mode: .live).toJSON()
        let t = live["paths"]?["with"]?["tokens"]
        #expect(t?["in"]?.intValue == 100)
        #expect(t?["out"]?.intValue == 200)
        #expect(t?["total"]?.intValue == 300)
    }

    @Test func passFailIsValid() {
        for p in [withP, withoutP] {
            let v = p?["pass_fail"]?.stringValue
            #expect(v == "pass" || v == "fail")
        }
    }

    @Test func wallClockIsFloat() {
        if case .double = withP?["wall_clock_s"] {} else {
            Issue.record("wall_clock_s must serialize as a float")
        }
    }

    @Test func locAndCountsAreInts() {
        for key in ["loc_produced", "test_count", "stage_count", "estimate_complexity_score"] {
            if case .int = withP?[key] {} else {
                Issue.record("with.\(key) not int")
            }
        }
    }
}

@Suite("Comparison block")
struct ComparisonBlock {
    let comp = makeTestRecord().toJSON()["comparison"]

    @Test func deterministicComparisonKeysPresent() {
        let keys = Set((comp?.objectPairs ?? []).map(\.0))
        for r in ["loc_produced", "test_count", "coverage_pct", "wall_clock_s",
                  "estimate_complexity_score", "stage_count"] {
            #expect(keys.contains(r), "missing comparison key: \(r)")
        }
    }

    @Test func comparisonEntryHasWithWithoutDeltaKeys() {
        for (key, entry) in comp?.objectPairs ?? [] {
            let keys = Set((entry.objectPairs ?? []).map(\.0))
            #expect(keys.contains("with"), "comparison.\(key) missing 'with'")
            #expect(keys.contains("without"), "comparison.\(key) missing 'without'")
            #expect(keys.contains("delta"), "comparison.\(key) missing 'delta'")
            #expect(!keys.contains("with_"), "comparison.\(key) leaked 'with_'")
        }
    }

    @Test func deltaComputedCorrectly() {
        let sc = comp?["stage_count"]
        #expect(sc?["with"]?.intValue == 5)
        #expect(sc?["without"]?.intValue == 1)
        #expect(sc?["delta"]?.intValue == 4)
    }

    @Test func deterministicComparisonHasNoLiveOnlyKeys() {
        // Deterministic mode never carries tokens_total / cost_usd comparison keys.
        let keys = Set((comp?.objectPairs ?? []).map(\.0))
        #expect(!keys.contains("tokens_total"))
        #expect(!keys.contains("cost_usd"))
    }

    @Test func liveAddsTokenAndCostComparison() {
        let liveComp = makeTestRecord(mode: .live).toJSON()["comparison"]
        let keys = Set((liveComp?.objectPairs ?? []).map(\.0))
        #expect(keys.contains("tokens_total"))
        #expect(keys.contains("cost_usd"))
    }
}

@Suite("JSON round-trip")
struct JsonRoundtrip {
    @Test func roundtripDeterministic() throws {
        let rec = makeTestRecord(mode: .deterministic)
        let loaded = try loads(dumps(rec))
        #expect(loaded.runID == rec.runID)
        #expect(loaded.mode == rec.mode)
        #expect(loaded.budgetUSD == nil)
        #expect(loaded.pathWith?.stageCount == 5)
        #expect(loaded.pathWithout?.stageCount == 1)
        #expect(loaded.comparison.first(where: { $0.0 == "stage_count" })?.1.delta == 4)
    }

    @Test func roundtripLive() throws {
        let rec = makeTestRecord(mode: .live)
        let loaded = try loads(dumps(rec))
        #expect(loaded.mode == .live)
        #expect(loaded.budgetUSD != nil)
        #expect(loaded.pathWith?.tokens.input != nil)
    }

    @Test func toJSONIsValidJSON() throws {
        // Parse with Foundation to prove standards-compliant JSON output.
        let text = dumps(makeTestRecord())
        let obj = try JSONSerialization.jsonObject(with: Data(text.utf8))
        #expect((obj as? [String: Any])?["run_id"] != nil)
    }
}

@Suite("MetricDelta.of")
struct MetricDeltaOf {
    @Test func computesDeltaBothPresent() {
        let md = MetricDelta.of(10, 3)
        #expect(md.with == 10)
        #expect(md.without == 3)
        #expect(md.delta == 7)
    }

    @Test func deltaNilWhenWithNil() {
        #expect(MetricDelta.of(nil, 3).delta == nil)
    }

    @Test func deltaNilWhenWithoutNil() {
        #expect(MetricDelta.of(5, nil).delta == nil)
    }

    @Test func floatDelta() {
        let md = MetricDelta.of(1.5, 0.5)
        #expect(abs((md.delta ?? 0) - 1.0) < 1e-9)
    }
}

@Suite("Tokens cache fields (D1)")
struct TokensCacheFields {
    @Test func tokensHasCacheReadAndCacheCreationKeys() {
        let d = makeTestRecord(mode: .live).toJSON()
        let keys = Set((d["paths"]?["with"]?["tokens"]?.objectPairs ?? []).map(\.0))
        #expect(keys.contains("cache_read"))
        #expect(keys.contains("cache_creation"))
    }

    @Test func deterministicCacheFieldsAreNull() {
        let d = makeTestRecord(mode: .deterministic).toJSON()
        let t = d["paths"]?["with"]?["tokens"]
        #expect(t?["cache_read"]?.isNull == true)
        #expect(t?["cache_creation"]?.isNull == true)
    }

    @Test func cacheFieldsAreIntWhenPopulated() {
        let d = makeTestRecord(mode: .live).toJSON()
        let t = d["paths"]?["with"]?["tokens"]
        #expect(t?["cache_read"]?.intValue == 677604)
        #expect(t?["cache_creation"]?.intValue == 129094)
    }

    @Test func roundtripPreservesCacheFields() {
        let tok = Tokens(input: 108592, output: 13160, total: 121752,
                         cacheRead: 677604, cacheCreation: 129094)
        let loaded = Tokens.fromJSON(tok.toJSON())
        #expect(loaded == tok)
        #expect(loaded.cacheRead == 677604)
        #expect(loaded.cacheCreation == 129094)
    }

    @Test func roundtripNilCacheFields() {
        let tok = Tokens()
        let d = tok.toJSON()
        // All 5 keys ALWAYS emitted (value or null), in order.
        let pairs = d.objectPairs ?? []
        #expect(pairs.map(\.0) == ["in", "out", "total", "cache_read", "cache_creation"])
        #expect(pairs.allSatisfy { $0.1.isNull })
        #expect(Tokens.fromJSON(d) == tok)
    }

    @Test func fromJSONLegacyTokensWithoutCacheKeys() {
        // The on-disk live record shape: no cache keys -> nil, no crash.
        let legacy = JSONValue.object([
            ("in", .int(574557)), ("out", .int(7329)), ("total", .int(581886)),
        ])
        let tok = Tokens.fromJSON(legacy)
        #expect(tok.input == 574557)
        #expect(tok.output == 7329)
        #expect(tok.total == 581886)
        #expect(tok.cacheRead == nil)
        #expect(tok.cacheCreation == nil)
    }

    @Test func positionalTokensThreeArgsStillResolves() {
        // Hazard guard: Tokens(input:output:total:) without cache args keeps working.
        let tok = Tokens(input: nil, output: nil, total: nil)
        #expect(tok.cacheRead == nil)
        #expect(tok.cacheCreation == nil)
    }

    @Test func totalExcludesCache() {
        // cache figures are additive siblings, NEVER summed into total.
        let tok = Tokens(input: 100, output: 200, total: 300,
                         cacheRead: 999, cacheCreation: 888)
        #expect(tok.total == 300)
    }
}

@Suite("StageAttribution (D2)")
struct StageAttributionTests {
    private func stagedRecord() -> BenchmarkRecord {
        let stages = [
            StageAttribution(stage: "estimate", freshIn: 33482, cacheCreation: 11639,
                             cacheRead: 23022, out: 997, costUSD: 0.1),
            StageAttribution(stage: "create", freshIn: 37652, cacheCreation: 56772,
                             cacheRead: 207310, out: 4227, costUSD: 0.5),
            StageAttribution(stage: "test", freshIn: 37458, cacheCreation: 60683,
                             cacheRead: 447272, out: 7936, costUSD: 0.9),
        ]
        return makeRecord(
            runID: "live-staged", timestampUTC: "2026-07-01T00:00:00Z", mode: .live,
            gitSHA: "abc1234", budgetUSD: 5.0,
            with: makePath(nullTokens: false), without: makePath(nullTokens: true),
            stages: stages
        )
    }

    @Test func stagesOmittedWhenEmpty() {
        let d = makeTestRecord(mode: .deterministic).toJSON()
        let keys = Set((d.objectPairs ?? []).map(\.0))
        #expect(!keys.contains("stages"))
    }

    @Test func stagesPresentAndShapedWhenPopulated() {
        let d = stagedRecord().toJSON()
        let stages = d["stages"]?.arrayItems
        #expect(stages?.count == 3)
        let s0 = stages?.first
        let keys = Set((s0?.objectPairs ?? []).map(\.0))
        for k in ["stage", "fresh_in", "cache_creation", "cache_read", "out", "cost_usd"] {
            #expect(keys.contains(k), "stage[0] missing \(k)")
        }
        #expect(s0?["stage"]?.stringValue == "estimate")
        #expect(s0?["cache_read"]?.intValue == 23022)
    }

    @Test func stagesRoundtrip() throws {
        let rec = stagedRecord()
        let loaded = try loads(dumps(rec))
        #expect(loaded.stages.count == 3)
        #expect(loaded.stages[2].stage == "test")
        #expect(loaded.stages[2].cacheRead == 447272)
        #expect(loaded.stages == rec.stages)
    }

    // D2 additive coverage field: appended AFTER cost_usd, ONLY when present.
    @Test func coverageOmittedWhenNil() {
        let s = StageAttribution(stage: "DV", freshIn: 1, cacheCreation: 2,
                                 cacheRead: 3, out: 4, costUSD: 0.5)
        let keys = (s.toJSON().objectPairs ?? []).map(\.0)
        #expect(keys == ["stage", "fresh_in", "cache_creation", "cache_read", "out", "cost_usd"])
    }

    @Test func coverageAppendedAfterCostUSDWhenPresent() {
        let cov = StageCoverage(agents: ["apple-developer:macos-developer"],
                                skills: ["swiftui-skills"], commands: ["/swiftui-review"],
                                toolCalls: 42)
        let s = StageAttribution(stage: "DV", freshIn: 1, cacheCreation: 2,
                                 cacheRead: 3, out: 4, costUSD: 0.5, coverage: cov)
        let keys = (s.toJSON().objectPairs ?? []).map(\.0)
        #expect(keys == ["stage", "fresh_in", "cache_creation", "cache_read", "out",
                         "cost_usd", "coverage"])
        let decoded = StageAttribution.fromJSON(s.toJSON())
        #expect(decoded.coverage == cov)
        #expect(decoded.coverage?.toolCalls == 42)
    }
}
