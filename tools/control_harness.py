#!/usr/bin/env python3
import hashlib
import json
import os
import re
import subprocess
import time
import uuid
from pathlib import Path
from typing import Any
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit


WORKSPACE_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RUNS_DIR = WORKSPACE_ROOT / ".control-runs"


def now_ms() -> int:
    return int(time.time() * 1000)


def timestamp() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def new_run_id(prefix: str = "control") -> str:
    return f"{prefix}-{time.strftime('%Y%m%d-%H%M%S', time.gmtime())}-{uuid.uuid4().hex[:8]}"


SENSITIVE_VALUE_KEYS = re.compile(r"(password|secret|token|cookie|authorization|api[_-]?key|credential)", re.I)
PRIVATE_TEXT_KEYS = re.compile(r"^(clipboard|text|textSnippet|query|stdout|stderr|stdout_tail|stderr_tail)$", re.I)


def redact_url(value: str) -> str:
    try:
        parsed = urlsplit(value)
    except ValueError:
        return value
    if not parsed.scheme or not parsed.netloc or not parsed.query:
        return value
    redacted_query = []
    changed = False
    for key, item in parse_qsl(parsed.query, keep_blank_values=True):
        if SENSITIVE_VALUE_KEYS.search(key):
            redacted_query.append((key, "[redacted]"))
            changed = True
        else:
            redacted_query.append((key, item))
    if not changed:
        return value
    return urlunsplit((parsed.scheme, parsed.netloc, parsed.path, urlencode(redacted_query), parsed.fragment))


def summarize_private_text(value: str) -> str:
    return f"[redacted text; chars={len(value)}]"


def redact_string(value: str) -> str:
    value = re.sub(r"https?://[^\s\"'<>]+", lambda m: redact_url(m.group(0)), value)
    value = re.sub(r"(?i)(authorization:\s*bearer\s+)[^\s]+", r"\1[redacted]", value)
    value = re.sub(r"(?i)((?:x-api-key|x-auth-token|api-key|auth-token|authorization)\s*[:=]\s*)[^\s,;]+", r"\1[redacted]", value)
    value = re.sub(r'(?i)("(?:password|secret|token|cookie|api[_-]?key|credential)"\s*:\s*")[^"]*(")', r"\1[redacted]\2", value)
    value = re.sub(r"\bsk-[A-Za-z0-9_-]{12,}\b", "sk-[redacted]", value)
    value = re.sub(r"\b[A-Za-z0-9_-]{32,}\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}\b", "[redacted-jwt]", value)
    return value


def redact(value: Any, key_hint: str | None = None) -> Any:
    if isinstance(value, dict):
        out: dict[str, Any] = {}
        for key, item in value.items():
            key_text = str(key)
            if SENSITIVE_VALUE_KEYS.search(key_text):
                out[key] = "[redacted]"
            elif PRIVATE_TEXT_KEYS.search(key_text):
                out[key] = summarize_private_text(item) if isinstance(item, str) and item else redact(item, key_text)
            else:
                out[key] = redact(item, key_text)
        return out
    if isinstance(value, list):
        return [redact(item, key_hint) for item in value]
    if isinstance(value, str):
        if key_hint and PRIVATE_TEXT_KEYS.search(key_hint):
            return summarize_private_text(value) if value else value
        return redact_string(value)
    try:
        json.dumps(value)
    except TypeError:
        return str(value)
    return value


class Ledger:
    def __init__(self, run_id: str | None = None, root: Path | str | None = None) -> None:
        self.run_id = run_id or new_run_id()
        self.root = Path(root) if root else DEFAULT_RUNS_DIR / self.run_id
        self.root.mkdir(parents=True, exist_ok=True)
        self.path = self.root / "ledger.jsonl"

    def event(
        self,
        *,
        phase: str,
        surface: str,
        intent: str,
        action: str,
        observation: Any = None,
        expected: Any = None,
        result: Any = None,
        verification: Any = None,
        artifact_paths: list[str] | None = None,
        risk_level: str = "low",
        ok: bool | None = None,
        started_ms: int | None = None,
    ) -> dict[str, Any]:
        record = {
            "timestamp": timestamp(),
            "run_id": self.run_id,
            "phase": phase,
            "surface": surface,
            "intent": intent,
            "action": redact(action),
            "observation": redact(observation),
            "expected": redact(expected),
            "result": redact(result),
            "verification": redact(verification),
            "artifact_paths": artifact_paths or [],
            "risk_level": risk_level,
            "ok": ok,
        }
        if started_ms is not None:
            record["duration_ms"] = now_ms() - started_ms
        with self.path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
        return record


def run_command(cmd: list[str], *, cwd: Path | str | None = None, timeout: int = 30) -> dict[str, Any]:
    started = now_ms()
    try:
        proc = subprocess.run(cmd, cwd=str(cwd or WORKSPACE_ROOT), text=True, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout.decode("utf-8", errors="replace") if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        stderr = exc.stderr.decode("utf-8", errors="replace") if isinstance(exc.stderr, bytes) else (exc.stderr or f"timed out after {timeout}s")
        return {
            "cmd": cmd,
            "returncode": 124,
            "stdout": stdout,
            "stderr": stderr,
            "duration_ms": now_ms() - started,
            "timed_out": True,
        }
    return {
        "cmd": cmd,
        "returncode": proc.returncode,
        "stdout": proc.stdout,
        "stderr": proc.stderr,
        "duration_ms": now_ms() - started,
    }


def parse_json_line(text: str) -> dict[str, Any] | None:
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            return value
    return None


def file_fingerprint(path: str | Path) -> dict[str, Any]:
    p = Path(path)
    if not p.exists():
        return {"ok": False, "path": str(path), "error": "missing"}
    sha = hashlib.sha256()
    size = 0
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            size += len(chunk)
            sha.update(chunk)
    return {
        "ok": True,
        "path": str(p),
        "bytes": size,
        "sha256": sha.hexdigest(),
    }


def verify_json_ok(payload: dict[str, Any] | None) -> dict[str, Any]:
    return {"ok": bool(payload and payload.get("ok") is True), "payload": payload}


def verify_text_contains(text: str, pattern: str, *, case_sensitive: bool = False) -> dict[str, Any]:
    flags = 0 if case_sensitive else re.IGNORECASE
    matched = bool(re.search(pattern, text, flags))
    return {"ok": matched, "pattern": pattern}


def verify_file_exists(path: str | Path) -> dict[str, Any]:
    fp = file_fingerprint(path)
    return {"ok": bool(fp.get("ok") and fp.get("bytes", 0) > 0), "file": fp}


def print_json(value: Any) -> None:
    print(json.dumps(redact(value), ensure_ascii=False, indent=2, sort_keys=True))
