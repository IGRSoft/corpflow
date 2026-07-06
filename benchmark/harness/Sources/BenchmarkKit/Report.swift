// Report.swift — render benchmark/results/history.json into a self-contained
// result.html. Port of benchmark/lib/report.py.
//
// Shows ALL metrics (WITH vs WITHOUT + deltas) for every retained run, per mode,
// newest first, plus each generated app's path, derived analysis rows (each
// degrades to an em-dash when inputs are missing), coverage rollup rows for live
// records that carry a per-stage coverage manifest, and a plugin-surface coverage
// ratio (exercised/declared) computed at report time from the repo's
// agents/*.md, commands/*.md, and skills/*/SKILL.md counts.

import Foundation

public enum Report {
    // (accessor, label, isDeltaNumeric)
    static let metricRows: [(String, String, Bool)] = [
        ("tokens.in", "tokens in", true),
        ("tokens.out", "tokens out", true),
        ("tokens.total", "tokens total", true),
        ("cost_usd", "cost (USD)", true),
        ("wall_clock_s", "wall clock (s)", true),
        ("loc_produced", "LOC produced", true),
        ("test_count", "test count", true),
        ("coverage_pct", "coverage %", true),
        ("estimate_complexity_score", "complexity score", true),
        ("stage_count", "stage count", true),
        ("tokens.cache_read", "cache read", true),
        ("tokens.cache_creation", "cache creation", true),
        ("pass_fail", "pass/fail", false),
    ]

    static func htmlEscape(_ s: String) -> String {
        var r = ""
        for ch in s {
            switch ch {
            case "&": r += "&amp;"
            case "<": r += "&lt;"
            case ">": r += "&gt;"
            case "\"": r += "&quot;"
            case "'": r += "&#x27;"
            default: r.append(ch)
            }
        }
        return r
    }

    static func get(_ pathMetrics: JSONValue?, _ accessor: String) -> JSONValue? {
        guard let pathMetrics else { return nil }
        if accessor.contains(".") {
            let parts = accessor.split(separator: ".", maxSplits: 1).map(String.init)
            return pathMetrics[parts[0]]?[parts[1]]
        }
        return pathMetrics[accessor]
    }

    /// Format a scalar JSONValue for a table cell (Python `_fmt`).
    static func fmt(_ v: JSONValue?) -> String {
        guard let v, !v.isNull else { return "&mdash;" }
        switch v {
        case .bool(let b): return b ? "pass" : "fail"
        case .int(let i): return groupInt(i)
        case .double(let d):
            if d == d.rounded() { return groupInt(Int(d)) }
            // 4dp then strip trailing zeros + dot.
            var s = String(format: "%.4f", d)
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
            return groupDecimal(s)
        case .string(let s): return htmlEscape(s)
        default: return htmlEscape(v.serialized(indent: 0))
        }
    }

    static func groupInt(_ i: Int) -> String {
        let neg = i < 0
        var digits = Array(String(abs(i)))
        var out: [Character] = []
        var c = 0
        for d in digits.reversed() {
            if c != 0 && c % 3 == 0 { out.append(",") }
            out.append(d); c += 1
        }
        digits = out.reversed()
        return (neg ? "-" : "") + String(digits)
    }

    static func groupDecimal(_ s: String) -> String {
        let parts = s.split(separator: ".", maxSplits: 1).map(String.init)
        guard let intPart = parts.first, let n = Int(intPart) else { return s }
        let grouped = groupInt(n)
        return parts.count == 2 ? "\(grouped).\(parts[1])" : grouped
    }

    static func delta(_ withV: JSONValue?, _ withoutV: JSONValue?) -> String {
        func num(_ v: JSONValue?) -> Double? {
            switch v {
            case .int(let i): return Double(i)
            case .double(let d): return d
            default: return nil
            }
        }
        if let w = num(withV), let wo = num(withoutV) {
            let d = w - wo
            let sign = d > 0 ? "+" : ""
            let dv: JSONValue = (d == d.rounded()) ? .int(Int(d)) : .double(d)
            return "\(sign)\(fmt(dv))"
        }
        return "&mdash;"
    }

    static func appPath(_ rec: JSONValue, _ which: String) -> String {
        let pm = rec["paths"]?[which]
        if let p = pm?["app_path"]?.stringValue, !p.isEmpty { return p }
        let runID = rec["run_id"]?.stringValue ?? "unknown"
        return "benchmark/workdirs/\(runID)/\(which)"
    }

    static func numOrNil(_ v: JSONValue?) -> Double? {
        switch v {
        case .int(let i): return Double(i)
        case .double(let d): return d
        default: return nil
        }
    }

    static func ratioFmt(_ v: Double) -> String {
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return groupDecimal(s)
    }

