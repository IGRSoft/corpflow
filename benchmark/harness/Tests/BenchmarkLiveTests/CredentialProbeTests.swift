// CredentialProbeTests.swift — port of benchmark/tests/live/
// test_credential_probe.py (12 tests). Every test injects env/fake runners —
// no network, no spend, no real `claude auth status` shell-out.

import Foundation
import Testing
@testable import BenchmarkKit
@testable import BenchmarkLive

private let frozenMessage =
    "live mode requires credentials; set ANTHROPIC_API_KEY or run claude login"

@Suite("Credential module")
struct CredentialModule {
    @Test func absentKeyThrowsWithFrozenMessage() {
        do {
            try Credentials.requireCredential(env: [:], cliLoginRunner: loggedOutRunner)
            Issue.record("expected CredentialError")
        } catch let e as Credentials.CredentialError {
            #expect(e.description == frozenMessage)
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test func emptyOrWhitespaceKeyCountsAsAbsent() {
        #expect(!Credentials.hasCredential(env: ["ANTHROPIC_API_KEY": ""],
                                           cliLoginRunner: loggedOutRunner))
        #expect(!Credentials.hasCredential(env: ["ANTHROPIC_API_KEY": "   "],
                                           cliLoginRunner: loggedOutRunner))
    }

    @Test func presentKeyPasses() throws {
        #expect(Credentials.hasCredential(env: ["ANTHROPIC_API_KEY": "sk-xxx"]))
        try Credentials.requireCredential(env: ["ANTHROPIC_API_KEY": "sk-xxx"])  // no throw
    }

    @Test func messageNeverContainsAKeyValue() throws {
        let secret = "sk-SUPERSECRET-DO-NOT-LEAK"
        try Credentials.requireCredential(env: ["ANTHROPIC_API_KEY": secret])
        #expect(!Credentials.missingCredentialMessage.contains(secret))
    }

    @Test func cliLoginAloneSatisfiesTheGate() throws {
        // No env var at all — CLI login (fake runner) is the ONLY credential.
        #expect(Credentials.hasCLILogin(runner: loggedInRunner))
        #expect(Credentials.hasCredential(env: [:], cliLoginRunner: loggedInRunner))
        try Credentials.requireCredential(env: [:], cliLoginRunner: loggedInRunner)  // no throw
    }

    @Test func cliLoginFalseWhenLoggedOut() {
        #expect(!Credentials.hasCLILogin(runner: loggedOutRunner))
    }

    @Test func cliLoginDefensiveOnMalformedOutput() {
        #expect(!Credentials.hasCLILogin(runner: { "not json" }))
        #expect(!Credentials.hasCLILogin(runner: { "" }))
        #expect(!Credentials.hasCLILogin(runner: { "[]" }))                     // not a dict
        #expect(!Credentials.hasCLILogin(runner: { "{\"loggedIn\": \"yes\"}" }))  // not bool true
    }

    @Test func cliLoginStatusNeverLeaksIdentityFields() {
        // hasCLILogin only ever returns a Bool; the frozen error message never
        // carries identity fields regardless of runner output.
        _ = Credentials.hasCLILogin(runner: loggedInRunner)
        do {
            try Credentials.requireCredential(env: [:], cliLoginRunner: loggedInRunner)
        } catch let e as Credentials.CredentialError {
            #expect(!e.description.contains("canary@example.invalid"))
            #expect(!e.description.contains("org-canary"))
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test func envKeyShortCircuitsBeforeCLIProbe() {
        // A tripwire runner that throws if ever called — proves the env-var
        // path is checked FIRST and the CLI probe is skipped.
        struct MustNotRun: Error {}
        let result = Credentials.hasCredential(
            env: ["ANTHROPIC_API_KEY": "sk-xxx"],
            cliLoginRunner: { throw MustNotRun() })
        #expect(result)
    }
}

@Suite("Dispatch credential gate")
struct DispatchCredentialGate {
    @Test func dispatchFastExitsWithoutCredential() throws {
        let tripwire = TripwireDispatcher()
        let (benchDir, prompts, record) = try makeLiveSandbox()
        defer { try? FileManager.default.removeItem(atPath: benchDir) }
        var stderrText = ""
        let rc = try Dispatch.dispatch(
            workdir: "cred-missing", budget: 10_000.0, recordPath: record,
            dispatcher: tripwire,
            env: [:],                                // NO credential
            promptsDir: prompts,
            cliLoginRunner: loggedOutRunner,          // NO CLI login either
            benchmarkDir: benchDir,
            stderr: { stderrText += $0 + "\n" })
        #expect(rc == 3)                              // D5: fast credential exit
        #expect(!tripwire.called)                     // dispatched nothing
        #expect(!FileManager.default.fileExists(atPath: record))  // no record
        #expect(stderrText.contains(frozenMessage))
    }

    @Test func dispatchSucceedsViaCLILoginAlone() throws {
        // No ANTHROPIC_API_KEY at all — CLI login (fake) satisfies the gate.
        let fake = RecordingFakeDispatcher(outputs: ["{\"usage\": {\"input_tokens\": 1, \"output_tokens\": 1}, \"total_cost_usd\": 0.001}"])
        let (benchDir, prompts, record) = try makeLiveSandbox(stages: ["PL"])
        defer { try? FileManager.default.removeItem(atPath: benchDir) }
        let rc = try Dispatch.dispatch(
            workdir: "cred-cli-login", budget: 10_000.0, recordPath: record,
            dispatcher: fake, env: [:],
            estimateRunner: { _ in "{\"ai_cost\": {\"usd\": 0.001}}" },
            promptsDir: prompts, stages: ["PL"],
            cliLoginRunner: loggedInRunner, benchmarkDir: benchDir, stderr: { _ in })
        #expect(rc == 0)
        #expect(!fake.calls.isEmpty)   // dispatch proceeded
    }

    @Test func dispatchNeverPrintsTheKeyValue() throws {
        let tripwire = TripwireDispatcher()
        let secret = "sk-LEAK-CANARY-123"
        let (benchDir, prompts, record) = try makeLiveSandbox(stages: ["PL"])
        defer { try? FileManager.default.removeItem(atPath: benchDir) }
        var stderrText = ""
        // Present key; budget passes; tripwire throws at dispatch — expected.
        // We only assert the key never appears in any emitted output.
        do {
            _ = try Dispatch.dispatch(
                workdir: "cred-present", budget: 10_000.0, recordPath: record,
                dispatcher: tripwire, env: ["ANTHROPIC_API_KEY": secret],
                estimateRunner: { _ in "{\"ai_cost\": {\"usd\": 0.001}}" },
                promptsDir: prompts, stages: ["PL"], benchmarkDir: benchDir,
                stderr: { stderrText += $0 + "\n" })
        } catch is TripwireDispatcher.Tripped {
            // tripwire fired — expected
        }
        #expect(!stderrText.contains(secret))
    }
}
