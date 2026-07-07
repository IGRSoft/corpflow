import TicTacToeKit
#if canImport(SwiftUI)
import SwiftUI
#endif
import Foundation

// MARK: - CLI

/// Plays `moves` against `board` in order, stopping early if the game ends,
/// then prints the final render + `result: <state>` line — matching
/// `tictactoe/cli.py::_play_scripted` exactly.
func playScripted(board: inout Board, moves: [Int]) throws(InvalidMove) -> GameState {
    var state = board.state()
    for m in moves {
        if state != .inProgress {
            break
        }
        state = try board.play(m)
    }
    print(board.render())
    print("result: \(state.rawValue)")
    return state
}

/// Parses a comma-separated list of integers. Returns `nil` if any token
/// fails to parse (matching Python's `int(x)` raising `ValueError`).
func parseMoves(_ raw: String) -> [Int]? {
    var result: [Int] = []
    for token in raw.split(separator: ",") {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { continue }
        guard let value = Int(trimmed) else { return nil }
        result.append(value)
    }
    return result
}

func runInteractiveCLI() -> Int32 {
    print("Tic-Tac-Toe — enter a cell index 0..8 (Ctrl-D to quit)")
    var board = Board()
    while board.state() == .inProgress {
        print(board.render())
        print("\(board.turn.rawValue) to move: ", terminator: "")
        guard let line = readLine(strippingNewline: true) else {
            print("\nbye")
            return 0
        }
        guard let value = Int(line.trimmingCharacters(in: .whitespaces)) else {
            print("invalid move: cell index out of range: \(line) (expected 0..8)")
            continue
        }
        do {
            try board.play(value)
        } catch {
            print("invalid move: \(error.message)")
        }
    }
    print(board.render())
    print("result: \(board.state().rawValue)")
    return 0
}

func runScriptedCLI(movesArg: String) -> Int32 {
    guard let moves = parseMoves(movesArg) else {
        FileHandle.standardError.write(
            Data("error: --moves must be comma-separated integers 0..8\n".utf8)
        )
        return 2
    }
    var board = Board()
    do {
        _ = try playScripted(board: &board, moves: moves)
    } catch {
        FileHandle.standardError.write(Data("invalid move: \(error.message)\n".utf8))
        return 1
    }
    return 0
}

// MARK: - SwiftUI App

#if canImport(SwiftUI)
struct TicTacToeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
#endif

// MARK: - Entry point

@MainActor
func runMain() -> Int32 {
    let args = Array(CommandLine.arguments.dropFirst())
    let hasCLIFlag = args.contains("--cli")
    let movesArg = args.firstIndex(of: "--moves").flatMap { idx -> String? in
        let next = idx + 1
        return next < args.count ? args[next] : nil
    }

    if let movesArg {
        return runScriptedCLI(movesArg: movesArg)
    }
    if hasCLIFlag {
        return runInteractiveCLI()
    }

    #if canImport(SwiftUI)
    TicTacToeApp.main()
    return 0
    #else
    return 0
    #endif
}

exit(MainActor.assumeIsolated { runMain() })