    /// Derived analysis rows (Python `_analysis_rows`). Each degrades to em-dash.
    static func analysisRows(_ rec: JSONValue) -> [(String, String)] {
        let withPM = rec["paths"]?["with"]
        let withoutPM = rec["paths"]?["without"]
        let wt = withPM?["tokens"]
        let ot = withoutPM?["tokens"]

        let wTotal = numOrNil(wt?["total"])
        let wOut = numOrNil(wt?["out"])
        let wFresh = numOrNil(wt?["in"])
        let wCR = numOrNil(wt?["cache_read"])
        let wCC = numOrNil(wt?["cache_creation"])
        let wLOC = numOrNil(withPM?["loc_produced"])
        let oTotal = numOrNil(ot?["total"])

        var rows: [(String, String)] = []

        // input:output ratio
        if let wTotal, let wOut, wOut != 0 {
            rows.append(("input:output ratio", "\(ratioFmt(wTotal / wOut)):1"))
        } else { rows.append(("input:output ratio", "&mdash;")) }

        // cache-hit %
        if let wCR, let wCC, let wFresh {
            let denom = wFresh + wCC + wCR
            rows.append(("cache-hit %", denom != 0 ? "\(ratioFmt(wCR / denom * 100))%" : "&mdash;"))
        } else { rows.append(("cache-hit %", "&mdash;")) }

        // per-stage token share
        let stages = rec["stages"]?.arrayItems ?? []
        var stageTotals: [(String, Int)] = []
        for s in stages {
            let fi = numOrNil(s["fresh_in"]).map(Int.init) ?? 0
            let cc = numOrNil(s["cache_creation"]).map(Int.init) ?? 0
            let cr = numOrNil(s["cache_read"]).map(Int.init) ?? 0
            stageTotals.append((s["stage"]?.stringValue ?? "?", fi + cc + cr))
        }
        let grand = stageTotals.reduce(0) { $0 + $1.1 }
        if !stageTotals.isEmpty && grand != 0 {
            let parts = stageTotals.map { "\(htmlEscape($0.0)) \(ratioFmt(Double($0.1) / Double(grand) * 100))%" }
            rows.append(("per-stage token share", parts.joined(separator: " &middot; ")))
        } else { rows.append(("per-stage token share", "&mdash;")) }

        // tokens per LOC
        if let wTotal, let wLOC, wLOC != 0 {
            rows.append(("tokens per LOC", ratioFmt(wTotal / wLOC)))
        } else { rows.append(("tokens per LOC", "&mdash;")) }

        // WITH-vs-WITHOUT premium
        if let wTotal, let oTotal, oTotal != 0 {
            rows.append(("WITH-vs-WITHOUT premium", "\(ratioFmt((wTotal - oTotal) / oTotal * 100))%"))
        } else { rows.append(("WITH-vs-WITHOUT premium", "&mdash;")) }

        return rows
    }

    /// Coverage rollup rows for a live record carrying a per-stage coverage
    /// manifest — distinct agents / skills / commands / total tool_calls across
    /// all stages. Empty when no stage has a coverage object.
    static func coverageRows(_ rec: JSONValue) -> [(String, String)] {
        var agents = Set<String>(), skills = Set<String>(), commands = Set<String>()
        var toolCalls = 0
        var any = false
        for s in rec["stages"]?.arrayItems ?? [] {
            guard let cov = s["coverage"], case .object = cov else { continue }
            any = true
            (cov["agents"]?.arrayItems ?? []).compactMap(\.stringValue).forEach { agents.insert($0) }
            (cov["skills"]?.arrayItems ?? []).compactMap(\.stringValue).forEach { skills.insert($0) }
            (cov["commands"]?.arrayItems ?? []).compactMap(\.stringValue).forEach { commands.insert($0) }
            toolCalls += cov["tool_calls"]?.intValue ?? 0
        }
        guard any else { return [] }
        return [
            ("agents exercised", agents.isEmpty ? "&mdash;" : htmlEscape(agents.sorted().joined(separator: ", "))),
            ("skills exercised", skills.isEmpty ? "&mdash;" : htmlEscape(skills.sorted().joined(separator: ", "))),
            ("commands exercised", commands.isEmpty ? "&mdash;" : htmlEscape(commands.sorted().joined(separator: ", "))),
            ("tool calls", String(toolCalls)),
        ]
    }

