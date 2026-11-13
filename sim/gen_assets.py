"""Generate assets for the FPGA simulation suite.

Two kinds of assets are produced into sim/work/:

1. ``phase_correction_pkg.vhd`` -- the active PHASE_CORRECTION table parsed
   out of src/Distribute.vhd, so the testbenches check the same values the
   hardware applies instead of duplicating the table.
2. ``frame_demo*.txt`` -- real 258-byte frames built by the Python demo code
   in ../demo, one decimal byte per line. testbenches stream these into the
   UART and check what Distribute does with them.

Run from the sim directory or let run_sim.ps1 call it.
"""

from __future__ import annotations

import math
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
FPGA_DIR = HERE.parent


def _find_demo_dir() -> Path:
    """Locate the host demo package.

    The FPGA project used to live next to ``demo``; it now sits under
    ``E:\\LUIS\\IPP\\fpga\\<role>`` with ``demo`` one level further up.
    Support both layouts so the suite runs from either tree.
    """
    for candidate in (FPGA_DIR.parent / "demo", FPGA_DIR.parent.parent / "demo"):
        if (candidate / "acoustics.py").is_file():
            return candidate
    return FPGA_DIR.parent / "demo"


DEMO_DIR = _find_demo_dir()
OUT_DIR = HERE / "work"


def parse_phase_correction() -> list[int]:
    text = (FPGA_DIR / "src" / "Distribute.vhd").read_text(encoding="utf-8")
    match = re.search(
        r"constant\s+PHASE_CORRECTION\s*:\s*T_PHASE_CORRECTION\s*:=\s*\(",
        text,
    )
    if not match:
        raise SystemExit("PHASE_CORRECTION table not found in Distribute.vhd")

    # Take the first non-comment line with >=256 values after the literal
    # opens; do not rely on the closing ");" because commented-out tables may
    # contain one earlier.
    for line in text[match.end():].splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("--"):
            continue
        values = [int(v) for v in re.findall(r"\d+", stripped)]
        if len(values) >= 256:
            return values[:256]

    raise SystemExit("Could not find 256 active PHASE_CORRECTION values")


def write_package(values: list[int]) -> None:
    lines = [
        "library IEEE;",
        "use IEEE.std_logic_1164.all;",
        "",
        "package phase_correction_pkg is",
        "  type correction_array is array (0 to 255) of integer range 0 to 255;",
        "  constant PHASE_CORRECTION : correction_array := (",
    ]
    for start in range(0, 256, 16):
        chunk = values[start : start + 16]
        suffix = "," if start + 16 < 256 else ""
        lines.append("    " + ", ".join(str(v) for v in chunk) + suffix)
    lines += [
        "  );",
        "",
        "  -- Value Distribute stores for one payload byte.",
        "  function corrected(bin_value : integer; index : integer) return integer;",
        "end package;",
        "",
        "package body phase_correction_pkg is",
        "  function corrected(bin_value : integer; index : integer) return integer is",
        "  begin",
        "    if bin_value = 16 then",
        "      return 16;",
        "    end if;",
        "    return (bin_value + PHASE_CORRECTION(index)) mod 16;",
        "  end function;",
        "end package body;",
        "",
    ]
    (OUT_DIR / "phase_correction_pkg.vhd").write_text("\n".join(lines), encoding="ascii")


def write_bytes(name: str, data: bytes) -> None:
    path = OUT_DIR / name
    path.write_text("".join(f"{b}\n" for b in data), encoding="ascii")


def main() -> None:
    OUT_DIR.mkdir(exist_ok=True)
    write_package(parse_phase_correction())

    sys.path.insert(0, str(DEMO_DIR))
    import acoustics  # noqa: E402
    import protocol  # noqa: E402

    def frame(bins) -> bytes:
        return protocol.build_frame(bins)

    cx, cy = 0.075, 0.075

    def circle_point(index: int, radius: float, z: float):
        angle = 2.0 * math.pi * index / 48.0
        return (cx + radius * math.cos(angle), cy + radius * math.sin(angle), z)

    # Demo 1: levitation -- hover, then two points of the 1.5 cm circle.
    demo1 = (
        frame(acoustics.focus_phase_bins((cx, cy, 0.05)))
        + frame(acoustics.focus_phase_bins(circle_point(0, 0.015, 0.05)))
        + frame(acoustics.focus_phase_bins(circle_point(1, 0.015, 0.05)))
    )
    write_bytes("frame_demo1.txt", demo1)

    # Demo 2: directional speaker -- mode byte, vortex, then a steered beam.
    demo2 = bytes([0xC9])
    demo2 += frame(acoustics.vortex_phase_bins((cx, cy, 0.05), 1))
    demo2 += frame(acoustics.steering_phase_bins(0.0, 30.0))
    write_bytes("frame_demo2.txt", demo2)

    # Demo 3: sandbox / touch -- focus near the surface, moving in a circle.
    demo3 = (
        frame(acoustics.focus_phase_bins(circle_point(12, 0.015, 0.005)))
        + frame(acoustics.focus_phase_bins(circle_point(13, 0.015, 0.005)))
    )
    write_bytes("frame_demo3.txt", demo3)

    print(f"Generated phase package and 3 frame files in {OUT_DIR}")


if __name__ == "__main__":
    main()
