import unittest

from tictactoe.board import Board, InvalidMoveError


class TestMoveValidation(unittest.TestCase):
    def test_valid_move_places_mark_and_switches_player(self):
        board = Board()
        board.make_move(0)
        self.assertEqual(board.cells[0], "X")
        self.assertEqual(board.current_player, "O")

    def test_rejects_out_of_range_position(self):
        board = Board()
        with self.assertRaises(InvalidMoveError):
            board.make_move(9)
        with self.assertRaises(InvalidMoveError):
            board.make_move(-1)

    def test_rejects_non_integer_position(self):
        board = Board()
        with self.assertRaises(InvalidMoveError):
            board.make_move("0")

    def test_rejects_occupied_cell(self):
        board = Board()
        board.make_move(4)
        with self.assertRaises(InvalidMoveError):
            board.make_move(4)

    def test_rejects_move_after_game_over(self):
        board = Board()
        # X wins across the top row: X X X / O O . / . . .
        for pos in (0, 3, 1, 4, 2):
            board.make_move(pos)
        self.assertTrue(board.is_game_over())
        with self.assertRaises(InvalidMoveError):
            board.make_move(8)

    def test_valid_moves_excludes_occupied_cells(self):
        board = Board()
        board.make_move(0)
        board.make_move(1)
        self.assertNotIn(0, board.valid_moves())
        self.assertNotIn(1, board.valid_moves())
        self.assertIn(2, board.valid_moves())


class TestWinDetection(unittest.TestCase):
    def _play(self, moves):
        board = Board()
        for pos in moves:
            board.make_move(pos)
        return board

    def test_row_win(self):
        # X: 0,1,2  O: 3,4
        board = self._play([0, 3, 1, 4, 2])
        self.assertEqual(board.winner, "X")
        self.assertTrue(board.is_game_over())
        self.assertFalse(board.is_draw())

    def test_column_win(self):
        # X: 0,3,6  O: 1,2
        board = self._play([0, 1, 3, 2, 6])
        self.assertEqual(board.winner, "X")

    def test_diagonal_win(self):
        # X: 0,4,8  O: 1,2
        board = self._play([0, 1, 4, 2, 8])
        self.assertEqual(board.winner, "X")

    def test_anti_diagonal_win(self):
        # X: 2,4,6  O: 0,1
        board = self._play([2, 0, 4, 1, 6])
        self.assertEqual(board.winner, "X")

    def test_o_can_win(self):
        # X: 0,1,8  O: 3,4,5 (row win for O)
        board = self._play([0, 3, 1, 4, 8, 5])
        self.assertEqual(board.winner, "O")

    def test_game_stops_advancing_after_win(self):
        board = self._play([0, 3, 1, 4, 2])
        self.assertEqual(board.current_player, "X")  # unchanged since winner locks turn


class TestDrawDetection(unittest.TestCase):
    def test_full_board_no_winner_is_draw(self):
        # X O X
        # X O O
        # O X X
        moves = [0, 1, 2, 4, 3, 5, 7, 6, 8]
        board = Board()
        for pos in moves:
            board.make_move(pos)
        self.assertTrue(board.is_game_over())
        self.assertIsNone(board.winner)
        self.assertTrue(board.is_draw())

    def test_non_full_board_is_not_draw(self):
        board = Board()
        board.make_move(0)
        self.assertFalse(board.is_draw())
        self.assertFalse(board.is_game_over())


if __name__ == "__main__":
    unittest.main()
