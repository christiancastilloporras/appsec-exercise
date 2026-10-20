terraform {
  required_version = ">= 1.7.0"

  backend "s3" {
    bucket                     = "tfstate"
    key                        = "terraform.tfstate"
    region                     = "us-east-1"
    endpoints = {
      s3 = "https://s3.cloudguardian.xyz"
    }
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_lockfile                = true
    # Override workspace_key_prefix from default "env:" to "env_" — the colon
    # gets URL-encoded as "%3A" in the ListObjectsV2 prefix query parameter,
    # which causes SigV4 SignatureDoesNotMatch with RustFS's s3s-rs library.
    # The aws CLI test uses "env_" as well, so both will match.
    workspace_key_prefix        = "env_"
  }
}
