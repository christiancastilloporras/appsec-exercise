#!/usr/bin/env python3
"""Download Terraform state file from Azure Blob Storage."""
import sys
import os
import subprocess
import time


def main():
    storage_account = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("TFSTATE_STORAGE_ACCOUNT", "")
    container_name = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("TFSTATE_CONTAINER", "tfstate")
    resource_group = sys.argv[3] if len(sys.argv) > 3 else os.environ.get("RESOURCE_GROUP", "appsec-exercise-rg")
    blob_name = "terraform.tfstate"

    if not storage_account:
        print("No storage account name provided")
        sys.exit(0)

    # Fetch storage account key (works with management-plane Contributor role)
    try:
        key_result = subprocess.run(
            ["az", "storage", "account", "keys", "list",
             "--account-name", storage_account,
             "--resource-group", resource_group,
             "--query", "[0].value", "-o", "tsv"],
            capture_output=True, text=True, timeout=60
        )
        if key_result.returncode != 0:
            print(f"Failed to get storage account key: {key_result.stderr}")
            sys.exit(0)
        storage_key = key_result.stdout.strip()
    except Exception as e:
        print(f"Failed to get storage key: {e}")
        sys.exit(0)

    # Get runner IP and add to storage account network rules
    # (storage account has public_network_access_enabled=false with default_action=Deny)
    runner_ip = None
    try:
        ip_result = subprocess.run(
            ["curl", "-s", "https://api.ipify.org"],
            capture_output=True, text=True, timeout=10
        )
        runner_ip = ip_result.stdout.strip()
        if runner_ip:
            print(f"Runner IP: {runner_ip}")
            # Add the runner IP to storage account network rules
            subprocess.run(
                ["az", "storage", "account", "network-rule", "add",
                 "--account-name", storage_account,
                 "--resource-group", resource_group,
                 "--ip", runner_ip],
                capture_output=True, text=True, timeout=60
            )
            # Wait a moment for the rule to propagate
            time.sleep(5)
    except Exception as e:
        print(f"Warning: Could not add runner IP to network rules: {e}")

    try:
        result = subprocess.run(
            ["az", "storage", "blob", "download",
             "--account-name", storage_account,
             "--container-name", container_name,
             "--name", blob_name,
             "--file", "terraform/terraform.tfstate",
             "--account-key", storage_key,
             "--auth-mode", "key",
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
    finally:
        # Clean up: remove the runner IP from network rules
        if runner_ip:
            print(f"Cleaning up: removing runner IP {runner_ip} from storage network rules")
            subprocess.run(
                ["az", "storage", "account", "network-rule", "remove",
                 "--account-name", storage_account,
                 "--resource-group", resource_group,
                 "--ip", runner_ip],
                capture_output=True, text=True, timeout=60
            )


if __name__ == "__main__":
    main()
