// Coverage.swift — dual-mode capture parser (coverage option 1).
//
// Modes:
//   stream-json — NDJSON, one JSON object per line. Per-event we collect the
//     coverage manifest (Task subagent_type -> agents, Skill names -> skills,
//     slash-command names -> commands, tool_use count -> tool_calls); the
//     terminal `result` line supplies usage + cost (same field shape as the
//     single-object capture — the Layer-1 parser is reused on that line).
//   json — today's single result object with `usage` + `total_cost_usd`;
//     coverage manifest = nil.
//
// NEVER fabricate: any field the output doesn't yield -> nil; the whole
// coverage object is nil when no event data exists. Per-event field paths are
// the ONLY residual unknown (AR q2) — they are grouped in `FieldPaths` below
// for one-place post-live tuning (PE0).

import BenchmarkKit
import Foundation

public enum Coverage {
    /// Per-event field-path constants — tune from the FIRST live NDJSON capture.
    public enum FieldPaths {
        public static let taskToolName = "Task"
        public static let subagentTypeKey = "subagent_type"
        public static let skillToolName = "Skill"
        public static let skillKey = "skill"
        public static let commandToolName = "SlashCommand"
        public static let commandKey = "command"
    }

    /// Parsed capture from one stage's stdout. All fields nil-degrade.
    public struct ParsedCapture: Sendable, Equatable {
        public var inputTokens: Int?
        public var outputTokens: Int?
        public var cacheRead: Int?
        public var cacheCreation: Int?
        public var costUSD: Double?
        public var coverage: StageCoverage?

        public var hasUsage: Bool {
            inputTokens != nil || outputTokens != nil || cacheRead != nil
                || cacheCreation != nil || costUSD != nil
        }
        public var isEmpty: Bool { !hasUsage && coverage == nil }
    }

    /// Layer-1 single-object parse (today's `--output-format json` result).
    /// Defensive: any JSON error, missing usage, or missing token keys -> nil.
    public static func parseSingleObject(_ text: String) -> ParsedCapture? {
        guard let obj = try? JSONParser.parse(text), case .object = obj else { return nil }
        guard let usage = obj["usage"], case .object = usage else { return nil }
        let inTok = usage["input_tokens"]?.intValue
        let outTok = usage["output_tokens"]?.intValue
        let cr = usage["cache_read_input_tokens"]?.intValue
        let cc = usage["cache_creation_input_tokens"]?.intValue
        // cost may be at result top-level or inside usage depending on CLI version.
        let cost = obj["total_cost_usd"]?.doubleValue ?? usage["total_cost_usd"]?.doubleValue
        if inTok == nil && outTok == nil && cost == nil && cr == nil && cc == nil {
            return nil
        }
        return ParsedCapture(inputTokens: inTok, outputTokens: outTok,
                             cacheRead: cr, cacheCreation: cc, costUSD: cost,
                             coverage: nil)
    }

    /// Walk one NDJSON event for tool_use blocks, accumulating manifest data.
    /// Handles both the API message shape (event.message.content[]) and a flat
    /// content array; unknown shapes contribute nothing.
    static func collectToolUses(from event: JSONValue,
                                agents: inout Set<String>, skills: inout Set<String>,
                                commands: inout Set<String>, toolCalls: inout Int) {
        var contents: [JSONValue] = []
        if let c = event["message"]?["content"]?.arrayItems { contents = c }
        else if let c = event["content"]?.arrayItems { contents = c }
        for block in contents {
            guard block["type"]?.stringValue == "tool_use" else { continue }
            toolCalls += 1
            let name = block["name"]?.stringValue ?? ""
            let input = block["input"]
            switch name {
            case FieldPaths.taskToolName:
                if let sub = input?[FieldPaths.subagentTypeKey]?.stringValue, !sub.isEmpty {
                    agents.insert(sub)
                }
            case FieldPaths.skillToolName:
                if let skill = input?[FieldPaths.skillKey]?.stringValue, !skill.isEmpty {
                    if skill.hasPrefix("/") { commands.insert(skill) }
                    else { skills.insert(skill) }
                }
            case FieldPaths.commandToolName:
                if let cmd = input?[FieldPaths.commandKey]?.stringValue, !cmd.isEmpty {
                    commands.insert(cmd)
                }
            default:
                break
            }
        }
    }

    /// Dual-mode parse: stream-json NDJSON first; single-object fallback.
    /// Returns nil only when the output yields NOTHING real.
    public static func parse(_ stdout: String) -> ParsedCapture? {
        let lines = stdout.split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // Single line (or none): treat as today's single-object JSON result.
        if lines.count <= 1 {
            return parseSingleObject(stdout)
        }

        // NDJSON: parse line-by-line, defensively skipping bad lines.
        var agents = Set<String>(), skills = Set<String>(), commands = Set<String>()
        var toolCalls = 0
        var usage: ParsedCapture?
        var sawEvent = false
        for line in lines {
            guard let event = try? JSONParser.parse(line), case .object = event else { continue }
            sawEvent = true
            collectToolUses(from: event, agents: &agents, skills: &skills,
                            commands: &commands, toolCalls: &toolCalls)
            if event["type"]?.stringValue == "result" {
                // Terminal line: reuse the Layer-1 parser shape on this event.
                if let u = parseSingleObject(line) { usage = u }
            }
        }
        // If nothing parsed as an event, fall back to whole-string single-object.
        if !sawEvent { return parseSingleObject(stdout) }

        let coverage: StageCoverage? = (toolCalls > 0 || !agents.isEmpty
                                        || !skills.isEmpty || !commands.isEmpty)
            ? StageCoverage(agents: agents.sorted(), skills: skills.sorted(),
                            commands: commands.sorted(), toolCalls: toolCalls)
            : nil
        var result = usage ?? ParsedCapture()
        result.coverage = coverage
        return result.isEmpty ? nil : result
    }
}
