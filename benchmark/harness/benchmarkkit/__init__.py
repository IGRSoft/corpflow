"""BenchmarkKit — deterministic benchmark harness (metrics, rotation, generation, report).

Imports must never reach ``benchmarklive`` (AC-8 import isolation): the deterministic
path and its entrypoints stay live-free.
"""
