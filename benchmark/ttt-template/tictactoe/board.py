"""tictactoe.board — core game logic (win / draw / move-validation).

This is the unit-tested surface of the generated app (see tests/test_board.py).
Pure stdlib, no third-party deps.
"""

from __future__ import annotations

from enum import Enum


class Player(str, Enum):
    X = "X"
    O = "O"

    @property
    def other(self) -> "Player":
        return Player.O if self is Player.X else Player.X


class GameState(str, Enum):
    IN_PROGRESS = "in_progress"
    X_WINS = "X_wins"
    O_WINS = "O_wins"
    DRAW = "draw"


# The 8 winning lines as index triples on the 0..8 flattened board.
_WIN_LINES: tuple[tuple[int, int, int], ...] = (
    (0, 1, 2), (3, 4, 5), (6, 7, 8),   # rows
    (0, 3, 6), (1, 4, 7), (2, 5, 8),   # cols
    (0, 4, 8), (2, 4, 6),              # diagonals
)


class InvalidMove(ValueError):
    """Raised when a move targets an out-of-range or occupied cell."""


class Board:
    """A 3x3 Tic-Tac-Toe board. Cells are None (empty) or a Player."""

    SIZE = 9

    def __init__(self) -> None:
        self._cells: list[Player | None] = [None] * self.SIZE
        self._turn: Player = Player.X

    # --- introspection -------------------------------------------------------
    @property
    def turn(self) -> Player:
        return self._turn

    def cell(self, index: int) -> Player | None:
        self._check_index(index)
        return self._cells[index]

    def empty_cells(self) -> list[int]:
        return [i for i, c in enumerate(self._cells) if c is None]

    def is_full(self) -> bool:
        return all(c is not None for c in self._cells)

    # --- move validation + application --------------------------------------
    @staticmethod
    def _check_index(index: int) -> None:
        if not isinstance(index, int) or not (0 <= index < Board.SIZE):
            raise InvalidMove(f"cell index out of range: {index!r} (expected 0..8)")

    def is_valid_move(self, index: int) -> bool:
        try:
            self._check_index(index)
        except InvalidMove:
            return False
        return self._cells[index] is None and self.state() is GameState.IN_PROGRESS

    def play(self, index: int) -> GameState:
        """Apply the current player's move at `index`; advance turn; return state.

        Raises InvalidMove for an out-of-range/occupied cell or a finished game.
        """
        self._check_index(index)
        if self.state() is not GameState.IN_PROGRESS:
            raise InvalidMove("game is already over")
        if self._cells[index] is not None:
            raise InvalidMove(f"cell {index} is already occupied")
        self._cells[index] = self._turn
        st = self.state()
        if st is GameState.IN_PROGRESS:
            self._turn = self._turn.other
        return st

    # --- win / draw detection ------------------------------------------------
    def winner(self) -> Player | None:
        for a, b, c in _WIN_LINES:
            v = self._cells[a]
            if v is not None and self._cells[b] is v and self._cells[c] is v:
                return v
        return None

    def state(self) -> GameState:
        w = self.winner()
        if w is Player.X:
            return GameState.X_WINS
        if w is Player.O:
            return GameState.O_WINS
        if self.is_full():
            return GameState.DRAW
        return GameState.IN_PROGRESS

    # --- rendering -----------------------------------------------------------
    def render(self) -> str:
        def sym(i: int) -> str:
            c = self._cells[i]
            return c.value if c is not None else str(i)
        rows = [
            f" {sym(0)} | {sym(1)} | {sym(2)} ",
            "---+---+---",
            f" {sym(3)} | {sym(4)} | {sym(5)} ",
            "---+---+---",
            f" {sym(6)} | {sym(7)} | {sym(8)} ",
        ]
        return "\n".join(rows)
