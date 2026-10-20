terraform {
  # We pin to Terraform 1.5.x because Terraform 1.6+ uses AWS SDK v2,
  # which signs extra headers (amz-sdk-invocation-id, amz-sdk-request,
  # accept-encoding) that are modified by Cloudflare/NGINX proxies,
  # causing SignatureDoesNotMatch errors with RustFS's s3s-rs library.
  # Terraform 1.5.x uses AWS SDK v1 which does not sign those headers.
  required_version = ">= 1.5.0, < 1.6.0"

  backend "s3" {
    bucket                     = "tfstate"
    key                        = "terraform.tfstate"
    region                     = "us-east-1"
    endpoint                   = "https://s3.cloudguardian.xyz"
    force_path_style           = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
  }
}
