// TempDirCleanupTests.swift — OI-1 (P1) regression: the harness must not leak
// ephemeral app-copy temp dirs. The Swift migration dropped the Python
// tempfile-context guarantee, which accumulated ~150MB `.build/` caches per run
// and ENOSPC-killed two live attempts. These tests are the CI gate ST
// recommended: they fail if any generated temp dir survives past completion.
//
// Deliberately light: none of these does a real 150MB nested `swift test`
// build. They exercise the CLEANUP seams directly (defer scoping), which is the
// behavior under regression — not the (already-covered) generation path.

import Foundation
import Testing
@testable import BenchmarkKit

@Suite("OI-1 temp-dir cleanup", .serialized)
struct TempDirCleanup {
    /// AC-OI1-3 (success path): withEphemeralWorkdir removes the workdir it owns
    /// after body returns normally.
    @Test func ephemeralWorkdirRemovedOnSuccess() throws {
        var captured = ""
        try Generators.withEphemeralWorkdir(prefix: "ttt_test_cleanup_") { wd in
            captured = wd
            #expect(FileManager.default.fileExists(atPath: wd),
                    "workdir must exist inside the body")
            // Simulate a generated app copy so the removal is non-trivial.
            try "x".write(toFile: wd + "/marker.txt", atomically: true, encoding: .utf8)
        }
        #expect(!captured.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: captured),
                "ephemeral workdir must NOT exist after withEphemeralWorkdir returns")
    }

    /// AC-OI1-3 (failure path): the defer sweeps the workdir even when body
    /// throws — a mid-generation error must not leak the copy.
    @Test func ephemeralWorkdirRemovedOnThrow() {
        struct Boom: Error {}
        var captured = ""
        #expect(throws: Boom.self) {
            try Generators.withEphemeralWorkdir(prefix: "ttt_test_cleanup_") { wd in
                captured = wd
                try "x".write(toFile: wd + "/marker.txt", atomically: true, encoding: .utf8)
                throw Boom()
            }
        }
        #expect(!captured.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: captured),
                "ephemeral workdir must NOT survive a thrown error")
    }

    /// AC-OI1-1: runAppTests removes the nested `.build/` cache (the ~150MB heavy
    /// artifact) on return, including the failure path. We stage an EMPTY appDir
    /// (no Package.swift) so the nested `swift test` fails fast (pass_fail=fail),
    /// and pre-seed a `.build/` dir standing in for the build cache; the defer in
    /// runAppTests must remove it regardless of the non-zero exit. No 150MB build.
    @Test func runAppTestsSweepsBuildCacheOnFailurePath() throws {
        let fm = FileManager.default
        try Generators.withEphemeralWorkdir(prefix: "ttt_test_build_") { appDir in
            let buildDir = appDir + "/.build"
            try fm.createDirectory(atPath: buildDir, withIntermediateDirectories: true)
            try "cache".write(toFile: buildDir + "/artifact.bin", atomically: true, encoding: .utf8)
            #expect(fm.fileExists(atPath: buildDir))

            let (_, passFail) = GenLib.runAppTests(appDir: appDir)
            // No Package.swift -> nested swift test exits non-zero.
            #expect(passFail == "fail")
            // The defer must have swept the build cache even on the failure path.
            #expect(!fm.fileExists(atPath: buildDir),
                    ".build cache must be removed after runAppTests returns")
            // The app copy itself (the caller's measured dir) is untouched.
            #expect(fm.fileExists(atPath: appDir),
                    "runAppTests must not delete the caller's appDir")
        }
    }

    /// Guard the scoping invariant (R3): withEphemeralWorkdir must never delete a
    /// sibling/external directory — only the workdir it created.
    @Test func cleanupDoesNotTouchExternalPaths() throws {
        let fm = FileManager.default
        let external = NSTemporaryDirectory() + "ttt_external_keep_\(UUID().uuidString)"
        try fm.createDirectory(atPath: external, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: external) }
        try Generators.withEphemeralWorkdir(prefix: "ttt_test_scope_") { _ in }
        #expect(fm.fileExists(atPath: external),
                "cleanup must not touch directories it does not own")
    }
}
