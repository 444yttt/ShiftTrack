#!/usr/bin/env python3
"""Export an App Store IPA.

Automatic cloud signing is tried first. If the API key cannot use a
cloud-managed distribution certificate, this creates a distribution
certificate and an App Store profile, then exports with manual signing.
Secrets and certificate material are not printed.
"""

import base64
import json
import os
import plistlib
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

BUNDLE_ID = "app.shifttrack.ios"
ARCHIVE = os.environ["RUNNER_TEMP"] + "/ShiftTrack.xcarchive"
EXPORT_DIR = os.environ["RUNNER_TEMP"] + "/export"
KEY_PATH = os.path.expanduser(
    "~/private_keys/AuthKey_" + os.environ["ASC_KEY_ID"] + ".p8"
)


def run(args, **kwargs):
    result = subprocess.run(args, text=True, capture_output=True, **kwargs)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        print(detail[-1500:] if detail else "command failed")
        raise SystemExit(result.returncode)
    return result


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    index = 2
    if der[1] & 0x80:
        index = 2 + (der[1] & 0x7F)

    def read_int(pos: int) -> tuple[bytes, int]:
        if der[pos] != 0x02:
            raise RuntimeError("unexpected signature")
        length = der[pos + 1]
        pos += 2
        value = der[pos : pos + length]
        pos += length
        if len(value) > 32:
            value = value[-32:]
        return value.rjust(32, b"\x00"), pos

    raw_r, index = read_int(index)
    raw_s, _ = read_int(index)
    return raw_r + raw_s


def token() -> str:
    header = b64url(
        json.dumps({"alg": "ES256", "kid": os.environ["ASC_KEY_ID"], "typ": "JWT"}).encode()
    )
    payload = b64url(
        json.dumps(
            {
                "iss": os.environ["ASC_ISSUER_ID"],
                "exp": int(time.time()) + 600,
                "aud": "appstoreconnect-v1",
            }
        ).encode()
    )
    signing_input = f"{header}.{payload}".encode()
    signature = subprocess.check_output(
        ["openssl", "dgst", "-sha256", "-sign", KEY_PATH], input=signing_input
    )
    return signing_input.decode() + "." + b64url(der_to_raw(signature))


