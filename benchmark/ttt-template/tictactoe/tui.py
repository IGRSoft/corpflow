"""tictactoe.tui — optional curses TUI.

Imports curses lazily inside main() so the package imports cleanly on hosts
without a usable terminal (the unittest suite never enters curses). Falls back
to the CLI when curses is unavailable.
"""

from __future__ import annotations

import sys

from .board import Board, GameState, InvalidMove


def available() -> bool:
    """True if the curses module imports on this host."""
    try:
        import curses  # noqa: F401
        return True
    except Exception:
        return False


def main(argv: list[str] | None = None) -> int:  # pragma: no cover - needs a TTY
    if not available():
        from .cli import main as cli_main
        print("curses unavailable; falling back to CLI", file=sys.stderr)
        return cli_main(argv)

    import curses

    def _run(stdscr) -> GameState:
        curses.curs_set(0)
        board = Board()
        cursor = 0
        while True:
            stdscr.clear()
            stdscr.addstr(0, 0, board.render())
            stdscr.addstr(7, 0, f"{board.turn.value} to move | cursor cell {cursor}")
            stdscr.addstr(8, 0, "arrows/jk move, space=play, q=quit")
            if board.state() is not GameState.IN_PROGRESS:
                stdscr.addstr(9, 0, f"result: {board.state().value} (any key)")
                stdscr.getch()
                return board.state()
            ch = stdscr.getch()
            if ch in (ord("q"), 27):
                return board.state()
            if ch in (curses.KEY_RIGHT, ord("l")):
                cursor = (cursor + 1) % Board.SIZE
            elif ch in (curses.KEY_LEFT, ord("h")):
                cursor = (cursor - 1) % Board.SIZE
            elif ch in (curses.KEY_DOWN, ord("j")):
                cursor = (cursor + 3) % Board.SIZE
            elif ch in (curses.KEY_UP, ord("k")):
                cursor = (cursor - 3) % Board.SIZE
            elif ch in (ord(" "), curses.KEY_ENTER, 10):
                try:
                    board.play(cursor)
                except InvalidMove:
                    pass

    state = curses.wrapper(_run)
    print(f"result: {state.value}")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
