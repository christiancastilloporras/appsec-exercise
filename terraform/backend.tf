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
  }
}
