# Proxmox node preflight status snapshot

- Generated UTC: `2026-10-13T04:44:59.052389+00:00`
- Overall status: **BLOCKED**
- Live environment was not available during repository construction. This is an initial status snapshot, not a live run.

## Inventory workbook and Envir worksheet — PASS

- Timestamp UTC: `2026-10-13T04:44:59.052389+00:00`
- Command/test: `scripts/inventory_check.py --path inventory/environment-inventory.xlsx --worksheet Envir`
- Evidence: Workbook template present; two rows loaded and both requested node entries are PROPOSED. This is a repository check only.
- Remediation: Complete verified network/owner fields and change records to ACTIVE only after live installation.

## Target IP availability (.111/.112) — NOT RUN

- Timestamp UTC: `2026-10-13T04:44:59.052389+00:00`
- Command/test: `scripts/check-ip-conflicts.ps1 / router-DHCP reservation lookup`
- Evidence: This environment cannot access the user's LAN or DHCP/router. A failed ping alone cannot prove an address is free.
- Remediation: Run the IP probe on the actual LAN and independently check authoritative DHCP/router reservations.

## VMware host resources and nested virtualization — NOT RUN

- Timestamp UTC: `2026-10-13T04:44:59.052389+00:00`
- Command/test: `scripts/preflight.ps1 (on the Windows VMware host)`
- Evidence: No access to the actual VMware host from this build environment.
- Remediation: Run host preflight; enable nested virtualization in both new VM settings and confirm host capacity.

## Installed Proxmox versions, node networking, name resolution, time, KVM and storage — NOT RUN

- Timestamp UTC: `2026-10-13T04:44:59.052389+00:00`
- Command/test: `scripts/check-proxmox-nodes.sh (from an SSH-capable management host)`
- Evidence: No live SSH/Proxmox commands were executed during repository construction.
- Remediation: Install into dedicated VM disks only after approval; run the node preflight and resolve every FAIL/BLOCKED status.

