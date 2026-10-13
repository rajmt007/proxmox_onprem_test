# Proxmox On-Premises Lab Automation

This repository contains the implementation prompt for preparing and validating a nested VMware + Proxmox lab.

## Target environment

- Proxmox node 1: `pve01` — `192.168.1.111`
- Proxmox node 2: `pve02` — `192.168.1.112`
- Workloads: one Windows VM and one Ubuntu VM
- Checks: inventory/IP conflict checks, Proxmox readiness, cluster/quorum status, and bidirectional Windows/Ubuntu connectivity

## Start here

1. Read [PROMPT.md](./PROMPT.md).
2. Inspect your environment inventory workbook and the `Envir` worksheet.
3. Provide any missing network settings, VM resource sizes, installation media paths, and credentials via local configuration or environment variables. Never commit secrets.
4. Run preflight first. Proceed with OS installation, cluster formation, or guest deployment only after prerequisite checks pass and you explicitly approve changes.
5. Review generated reports; do not mark checks that have not run as passed.

## Important

This repository currently contains a specification prompt, not proof that Proxmox nodes or guest VMs have been deployed. Actual provisioning requires access to your VMware host, official installation media, correct network settings, enough compute/storage, and Proxmox credentials.

A two-node Proxmox cluster has quorum limitations if one node goes offline. See the guidance in [PROMPT.md](./PROMPT.md) about a QDevice or third voting node before relying on the cluster for availability.
