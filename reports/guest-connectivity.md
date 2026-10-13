# Guest-to-guest connectivity status snapshot

- Generated UTC: `2026-10-13T04:44:59.052389+00:00`
- Overall status: **BLOCKED**
- Live environment was not available during repository construction. This is an initial status snapshot, not a live run.

## Windows and Ubuntu VM creation — BLOCKED

- Timestamp UTC: `2026-10-13T04:44:59.052389+00:00`
- Command/test: `scripts/deploy-guests.sh --dry-run then explicit apply gate`
- Evidence: Blocked because no live cluster/quorum/storage/ISO/IP/VMID evidence or user-supplied guest network values are available here.
- Remediation: Supply verified guest IDs, guest IPs, prefix, gateway, bridge, storage IDs and official installation media; complete live preflight first.

## Ubuntu to Windows connectivity — NOT RUN

- Timestamp UTC: `2026-10-13T04:44:59.052389+00:00`
- Command/test: `scripts/test-guest-connectivity.sh using Ubuntu SSH endpoint`
- Evidence: Guest VM addresses/endpoints and OS installs are unknown; no guest probe ran.
- Remediation: After guest installs and network configuration, run the two-direction connectivity script from a management host with SSH access to both guests.

## Windows to Ubuntu connectivity — NOT RUN

- Timestamp UTC: `2026-10-13T04:44:59.052389+00:00`
- Command/test: `scripts/test-guest-connectivity.sh using Windows SSH endpoint`
- Evidence: Guest VM addresses/endpoints and OS installs are unknown; no guest probe ran.
- Remediation: If Echo is blocked, diagnose routing/firewall; do not disable firewalls globally. A narrow, approved ICMP rule or TCP service test may help.

