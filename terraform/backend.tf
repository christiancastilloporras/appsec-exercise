terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "your-tfc-org-name"

    workspaces {
      name = "appsec-exercise"
    }
  }
}
