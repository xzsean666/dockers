#!/usr/bin/env python3
import argparse
import json
import socket
import sys
import threading
import urllib.parse
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"
DEFAULT_SCOPE = "https://www.googleapis.com/auth/drive"


class CallbackHandler(BaseHTTPRequestHandler):
    server_version = "rclone-sync-oauth/1.0"

    def do_GET(self):  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(parsed.query)
        self.server.oauth_result = query

        if "error" in query:
            body = "Google authorization failed. You can close this tab."
            status = 400
        else:
            body = "Google authorization finished. You can close this tab."
            status = 200

        encoded = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

        threading.Thread(target=self.server.shutdown, daemon=True).start()

    def log_message(self, fmt, *args):
        return


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Get a Google Drive OAuth refresh token without using rclone."
    )
    parser.add_argument("client_secret_json", help="Google OAuth client secret JSON file")
    parser.add_argument(
        "--scope",
        default=DEFAULT_SCOPE,
        help=f"OAuth scope to request. Default: {DEFAULT_SCOPE}",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=53682,
        help="Local loopback callback port. Default: 53682",
    )
    parser.add_argument(
        "--no-browser",
        action="store_true",
        help="Print the authorization URL instead of opening a browser",
    )
    args = parser.parse_args()

    secret = load_client_secret(Path(args.client_secret_json))
    client_id = secret.get("client_id")
    client_secret = secret.get("client_secret", "")
    if not client_id:
        raise SystemExit("client_secret_json does not contain client_id")

    port = find_port(args.port)
    redirect_uri = f"http://127.0.0.1:{port}/"

    auth_params = {
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": args.scope,
        "access_type": "offline",
        "prompt": "consent",
        "include_granted_scopes": "true",
    }
    auth_url = AUTH_URL + "?" + urllib.parse.urlencode(auth_params)

    httpd = HTTPServer(("127.0.0.1", port), CallbackHandler)
    httpd.oauth_result = {}

    print("Open this URL in a browser and approve access:")
    print(auth_url)
    print()
    if not args.no_browser:
        webbrowser.open(auth_url)

    print(f"Waiting for Google callback on {redirect_uri} ...", file=sys.stderr)
    httpd.serve_forever()

    result = httpd.oauth_result
    if "error" in result:
        error = result.get("error", ["unknown_error"])[0]
        detail = result.get("error_description", [""])[0]
        raise SystemExit(f"authorization failed: {error} {detail}".strip())
    code = result.get("code", [""])[0]
    if not code:
        raise SystemExit("authorization callback did not contain a code")

    token = exchange_code(client_id, client_secret, code, redirect_uri)
    refresh_token = token.get("refresh_token")
    if not refresh_token:
        raise SystemExit(
            "Google did not return a refresh_token. Revoke the app access or retry with prompt=consent."
        )

    print("Use this env value:")
    print(f"RCLONE_SYNC_TARGET_CONFIG_TOKEN_REFRESH_TOKEN={refresh_token}")
    return 0


def load_client_secret(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if "installed" in data:
        return data["installed"]
    if "web" in data:
        return data["web"]
    return data


def find_port(preferred: int) -> int:
    for port in (preferred, 0):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            try:
                sock.bind(("127.0.0.1", port))
            except OSError:
                continue
            return sock.getsockname()[1]
    raise SystemExit("could not allocate a local callback port")


def exchange_code(client_id: str, client_secret: str, code: str, redirect_uri: str) -> dict:
    payload = {
        "client_id": client_id,
        "code": code,
        "grant_type": "authorization_code",
        "redirect_uri": redirect_uri,
    }
    if client_secret:
        payload["client_secret"] = client_secret
    body = urllib.parse.urlencode(payload).encode("utf-8")
    request = urllib.request.Request(
        TOKEN_URL,
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"token exchange failed: HTTP {exc.code}: {detail}") from exc


if __name__ == "__main__":
    raise SystemExit(main())
