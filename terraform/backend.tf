terraform {
  required_version = ">= 1.7.0"

  backend "s3" {
    bucket                      = "tfstate"
    key                         = "terraform.tfstate"
    region                      = "us-east-1"
    endpoints {
      s3 = "https://s3.cloudguardian.xyz"
    }
    force_path_style            = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
  }
}
