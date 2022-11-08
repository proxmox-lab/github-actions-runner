locals {
  description      = "Github Actions Runner for Proxmox Lab organization."
  domain           = "home.local"
  golden_image     = "centos-2009-master-7a750ca6f"
  ip_address       = "192.168.1.102"
  name             = terraform.workspace == "production" ? "github-actions-runner" : "github-actions-runner-${terraform.workspace}"
  organization     = {
    name     = "DANNE LLC"
    locality = "Norwalk"
    province = "IA"
    country  = "United States"
  }
  salt_environment = terraform.workspace == "production" ? "base" : "development"
  tags             = {
    git_repository = var.GIT_REPOSITORY
    git_short_sha  = var.GIT_SHORT_SHA
    description    = "Managed by Terraform"
  }
}
