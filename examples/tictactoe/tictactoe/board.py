"""Core game state and rules for Tic-Tac-Toe."""

EMPTY = " "
SIZE = 3

_WIN_LINES = [
    (0, 1, 2), (3, 4, 5), (6, 7, 8),  # rows
    (0, 3, 6), (1, 4, 7), (2, 5, 8),  # columns
    (0, 4, 8), (2, 4, 6),             # diagonals
]


class InvalidMoveError(Exception):
    """Raised when a move is out of range, occupied, or the game has ended."""


class Board:
    """A 3x3 Tic-Tac-Toe board with turn tracking and win/draw detection."""

    def __init__(self):
        self.cells = [EMPTY] * (SIZE * SIZE)
        self.current_player = "X"
        self.winner = None

    def is_full(self):
        return all(cell != EMPTY for cell in self.cells)

    def is_game_over(self):
        return self.winner is not None or self.is_full()

    def is_draw(self):
        return self.winner is None and self.is_full()

    def valid_moves(self):
        return [i for i, cell in enumerate(self.cells) if cell == EMPTY]

    def make_move(self, position):
        """Place the current player's mark at `position` (0-8).

        Raises InvalidMoveError if the position is out of range, already
        occupied, or the game has already ended.
        """
        if self.is_game_over():
            raise InvalidMoveError("Game is already over")
        if not isinstance(position, int) or not (0 <= position < SIZE * SIZE):
            raise InvalidMoveError(f"Position must be an int in 0..8, got {position!r}")
        if self.cells[position] != EMPTY:
            raise InvalidMoveError(f"Cell {position} is already occupied")

        self.cells[position] = self.current_player
        self.winner = self._check_winner()
        if self.winner is None:
            self.current_player = "O" if self.current_player == "X" else "X"
        return self

    def _check_winner(self):
        for a, b, c in _WIN_LINES:
            if self.cells[a] != EMPTY and self.cells[a] == self.cells[b] == self.cells[c]:
                return self.cells[a]
        return None

    def render(self):
        rows = []
        for r in range(SIZE):
            row_cells = self.cells[r * SIZE:(r + 1) * SIZE]
            rows.append(" | ".join(row_cells))
        return "\n---------\n".join(rows)
