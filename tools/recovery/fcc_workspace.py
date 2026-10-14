"""Decode requested Glory FTC/FCC files from workspace-local raw sources.

Compiles the 32-bit fkernel.dll wrapper on demand and removes temporary output
on exit. STARHOME_WINE, STARHOME_WINEPREFIX, STARHOME_MINGW_CC and
STARHOME_CABEXTRACT override the system tools when needed.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path, PurePosixPath
from tempfile import TemporaryDirectory
from .paths import source_path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_RAW_ROOT = PROJECT_ROOT / "../starhome_lz_ry_full" / "raw"
DECODER_SOURCE = Path(__file__).resolve().parent / "ftc" / "fch_decode.c"


def decode_text(data: bytes) -> tuple[str, str]:
    for encoding in ("utf-8-sig", "gb18030"):
        try:
            return data.decode(encoding), encoding
        except UnicodeDecodeError:
            pass
    return data.decode("gb18030", errors="replace"), "gb18030-replace"


class RawFccWorkspace:
    def __init__(self, raw_root: Path = DEFAULT_RAW_ROOT, fkernel: Path | None = None):
        self.raw_root = raw_root
        self.fkernel = fkernel or raw_root.parent / "fkernel.dll"
        self._temporary: TemporaryDirectory[str] | None = None
        self._decoded: dict[str, Path] = {}
        self._payloads: dict[str, bytes] = {}
        self._decoder: Path | None = None

    def __enter__(self) -> RawFccWorkspace:
        self._temporary = TemporaryDirectory(prefix="starhome-fcc-")
        return self

    def __exit__(self, *_: object) -> None:
        assert self._temporary is not None
        self._temporary.cleanup()
        self._temporary = None
        self._decoded.clear()
        self._payloads.clear()
        self._decoder = None

    def source(self, logical_path: str) -> Path:
        return source_path(self.raw_root, logical_path)

    def require(self, logical_paths: list[str]) -> None:
        missing = []
        for path in sorted(set(logical_paths)):
            try:
                self.source(path)
            except FileNotFoundError:
                missing.append(path)
        if missing:
            raise FileNotFoundError(f"missing raw FTC sources in {self.raw_root}:\n" + "\n".join(missing))

    def _tool(self, env_name: str, executable: str) -> str:
        value = os.environ.get(env_name) or shutil.which(executable)
        if not value and executable == "wine":
            runners = (Path.home() / ".var/app/com.usebottles.bottles/data/bottles/runners").glob("*/bin/wine")
            value = max(runners, key=lambda path: tuple(map(int, re.findall(r"\d+", path.parent.parent.name))), default=None)
        if not value:
            raise RuntimeError(f"{executable} is required; set {env_name} to its executable path")
        return str(value)

    def _prepare_decoder(self) -> Path:
        configured = os.environ.get("STARHOME_FTC_DECODER")
        if configured:
            decoder = Path(configured).resolve()
            if not decoder.is_file(): raise FileNotFoundError(decoder)
            return decoder
        if self._decoder is None:
            assert self._temporary is not None
            compiler = self._tool("STARHOME_MINGW_CC", "i686-w64-mingw32-gcc")
            self._decoder = Path(self._temporary.name) / "fch_decode.exe"
            subprocess.run([compiler, "-std=c11", "-O2", "-static-libgcc",
                            "-o", str(self._decoder), str(DECODER_SOURCE)], check=True)
        return self._decoder

    def payload(self, logical_path: str) -> bytes:
        if logical_path in self._payloads:
            return self._payloads[logical_path]
        if self._temporary is None:
            raise RuntimeError("RawFccWorkspace must be used as a context manager")
        source = self.source(logical_path)
        with source.open("rb") as handle:
            magic = handle.read(4)
        if magic not in (b"FTC1", b"FTC!"):
            raise ValueError(f"unsupported FTC container {logical_path}: {magic!r}")
        if not self.fkernel.is_file():
            raise FileNotFoundError(f"missing local FTC decoder DLL: {self.fkernel}")
        launcher = [] if os.name == "nt" else [self._tool("STARHOME_WINE", "wine")]
        encoded = Path(self._temporary.name) / "decoded" / logical_path
        encoded.parent.mkdir(parents=True, exist_ok=True)
        environment = os.environ.copy()
        environment["WINEPREFIX"] = environment.get("STARHOME_WINEPREFIX", str(Path(self._temporary.name) / "wineprefix"))
        result = subprocess.run([*launcher, str(self._prepare_decoder()), str(self.fkernel),
                                 str(source), str(encoded), "0003"], env=environment,
                                text=True, capture_output=True, timeout=120)
        if result.returncode or not encoded.is_file():
            raise RuntimeError(f"FTC decode failed for {logical_path}: {result.stdout}{result.stderr}")
        if magic == b"FTC!":
            with encoded.open("rb") as handle:
                cab_magic = handle.read(4)
            if cab_magic != b"MSCF":
                raise ValueError(f"decoded {logical_path} is not a CAB archive")
            expanded = Path(self._temporary.name) / "expanded" / logical_path
            expanded.mkdir(parents=True, exist_ok=True)
            command = ([str(Path(os.environ["SystemRoot"]) / "System32/expand.exe"),
                        "-F:*", str(encoded), str(expanded)] if os.name == "nt" else
                       [self._tool("STARHOME_CABEXTRACT", "cabextract"), "-q", "-d", str(expanded), str(encoded)])
            subprocess.run(command, check=True, timeout=120, capture_output=True)
            payloads = [path for path in expanded.rglob("*") if path.is_file()]
            if len(payloads) != 1:
                raise ValueError(f"{logical_path}: expected one CAB payload, got {len(payloads)}")
            payload = payloads[0].read_bytes()
        else:
            payload = encoded.read_bytes()
        self._payloads[logical_path] = payload
        return payload

    def path(self, logical_path: str) -> Path:
        if logical_path in self._decoded:
            return self._decoded[logical_path]
        if PurePosixPath(logical_path).suffix.lower() != ".fcc":
            raise ValueError(f"not an FCC source: {logical_path}")
        payload = self.payload(logical_path)
        assert self._temporary is not None
        if payload.startswith(b"XY20"):
            raise ValueError(f"{logical_path} is binary XY20, not FCC text")
        content, encoding = decode_text(payload)
        if encoding.endswith("-replace"):
            raise UnicodeError(f"{logical_path}: source text requires replacement characters")
        destination = Path(self._temporary.name) / "source" / logical_path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(content.replace("\r\n", "\n").replace("\r", "\n"), encoding="utf-8")
        self._decoded[logical_path] = destination
        return destination

    def text(self, logical_path: str) -> str:
        return self.path(logical_path).read_text(encoding="utf-8")
