#!/usr/bin/env python3
"""Download Terraform state file from Azure Blob Storage."""
import sys
import os
import subprocess
import time
import urllib.request


def get_runner_ip():
    """Fetch the current runner's public IP address."""
    try:
        with urllib.request.urlopen("https://api.ipify.org", timeout=10) as resp:
            return resp.read().decode().strip()
    except Exception:
        return None


def add_ip_to_storage(runner_ip, storage_account, resource_group):
    """Add runner IP to storage account network rules, returning True on success."""
    # First, check if the IP is already in the rules
    try:
        result = subprocess.run(
            ["az", "storage", "account", "network-rule", "list",
             "--account-name", storage_account,
             "--resource-group", resource_group,
             "--query", f"[?ipRule.value=='{runner_ip}'].ipRule.value | [0]",
             "-o", "tsv"],
            capture_output=True, text=True, timeout=60
        )
        if result.returncode == 0 and result.stdout.strip():
            print(f"Runner IP {runner_ip} already in storage network rules")
            return True
    except Exception:
        pass

    # Add the IP to the network rules
    try:
        result = subprocess.run(
            ["az", "storage", "account", "network-rule", "add",
             "--account-name", storage_account,
             "--resource-group", resource_group,
             "--ip", runner_ip],
            capture_output=True, text=True, timeout=60
        )
        if result.returncode == 0:
            print(f"Added runner IP {runner_ip} to storage network rules")
            return True
        else:
            stderr = result.stderr.strip()
            if "already exists" in stderr.lower() or "network rule already exists" in stderr.lower():
                print(f"Runner IP {runner_ip} already in storage network rules")
                return True
            print(f"Warning: Could not add runner IP to network rules: {stderr}")
    except Exception as e:
        print(f"Warning: Could not add runner IP to network rules: {e}")
    return False


def remove_ip_from_storage(runner_ip, storage_account, resource_group):
    """Remove runner IP from storage account network rules (cleanup)."""
    try:
        subprocess.run(
            ["az", "storage", "account", "network-rule", "remove",
             "--account-name", storage_account,
             "--resource-group", resource_group,
             "--ip", runner_ip],
            capture_output=True, text=True, timeout=60
        )
        print(f"Removed runner IP {runner_ip} from storage network rules")
    except Exception as e:
        print(f"Warning: Could not remove runner IP from network rules: {e}")


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
    runner_ip = get_runner_ip()
    ip_added = False
    if runner_ip:
        print(f"Runner IP: {runner_ip}")
        ip_added = add_ip_to_storage(runner_ip, storage_account, resource_group)
        # Wait for network rule propagation (Azure can take up to 30s)
        if ip_added:
            print("Waiting for network rule propagation (15s)...")
            time.sleep(15)

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
            stderr = result.stderr.strip()
            if ip_added and "blocked by network rules" in stderr.lower():
                print(f"Network rule propagation may still be in progress. Retrying in 15s...")
                time.sleep(15)
                result2 = subprocess.run(
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
                if result2.returncode == 0:
                    size = os.path.getsize("terraform/terraform.tfstate")
                    print(f"Downloaded state file ({size} bytes) on retry")
                else:
                    print(f"Failed to download on retry: {result2.stderr}")
            else:
                print(f"Failed to download: {stderr}")
    except subprocess.TimeoutExpired:
        print("Download timed out")
    except FileNotFoundError:
        print("State file not found in blob storage")
    except Exception as e:
        print(f"Failed to download state file: {e}")
    finally:
        # Clean up: remove the runner IP from network rules
        if runner_ip and ip_added:
            remove_ip_from_storage(runner_ip, storage_account, resource_group)


if __name__ == "__main__":
    main()
