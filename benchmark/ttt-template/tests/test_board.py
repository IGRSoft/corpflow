"""Stdlib unittest suite shipped WITH the generated Tic-Tac-Toe app.

Covers the AC-5 unit-tested surface: win, draw, and move-validation. The
benchmark harness RUNS this suite (in each generated app's workdir) and records
the real pass/fail + test_count. Importable both as part of the package layout
(`python3 -m unittest discover` from the app root) and standalone.
"""

import os
import sys
import unittest

# Make the package importable whether run from the app root or elsewhere.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tictactoe.board import Board, Player, GameState, InvalidMove  # noqa: E402


class TestMoveValidation(unittest.TestCase):
    def test_initial_turn_is_x(self):
        self.assertIs(Board().turn, Player.X)

    def test_play_advances_turn(self):
        b = Board()
        b.play(0)
        self.assertIs(b.turn, Player.O)

    def test_occupied_cell_rejected(self):
        b = Board()
        b.play(0)
        with self.assertRaises(InvalidMove):
            b.play(0)

    def test_out_of_range_rejected(self):
        b = Board()
        for bad in (-1, 9, 100):
            with self.assertRaises(InvalidMove):
                b.play(bad)
        self.assertFalse(b.is_valid_move(9))

    def test_non_int_index_rejected(self):
        b = Board()
        with self.assertRaises(InvalidMove):
            b.play("0")
        self.assertFalse(b.is_valid_move("0"))

    def test_cell_out_of_range_raises(self):
        b = Board()
        with self.assertRaises(InvalidMove):
            b.cell(9)
        with self.assertRaises(InvalidMove):
            b.cell(-1)

    def test_cell_reflects_played_move(self):
        b = Board()
        self.assertIsNone(b.cell(0))
        b.play(0)
        self.assertIs(b.cell(0), Player.X)

    def test_is_valid_move_false_when_occupied(self):
        b = Board()
        b.play(0)
        self.assertFalse(b.is_valid_move(0))

    def test_is_valid_move_false_when_game_over(self):
        b = Board()
        for m in (0, 3, 1, 4, 2):
            b.play(m)
        self.assertIs(b.state(), GameState.X_WINS)
        self.assertFalse(b.is_valid_move(5))

    def test_empty_cells_shrink(self):
        b = Board()
        self.assertEqual(len(b.empty_cells()), 9)
        b.play(4)
        self.assertEqual(len(b.empty_cells()), 8)
        self.assertNotIn(4, b.empty_cells())

    def test_player_other(self):
        self.assertIs(Player.X.other, Player.O)
        self.assertIs(Player.O.other, Player.X)


class TestWin(unittest.TestCase):
    def test_row_win_for_x(self):
        b = Board()
        # X:0 O:3 X:1 O:4 X:2  -> X wins top row
        for m in (0, 3, 1, 4, 2):
            state = b.play(m)
        self.assertIs(state, GameState.X_WINS)
        self.assertIs(b.winner(), Player.X)

    def test_column_win_for_x(self):
        b = Board()
        # X:0 O:1 X:3 O:2 X:6  -> X wins left column (0,3,6)
        for m in (0, 1, 3, 2, 6):
            state = b.play(m)
        self.assertIs(state, GameState.X_WINS)
        self.assertIs(b.winner(), Player.X)

    def test_diagonal_win_for_o(self):
        b = Board()
        # X:1 O:0 X:2 O:4 X:5 O:8 -> O wins 0,4,8 diagonal
        for m in (1, 0, 2, 4, 5, 8):
            state = b.play(m)
        self.assertIs(state, GameState.O_WINS)
        self.assertIs(b.winner(), Player.O)

    def test_anti_diagonal_win_for_o(self):
        b = Board()
        # X:0 O:2 X:1 O:4 X:3 O:6 -> O wins 2,4,6 anti-diagonal
        for m in (0, 2, 1, 4, 3, 6):
            state = b.play(m)
        self.assertIs(state, GameState.O_WINS)
        self.assertIs(b.winner(), Player.O)

    def test_all_eight_win_lines(self):
        lines = (
            (0, 1, 2), (3, 4, 5), (6, 7, 8),
            (0, 3, 6), (1, 4, 7), (2, 5, 8),
            (0, 4, 8), (2, 4, 6),
        )
        for line in lines:
            with self.subTest(line=line):
                b = Board()
                others = [i for i in range(9) if i not in line]
                # Interleave X on the winning line with O elsewhere so X
                # completes the line on its third move.
                for x, o in zip(line, others):
                    b.play(x)
                    if x != line[-1]:
                        b.play(o)
                self.assertIs(b.winner(), Player.X)
                self.assertIs(b.state(), GameState.X_WINS)

    def test_no_moves_after_win(self):
        b = Board()
        for m in (0, 3, 1, 4, 2):
            b.play(m)
        with self.assertRaises(InvalidMove):
            b.play(5)

    def test_winner_none_mid_game(self):
        b = Board()
        b.play(0)
        self.assertIsNone(b.winner())
        self.assertIs(b.state(), GameState.IN_PROGRESS)


class TestDraw(unittest.TestCase):
    def test_full_board_draw(self):
        b = Board()
        # A known draw layout:
        #  X O X
        #  X O O
        #  O X X
        moves = (0, 1, 2, 4, 3, 5, 7, 6, 8)
        state = b.state()
        for m in moves:
            state = b.play(m)
        self.assertIs(state, GameState.DRAW)
        self.assertIsNone(b.winner())
        self.assertTrue(b.is_full())

    def test_is_full_false_until_last_move(self):
        b = Board()
        moves = (0, 1, 2, 4, 3, 5, 7, 6, 8)
        for m in moves[:-1]:
            b.play(m)
            self.assertFalse(b.is_full())
        b.play(moves[-1])
        self.assertTrue(b.is_full())


if __name__ == "__main__":
    unittest.main()