def api(method: str, path: str, body=None):
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path,
        data=data,
        method=method,
        headers={
            "Authorization": "Bearer " + token(),
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        raw = error.read()
        parsed = {}
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            parsed = {}
        summaries = []
        for item in parsed.get("errors", []):
            if not isinstance(item, dict):
                continue
            detail = str(item.get("detail") or item.get("title") or "")
            detail = detail.replace(os.environ.get("APPLE_TEAM_ID", "___"), "TEAM")
            summaries.append(f"{item.get('code', '')} {detail[:240]}".strip())
        print(f"App Store Connect API {method} {path.split('?')[0]} -> {error.code} {' | '.join(summaries)}")
        return error.code, parsed


def automatic_export() -> bool:
    plist_path = os.environ["RUNNER_TEMP"] + "/ExportOptions.plist"
    plist = {
        "method": "app-store-connect",
        "teamID": os.environ["APPLE_TEAM_ID"],
        "signingStyle": "automatic",
        "uploadSymbols": True,
        "manageAppVersionAndBuildNumber": False,
    }
    with open(plist_path, "wb") as handle:
        plistlib.dump(plist, handle)
    result = subprocess.run(
        [
            "xcodebuild",
            "-exportArchive",
            "-archivePath",
            ARCHIVE,
            "-exportPath",
            EXPORT_DIR,
            "-exportOptionsPlist",
            plist_path,
            "-allowProvisioningUpdates",
            "-authenticationKeyPath",
            KEY_PATH,
            "-authenticationKeyID",
            os.environ["ASC_KEY_ID"],
            "-authenticationKeyIssuerID",
            os.environ["ASC_ISSUER_ID"],
        ]
    )
    return result.returncode == 0


def bundle_resource_id() -> str:
    query = urllib.parse.urlencode({"filter[identifier]": BUNDLE_ID})
    status, payload = api("GET", "/v1/bundleIds?" + query)
    if status != 200 or not payload.get("data"):
        raise SystemExit("Bundle ID が見つかりません: " + BUNDLE_ID)
    return payload["data"][0]["id"]


def certificate_name(path: str) -> str:
    subject = subprocess.check_output(
        [
            "openssl",
            "x509",
            "-inform",
            "DER",
            "-in",
            path,
            "-noout",
            "-subject",
            "-nameopt",
            "RFC2253",
        ],
        text=True,
    )
    for part in subject.split(","):
        part = part.strip().removeprefix("subject=").strip()
        if part.startswith("CN="):
            return part[3:]
    raise RuntimeError("証明書の名前を読めません")


def revoke_recent_certificate(certificate_type: str) -> bool:
    status, payload = api(
        "GET",
        "/v1/certificates?limit=20&filter[certificateType]=" + certificate_type,
    )
    if status != 200:
        return False
    newest = None
    for item in payload.get("data", []):
        expiration = item.get("attributes", {}).get("expirationDate", "")
        if newest is None or expiration > newest[0]:
            newest = (expiration, item["id"])
    if newest is None:
        return False
    try:
        expires = time.strptime(newest[0][:19], "%Y-%m-%dT%H:%M:%S")
    except ValueError:
        return False
    days_left = (time.mktime(expires) - time.time()) / 86400
    print(f"{certificate_type} の残日数が最も長い証明書は {days_left:.1f} 日")
    if days_left < 360:
        return False
    deleted, _ = api("DELETE", "/v1/certificates/" + newest[1])
    print(f"直近の {certificate_type} を取り消しました ({deleted})")
    return deleted in (200, 204)


def create_distribution_identity(work: str) -> tuple[str, str]:
    run(
        [
            "openssl",
            "req",
            "-new",
            "-newkey",
            "rsa:2048",
            "-nodes",
            "-keyout",
            f"{work}/key.pem",
            "-out",
            f"{work}/csr.pem",
            "-subj",
            "/CN=ShiftTrack Distribution/O=ShiftTrack/C=US",
        ]
    )
    csr = open(f"{work}/csr.pem", encoding="utf-8").read()
    certificate_id = None
    for certificate_type in ("DISTRIBUTION", "IOS_DISTRIBUTION"):
        status, payload = api(
            "POST",
            "/v1/certificates",
            {
                "data": {
                    "type": "certificates",
                    "attributes": {
                        "certificateType": certificate_type,
                        "csrContent": csr,
                    },
                }
            },
        )
        if status == 409 and revoke_recent_certificate(certificate_type):
            status, payload = api(
                "POST",
                "/v1/certificates",
                {
                    "data": {
                        "type": "certificates",
                        "attributes": {
                            "certificateType": certificate_type,
                            "csrContent": csr,
                        },
                    }
                },
            )
        if status in (200, 201):
            certificate_id = payload["data"]["id"]
            encoded = payload["data"]["attributes"]["certificateContent"]
            open(f"{work}/cert.der", "wb").write(base64.b64decode(encoded))
            print(f"配布用証明書を作成しました ({certificate_type})")
            break
        if status not in (403, 409, 422):
            break
    if not certificate_id:
        raise SystemExit(
            "配布用証明書を作成できません。クラウド署名には Admin の API キーが必要です。"
        )
    run(
        [
            "openssl",
            "x509",
            "-inform",
            "DER",
            "-in",
            f"{work}/cert.der",
            "-out",
            f"{work}/cert.pem",
        ]
    )
    password = base64.b64encode(os.urandom(18)).decode()
    open(f"{work}/p12pass", "w", encoding="utf-8").write(password)
    exported = subprocess.run(
        [
            "openssl",
            "pkcs12",
            "-export",
            "-inkey",
            f"{work}/key.pem",
            "-in",
            f"{work}/cert.pem",
            "-out",
            f"{work}/cert.p12",
            "-passout",
            "pass:" + password,
        ],
        text=True,
        capture_output=True,
    )
    if exported.returncode != 0:
        exported = subprocess.run(
            [
                "openssl",
                "pkcs12",
                "-export",
                "-legacy",
                "-inkey",
                f"{work}/key.pem",
                "-in",
                f"{work}/cert.pem",
                "-out",
                f"{work}/cert.p12",
                "-passout",
                "pass:" + password,
            ],
            text=True,
            capture_output=True,
        )
    if exported.returncode != 0:
        print((exported.stderr or "pkcs12 export failed")[-1500:])
        raise SystemExit(exported.returncode)
    return certificate_id, certificate_name(f"{work}/cert.der")


def install_identity(work: str) -> None:
    password = base64.b64encode(os.urandom(18)).decode()
    p12_password = open(f"{work}/p12pass", encoding="utf-8").read()
    keychain = f"{work}/build.keychain-db"
    run(["security", "create-keychain", "-p", password, keychain])
    run(["security", "set-keychain-settings", "-lut", "21600", keychain])
    run(["security", "unlock-keychain", "-p", password, keychain])
    existing = subprocess.check_output(["security", "list-keychains", "-d", "user"], text=True)
    names = [line.strip().strip('"') for line in existing.splitlines() if line.strip()]
    run(["security", "list-keychains", "-d", "user", "-s", keychain, *names])
    run(["security", "default-keychain", "-s", keychain])
    run(
        [
            "security",
            "import",
            f"{work}/cert.p12",
            "-k",
            keychain,
            "-P",
            p12_password,
            "-A",
            "-T",
            "/usr/bin/codesign",
            "-T",
            "/usr/bin/security",
            "-f",
            "pkcs12",
        ]
    )
    run(
        [
            "security",
            "set-key-partition-list",
            "-S",
            "apple-tool:,apple:,codesign:",
            "-s",
            "-k",
            password,
            keychain,
        ]
    )


def create_profile(work: str, bundle_id: str, certificate_id: str) -> str:
    name = "ShiftTrack App Store " + os.environ.get("GITHUB_RUN_ID", "local")
    status, payload = api(
        "POST",
        "/v1/profiles",
        {
            "data": {
                "type": "profiles",
                "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
                "relationships": {
                    "bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
                    "certificates": {
                        "data": [{"type": "certificates", "id": certificate_id}]
                    },
                },
            },
        },
    )
    if status not in (200, 201):
        raise SystemExit("App Store 用プロファイルを作成できません。")
    encoded = payload["data"]["attributes"]["profileContent"]
    profile_path = f"{work}/profile.mobileprovision"
    open(profile_path, "wb").write(base64.b64decode(encoded))
    decoded = subprocess.check_output(["security", "cms", "-D", "-i", profile_path])
    info = plistlib.loads(decoded)
    profiles = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")
    os.makedirs(profiles, exist_ok=True)
    destination = os.path.join(profiles, info["UUID"] + ".mobileprovision")
    open(destination, "wb").write(open(profile_path, "rb").read())
    print("App Store 用プロファイルを作成しました")
    return info["Name"]


def manual_export(profile_name: str, signing_certificate: str) -> None:
    plist_path = os.environ["RUNNER_TEMP"] + "/ExportOptions-manual.plist"
    plist = {
        "method": "app-store-connect",
        "teamID": os.environ["APPLE_TEAM_ID"],
        "signingStyle": "manual",
        "signingCertificate": signing_certificate,
        "provisioningProfiles": {BUNDLE_ID: profile_name},
        "uploadSymbols": True,
        "manageAppVersionAndBuildNumber": False,
    }
    with open(plist_path, "wb") as handle:
        plistlib.dump(plist, handle)
    subprocess.run(
        [
            "xcodebuild",
            "-exportArchive",
            "-archivePath",
            ARCHIVE,
            "-exportPath",
            EXPORT_DIR,
            "-exportOptionsPlist",
            plist_path,
        ],
        check=True,
    )


def main() -> None:
    os.makedirs(EXPORT_DIR, exist_ok=True)
    print("自動署名で書き出します")
    if automatic_export():
        print("自動署名で書き出しました")
        return
    print("自動署名はクラウド署名の権限で止まったため、配布用証明書で書き出します")
    with tempfile.TemporaryDirectory() as work:
        certificate_id, signing_certificate = create_distribution_identity(work)
        try:
            install_identity(work)
            profile_name = create_profile(work, bundle_resource_id(), certificate_id)
            manual_export(profile_name, signing_certificate)
        except BaseException:
            api("DELETE", "/v1/certificates/" + certificate_id)
            raise
    print("手動署名で書き出しました")


if __name__ == "__main__":
    main()
