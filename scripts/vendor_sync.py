#!/usr/bin/env python3
"""Vendored files from the platform and data repositories, pinned by commit and sha256.

The app is built and tested against inputs other repositories own: the golden contract and
the contributors roster (platform) and the iOS database builder (sggs-data). They are
committed here at the same paths they have upstream, so the app, its tests and its tooling
read them unchanged — and vendor.lock.json records where each came from and its sha256.

    python3 scripts/vendor_sync.py check            # every vendored file == its lock hash (CI)
    python3 scripts/vendor_sync.py check --remote   # ... and == the file at source@commit
    python3 scripts/vendor_sync.py sync platform <ref>   # re-vendor from a platform ref
    python3 scripts/vendor_sync.py sync data             # re-vendor from dataset.lock.json's commit

`sync platform` also records the platform's APP_VERSION at that ref: the one-version policy
(scripts/release/check_versions.py) requires this app's MARKETING_VERSION to equal it, so a
binary always ships with the contract of the release it carries the number of.

Stdlib only. GH_TOKEN / GITHUB_TOKEN is sent when set (needed once the sources are private).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "vendor.lock.json"

# What each source contributes. Globs are expanded against the source tree at sync time.
SOURCES = {
    "platform": {
        "repository": "Algorythmos-AI/sggs-knowledge-base",
        "paths": ["contract/_meta.json", "contract/golden_*.ndjson", "frontend/public/contributors.json"],
        "version_from": ("webapp/serve.py", r"APP_VERSION\s*=\s*'([^']+)'"),
    },
    "data": {
        "repository": "Algorythmos-AI/sggs-data",
        "paths": ["pipeline/build_ios_db.py"],
        "version_from": ("DATASET_VERSION", r"^\s*(\S+)\s*$"),
    },
}


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def _get(url: str, accept: str = "application/vnd.github.raw") -> bytes:
    headers = {"User-Agent": "gurbani-soul-vendor-sync", "Accept": accept,
               "X-GitHub-Api-Version": "2022-11-28"}
    tok = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    for auth in ([f"Bearer {tok}"] if tok else []) + [None]:
        req = urllib.request.Request(url, headers=headers | ({"Authorization": auth} if auth else {}))
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if auth and e.code in (401, 403):
                continue        # a token scoped elsewhere must not block reading a public source
            raise
    raise AssertionError("unreachable")


def _api(repo: str, path: str) -> str:
    return f"https://api.github.com/repos/{repo}/{path}"


def resolve(repo: str, ref: str) -> str:
    data = json.loads(_get(_api(repo, f"commits/{urllib.parse.quote(ref, safe='')}"),
                           "application/vnd.github+json"))
    return data["sha"]


def list_tree(repo: str, commit: str) -> list[str]:
    data = json.loads(_get(_api(repo, f"git/trees/{commit}?recursive=1"), "application/vnd.github+json"))
    if data.get("truncated"):
        raise SystemExit(f"{repo}@{commit[:12]}: tree listing truncated")
    return [e["path"] for e in data["tree"] if e["type"] == "blob"]


def fetch_file(repo: str, commit: str, path: str) -> bytes:
    return _get(_api(repo, f"contents/{urllib.parse.quote(path)}?ref={commit}"))


def _write_atomic(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, 0o755 if data.startswith(b"#!") else 0o644)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def load_lock() -> dict:
    return json.loads(LOCK.read_text(encoding="utf-8")) if LOCK.exists() else {"sources": {}}


def save_lock(lock: dict) -> None:
    _write_atomic(LOCK, (json.dumps(lock, indent=2, sort_keys=True) + "\n").encode())


def sync(name: str, ref: str | None) -> None:
    spec = SOURCES[name]
    repo = spec["repository"]
    if name == "data" and ref is None:
        ref = json.loads((ROOT / "dataset.lock.json").read_text())["commit"]
    if ref is None:
        raise SystemExit("sync platform needs a ref (tag, branch or commit)")
    commit = resolve(repo, ref)
    tree = list_tree(repo, commit)
    wanted = sorted({p for pat in spec["paths"] for p in tree if Path(p).match(pat) and
                     Path(p).parent == Path(pat).parent})
    if not wanted:
        raise SystemExit(f"{repo}@{commit[:12]}: none of {spec['paths']} exist")
    vpath, vpat = spec["version_from"]
    m = re.search(vpat, fetch_file(repo, commit, vpath).decode("utf-8"), re.MULTILINE)
    if not m:
        raise SystemExit(f"{repo}@{commit[:12]}: no version in {vpath}")

    lock = load_lock()
    previous = set((lock["sources"].get(name) or {}).get("files", {}))
    files = {}
    for p in wanted:
        body = fetch_file(repo, commit, p)
        _write_atomic(ROOT / p, body)
        files[p] = sha256_bytes(body)
    for gone in sorted(previous - set(files)):          # a file the source no longer ships
        (ROOT / gone).unlink(missing_ok=True)
    lock["sources"][name] = {"repository": repo, "ref": ref, "commit": commit,
                             "version": m.group(1), "files": files}
    save_lock(lock)
    print(f"{name}: {repo}@{commit[:12]} ({ref}) version {m.group(1)} — {len(files)} files")


def check(remote: bool) -> int:
    lock = load_lock()
    problems = []
    if set(lock.get("sources", {})) != set(SOURCES):
        problems.append(f"vendor.lock.json sources {sorted(lock.get('sources', {}))} != {sorted(SOURCES)}")
    for name, src in sorted(lock.get("sources", {}).items()):
        for p, sha in sorted(src["files"].items()):
            local = ROOT / p
            if not local.is_file():
                problems.append(f"{p}: missing (vendored from {name})")
            elif sha256_bytes(local.read_bytes()) != sha:
                problems.append(f"{p}: edited locally — vendored files change only through "
                                f"`scripts/vendor_sync.py sync {name}`")
            elif remote and sha256_bytes(fetch_file(src["repository"], src["commit"], p)) != sha:
                problems.append(f"{p}: differs from {src['repository']}@{src['commit'][:12]}")
    if "data" in lock.get("sources", {}):
        ds = json.loads((ROOT / "dataset.lock.json").read_text())
        if lock["sources"]["data"]["commit"] != ds["commit"]:
            problems.append("vendored data files come from a different sggs-data commit than "
                            "dataset.lock.json — run `scripts/vendor_sync.py sync data`")
        meta = ROOT / "contract/_meta.json"
        if meta.is_file() and json.loads(meta.read_text()).get("db_sha256") != ds["database"]["sha256"]:
            problems.append("contract/_meta.json was generated over a different database than "
                            "dataset.lock.json pins — sync the platform release that pins it")
    for p in problems:
        print(f"::error::{p}")
    if problems:
        return 1
    n = sum(len(s["files"]) for s in lock["sources"].values())
    where = ", ".join(f"{k}@{v['commit'][:12]} ({v['version']})" for k, v in sorted(lock["sources"].items()))
    print(f"vendor OK: {n} files match the lock{' and their sources' if remote else ''} — {where}")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check")
    c.add_argument("--remote", action="store_true")
    s = sub.add_parser("sync")
    s.add_argument("source", choices=sorted(SOURCES))
    s.add_argument("ref", nargs="?")
    a = ap.parse_args(argv)
    if a.cmd == "check":
        return check(a.remote)
    sync(a.source, a.ref)
    return 0


if __name__ == "__main__":
    sys.exit(main())