    /// Count the plugin's declared surface (agents/commands/skills) for the
    /// exercised/declared ratio. Best-effort; missing dirs -> 0.
    public static func declaredSurface(pluginRoot: String) -> (agents: Int, skills: Int, commands: Int) {
        let fm = FileManager.default
        func countMD(_ dir: String) -> Int {
            ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".md") }.count
        }
        let agents = countMD((pluginRoot as NSString).appendingPathComponent("agents"))
        let commands = countMD((pluginRoot as NSString).appendingPathComponent("commands"))
        // skills/*/SKILL.md
        var skills = 0
        let skillsDir = (pluginRoot as NSString).appendingPathComponent("skills")
        for sub in (try? fm.contentsOfDirectory(atPath: skillsDir)) ?? [] {
            let p = (skillsDir as NSString).appendingPathComponent(sub) + "/SKILL.md"
            if fm.fileExists(atPath: p) { skills += 1 }
        }
        return (agents, skills, commands)
    }

    static func recordHTML(_ rec: JSONValue) -> String {
        let runID = htmlEscape(rec["run_id"]?.stringValue ?? "?")
        let ts = htmlEscape(rec["timestamp_utc"]?.stringValue ?? "?")
        let mode = htmlEscape(rec["mode"]?.stringValue ?? "?")
        let sha = htmlEscape(rec["git_sha"]?.stringValue ?? "?")
        let budget = rec["budget_usd"]
        let partial = rec["live_partial"]?.boolValue ?? false
        let withPM = rec["paths"]?["with"]
        let withoutPM = rec["paths"]?["without"]

        var rows = ""
        for (accessor, label, _) in metricRows {
            let wv = get(withPM, accessor)
            let ov = get(withoutPM, accessor)
            rows += "<tr><td class='metric'>\(htmlEscape(label))</td>"
                + "<td class='with'>\(fmt(wv))</td>"
                + "<td class='without'>\(fmt(ov))</td>"
                + "<td class='delta'>\(delta(wv, ov))</td></tr>"
        }

        var badges = "<span class='badge mode-\(mode)'>\(mode)</span>"
        if let budget, !budget.isNull { badges += "<span class='badge budget'>budget $\(fmt(budget))</span>" }
        if partial { badges += "<span class='badge partial'>live_partial</span>" }

        let withApp = htmlEscape(appPath(rec, "with"))
        let withoutApp = htmlEscape(appPath(rec, "without"))

        let analysis = analysisRows(rec).map {
            "<tr><td class='metric'>\(htmlEscape($0.0))</td><td class='analysis' colspan='3'>\($0.1)</td></tr>"
        }.joined()

        let coverage = coverageRows(rec)
        var coverageSection = ""
        if !coverage.isEmpty {
            let covBody = coverage.map {
                "<tr><td class='metric'>\(htmlEscape($0.0))</td><td class='analysis' colspan='3'>\($0.1)</td></tr>"
            }.joined()
            coverageSection = """
              <table class="analysis-table">
                <thead><tr><th>coverage manifest</th><th colspan="3">exercised</th></tr></thead>
                <tbody>\(covBody)</tbody>
              </table>
            """
        }

        return """
            <section class="run">
              <h3>\(runID) \(badges)</h3>
              <div class="meta">\(ts) &middot; git \(sha)</div>
              <table>
                <thead><tr><th>metric</th><th>WITH plugin</th><th>WITHOUT plugin</th><th>&Delta; (with&minus;without)</th></tr></thead>
                <tbody>\(rows)</tbody>
              </table>
              <table class="analysis-table">
                <thead><tr><th>analysis (derived)</th><th colspan="3">value</th></tr></thead>
                <tbody>\(analysis)</tbody>
              </table>
              \(coverageSection)
              <div class="apps">
                <div><span class="lbl">WITH app:</span> <code>\(withApp)</code></div>
                <div><span class="lbl">WITHOUT app:</span> <code>\(withoutApp)</code></div>
              </div>
            </section>
        """
    }

    static let css = """
    :root { --with:#2563eb; --without:#64748b; --pos:#16a34a; --bg:#0b1020; --card:#141b2e; --fg:#e5e9f0; }
    * { box-sizing:border-box; } body { margin:0; font:14px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;
      background:var(--bg); color:var(--fg); padding:24px; }
    h1 { font-size:20px; margin:0 0 4px; } h2 { font-size:16px; margin:28px 0 8px; border-bottom:1px solid #26304a; padding-bottom:4px; }
    .sub { color:#94a3b8; margin:0 0 20px; }
    .run { background:var(--card); border:1px solid #26304a; border-radius:10px; padding:16px; margin:12px 0; }
    .run h3 { margin:0 0 2px; font-size:14px; font-family:ui-monospace,Menlo,monospace; }
    .meta { color:#94a3b8; font-size:12px; margin-bottom:10px; }
    table { width:100%; border-collapse:collapse; }
    th,td { text-align:right; padding:5px 10px; border-bottom:1px solid #232c44; }
    th:first-child, td.metric { text-align:left; color:#cbd5e1; }
    td.with { color:#93b4fb; } td.without { color:#cbd5e1; } td.delta { color:#86efac; font-variant-numeric:tabular-nums; }
    td.analysis { color:#fcd34d; text-align:right; font-variant-numeric:tabular-nums; }
    .analysis-table { margin-top:8px; } .analysis-table th { color:#fbbf24; }
    td { font-variant-numeric:tabular-nums; }
    .apps { margin-top:12px; font-size:13px; } .apps .lbl { color:#94a3b8; display:inline-block; width:90px; }
    .apps code { background:#0b1224; padding:2px 6px; border-radius:5px; color:#e2e8f0; }
    .badge { font-size:11px; padding:2px 7px; border-radius:999px; margin-left:8px; vertical-align:middle; }
    .mode-deterministic { background:#1e3a5f; color:#93c5fd; } .mode-live { background:#4a1d3f; color:#f0abfc; }
    .budget { background:#3a2f0b; color:#fde047; } .partial { background:#4a1d1d; color:#fca5a5; }
    .empty { color:#94a3b8; }
    footer { color:#64748b; margin-top:28px; font-size:12px; }
    """

    public static func renderHTML(history: JSONValue, pluginRoot: String? = nil) -> String {
        var bodyParts: [String] = []
        var latestTS = ""
        for mode in ["deterministic", "live"] {
            guard let recs = history[mode]?.arrayItems, !recs.isEmpty else { continue }
            bodyParts.append("<h2>\(htmlEscape(mode)) &mdash; latest \(recs.count)</h2>")
            for rec in recs.reversed() {
                if latestTS.isEmpty { latestTS = rec["timestamp_utc"]?.stringValue ?? "" }
                bodyParts.append(recordHTML(rec))
            }
        }
        if bodyParts.isEmpty {
            bodyParts.append("<p class='empty'>No benchmark results yet. Run <code>make benchmark</code>.</p>")
        }

        // Plugin-surface coverage ratio (exercised/declared), computed at report
        // time. exercised = distinct agents/skills/commands across all live
        // records' coverage manifests.
        var surfaceLine = ""
        if let pluginRoot {
            let declared = declaredSurface(pluginRoot: pluginRoot)
            var exAgents = Set<String>(), exSkills = Set<String>(), exCommands = Set<String>()
            for rec in (history["live"]?.arrayItems ?? []) {
                for s in rec["stages"]?.arrayItems ?? [] {
                    guard let cov = s["coverage"], case .object = cov else { continue }
                    (cov["agents"]?.arrayItems ?? []).compactMap(\.stringValue).forEach { exAgents.insert($0) }
                    (cov["skills"]?.arrayItems ?? []).compactMap(\.stringValue).forEach { exSkills.insert($0) }
                    (cov["commands"]?.arrayItems ?? []).compactMap(\.stringValue).forEach { exCommands.insert($0) }
                }
            }
            func ratio(_ ex: Int, _ decl: Int) -> String {
                decl > 0 ? "\(ex)/\(decl) (\(ratioFmt(Double(ex) / Double(decl) * 100))%)" : "\(ex)/0"
            }
            surfaceLine = "<p class='sub'>Plugin-surface coverage — agents "
                + "\(ratio(exAgents.count, declared.agents)) &middot; skills "
                + "\(ratio(exSkills.count, declared.skills)) &middot; commands "
                + "\(ratio(exCommands.count, declared.commands)).</p>"
        }

        let asof = latestTS.isEmpty ? "no runs" : htmlEscape(latestTS)
        return """
        <!DOCTYPE html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>igrsoft benchmark &mdash; Tic-Tac-Toe with/without plugin</title>
        <style>\(css)</style></head>
        <body>
          <h1>Tic-Tac-Toe benchmark &mdash; WITH vs WITHOUT plugin</h1>
          <p class="sub">All metrics per retained run (latest-3 per mode). As of \(asof). Deterministic tokens/cost are null by design; live fills them.</p>
          \(surfaceLine)
          \(bodyParts.joined())
          <footer>Generated by bench-report from benchmark/results/history.json &middot; app paths point to gitignored per-run workdirs.</footer>
        </body></html>

        """
    }

    /// Read history at `historyPath`, render, and write `outPath`. Returns outPath.
    @discardableResult
    public static func buildReport(historyPath: String, outPath: String,
                                   pluginRoot: String? = nil) throws -> String {
        var history: JSONValue = .object([])
        if let text = try? String(contentsOfFile: historyPath, encoding: .utf8),
           let parsed = try? JSONParser.parse(text), case .object = parsed {
            history = parsed
        }
        let htmlText = renderHTML(history: history, pluginRoot: pluginRoot)
        let outDir = (outPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        try htmlText.write(toFile: outPath, atomically: true, encoding: .utf8)
        return outPath
    }
}
