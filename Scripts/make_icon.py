#!/usr/bin/env python3
import struct
import subprocess
import sys
import tempfile
from pathlib import Path


SIZES = [
    ("icp4", 16),
    ("icp5", 32),
    ("icp6", 64),
    ("ic07", 128),
    ("ic08", 256),
    ("ic09", 512),
    ("ic10", 1024),
]


def run_magick(source: Path, size: int, output: Path) -> None:
    subprocess.run(
        [
            "magick",
            str(source),
            "-resize",
            f"{size}x{size}",
            "-background",
            "none",
            "-gravity",
            "center",
            "-extent",
            f"{size}x{size}",
            "-alpha",
            "on",
            "-strip",
            f"PNG32:{output}",
        ],
        check=True,
    )


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: make_icon.py source.png output.icns", file=sys.stderr)
        return 2

    source = Path(sys.argv[1])
    output = Path(sys.argv[2])
    chunks = []

    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        for code, size in SIZES:
            png = tmpdir / f"{code}.png"
            run_magick(source, size, png)
            data = png.read_bytes()
            chunks.append(code.encode("ascii") + struct.pack(">I", len(data) + 8) + data)

    body = b"".join(chunks)
    output.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
