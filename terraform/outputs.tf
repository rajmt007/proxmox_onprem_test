output "windows_vm_id" {
  description = "Windows VM ID, populated only when template-clone mode is enabled."
  value       = var.enable_terraform_guests ? proxmox_virtual_environment_vm.windows[0].vm_id : null
}

output "ubuntu_vm_id" {
  description = "Ubuntu VM ID, populated only when template-clone mode is enabled."
  value       = var.enable_terraform_guests ? proxmox_virtual_environment_vm.ubuntu[0].vm_id : null
}

output "guest_addresses_to_configure_or_verify" {
  description = "Intended IPs; Windows may need manual guest-side network configuration when cloned from a generalized Windows template."
  value = var.enable_terraform_guests ? {
    windows = var.windows_guest_ip
    ubuntu  = var.ubuntu_guest_ip
  } : null
}
