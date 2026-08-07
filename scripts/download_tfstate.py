#!/usr/bin/env python3
"""Download Terraform state file from Azure Blob Storage."""
import sys
import os
import subprocess


def main():
    storage_account = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("TFSTATE_STORAGE_ACCOUNT", "")
    container_name = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("TFSTATE_CONTAINER", "tfstate")
    blob_name = "terraform.tfstate"

    if not storage_account:
        print("No storage account name provided")
        sys.exit(0)

    try:
        result = subprocess.run(
            ["az", "storage", "blob", "download",
             "--account-name", storage_account,
             "--container-name", container_name,
             "--name", blob_name,
             "--file", "terraform/terraform.tfstate",
             "--auth-mode", "login",
             "--no-progress"],
            capture_output=True, text=True, timeout=120
        )
        if result.returncode == 0:
            size = os.path.getsize("terraform/terraform.tfstate")
            print(f"Downloaded state file ({size} bytes)")
        else:
            print(f"Failed to download: {result.stderr}")
    except subprocess.TimeoutExpired:
        print("Download timed out")
    except FileNotFoundError:
        print("State file not found in blob storage")
    except Exception as e:
        print(f"Failed to download state file: {e}")


if __name__ == "__main__":
    main()
