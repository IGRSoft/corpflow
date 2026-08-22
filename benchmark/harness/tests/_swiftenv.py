"""One predicate for "can this host build benchmark/ttt-template?".

Two independent things can be missing, and the classes gated on this used to probe
only the first, which is why a Linux runner entered them and failed instead of
skipping: the toolchain itself (a swiftly shim stays on PATH after its toolchain is
uninstalled), and the Apple frameworks the template imports, which a perfectly
working Linux toolchain does not ship. Compiling the imports answers both at once.

Not named test_*.py, so unittest discovery never collects it.
"""

from __future__ import annotations

import functools
import os
import shutil
import subprocess
import tempfile

# Every non-stdlib framework benchmark/ttt-template imports. Adding one here is
# what keeps the gate honest when the template grows a new dependency.
_TEMPLATE_FRAMEWORKS = ("SwiftUI", "AppKit", "AudioToolbox")


@functools.lru_cache(maxsize=1)
def swift_can_build_template() -> bool:
    """True only if a swift compiler exists AND resolves the template's imports."""
    if not shutil.which("swiftc"):
        return False
    tmp = tempfile.mkdtemp(prefix="swiftenv-probe-")
    try:
        probe = os.path.join(tmp, "probe.swift")
        with open(probe, "w", encoding="utf-8") as f:
            f.write("".join(f"import {m}\n" for m in _TEMPLATE_FRAMEWORKS))
        return subprocess.run(["swiftc", "-typecheck", probe],
                              capture_output=True, cwd=tmp,
                              timeout=300).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


SKIP_REASON = ("benchmark/ttt-template needs a swift toolchain with "
               + ", ".join(_TEMPLATE_FRAMEWORKS)
               + " (Apple platforms only) — measurement instrument unavailable here")
