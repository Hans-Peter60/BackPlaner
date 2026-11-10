#!/usr/bin/env python3
"""Talks to the Google Play Developer API for BakePlanner.

    python3 scripts/play-console.py status
        Shows every track of the app with its releases (name, status,
        version codes, release-note languages) and the bundles Play holds.
        Google's review itself is not part of the API: a release that is
        still being reviewed shows as "inProgress"/"completed" all the same —
        whether testers can already install it, only the Play Console says.

    python3 scripts/play-console.py upload BakePlannerAndroid/.build/export/BakePlanner-release.aab
        Uploads the bundle and puts it as a *draft* release on the closed
        test track "alpha" (Play's identifier for the first closed track),
        with the release notes from
        BakePlannerAndroid/Android/fastlane/metadata/android/<locale>/changelogs/<versionCode>.txt.
        In the Play Console the draft then only needs "Überprüfen" and
        "Roll-out starten".
        --track <id>     another track (see `status`; "internal", "beta",
                         "production" or a custom closed track's id)
        --rollout        complete the release right away instead of a draft
                         (that submits it for review)

Needs a service-account key with access to the app in the Play Console,
by default at ~/.config/bakeplanner/play-service-account.json (override
with PLAY_SERVICE_ACCOUNT=<path>). How to create it: docs/Android-Play-Release.md,
section 8. Only Python's standard library and the openssl command are used.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

PACKAGE = "de.hpm64625.bakeplanner"
API = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}"
UPLOAD = f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PACKAGE}"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"
KEY_FILE = pathlib.Path(os.environ.get("PLAY_SERVICE_ACCOUNT",
                                       os.path.expanduser("~/.config/bakeplanner/play-service-account.json")))
REPO = pathlib.Path(__file__).resolve().parent.parent
METADATA = REPO / "BakePlannerAndroid/Android/fastlane/metadata/android"
LOCALES = ["de-DE", "en-US", "fr-FR"]


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def access_token() -> str:
    """An OAuth token for the service account: a JWT signed with its private
    key (RS256 through the openssl command), exchanged at Google's token endpoint."""
    if not KEY_FILE.exists():
        sys.exit(f"No service-account key at {KEY_FILE}.\n"
                 "Create one as described in docs/Android-Play-Release.md, section 8, "
                 "or point PLAY_SERVICE_ACCOUNT at it.")
    key = json.loads(KEY_FILE.read_text())
    now = int(time.time())
    header = b64url(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    claims = b64url(json.dumps({"iss": key["client_email"], "scope": SCOPE, "aud": key["token_uri"],
                                "iat": now, "exp": now + 3600}).encode())
    signing_input = f"{header}.{claims}".encode()
    with tempfile.NamedTemporaryFile("w", suffix=".pem", delete=False) as pem:
        pem.write(key["private_key"])
    try:
        signature = subprocess.run(["openssl", "dgst", "-sha256", "-sign", pem.name],
                                   input=signing_input, capture_output=True, check=True).stdout
    finally:
        os.unlink(pem.name)
    assertion = f"{header}.{claims}.{b64url(signature)}"
    form = urllib.parse.urlencode({"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                                   "assertion": assertion}).encode()
    try:
        with urllib.request.urlopen(urllib.request.Request(key["token_uri"], data=form)) as response:
            return json.load(response)["access_token"]
    except urllib.error.HTTPError as error:
        sys.exit(f"Token request failed: HTTP {error.code}\n{error.read().decode(errors='replace')}")


class Play:
    def __init__(self):
        self.token = access_token()

    def call(self, method: str, url: str, body=None, raw: bytes | None = None,
             content_type: str = "application/json"):
        data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
        request = urllib.request.Request(url, data=data, method=method, headers={
            "Authorization": f"Bearer {self.token}", "Content-Type": content_type})
        try:
            with urllib.request.urlopen(request, timeout=900) as response:
                text = response.read().decode()
                return json.loads(text) if text else {}
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")
            try:
                detail = json.loads(detail)["error"]["message"]
            except (ValueError, KeyError, TypeError):
                pass
            sys.exit(f"{method} {url}\nHTTP {error.code}: {detail}")

    def open_edit(self) -> str:
        return self.call("POST", f"{API}/edits")["id"]

    def delete_edit(self, edit: str):
        self.call("DELETE", f"{API}/edits/{edit}")


def show_status(play: Play):
    edit = play.open_edit()
    try:
        tracks = play.call("GET", f"{API}/edits/{edit}/tracks").get("tracks", [])
        bundles = play.call("GET", f"{API}/edits/{edit}/bundles").get("bundles", [])
    finally:
        play.delete_edit(edit)
    print(f"{PACKAGE}\n")
    for track in tracks:
        print(f"Track {track['track']!r}")
        releases = track.get("releases", [])
        if not releases:
            print("  (no release)")
        for release in releases:
            codes = ", ".join(str(code) for code in release.get("versionCodes", [])) or "–"
            fraction = release.get("userFraction")
            notes = ", ".join(note["language"] for note in release.get("releaseNotes", []))
            print(f"  {release.get('name', '?'):<10} {release.get('status', '?'):<11} versionCode {codes}"
                  + (f"  rollout {fraction:.0%}" if fraction else "")
                  + (f"  notes: {notes}" if notes else ""))
        print()
    if bundles:
        print("Bundles Play holds: versionCode "
              + ", ".join(str(bundle["versionCode"]) for bundle in bundles))
    print("\nGoogle's review state is not in the API: look in the Play Console → Testen → Geschlossener Test.")


def release_notes(version_code: int) -> list[dict]:
    notes = []
    for locale in LOCALES:
        path = METADATA / locale / "changelogs" / f"{version_code}.txt"
        if path.exists():
            text = path.read_text().strip()
            if len(text) > 500:
                sys.exit(f"{path} has {len(text)} characters; Play allows 500.")
            notes.append({"language": locale, "text": text})
        else:
            print(f"warning: no release notes at {path}", file=sys.stderr)
    return notes


def upload(play: Play, aab: pathlib.Path, track: str, rollout: bool):
    if not aab.exists():
        sys.exit(f"{aab} does not exist — run `skip export --release --no-ios` first.")
    edit = play.open_edit()
    try:
        print(f"Uploading {aab.name} ({aab.stat().st_size / 1_000_000:.0f} MB) …")
        bundle = play.call("POST", f"{UPLOAD}/edits/{edit}/bundles?uploadType=media",
                           raw=aab.read_bytes(), content_type="application/octet-stream")
        version_code = bundle["versionCode"]
        print(f"Bundle accepted: versionCode {version_code}, sha256 {bundle.get('sha256', '?')[:12]}…")
        release = {"versionCodes": [str(version_code)],
                   "status": "completed" if rollout else "draft",
                   "releaseNotes": release_notes(version_code)}
        play.call("PUT", f"{API}/edits/{edit}/tracks/{urllib.parse.quote(track, safe='')}",
                  body={"track": track, "releases": [release]})
        play.call("POST", f"{API}/edits/{edit}:commit")
    except SystemExit:
        play.delete_edit(edit)
        raise
    state = "rolled out (submitted for review)" if rollout else "a draft release — finish it in the Play Console"
    print(f"Done: versionCode {version_code} is on track {track!r} as {state}.")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status", help="tracks, releases and bundles")
    up = commands.add_parser("upload", help="upload a bundle to a track")
    up.add_argument("aab", type=pathlib.Path)
    up.add_argument("--track", default="alpha")
    up.add_argument("--rollout", action="store_true")
    args = parser.parse_args()
    play = Play()
    if args.command == "status":
        show_status(play)
    else:
        upload(play, args.aab, args.track, args.rollout)


if __name__ == "__main__":
    main()
