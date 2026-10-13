"""Pure validation helpers shared by inventory and safety tests (stdlib only)."""
from __future__ import annotations

import ipaddress
from typing import Iterable, Mapping, Any


class ValidationError(ValueError):
    """Raised when a lab configuration is unsafe or incomplete."""


def normalize_ip(value: Any) -> str | None:
    if value is None or str(value).strip() == "":
        return None
    try:
        return str(ipaddress.ip_address(str(value).strip()))
    except ValueError as exc:
        raise ValidationError(f"Invalid IP address: {value!r}") from exc


def normalize_prefix(value: Any) -> int:
    if value is None or str(value).strip() == "":
        raise ValidationError("Subnet prefix is required; it must be read from verified network data.")
    text = str(value).strip()
    if text.startswith("/"):
        text = text[1:]
    try:
        prefix = int(text)
    except ValueError as exc:
        raise ValidationError(f"Invalid subnet prefix: {value!r}") from exc
    if not 0 <= prefix <= 32:
        raise ValidationError(f"IPv4 subnet prefix must be between 0 and 32, got {prefix}.")
    return prefix


def inventory_ip_matches(rows: Iterable[Mapping[str, Any]], target_ip: str) -> list[dict[str, Any]]:
    target = normalize_ip(target_ip)
    if target is None:
        raise ValidationError("Target IP address is required.")
    matches = []
    for row in rows:
        # Proposed template records are not evidence that a device currently owns an address.
        # A blank status is treated conservatively as inventory that may be in use.
        status = next((str(v).strip().upper() for k, v in row.items()
                       if str(k).strip().lower() == "status"), "")
        if status in {"PROPOSED", "RETIRED"}:
            continue
        for key, value in row.items():
            if str(key).strip().lower() in {"ip_address", "ip address", "ip", "ipv4", "address"}:
                if value is None or str(value).strip() == "":
                    continue
                try:
                    candidate = normalize_ip(value)
                except ValidationError:
                    continue
                if candidate == target:
                    matches.append(dict(row))
                    break
    return matches


def ip_availability_status(*, inventory_matches: int, ping_reply: bool, neighbor_mac_found: bool,
                           authoritative_reservation_checked: bool = False,
                           authoritative_reservation_conflict: bool = False) -> str:
    """Never infer availability from failed ping alone."""
    if inventory_matches > 0 or ping_reply or neighbor_mac_found or authoritative_reservation_conflict:
        return "CONFLICT"
    if authoritative_reservation_checked:
        return "REVIEW_REQUIRED"  # authoritative DHCP/router check is necessary but not sufficient
    return "UNKNOWN_BLOCKED"


def validate_candidate_vm_ids(candidate_ids: Iterable[Any], existing_ids: Iterable[Any]) -> list[int]:
    def convert(value: Any) -> int:
        try:
            result = int(value)
        except (TypeError, ValueError) as exc:
            raise ValidationError(f"Invalid VM ID: {value!r}") from exc
        if result < 100 or result > 999999999:
            raise ValidationError(f"VM ID {result} is outside the accepted Proxmox range 100..999999999.")
        return result

    candidates = [convert(x) for x in candidate_ids]
    existing = {convert(x) for x in existing_ids}
    duplicates = sorted({x for x in candidates if candidates.count(x) > 1})
    conflicts = sorted(set(candidates) & existing)
    if duplicates:
        raise ValidationError(f"Candidate VM IDs are duplicated: {duplicates}")
    if conflicts:
        raise ValidationError(f"Candidate VM ID(s) already exist: {conflicts}")
    return candidates


def secret_is_configured(value: Any) -> bool:
    if value is None:
        return False
    text = str(value).strip()
    return bool(text) and not any(marker in text.lower() for marker in (
        "changeme", "change_me", "replace-me", "placeholder", "your-token", "example-token", "todo", "<token>"
    ))


def deployment_blockers(*, preflight_passed: bool, cluster_quorate: bool,
                         both_nodes_online: bool, guest_ips: Iterable[Any],
                         node_ips: Iterable[Any], inventory_ips: Iterable[Any],
                         prefix: Any, gateway: Any, bridge: Any, storage: Any,
                         windows_iso: Any, ubuntu_iso: Any, vm_ids: Iterable[Any] | None = None,
                         existing_vm_ids: Iterable[Any] = ()) -> list[str]:
    blockers: list[str] = []
    if not preflight_passed:
        blockers.append("Required preflight checks have not all passed.")
    if not cluster_quorate:
        blockers.append("Cluster is not quorate.")
    if not both_nodes_online:
        blockers.append("Both cluster nodes must be online and healthy.")
    ips = list(guest_ips)
    if len(ips) != 2 or any(normalize_ip(x) is None for x in ips):
        blockers.append("Both guest IP addresses must be explicitly configured.")
    else:
        normalized = [normalize_ip(x) for x in ips]
        if len(set(normalized)) != len(normalized):
            blockers.append("Windows and Ubuntu guest IP addresses must be different.")
        forbidden = {normalize_ip(x) for x in node_ips if x}
        known_inventory = {normalize_ip(x) for x in inventory_ips if x}
        collisions = set(normalized) & (forbidden | known_inventory)
        if collisions:
            blockers.append(f"Guest IP conflicts with node or inventory IP(s): {sorted(collisions)}.")
    try:
        normalize_prefix(prefix)
    except ValidationError:
        blockers.append("A valid, verified IPv4 subnet prefix is required.")
    try:
        if normalize_ip(gateway) is None:
            blockers.append("A verified gateway IP is required before guest network configuration.")
    except ValidationError:
        blockers.append("A valid, verified gateway IP is required before guest network configuration.")
    for field, value in (("bridge", bridge), ("storage target", storage),
                         ("Windows ISO path", windows_iso), ("Ubuntu ISO path", ubuntu_iso)):
        if not secret_is_configured(value):
            blockers.append(f"A valid {field} value is required.")
    if vm_ids is None:
        blockers.append("Guest VM IDs must be selected after checking all existing nodes.")
    else:
        try:
            validate_candidate_vm_ids(vm_ids, existing_vm_ids)
        except ValidationError as exc:
            blockers.append(str(exc))
    return blockers


def cluster_checks_pass(checks: Mapping[str, str]) -> bool:
    required = {"version_compatibility", "stable_ips", "hostname_resolution", "node_connectivity",
                "time_sync", "not_in_existing_cluster", "corosync_network", "no_workload_overwrite"}
    return required.issubset(checks) and all(str(checks[name]).upper() == "PASS" for name in required)
