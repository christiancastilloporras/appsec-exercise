#!/usr/bin/env python3
"""Download Terraform state file from GitHub release assets."""
import sys
import json
import base64
import urllib.request


def main():
    if len(sys.argv) < 2:
        print("Usage: download_tfstate.py <release.json>")
        sys.exit(0)

    release_file = sys.argv[1]
    try:
        with open(release_file) as f:
            data = json.load(f)
    except Exception as e:
        print(f"No release found: {e}")
        sys.exit(0)

    if not data or isinstance(data, dict) and "message" in data:
        print("No release found")
        sys.exit(0)

    for asset in data.get("assets", []):
        if asset["name"] == "terraform.tfstate":
            url = asset["url"]
            token = sys.argv[2] if len(sys.argv) > 2 else ""
            req = urllib.request.Request(
                url,
                headers={
                    "Authorization": f"token {token}",
                    "Accept": "application/octet-stream",
                },
            )
            with urllib.request.urlopen(req) as r:
                content = r.read()
            with open("terraform/terraform.tfstate", "wb") as f:
                f.write(content)
            print(f"Downloaded state file ({len(content)} bytes)")
            sys.exit(0)

    print("No terraform.tfstate asset found in latest release")


if __name__ == "__main__":
    main()
