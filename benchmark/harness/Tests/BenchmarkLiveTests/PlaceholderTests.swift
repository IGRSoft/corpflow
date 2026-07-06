// PlaceholderTests.swift — T2 placeholder so the test target compiles before
// T3 lands the full BenchmarkLive suite (live-gate, budget, credentials,
// prompt-assembly, SSOT, prompt-coverage lint). Replaced in T3.

import Testing
@testable import BenchmarkLive

@Suite("BenchmarkLive placeholder")
struct BenchmarkLivePlaceholder {
    @Test func moduleLinks() {
        #expect(Bool(true))
    }
}
