# Optional alternative to scripts/deploy-guests.sh:
# clones a prepared Windows template and a prepared Ubuntu cloud-init template.
# This is not the interactive-ISO installation path and remains disabled by default.
# Do not use this Terraform path and the qm-based script to create the same guest VMs.

resource "proxmox_virtual_environment_vm" "windows" {
  count       = var.enable_terraform_guests ? 1 : 0
  name        = var.windows_name
  description = "Windows lab guest cloned from an existing prepared template"
  tags        = ["lab", "windows", "managed-by-terraform"]
  node_name   = var.windows_node
  vm_id       = var.windows_vm_id

  clone {
    node_name = var.windows_template_node
    vm_id     = var.windows_template_vm_id
    full      = true
  }

  cpu {
    cores = var.windows_vcpu
    type  = "x86-64-v2-AES"
  }
  memory {
    dedicated = var.windows_memory_mib
  }
  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  lifecycle {
    precondition {
      condition     = !var.enable_terraform_guests || (var.windows_vm_id != null && var.windows_vm_id >= 100 && var.windows_template_vm_id != null && var.windows_template_vm_id >= 100)
      error_message = "Enable mode requires a verified, unused Windows guest VM ID and an existing prepared Windows template VM ID."
    }
    precondition {
      condition     = !var.enable_terraform_guests || (var.windows_node != "" && var.windows_template_node != "" && var.bridge != "" && var.windows_guest_ip != "")
      error_message = "Enable mode requires verified Windows node, template node, bridge, and reserved Windows guest IP values."
    }
  }
}

resource "proxmox_virtual_environment_vm" "ubuntu" {
  count       = var.enable_terraform_guests ? 1 : 0
  name        = var.ubuntu_name
  description = "Ubuntu lab guest cloned from a prepared cloud-init template"
  tags        = ["lab", "ubuntu", "managed-by-terraform"]
  node_name   = var.ubuntu_node
  vm_id       = var.ubuntu_vm_id
  agent {
    enabled = true
  }
  clone {
    node_name = var.ubuntu_template_node
    vm_id     = var.ubuntu_template_vm_id
    full      = true
  }
  cpu {
    cores = var.ubuntu_vcpu
    type  = "x86-64-v2-AES"
  }
  memory {
    dedicated = var.ubuntu_memory_mib
  }
  network_device {
    bridge = var.bridge
    model  = "virtio"
  }
  initialization {
    dns {
      servers = var.dns_servers
    }
    ip_config {
      ipv4 {
        address = "${var.ubuntu_guest_ip}/${var.subnet_prefix}"
        gateway = var.gateway
      }
    }
    user_account {
      username = var.ubuntu_username
      keys     = var.ubuntu_ssh_public_key_path == "" ? [] : [trimspace(file(var.ubuntu_ssh_public_key_path))]
    }
  }

  lifecycle {
    precondition {
      condition     = !var.enable_terraform_guests || (var.ubuntu_vm_id != null && var.ubuntu_vm_id >= 100 && var.ubuntu_template_vm_id != null && var.ubuntu_template_vm_id >= 100)
      error_message = "Enable mode requires a verified, unused Ubuntu guest VM ID and an existing prepared Ubuntu template VM ID."
    }
    precondition {
      condition     = !var.enable_terraform_guests || (var.ubuntu_node != "" && var.ubuntu_template_node != "" && var.bridge != "" && var.ubuntu_guest_ip != "" && var.gateway != "" && var.subnet_prefix != null && var.ubuntu_ssh_public_key_path != "")
      error_message = "Enable mode requires verified Ubuntu node/template, bridge, reserved guest IP, gateway, prefix, and public-key path."
    }
  }
}
