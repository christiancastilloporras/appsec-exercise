terraform {
  backend "http" {
    address = "https://app.terraform.io/api/v2/workspaces/appsec-exercise/state-versions"
  }
}
