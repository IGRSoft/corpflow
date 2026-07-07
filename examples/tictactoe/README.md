# TicTacToe — benchmark fixture reference output

This package is the **reference output of the A/B token benchmark fixture**
(`benchmark/ttt-template/`) — a copy of the finished SwiftUI multiplatform
Tic-Tac-Toe app the benchmark builds WITH and WITHOUT the worktask pipeline.
It is a benchmark workload, not a shipping product.

- Swift 6.2 SwiftPM package, platforms macOS 15+ / iOS 18+, zero external
  dependencies, Swift Testing (`@Test`/`#expect`).
- `TicTacToeKit` library: game engine (board/win/draw/AI minimax), Codable
  leaderboard + settings models with injectable store URLs, cross-platform
  SwiftUI views (main menu / game / leaderboard / settings) with animated
  transitions, protocol-based sound (`SoundPlaying`) with NSSound (macOS) and
  AudioToolbox (iOS) implementations.
- `tictactoe` executable (macOS): `swift run tictactoe --cli` for the
  interactive text loop, `--cli --moves 0,4,1,5,2` for scripted play; default
  launches the SwiftUI app.

Verify:

```sh
swift test                      # full suite (48 tests)
swift run tictactoe --cli --moves 0,4,1,5,2
```

The canonical, benchmarked source of this package lives at
`benchmark/ttt-template/`; regenerate this copy from there after fixture
changes (exclude `.build/` and `.swiftpm/`).
