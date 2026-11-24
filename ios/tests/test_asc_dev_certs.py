"""asc_dev_certs.py and the workflows that use it: CI must give back the certificate slot it takes."""
import base64
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ios" / "tools"))
import asc_dev_certs as m  # noqa: E402

UPLOAD_WF = (ROOT / ".github" / "workflows" / "ios-testflight.yml").read_text()
PRUNE_WF = (ROOT / ".github" / "workflows" / "ios-dev-certs.yml").read_text()


def cert(cid, serial):
    return {"id": cid, "serialNumber": serial, "expirationDate": "2027-11-24T00:00:00.000+0000"}


class Selection(unittest.TestCase):
    def test_revoke_new_takes_only_this_machines_new_certificate(self):
        now = [cert("OLD0000001", "0A11"), cert("MINE000001", "00BEEF"), cert("OTHER00001", "CAFE")]
        got = m.to_revoke_new({"OLD0000001"}, now, {"BEEF", "0A11"})
        self.assertEqual([c["id"] for c in got], ["MINE000001"])  # new and in the keychain

    def test_revoke_new_never_takes_an_old_certificate_even_if_local(self):
        now = [cert("LOCALMAC01", "810D3F")]
        self.assertEqual(m.to_revoke_new({"LOCALMAC01"}, now, {"810D3F"}), [])

    def test_revoke_new_ignores_a_new_certificate_from_another_machine(self):
        self.assertEqual(m.to_revoke_new(set(), [cert("ELSEWHERE1", "ABC")], {"DEF"}), [])

    def test_serials_compare_without_case_or_leading_zeros(self):
        self.assertEqual(m.norm_serial("00abC1"), "ABC1")

    def test_prune_keeps_the_named_ones(self):
        now = [cert("KEEP000001", "1"), cert("DROP000001", "2")]
        self.assertEqual([c["id"] for c in m.to_prune(now, {"KEEP000001"})], ["DROP000001"])


class Token(unittest.TestCase):
    def test_der_to_raw_pads_and_strips_integers(self):
        r, s = 1, (1 << 255) | 5          # short r; s needs a leading 0x00 in DER
        sb = b"\x00" + s.to_bytes(32, "big")
        der = b"\x30" + bytes([2 + 1 + 2 + len(sb)]) + b"\x02\x01\x01" + b"\x02" + bytes([len(sb)]) + sb
        raw = m.der_to_raw(der)
        self.assertEqual(len(raw), 64)
        self.assertEqual(int.from_bytes(raw[:32], "big"), r)
        self.assertEqual(int.from_bytes(raw[32:], "big"), s)

    def test_token_is_an_es256_jwt_that_verifies(self):
        with tempfile.TemporaryDirectory() as d:
            key, pub = Path(d, "k.p8"), Path(d, "k.pub")
            subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(key)],
                           check=True, capture_output=True)
            subprocess.run(["openssl", "ec", "-in", str(key), "-pubout", "-out", str(pub)], check=True, capture_output=True)
            tok = m.token("KEYID12345", "issuer-uuid", str(key))
            head, body, sig = tok.split(".")
            pad = lambda x: base64.urlsafe_b64decode(x + "=" * (-len(x) % 4))
            self.assertEqual(json.loads(pad(head)), {"alg": "ES256", "kid": "KEYID12345", "typ": "JWT"})
            claims = json.loads(pad(body))
            self.assertEqual((claims["iss"], claims["aud"]), ("issuer-uuid", "appstoreconnect-v1"))
            self.assertLessEqual(claims["exp"] - claims["iat"], 1200)  # Apple's 20-minute ceiling
            raw = pad(sig)
            self.assertEqual(len(raw), 64)
            # Re-encode r||s as DER and let openssl verify it against the public key.
            def der_int(b):
                b = b.lstrip(b"\x00") or b"\x00"
                if b[0] & 0x80:
                    b = b"\x00" + b
                return b"\x02" + bytes([len(b)]) + b
            body_der = der_int(raw[:32]) + der_int(raw[32:])
            Path(d, "sig").write_bytes(b"\x30" + bytes([len(body_der)]) + body_der)
            v = subprocess.run(["openssl", "dgst", "-sha256", "-verify", str(pub), "-signature", str(Path(d, "sig"))],
                               input=f"{head}.{body}".encode(), capture_output=True)
            self.assertEqual(v.returncode, 0, v.stdout + v.stderr)


class Workflows(unittest.TestCase):
    def step(self, wf, name_part):
        steps = re.split(r"\n      - ", wf)
        hits = [s for s in steps if name_part in s.split("\n", 1)[0]]
        self.assertEqual(len(hits), 1, f"one step named like {name_part!r}")
        return hits[0], steps.index(hits[0])

    def test_upload_run_snapshots_before_and_revokes_after_archiving(self):
        snap, i_snap = self.step(UPLOAD_WF, "Note the team's development certificates")
        _, i_arch = self.step(UPLOAD_WF, "Archive, gate, and export / upload")
        rev, i_rev = self.step(UPLOAD_WF, "Revoke the development certificate this run created")
        _, i_rm = self.step(UPLOAD_WF, "Remove the API key")
        self.assertLess(i_snap, i_arch)
        self.assertLess(i_arch, i_rev)
        self.assertLess(i_rev, i_rm)          # the key is still there when revoking
        self.assertIn("continue-on-error: true", snap)  # a snapshot hiccup never blocks an upload
        self.assertIn("if: always()", rev)    # a failed archive still gives its slot back
        self.assertIn("revoke-new", rev)
        self.assertNotIn("prune", rev)

    def test_prune_workflow_is_a_manual_dry_run_by_default(self):
        self.assertRegex(PRUNE_WF, r"on:\n  workflow_dispatch:")
        self.assertNotRegex(PRUNE_WF, r"\n  (push|pull_request|schedule):")
        self.assertRegex(PRUNE_WF, r"apply:\n(?:        .*\n)*?        default: false")
        self.assertIn("group: ios-testflight", PRUNE_WF)  # never while an upload is signing


if __name__ == "__main__":
    unittest.main()
