"""tictactoe.cli — a minimal stdlib command-line interface.

Run: python3 -m tictactoe.cli            (interactive)
     python3 -m tictactoe.cli --moves 0,4,1,5,2   (scripted; for non-interactive demo)
"""

from __future__ import annotations

import argparse
import sys

from .board import Board, GameState, InvalidMove


def _play_scripted(board: Board, moves: list[int], out=sys.stdout) -> GameState:
    state = board.state()
    for m in moves:
        if state is not GameState.IN_PROGRESS:
            break
        state = board.play(m)
    print(board.render(), file=out)
    print(f"result: {state.value}", file=out)
    return state


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="tictactoe", description="Tic-Tac-Toe CLI")
    parser.add_argument(
        "--moves",
        help="comma-separated cell indices (0..8) to play non-interactively",
    )
    args = parser.parse_args(argv)

    board = Board()

    if args.moves is not None:
        try:
            moves = [int(x) for x in args.moves.split(",") if x.strip() != ""]
        except ValueError:
            print("error: --moves must be comma-separated integers 0..8", file=sys.stderr)
            return 2
        try:
            _play_scripted(board, moves)
        except InvalidMove as e:
            print(f"invalid move: {e}", file=sys.stderr)
            return 1
        return 0

    # Interactive loop (best-effort; EOF ends the game gracefully).
    print("Tic-Tac-Toe — enter a cell index 0..8 (Ctrl-D to quit)")
    while board.state() is GameState.IN_PROGRESS:
        print(board.render())
        print(f"{board.turn.value} to move: ", end="", flush=True)
        line = sys.stdin.readline()
        if not line:
            print("\nbye")
            return 0
        try:
            board.play(int(line.strip()))
        except (ValueError, InvalidMove) as e:
            print(f"invalid move: {e}")
    print(board.render())
    print(f"result: {board.state().value}")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
