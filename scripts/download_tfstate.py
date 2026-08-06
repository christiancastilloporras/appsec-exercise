#!/usr/bin/env python3
"""Download Terraform state file from GitHub release assets."""
import sys
import json
import urllib.request
import os


def main():
    release_file = sys.argv[1] if len(sys.argv) > 1 else "/tmp/release.json"
    token_arg = sys.argv[2].strip() if len(sys.argv) > 2 else os.environ.get("GITHUB_TOKEN", "")

    try:
        with open(release_file) as f:
            data = json.load(f)
    except Exception as e:
        print(f"No release file found: {e}")
        sys.exit(0)

    if not data or (isinstance(data, dict) and "message" in data):
        print("No release found in JSON response")
        sys.exit(0)

    for asset in data.get("assets", []):
        if asset["name"] == "terraform.tfstate":
            url = asset["url"]
            headers = {"Accept": "application/octet-stream"}
            if token_arg:
                headers["Authorization"] = f"token {token_arg}"
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req) as r:
                content = r.read()
            os.makedirs("terraform", exist_ok=True)
            with open("terraform/terraform.tfstate", "wb") as f:
                f.write(content)
            print(f"Downloaded state file ({len(content)} bytes)")
            sys.exit(0)

    print("No terraform.tfstate asset found in latest release")


if __name__ == "__main__":
    main()
