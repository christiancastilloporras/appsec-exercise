terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = var.tfc_organization
    workspaces {
      name = "appsec-exercise"
    }
  }
}
