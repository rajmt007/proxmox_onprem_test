# Proxmox On-Premises Lab Automation

This repository includes the master prompt, an Ansible starter kit, and safety-gated scripts for a nested VMware + Proxmox lab.

## Targets
- Proxmox node 1: `pve01` — `192.168.1.111`
- Proxmox node 2: `pve02` — `192.168.1.112`
- Guests: one Windows VM and one Ubuntu VM
- Checks: `Envir` inventory, node SSH/API readiness, ping, cluster quorum, VM deployment, and guest-to-guest connectivity

Start with [PROMPT.md](./PROMPT.md), [Ansible instructions](./ansible/README.md), and the [VMware setup notes](./vmware/README.md). The new [Proxmox Lab Guide](./PROXMOX_LAB_GUIDE.md) documents the additional cross-platform scripts, Terraform template path, and local validation.

The repository now includes `inventory/environment-inventory.xlsx` with an `Envir` worksheet. Its two requested node records are marked **PROPOSED**, not active: the workbook is a template, not proof that the IP addresses are available. Confirm the actual DHCP/router reservations and physical LAN state before assigning either address.

The Ansible playbooks manage already-installed Proxmox nodes. VMware VM-shell creation and Proxmox OS installation remain deliberate, approval-gated steps to prevent accidental disk wipes. Cluster creation and guest creation are separate gated stages. A two-node cluster can lose quorum when one node is offline; review QDevice/third-voting-node guidance before relying on availability.

## Additional automation

The `scripts/` directory contains host preflight, inventory/IP conflict checks, node readiness reports, explicit cluster creation, guest VM-shell deployment, and connectivity tests. Run offline validation with:

```bash
python -m unittest discover -s tests -v
bash -n scripts/preflight.sh scripts/check-proxmox-nodes.sh scripts/configure-cluster.sh scripts/deploy-guests.sh scripts/test-guest-connectivity.sh
```

Terraform under `terraform/` is an optional **prepared-template clone** path and is disabled by default; do not use it to create the same guests as `scripts/deploy-guests.sh`. No live VMware, LAN, Proxmox, or guest connectivity result is implied by the offline tests.