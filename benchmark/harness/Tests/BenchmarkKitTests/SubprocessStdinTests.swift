// SubprocessStdinTests.swift — regression tests for the nil-input stdin
// contract (QA live-probe finding 1): a Subprocess spawned WITHOUT input must
// NOT inherit the caller's stdin (an inherited tty/pipe stdin blocks children
// like `claude auth status --json` forever in nested/headless contexts). With
// no input the child gets FileHandle.nullDevice — immediate EOF.

import Foundation
import Testing
@testable import BenchmarkKit

// `.serialized`: every test here spawns a real child via `Subprocess.run`,
// which holds one thread in `waitUntilExit` plus two draining the stdout/stderr
// pipes. Run in parallel with the equally subprocess-heavy generator suites,
// enough of these at once exhaust the libdispatch worker pool and the whole
// `swift test` run deadlocks (reproduced: 0 progress for >250s). Serializing
// this suite caps its own concurrent-child count at one, keeping the run's peak
// subprocess/thread demand at the (green) baseline level.
@Suite("Subprocess nil-input stdin contract", .serialized)
struct SubprocessStdinContract {
    @Test func nilInputChildStdinIsTheNullDevice() {
        // Deterministic identity check: the child's fd 0 must be /dev/null
        // (same device:inode), regardless of what the test runner's stdin is.
        let r = Subprocess.run(["bash", "-c",
            "a=$(stat -L -f '%d:%i' /dev/fd/0); b=$(stat -L -f '%d:%i' /dev/null); "
            + "if [ \"$a\" = \"$b\" ]; then echo NULLDEV; else echo OTHER:$a; fi"])
        #expect(r.exitCode == 0, "probe failed: \(r.stderr.prefix(200))")
        #expect(r.stdout.contains("NULLDEV"),
                "child stdin is not /dev/null: \(r.stdout.prefix(120))")
    }

    @Test func nilInputChildSeesImmediateEOF() {
        // Behavioral check with a watchdog: `cat` with nil input must hit EOF
        // and TERMINATE instead of hanging forever on an inherited
        // never-closing stdin. The watchdog turns the regression (an infinite
        // hang) into a test FAILURE rather than a suite hang.
        //
        // The bound is termination, not latency: a true stdin-inheritance
        // regression never terminates, so any finite watchdog catches it. The
        // 60s budget is deliberately generous — `Subprocess.run` drains its
        // pipes on the global libdispatch pool, which the concurrently running
        // generator suites can saturate; under that contention a correct child
        // still finishes but its observation can be delayed well past a few
        // seconds. 60s stays comfortably below any real hang (∞) while
        // absorbing pool starvation, keeping the test non-flaky in parallel.
        let done = DispatchSemaphore(value: 0)
        let result = ResultBox()
        Thread.detachNewThread {
            result.store(Subprocess.run(["cat"]))
            done.signal()
        }
        let waited = done.wait(timeout: .now() + 60)
        #expect(waited == .success,
                "cat with nil input did not terminate within 60s — stdin was inherited")
        if waited == .success, let r = result.value {
            #expect(r.exitCode == 0)
            #expect(r.stdout.isEmpty)
        }
    }

    @Test func explicitInputStillFlowsToTheChild() {
        // The fix must not break the input path: stdin content round-trips.
        let r = Subprocess.run(["cat"], input: "hello stdin\n")
        #expect(r.exitCode == 0)
        #expect(r.stdout == "hello stdin\n")
    }
}

/// Thread-safe result carrier for the watchdog test.
private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Subprocess?
    func store(_ r: Subprocess) { lock.lock(); stored = r; lock.unlock() }
    var value: Subprocess? { lock.lock(); defer { lock.unlock() }; return stored }
}
