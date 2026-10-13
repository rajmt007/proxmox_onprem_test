provider "proxmox" {
  endpoint  = var.virtual_environment_endpoint
  api_token = var.virtual_environment_api_token
  insecure  = false

  # Optional SSH access is used only by provider operations that need it.
  ssh {
    agent    = true
    username = var.ssh_user
  }
}
