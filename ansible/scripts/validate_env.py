#!/usr/bin/env python3
"""Validate local Ansible environment variables without revealing secret values."""
from __future__ import annotations
import argparse
import ipaddress
import os
import sys
from pathlib import Path

NODE_IPS = {"192.168.1.111", "192.168.1.112"}
API = ["PROXMOX_USER", "PROXMOX_TOKEN_ID", "PROXMOX_TOKEN_SECRET"]
REQUIRED = {
    "preflight": [],
    "cluster": API + ["PROXMOX_MASTER_PASSWORD", "ENVIR_WORKBOOK"],
    "deploy": API + [
        "ENVIR_WORKBOOK", "PVE_VM_STORAGE", "PVE_ISO_STORAGE", "PVE_BRIDGE",
        "WINDOWS_ISO_NAME", "WINDOWS_VIRTIO_ISO_NAME", "UBUNTU_ISO_NAME",
        "WINDOWS_GUEST_IP", "UBUNTU_GUEST_IP", "IP_RESERVATIONS_CONFIRMED",
    ],
    "connectivity": [
        "WINDOWS_GUEST_IP", "UBUNTU_GUEST_IP", "WINRM_USER", "WINRM_PASSWORD",
        "UBUNTU_SSH_USER", "UBUNTU_SSH_KEY",
    ],
}

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", choices=REQUIRED, required=True)
    args = parser.parse_args()
    errors = []
    missing = [key for key in REQUIRED[args.stage] if not os.environ.get(key, "").strip()]
    if missing:
        errors.append("Missing required environment variables: " + ", ".join(missing))

    addresses = {}
    if args.stage in {"deploy", "connectivity"}:
        for key in ("WINDOWS_GUEST_IP", "UBUNTU_GUEST_IP"):
            raw = os.environ.get(key, "").strip()
            if not raw:
                continue
            try:
                value = str(ipaddress.IPv4Address(raw))
            except ipaddress.AddressValueError:
                errors.append(f"{key} must be a valid IPv4 address.")
                continue
            if value in NODE_IPS:
                errors.append(f"{key} overlaps a Proxmox node IP ({value}).")
            addresses[key] = value
        if len(addresses) == 2 and len(set(addresses.values())) != 2:
            errors.append("Windows and Ubuntu guest IPs must be different.")

    if args.stage in {"cluster", "deploy"}:
        path = Path(os.environ.get("ENVIR_WORKBOOK", "")).expanduser()
        if not path.is_file():
            errors.append("ENVIR_WORKBOOK must point to an existing workbook with a populated Envir worksheet.")
    if args.stage == "deploy" and os.environ.get("IP_RESERVATIONS_CONFIRMED", "").strip().lower() != "true":
        errors.append("Set IP_RESERVATIONS_CONFIRMED=true only after reviewing Envir, DHCP/router/IPAM and live conflicts.")
    if args.stage == "connectivity":
        key = Path(os.environ.get("UBUNTU_SSH_KEY", "")).expanduser()
        if os.environ.get("UBUNTU_SSH_KEY", "").strip() and not key.is_file():
            errors.append("UBUNTU_SSH_KEY must point to an existing private key file.")

    if errors:
        print(f"Validation status: BLOCKED ({args.stage})")
        for error in errors:
            print(f"- {error}")
        return 2
    print(f"Validation status: PASS ({args.stage}); no secret values were displayed.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
