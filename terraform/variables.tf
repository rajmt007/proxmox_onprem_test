variable "enable_terraform_guests" {
  description = "Disabled by default. Enable only when using the template-clone path instead of scripts/deploy-guests.sh. Do not use both paths for the same lab."
  type        = bool
  default     = false
}

variable "virtual_environment_endpoint" {
  description = "Proxmox API endpoint, including https:// and port 8006. Supply using TF_VAR_virtual_environment_endpoint."
  type        = string
  default     = ""
}

variable "virtual_environment_api_token" {
  description = "Least-privilege Proxmox API token. Supply using TF_VAR_virtual_environment_api_token or a supported secret store; never commit it."
  type        = string
  sensitive   = true
  default     = ""
}

variable "ssh_user" {
  description = "SSH account used by provider operations that require SSH."
  type        = string
  default     = "root"
}

variable "bridge" {
  description = "Existing Proxmox bridge verified on both target nodes."
  type        = string
  default     = ""
}

variable "windows_name" {
  type = string
  default = "win-lab01"
}
variable "windows_node" {
  description = "Verified cluster node for the Windows guest."
  type        = string
  default     = ""
}
variable "windows_vm_id" {
  description = "Unused Windows guest VM ID verified across the cluster."
  type        = number
  default     = null
}
variable "windows_template_node" {
  description = "Node on which the prepared Windows template exists."
  type        = string
  default     = ""
}
variable "windows_template_vm_id" {
  description = "Existing prepared Windows template VM ID; template must be licensed/authorized and correctly prepared."
  type        = number
  default     = null
}
variable "windows_memory_mib" {
  type = number
  default = 4096
}
variable "windows_vcpu" {
  type = number
  default = 2
}
variable "windows_guest_ip" {
  description = "Address reserved and verified for Windows; configure in guest OS as needed."
  type        = string
  default     = ""
}

variable "ubuntu_name" {
  type = string
  default = "ubuntu-lab01"
}
variable "ubuntu_node" {
  description = "Verified cluster node for the Ubuntu guest."
  type        = string
  default     = ""
}
variable "ubuntu_vm_id" {
  description = "Unused Ubuntu guest VM ID verified across the cluster."
  type        = number
  default     = null
}
variable "ubuntu_template_node" {
  description = "Node on which the prepared Ubuntu cloud-init template exists."
  type        = string
  default     = ""
}
variable "ubuntu_template_vm_id" {
  description = "Existing prepared Ubuntu cloud-init template VM ID."
  type        = number
  default     = null
}
variable "ubuntu_memory_mib" {
  type = number
  default = 2048
}
variable "ubuntu_vcpu" {
  type = number
  default = 2
}
variable "ubuntu_guest_ip" {
  description = "Address reserved and verified for Ubuntu; must not overlap any active inventory address."
  type        = string
  default     = ""
}
variable "subnet_prefix" {
  description = "Verified IPv4 prefix (for example 24 only after network inspection)."
  type        = number
  default     = null
}
variable "gateway" {
  description = "Verified IPv4 gateway; no default is assumed."
  type        = string
  default     = ""
}
variable "dns_servers" {
  description = "Verified DNS server addresses."
  type        = list(string)
  default     = []
}
variable "ubuntu_username" {
  description = "Initial Ubuntu username configured in the prepared cloud-init template."
  type        = string
  default     = "labadmin"
}
variable "ubuntu_ssh_public_key_path" {
  description = "Path to a local SSH public key. Never point this at a private key."
  type        = string
  default     = ""
}
