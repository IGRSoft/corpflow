// Credentials.swift — fail-fast credential probe, port of
// benchmark/live/credentials.py.
//
// Live mode requires an Anthropic credential before ANY stage is dispatched.
// Two sources: ANTHROPIC_API_KEY (checked FIRST when present — cheap
// short-circuit) OR an active `claude` CLI login (`claude auth status --json`,
// machine-login PREFERRED source; an OAuth-token-shaped ANTHROPIC_API_KEY 401s
// and would override a working machine login — see benchmark/README.md).
// Neither the key VALUE nor any CLI-login identity detail (email/org) is EVER
// printed, logged, echoed into argv, or written to any record — only boolean
// presence is observed. rc=3 semantics live in Dispatch.dispatch.

import BenchmarkKit
import Foundation

public enum Credentials {
    public static let credentialEnv = "ANTHROPIC_API_KEY"

    /// Frozen error message (byte-exact contract; ported tests assert equality).
    public static let missingCredentialMessage =
        "live mode requires credentials; set ANTHROPIC_API_KEY or run claude login"

    public struct CredentialError: Error, CustomStringConvertible {
        public let description: String
        init() { description = Credentials.missingCredentialMessage }
    }

    /// Production runner: `claude auth status --json`, read-only, no spend.
    /// Never throws on non-zero exit — a CLI that can't answer is treated as
    /// "not logged in" by the caller, not a hard error.
    public static func defaultAuthStatusRunner() -> String {
        let r = Subprocess.run(["claude", "auth", "status", "--json"])
        return r.stdout
    }

    /// True iff `claude auth status --json` reports `loggedIn: true`.
    /// `runner` is an injectable zero-arg closure -> stdout string (tests inject
    /// fakes; never a real subprocess in the suite). Defensive on every failure
    /// mode -> false, never fabricates. Only the boolean is ever returned —
    /// email/orgId/authMethod NEVER touch the return value, logs, or errors.
    public static func hasCLILogin(runner: (() throws -> String)? = nil) -> Bool {
        let run = runner ?? { defaultAuthStatusRunner() }
        guard let stdout = try? run() else { return false }
        guard let parsed = try? JSONParser.parse(stdout), case .object = parsed else {
            return false
        }
        return parsed["loggedIn"]?.boolValue == true
    }

    /// True iff a usable credential exists via EITHER source. Source 1: a
    /// non-empty ANTHROPIC_API_KEY in `env` (defaults to the process env).
    /// Source 2: an active CLI login, checked ONLY when source 1 is absent.
    public static func hasCredential(
        env: [String: String]? = nil,
        cliLoginRunner: (() throws -> String)? = nil
    ) -> Bool {
        let source = env ?? ProcessInfo.processInfo.environment
        if let value = source[credentialEnv],
           !value.trimmingCharacters(in: .whitespaces).isEmpty {
            return true
        }
        return hasCLILogin(runner: cliLoginRunner)
    }

    /// Throw CredentialError (frozen message) when no credential exists. Never
    /// includes the key value, CLI-login identity, or any distinguishing detail.
    public static func requireCredential(
        env: [String: String]? = nil,
        cliLoginRunner: (() throws -> String)? = nil
    ) throws {
        if !hasCredential(env: env, cliLoginRunner: cliLoginRunner) {
            throw CredentialError()
        }
    }
}
