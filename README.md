# Proxmox On-Premises Lab Automation

This repository includes a master prompt and Ansible starter kit for a nested VMware + Proxmox lab.

## Targets
- Proxmox node 1: `pve01` — `192.168.1.111`
- Proxmox node 2: `pve02` — `192.168.1.112`
- Guests: one Windows VM and one Ubuntu VM
- Checks: `Envir` inventory, node SSH/API readiness, ping, cluster quorum, VM deployment, and guest-to-guest ping

Start with [PROMPT.md](./PROMPT.md) and [Ansible instructions](./ansible/README.md). The actual environment inventory workbook is not in this repository; provide it locally.

The playbooks manage already-installed Proxmox nodes. VMware VM-shell creation and Proxmox OS installation are documented manual stages in [vmware/README.md](./vmware/README.md), to prevent accidental disk wipes. Cluster creation and guest creation are separate, approval-gated stages. A two-node cluster has quorum limitations when a node is offline; review QDevice/third-voting-node guidance before relying on availability.
