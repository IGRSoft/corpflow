#!/usr/bin/env python3
"""App Store screenshot layout calculator.

Encodes the device matrix from references/device-specs.md and the proportional
layout formulas from references/layout-patterns.md.  Outputs compact JSON ready
to paste into batch_design.  Op-string assembly, copy, and color decisions stay
with the model — this script only resolves geometry.

Usage
-----
  # By device key
  python layout-calc.py iphone-6.9-1320x2868 --layout A

  # By explicit dimensions
  python layout-calc.py --w 1320 --h 2868 --platform ios --layout B

  # With aspect override (e.g. forced 9:19.5 ratio)
  python layout-calc.py iphone-6.9-1320x2868 --layout A --aspect 0.461

  # Self-test (no network, no external deps)
  python layout-calc.py --self-test
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from typing import Literal

# ---------------------------------------------------------------------------
# Device matrix (from references/device-specs.md)
# ---------------------------------------------------------------------------

Platform = Literal["ios", "ipad", "macos", "tvos", "watchos"]

FULL_BLEED_PLATFORMS: frozenset[str] = frozenset({"tvos", "watchos"})


@dataclass(frozen=True)
class DeviceSpec:
    name: str
    w: int
    h: int
    platform: Platform
    headline_fs: int
    subtitle_fs: int
    # True  → full-bleed passthrough (tvOS / watchOS)
    full_bleed: bool = False


# Key format: <platform>-<screen-size>-<WxH>  (lowercase, no spaces)
_DEVICE_REGISTRY: dict[str, DeviceSpec] = {
    # iOS Phones
    "iphone-6.9-1320x2868": DeviceSpec("iPhone 6.9\" (1320x2868)", 1320, 2868, "ios", 72, 42),
    "iphone-6.9-1290x2796": DeviceSpec("iPhone 6.9\" (1290x2796)", 1290, 2796, "ios", 70, 40),
    "iphone-6.9-1260x2736": DeviceSpec("iPhone 6.9\" (1260x2736)", 1260, 2736, "ios", 68, 40),
    "iphone-6.5-1284x2778": DeviceSpec("iPhone 6.5\" (1284x2778)", 1284, 2778, "ios", 70, 40),
    "iphone-6.5-1242x2688": DeviceSpec("iPhone 6.5\" (1242x2688)", 1242, 2688, "ios", 68, 38),
    "iphone-6.3-1206x2622": DeviceSpec("iPhone 6.3\" (1206x2622)", 1206, 2622, "ios", 66, 38),
    "iphone-6.3-1179x2556": DeviceSpec("iPhone 6.3\" (1179x2556)", 1179, 2556, "ios", 64, 36),
    # iPads
    "ipad-13-2064x2752":    DeviceSpec("iPad 13\" (2064x2752)", 2064, 2752, "ipad", 84, 48),
    "ipad-13-2048x2732":    DeviceSpec("iPad 13\" (2048x2732)", 2048, 2732, "ipad", 84, 48),
    "ipad-12.9-2048x2732":  DeviceSpec("iPad 12.9\" (2048x2732)", 2048, 2732, "ipad", 84, 48),
    "ipad-11-1668x2420":    DeviceSpec("iPad 11\" (1668x2420)", 1668, 2420, "ipad", 72, 42),
    "ipad-11-1668x2388":    DeviceSpec("iPad 11\" (1668x2388)", 1668, 2388, "ipad", 72, 42),
    "ipad-11-1640x2360":    DeviceSpec("iPad 11\" (1640x2360)", 1640, 2360, "ipad", 70, 40),
    "ipad-11-1488x2266":    DeviceSpec("iPad 11\" (1488x2266)", 1488, 2266, "ipad", 64, 36),
    # macOS (landscape)
    "mac-2880x1800":        DeviceSpec("Mac 2880x1800", 2880, 1800, "macos", 84, 48),
    "mac-2560x1600":        DeviceSpec("Mac 2560x1600", 2560, 1600, "macos", 72, 42),
    "mac-1280x800":         DeviceSpec("Mac 1280x800", 1280, 800, "macos", 48, 28),
    # tvOS (full-bleed)
    "appletv-4k-3840x2160": DeviceSpec("Apple TV 4K (3840x2160)", 3840, 2160, "tvos", 0, 0, full_bleed=True),
    "appletv-1920x1080":    DeviceSpec("Apple TV (1920x1080)", 1920, 1080, "tvos", 0, 0, full_bleed=True),
    # watchOS (full-bleed)
    "watch-ultra3-422x514": DeviceSpec("Apple Watch Ultra 3 (422x514)", 422, 514, "watchos", 0, 0, full_bleed=True),
    "watch-ultra-410x502":  DeviceSpec("Apple Watch Ultra (410x502)", 410, 502, "watchos", 0, 0, full_bleed=True),
    "watch-s10-416x496":    DeviceSpec("Apple Watch Series 10 (416x496)", 416, 496, "watchos", 0, 0, full_bleed=True),
}

# ---------------------------------------------------------------------------
# Aspect ratios
# ---------------------------------------------------------------------------

_PHONE_ASPECT = 19.5 / 9.0   # ~2.167  — phone screenshot height:width
_MAC_ASPECT   = 16.0 / 10.0  # 1.6     — Mac screenshot width:height

# ---------------------------------------------------------------------------
# Layout formulas  (from references/layout-patterns.md)
# ---------------------------------------------------------------------------

LayoutKey = Literal["A", "B", "C", "D"]


def _compute_screenshot(
    w: int,
    h: int,
    height_ratio: float,
    y_ratio: float,
    aspect: float,  # h/w for portrait, w/h for landscape (mac)
    is_mac: bool,
    corner_radius: int,
) -> dict[str, int | float]:
    ss_h = round(h * height_ratio)
    if is_mac:
        # mac: ss_w derived from height × mac_aspect (w/h = 1.6)
        ss_w = round(ss_h * aspect)
    else:
        # portrait: ss_w derived from height ÷ aspect (h/w ratio)
        ss_w = round(ss_h / aspect)
    ss_x = round((w - ss_w) / 2)
    ss_y = round(h * y_ratio)
    return {"x": ss_x, "y": ss_y, "w": ss_w, "h": ss_h, "cornerRadius": corner_radius}


def compute_layout(
    w: int,
    h: int,
    platform: Platform,
    layout: LayoutKey,
    headline_fs: int,
    subtitle_fs: int,
    aspect: float | None = None,
) -> dict[str, object]:
    """Return the geometry dict for one device/layout combination."""
    is_mac = platform == "macos"

    # Default aspect based on platform
    if aspect is None:
        effective_aspect = _MAC_ASPECT if is_mac else _PHONE_ASPECT
    else:
        effective_aspect = aspect

    corner_radius = 16 if is_mac else 32

    # ---- Layout A: text top, screenshot bottom-center (hero shot) ----
    if layout == "A":
        headline = {
            "x": round(w * 0.06), "y": round(h * 0.04),
            "w": round(w * 0.88), "fontSize": headline_fs, "textAlign": "center",
        }
        subtitle = {
            "x": round(w * 0.10), "y": round(h * 0.13),
            "w": round(w * 0.80), "fontSize": subtitle_fs,
            "opacity": 0.75, "textAlign": "center",
        }
        if is_mac:
            subtitle["y"] = round(h * 0.16)
            screenshot = _compute_screenshot(w, h, 0.68, 0.30, effective_aspect, True, corner_radius)
        else:
            screenshot = _compute_screenshot(w, h, 0.74, 0.24, effective_aspect, False, corner_radius)

    # ---- Layout B: text top-left, screenshot below centered ----
    elif layout == "B":
        headline = {
            "x": round(w * 0.06), "y": round(h * 0.04),
            "w": round(w * 0.88), "fontSize": headline_fs, "textAlign": "left",
        }
        subtitle = {
            "x": round(w * 0.06), "y": round(h * 0.13),
            "w": round(w * 0.80), "fontSize": subtitle_fs,
            "opacity": 0.75, "textAlign": "left",
        }
        if is_mac:
            subtitle["y"] = round(h * 0.16)
            screenshot = _compute_screenshot(w, h, 0.68, 0.30, effective_aspect, True, corner_radius)
        else:
            screenshot = _compute_screenshot(w, h, 0.74, 0.24, effective_aspect, False, corner_radius)

    # ---- Layout C: screenshot top, text bottom ----
    elif layout == "C":
        screenshot = _compute_screenshot(w, h, 0.65, 0.03, effective_aspect, is_mac, corner_radius)
        headline = {
            "x": round(w * 0.06), "y": round(h * 0.72),
            "w": round(w * 0.88), "fontSize": headline_fs, "textAlign": "center",
        }
        subtitle = {
            "x": round(w * 0.10), "y": round(h * 0.81),
            "w": round(w * 0.80), "fontSize": subtitle_fs,
            "opacity": 0.75, "textAlign": "center",
        }

    # ---- Layout D: text top, large screenshot below ----
    elif layout == "D":
        headline = {
            "x": round(w * 0.06), "y": round(h * 0.04),
            "w": round(w * 0.88), "fontSize": headline_fs, "textAlign": "center",
        }
        subtitle = {
            "x": round(w * 0.10), "y": round(h * 0.13),
            "w": round(w * 0.80), "fontSize": subtitle_fs,
            "opacity": 0.75, "textAlign": "center",
        }
        if is_mac:
            subtitle["y"] = round(h * 0.16)
            screenshot = _compute_screenshot(w, h, 0.68, 0.30, effective_aspect, True, corner_radius)
        else:
            screenshot = _compute_screenshot(w, h, 0.78, 0.22, effective_aspect, False, corner_radius)

    else:
        msg = f"Unknown layout: {layout!r}"
        raise ValueError(msg)

    return {
        "headline":   headline,
        "subtitle":   subtitle,
        "screenshot": screenshot,
    }


# ---------------------------------------------------------------------------
# Full-bleed passthrough
# ---------------------------------------------------------------------------

def full_bleed_result(spec: DeviceSpec) -> dict[str, object]:
    """Return a canvas-fill passthrough for tvOS / watchOS."""
    return {
        "device": {"name": spec.name, "w": spec.w, "h": spec.h},
        "full_bleed": True,
        "screenshot": {"x": 0, "y": 0, "w": spec.w, "h": spec.h, "cornerRadius": 0},
    }


# ---------------------------------------------------------------------------
# CLI helpers
# ---------------------------------------------------------------------------

def _resolve_spec(args: argparse.Namespace) -> DeviceSpec:
    """Resolve DeviceSpec from CLI args."""
    if args.device:
        key = args.device.lower()
        if key not in _DEVICE_REGISTRY:
            known = ", ".join(sorted(_DEVICE_REGISTRY))
            sys.exit(f"Unknown device key {key!r}. Known keys:\n  {known}")
        return _DEVICE_REGISTRY[key]

    # --w / --h / --platform path
    if args.w is None or args.h is None or args.platform is None:
        sys.exit("Provide either a device key or --w, --h, and --platform.")

    platform: Platform = args.platform
    full_bleed = platform in FULL_BLEED_PLATFORMS

    # Infer font sizes from the closest device in the registry for the platform
    candidates = [s for s in _DEVICE_REGISTRY.values() if s.platform == platform]
    if candidates and not full_bleed:
        # pick closest by area
        area = args.w * args.h
        closest = min(candidates, key=lambda s: abs(s.w * s.h - area))
        hfs, sfs = closest.headline_fs, closest.subtitle_fs
    else:
        hfs, sfs = 0, 0

    name = f"{platform.upper()} ({args.w}x{args.h})"
    return DeviceSpec(name, args.w, args.h, platform, hfs, sfs, full_bleed=full_bleed)


# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

def _self_test() -> None:  # noqa: PLR0912, PLR0915
    """Verify hand-computed values for two devices and layouts."""
    errors: list[str] = []

    def check(label: str, got: object, expected: object) -> None:
        if got != expected:
            errors.append(f"{label}: expected {expected!r}, got {got!r}")

    # --- Test 1: iPhone 6.9 (1320x2868), Layout A ---
    spec = _DEVICE_REGISTRY["iphone-6.9-1320x2868"]
    result = compute_layout(spec.w, spec.h, spec.platform, "A", spec.headline_fs, spec.subtitle_fs)

    # headline: x=W*0.06=79.2→79, y=H*0.04=114.72→115, w=W*0.88=1161.6→1162
    check("A/headline/x", result["headline"]["x"], round(1320 * 0.06))   # 79
    check("A/headline/y", result["headline"]["y"], round(2868 * 0.04))   # 115
    check("A/headline/w", result["headline"]["w"], round(1320 * 0.88))   # 1162
    check("A/headline/fontSize", result["headline"]["fontSize"], 72)

    # subtitle: x=W*0.10=132, y=H*0.13=372.84→373, w=W*0.80=1056
    check("A/subtitle/x", result["subtitle"]["x"], round(1320 * 0.10))   # 132
    check("A/subtitle/y", result["subtitle"]["y"], round(2868 * 0.13))   # 373
    check("A/subtitle/w", result["subtitle"]["w"], round(1320 * 0.80))   # 1056
    check("A/subtitle/opacity", result["subtitle"]["opacity"], 0.75)

    # screenshot: h=H*0.74=2122.32→2122, w=2122/2.167≈979.3→979,
    #             x=(1320-979)/2=170.5→170 (round), y=H*0.24=688.32→688
    ss_h = round(2868 * 0.74)   # 2122
    ss_w = round(ss_h / _PHONE_ASPECT)  # 979
    ss_x = round((1320 - ss_w) / 2)    # 171
    ss_y = round(2868 * 0.24)   # 688
    check("A/screenshot/h", result["screenshot"]["h"], ss_h)
    check("A/screenshot/w", result["screenshot"]["w"], ss_w)
    check("A/screenshot/x", result["screenshot"]["x"], ss_x)
    check("A/screenshot/y", result["screenshot"]["y"], ss_y)
    check("A/screenshot/cornerRadius", result["screenshot"]["cornerRadius"], 32)

    # --- Test 2: iPhone 6.9 (1320x2868), Layout C (screenshot top) ---
    result_c = compute_layout(spec.w, spec.h, spec.platform, "C", spec.headline_fs, spec.subtitle_fs)
    c_ss_h = round(2868 * 0.65)
    c_ss_w = round(c_ss_h / _PHONE_ASPECT)
    c_ss_x = round((1320 - c_ss_w) / 2)
    c_ss_y = round(2868 * 0.03)
    check("C/screenshot/h", result_c["screenshot"]["h"], c_ss_h)
    check("C/screenshot/w", result_c["screenshot"]["w"], c_ss_w)
    check("C/screenshot/x", result_c["screenshot"]["x"], c_ss_x)
    check("C/screenshot/y", result_c["screenshot"]["y"], c_ss_y)
    check("C/headline/y", result_c["headline"]["y"], round(2868 * 0.72))   # 2065
    check("C/subtitle/y", result_c["subtitle"]["y"], round(2868 * 0.81))   # 2323

    # --- Test 3: Mac 2880x1800, Layout A (landscape) ---
    mac_spec = _DEVICE_REGISTRY["mac-2880x1800"]
    result_mac = compute_layout(mac_spec.w, mac_spec.h, mac_spec.platform, "A",
                                mac_spec.headline_fs, mac_spec.subtitle_fs)
    mac_ss_h = round(1800 * 0.68)
    mac_ss_w = round(mac_ss_h * _MAC_ASPECT)
    mac_ss_x = round((2880 - mac_ss_w) / 2)
    mac_ss_y = round(1800 * 0.30)
    check("mac-A/screenshot/h", result_mac["screenshot"]["h"], mac_ss_h)
    check("mac-A/screenshot/w", result_mac["screenshot"]["w"], mac_ss_w)
    check("mac-A/screenshot/x", result_mac["screenshot"]["x"], mac_ss_x)
    check("mac-A/screenshot/y", result_mac["screenshot"]["y"], mac_ss_y)
    check("mac-A/screenshot/cornerRadius", result_mac["screenshot"]["cornerRadius"], 16)
    # subtitle y: H*0.16 for mac
    check("mac-A/subtitle/y", result_mac["subtitle"]["y"], round(1800 * 0.16))

    # --- Test 4: Full-bleed device (tvOS) ---
    tv_spec = _DEVICE_REGISTRY["appletv-4k-3840x2160"]
    fb = full_bleed_result(tv_spec)
    check("tvos/full_bleed", fb["full_bleed"], True)
    check("tvos/screenshot/w", fb["screenshot"]["w"], 3840)  # type: ignore[index]
    check("tvos/screenshot/h", fb["screenshot"]["h"], 2160)  # type: ignore[index]

    # --- Test 5: Layout D has larger screenshot than A ---
    result_d = compute_layout(spec.w, spec.h, spec.platform, "D", spec.headline_fs, spec.subtitle_fs)
    d_ss_h = round(2868 * 0.78)
    check("D/screenshot/h", result_d["screenshot"]["h"], d_ss_h)
    # D screenshot must be taller than A
    if result_d["screenshot"]["h"] <= result["screenshot"]["h"]:  # type: ignore[operator]
        errors.append("D screenshot should be taller than A")

    if errors:
        for e in errors:
            print(f"FAIL: {e}", file=sys.stderr)
        sys.exit(1)

    print("self-test passed (5 tests, 23 assertions)")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="App Store screenshot layout calculator. Outputs compact JSON.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "device", nargs="?",
        help="Device key, e.g. iphone-6.9-1320x2868. Run with no args to list keys.",
    )
    parser.add_argument("--w", type=int, help="Canvas width (use with --h --platform)")
    parser.add_argument("--h", type=int, help="Canvas height")
    parser.add_argument("--platform", choices=["ios", "ipad", "macos", "tvos", "watchos"])
    parser.add_argument("--layout", choices=["A", "B", "C", "D"], default="A",
                        help="Layout pattern (default: A)")
    parser.add_argument("--aspect", type=float,
                        help="Override aspect ratio: h/w for portrait, w/h for landscape (mac)")
    parser.add_argument("--list-devices", action="store_true",
                        help="Print all known device keys and exit")
    parser.add_argument("--self-test", action="store_true",
                        help="Run built-in self-tests and exit")

    args = parser.parse_args()

    if args.self_test:
        _self_test()
        return

    if args.list_devices:
        for key, spec in sorted(_DEVICE_REGISTRY.items()):
            tag = " [full-bleed]" if spec.full_bleed else ""
            print(f"{key:<35}  {spec.name}{tag}")
        return

    if args.device is None and args.w is None:
        parser.print_help()
        sys.exit(0)

    spec = _resolve_spec(args)

    if spec.full_bleed:
        output = full_bleed_result(spec)
        print(json.dumps(output, separators=(",", ":")))
        return

    layout_key: LayoutKey = args.layout  # type: ignore[assignment]
    geo = compute_layout(
        spec.w, spec.h, spec.platform, layout_key,
        spec.headline_fs, spec.subtitle_fs,
        aspect=args.aspect,
    )

    output = {
        "device": {"name": spec.name, "w": spec.w, "h": spec.h},
        **geo,
    }
    print(json.dumps(output, separators=(",", ":")))


if __name__ == "__main__":
    main()
