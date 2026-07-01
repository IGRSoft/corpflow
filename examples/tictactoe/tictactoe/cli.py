"""Interactive command-line Tic-Tac-Toe."""

from .board import Board, InvalidMoveError


def prompt_move(board):
    while True:
        raw = input(f"Player {board.current_player}, choose a cell (1-9): ").strip()
        try:
            position = int(raw) - 1
        except ValueError:
            print("Please enter a number between 1 and 9.")
            continue
        try:
            board.make_move(position)
            return
        except InvalidMoveError as exc:
            print(f"Invalid move: {exc}")


def main():
    board = Board()
    print("Tic-Tac-Toe — cells are numbered 1-9, left to right, top to bottom.\n")
    while not board.is_game_over():
        print(board.render())
        print()
        prompt_move(board)

    print(board.render())
    if board.winner:
        print(f"\nPlayer {board.winner} wins!")
    else:
        print("\nIt's a draw!")


if __name__ == "__main__":
    main()
