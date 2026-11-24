#!/usr/bin/env python3
"""asc_dev_certs.py — keep CI from filling the team's Apple Development certificate slots.

Every ios-testflight run signs on a fresh GitHub runner with automatic signing and the App Store
Connect API key, so Xcode creates a new "Apple Development: Created via API" certificate each time.
The runner is thrown away with its private key, the certificate stays, and after ten runs Apple
refuses the next one ("maximum number of certificates"): run 45300354850, 2026-11-24.

  snapshot OUT        write the ids of the team's DEVELOPMENT certificates to OUT (before the archive)
  revoke-new BEFORE   revoke the DEVELOPMENT certificates that are not in BEFORE *and* whose serial
                      number is in this machine's keychain: the one this run created, never another
                      machine's. Run it last, under `if: always()`.
  prune --keep ID     list every DEVELOPMENT certificate except the kept ones; with --apply, revoke
                      them. Dry run by default. For clearing slots left by earlier runs.

A development certificate only signs development builds; the archive is re-signed for distribution
at export, so revoking it after the run never touches an uploaded build.

Credentials come from SGGS_ASC_KEY_ID, SGGS_ASC_ISSUER_ID and SGGS_ASC_KEY_PATH (the .p8 path; the
key is read by openssl, never printed). Stdlib + the openssl and security command-line tools.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"


def b64url(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    """An ECDSA DER signature (SEQUENCE { INTEGER r, INTEGER s }) as JWS's raw 64-byte r||s."""
    def read_len(i):
        n = der[i]
        if n < 0x80:
            return n, i + 1
        k = n & 0x7F
        return int.from_bytes(der[i + 1:i + 1 + k], "big"), i + 1 + k

    if der[0] != 0x30:
        raise ValueError("not a DER sequence")
    _, i = read_len(1)
    out = b""
    for _ in range(2):
        if der[i] != 0x02:
            raise ValueError("not a DER integer")
        n, i = read_len(i + 1)
        out += int.from_bytes(der[i:i + n], "big").to_bytes(32, "big")
        i += n
    return out


def token(key_id: str, issuer: str, key_path: str) -> str:
    now = int(time.time())
    head = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    body = b64url(json.dumps({"iss": issuer, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}).encode())
    signing_input = f"{head}.{body}".encode()
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path], input=signing_input,
                         capture_output=True, check=True).stdout
    return f"{head}.{body}.{b64url(der_to_raw(der))}"


class ASC:
    def __init__(self, tok: str):
        self.tok = tok

    def call(self, method: str, path: str):
        req = urllib.request.Request(API + path, method=method, headers={"Authorization": f"Bearer {self.tok}"})
        with urllib.request.urlopen(req, timeout=60) as r:
            data = r.read()
        return json.loads(data) if data else None

    def dev_certs(self) -> list[dict]:
        d = self.call("GET", "/certificates?limit=200&filter[certificateType]=DEVELOPMENT"
                             "&fields[certificates]=name,certificateType,serialNumber,expirationDate")
        return [{"id": c["id"], **c["attributes"]} for c in d["data"]]

    def revoke(self, cert_id: str) -> None:
        self.call("DELETE", f"/certificates/{cert_id}")


def keychain_serials() -> set[str]:
    """Serial numbers (upper-case hex, no leading zeros) of the Apple Development certs in the keychains."""
    pem = subprocess.run(["security", "find-certificate", "-a", "-c", "Apple Development", "-p"],
                         capture_output=True, text=True).stdout
    serials = set()
    for block in re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", pem, re.S):
        out = subprocess.run(["openssl", "x509", "-noout", "-serial"], input=block,
                             capture_output=True, text=True).stdout
        m = re.search(r"serial=([0-9A-Fa-f]+)", out)
        if m:
            serials.add(norm_serial(m.group(1)))
    return serials


def norm_serial(s: str) -> str:
    return s.upper().lstrip("0")


def to_revoke_new(before: set[str], now: list[dict], local: set[str]) -> list[dict]:
    return [c for c in now if c["id"] not in before and norm_serial(c["serialNumber"]) in local]


def to_prune(now: list[dict], keep: set[str]) -> list[dict]:
    return [c for c in now if c["id"] not in keep]


def client() -> ASC:
    env = {k: os.environ.get(k, "") for k in ("SGGS_ASC_KEY_ID", "SGGS_ASC_ISSUER_ID", "SGGS_ASC_KEY_PATH")}
    missing = [k for k, v in env.items() if not v]
    if missing:
        raise SystemExit(f"error: {', '.join(missing)} not set")
    return ASC(token(env["SGGS_ASC_KEY_ID"], env["SGGS_ASC_ISSUER_ID"], env["SGGS_ASC_KEY_PATH"]))


def describe(c: dict) -> str:
    return f"{c['id']}  expires {c['expirationDate'][:10]}  serial …{c['serialNumber'][-6:]}"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("snapshot"); s.add_argument("out")
    r = sub.add_parser("revoke-new"); r.add_argument("before")
    p = sub.add_parser("prune"); p.add_argument("--keep", action="append", default=[], required=True)
    p.add_argument("--apply", action="store_true")
    a = ap.parse_args(argv)
    asc = client()
    try:
        certs = asc.dev_certs()
        if a.cmd == "snapshot":
            with open(a.out, "w") as f:
                json.dump(sorted(c["id"] for c in certs), f)
            print(f"  {len(certs)} development certificate(s) before this run")
            return 0
        if a.cmd == "revoke-new":
            with open(a.before) as f:
                before = set(json.load(f))
            mine = to_revoke_new(before, certs, keychain_serials())
            unmatched = [c for c in certs if c["id"] not in before and c not in mine]
            if unmatched:  # new since the snapshot but not in this keychain: report, never revoke
                print(f"::warning::{len(unmatched)} development certificate(s) appeared during this run but are not in "
                      f"this machine's keychain, so they were left alone: {', '.join(c['id'] for c in unmatched)}")
            if not mine:
                print("  no development certificate of this run to revoke")
            for c in mine:
                asc.revoke(c["id"])
                print(f"  ✓ revoked this run's development certificate {describe(c)}")
            return 0
        keep = set(a.keep)
        unknown = keep - {c["id"] for c in certs}
        if unknown:
            raise SystemExit(f"error: --keep {', '.join(sorted(unknown))} is not a development certificate of this team")
        gone = to_prune(certs, keep)
        for c in gone:
            if a.apply:
                asc.revoke(c["id"])
            print(f"  {'✓ revoked' if a.apply else 'would revoke'} {describe(c)}")
        print(f"  kept {len(keep)}; {'revoked' if a.apply else 'dry run, would revoke'} {len(gone)}")
        return 0
    except urllib.error.HTTPError as e:
        print(f"error: App Store Connect answered HTTP {e.code} for {e.url}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
