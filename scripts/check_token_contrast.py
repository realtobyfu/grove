#!/usr/bin/env python3

import json
from pathlib import Path

AA_MIN_RATIO = 4.5

ASSET_ROOT = Path("grove/Resources/Assets.xcassets")

PAIRS = [
    ("textSecondary", "bgPrimary"),
    ("textSecondary", "bgCard"),
    ("textSecondary", "bgSidebar"),
    ("textSecondary", "bgInspector"),
    ("textTertiary", "bgPrimary"),
    ("textTertiary", "bgCard"),
    ("textTertiary", "bgSidebar"),
    ("textTertiary", "bgInspector"),
    ("textMuted", "bgPrimary"),
    ("textMuted", "bgCard"),
    ("textMuted", "bgSidebar"),
    ("textMuted", "bgInspector"),
]


def channel_to_linear(value: float) -> float:
    if value <= 0.04045:
        return value / 12.92
    return ((value + 0.055) / 1.055) ** 2.4


def luminance(rgb: tuple[float, float, float]) -> float:
    r, g, b = rgb
    return (
        0.2126 * channel_to_linear(r)
        + 0.7152 * channel_to_linear(g)
        + 0.0722 * channel_to_linear(b)
    )


def contrast_ratio(foreground: tuple[float, float, float], background: tuple[float, float, float]) -> float:
    fg_l = luminance(foreground)
    bg_l = luminance(background)
    lighter = max(fg_l, bg_l)
    darker = min(fg_l, bg_l)
    return (lighter + 0.05) / (darker + 0.05)


def load_color_variants(token: str) -> dict[str, tuple[float, float, float]]:
    path = ASSET_ROOT / f"{token}.colorset" / "Contents.json"
    data = json.loads(path.read_text())
    variants: dict[str, tuple[float, float, float]] = {}

    for entry in data["colors"]:
        components = entry["color"]["components"]
        rgb = (
            float(components["red"]),
            float(components["green"]),
            float(components["blue"]),
        )
        variant = "light"
        for appearance in entry.get("appearances", []):
            if appearance.get("appearance") == "luminosity" and appearance.get("value") == "dark":
                variant = "dark"
                break
        variants[variant] = rgb

    if "light" not in variants or "dark" not in variants:
        raise ValueError(f"Missing light/dark variants in {path}")

    return variants


def main() -> int:
    print("Token contrast check (WCAG AA >= 4.5 for normal text)\n")

    all_pass = True
    min_ratio = 999.0
    min_pair = ""

    for text_token, bg_token in PAIRS:
        text = load_color_variants(text_token)
        bg = load_color_variants(bg_token)

        light_ratio = contrast_ratio(text["light"], bg["light"])
        dark_ratio = contrast_ratio(text["dark"], bg["dark"])

        light_ok = light_ratio >= AA_MIN_RATIO
        dark_ok = dark_ratio >= AA_MIN_RATIO
        pair_ok = light_ok and dark_ok
        all_pass = all_pass and pair_ok

        min_for_pair = min(light_ratio, dark_ratio)
        if min_for_pair < min_ratio:
            min_ratio = min_for_pair
            min_pair = f"{text_token} on {bg_token}"

        status = "PASS" if pair_ok else "FAIL"
        print(
            f"{status:4} {text_token:13} on {bg_token:10} "
            f"light={light_ratio:.2f} dark={dark_ratio:.2f}"
        )

    print(f"\nLowest ratio: {min_ratio:.2f} ({min_pair})")
    return 0 if all_pass else 1


if __name__ == "__main__":
    raise SystemExit(main())
