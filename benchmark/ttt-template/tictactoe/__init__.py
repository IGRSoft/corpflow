"""tictactoe — a minimal, runnable stdlib Tic-Tac-Toe package.

This package is the canonical benchmark workload. In deterministic mode BOTH the
WITH-plugin and WITHOUT-plugin generators materialize this same source (quality
held constant; the comparison measures process overhead). The harness then runs
this package's own unittest suite and records real loc/test_count/pass_fail.
"""

from .board import Board, Player, GameState

__all__ = ["Board", "Player", "GameState"]
__version__ = "1.0.0"
