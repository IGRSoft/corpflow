// PromptCoverageLintTests.swift — coverage option 3 (offline prompt lint).
//
// Each rewritten [5]-payload in benchmark/live/prompts/*.txt must name its
// expected skills/agents/commands so the live run actually exercises the
// plugin surface the manifest then verifies. The expected-token table below is
// the checked-in contract (T5 writes prompts against it; the live manifest
// verifies invocations actually happened).
//
// Pending-guard: the suite enables itself once the prompts are rewritten for
// the SwiftUI multiplatform scope (sentinel: pl.txt names SwiftUI). Before T5
// lands, the suite is skipped with a visible message; at gate G4 it MUST run
// green. If T5 rewrites pl.txt but misses another file, the suite runs and
// fails on that file — exactly the drift this lint exists to catch.

import Foundation
import Testing

private let promptsDir = liveTestsRepoRoot + "/benchmark/live/prompts"

/// Sentinel: prompts are considered rewritten once pl.txt targets the SwiftUI
/// multiplatform scope.
private func promptsRewrittenForSwiftUIScope() -> Bool {
    guard let pl = try? String(contentsOfFile: promptsDir + "/pl.txt", encoding: .utf8)
    else { return false }
    return pl.contains("SwiftUI")
}

/// stage-file -> tokens the [5] payload MUST contain (case-sensitive).
private let expectedTokens: [String: [String]] = [
    "pl.txt": ["SwiftUI", "PRD", "complexity"],
    "ar.txt": ["apple-architector", "MVVM", "router"],
    "tl.txt": ["track", "engine", "tests"],
    "dv.txt": ["apple-developer:macos-developer", "apple-developer:ios-developer",
               "swiftui-skills", "swift-testing-entry", "accessibility-patterns",
               "swift test"],
    "dr.txt": ["/swiftui-review", "state-management", "animation"],
    "sr.txt": ["security-review-process", "sandbox", "input validation"],
    "qa.txt": ["test-generator", "make test-ios"],
    "dc.txt": ["README"],
    "fn.txt": ["close-out"],
    "st.txt": ["ROI"],
]

@Suite("Prompt coverage lint (option 3)",
       .enabled(if: promptsRewrittenForSwiftUIScope(),
                "pending: prompts not yet rewritten for the SwiftUI scope (T5)"))
struct PromptCoverageLint {
    @Test(arguments: expectedTokens.keys.sorted())
    func promptNamesItsExpectedSurface(file: String) throws {
        let text = try String(contentsOfFile: promptsDir + "/" + file, encoding: .utf8)
        for token in expectedTokens[file] ?? [] {
            #expect(text.contains(token), "\(file) must name '\(token)'")
        }
    }

    @Test(arguments: expectedTokens.keys.sorted())
    func promptKeepsTheNoThirdPartyFraming(file: String) throws {
        // Preserve the stdlib-only spirit: Swift 6 + SwiftPM + Apple SDKs ONLY.
        let text = try String(contentsOfFile: promptsDir + "/" + file, encoding: .utf8)
        #expect(text.contains("Swift"), "\(file) lost the Swift scope framing")
    }

    @Test func allTenPromptFilesExist() {
        for file in expectedTokens.keys {
            #expect(FileManager.default.fileExists(atPath: promptsDir + "/" + file),
                    "missing prompt file \(file)")
        }
    }

    @Test func srPromptIsRewrittenForTheSwiftScope() throws {
        // D3 headline: the live pipeline dispatches SR even though this
        // worktask dropped SR as a stage — sr.txt must target the new scope.
        let sr = try String(contentsOfFile: promptsDir + "/sr.txt", encoding: .utf8)
        #expect(sr.contains("SwiftUI") || sr.contains("Swift"),
                "sr.txt still targets the old Python scope")
        #expect(sr.contains("score"), "sr.txt should cover leaderboard score storage")
    }
}
