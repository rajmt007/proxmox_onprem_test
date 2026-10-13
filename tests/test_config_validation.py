import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from inventory_check import load_rows
from lab_validation import (
    ValidationError, cluster_checks_pass, deployment_blockers, inventory_ip_matches,
    ip_availability_status, normalize_ip, normalize_prefix, secret_is_configured,
    validate_candidate_vm_ids,
)


class ValidationTests(unittest.TestCase):
    def test_inventory_ip_conflict_detection(self):
        rows = [{"MachineName": "old-host", "IP_Address": "192.168.1.111", "Status": "ACTIVE"}]
        self.assertEqual(len(inventory_ip_matches(rows, "192.168.1.111")), 1)
        self.assertEqual(inventory_ip_matches(rows, "192.168.1.112"), [])

    def test_proposed_inventory_rows_are_not_active_conflicts(self):
        root = Path(__file__).resolve().parents[1]
        rows = load_rows(root / "inventory" / "environment-inventory.xlsx", "Envir")
        self.assertEqual(len(rows), 2)
        self.assertTrue(all(str(row.get("Status", "")).upper() == "PROPOSED" for row in rows))
        self.assertEqual(inventory_ip_matches(rows, "192.168.1.111"), [])
        self.assertEqual(inventory_ip_matches(rows, "192.168.1.112"), [])

    def test_missing_inventory_sheet_fails_closed(self):
        root = Path(__file__).resolve().parents[1]
        self.assertFalse(root.joinpath("inventory", "missing.xlsx").exists())
        with self.assertRaises(KeyError):
            load_rows(root / "inventory" / "environment-inventory.xlsx", "MissingSheet")
        # The availability checker must not infer free IPs from a failed ping.
        self.assertEqual(ip_availability_status(inventory_matches=0, ping_reply=False,
                         neighbor_mac_found=False), "UNKNOWN_BLOCKED")

    def test_invalid_ip_and_prefix_are_rejected(self):
        with self.assertRaises(ValidationError): normalize_ip("192.168.1.999")
        with self.assertRaises(ValidationError): normalize_prefix(None)
        with self.assertRaises(ValidationError): normalize_prefix(33)
        self.assertEqual(normalize_prefix("/24"), 24)

    def test_unconfigured_secrets_are_not_accepted(self):
        for value in (None, "", "CHANGE_ME", "your-token-here", "placeholder"):
            self.assertFalse(secret_is_configured(value))
        self.assertTrue(secret_is_configured("pve-api!lab=opaque-value"))

    def test_existing_or_duplicate_vm_ids_are_rejected(self):
        with self.assertRaisesRegex(ValidationError, "already exist"):
            validate_candidate_vm_ids([9001, 9002], [9002, 9003])
        with self.assertRaisesRegex(ValidationError, "duplicated"):
            validate_candidate_vm_ids([9001, 9001], [])
        self.assertEqual(validate_candidate_vm_ids([9001, 9002], []), [9001, 9002])

    def test_ping_failure_never_means_ip_is_free(self):
        self.assertEqual(ip_availability_status(inventory_matches=0, ping_reply=False,
                         neighbor_mac_found=False), "UNKNOWN_BLOCKED")
        self.assertEqual(ip_availability_status(inventory_matches=0, ping_reply=True,
                         neighbor_mac_found=False), "CONFLICT")

    def test_failed_quorum_blocks_cluster_ready_checks(self):
        checks = {k: "PASS" for k in ("version_compatibility", "stable_ips", "hostname_resolution",
            "node_connectivity", "time_sync", "not_in_existing_cluster", "corosync_network", "no_workload_overwrite")}
        self.assertTrue(cluster_checks_pass(checks))
        checks["node_connectivity"] = "FAIL"
        self.assertFalse(cluster_checks_pass(checks))

    def test_deployment_blocked_when_checks_or_required_values_fail(self):
        blockers = deployment_blockers(
            preflight_passed=False, cluster_quorate=False, both_nodes_online=False,
            guest_ips=[None, None], node_ips=["192.168.1.111", "192.168.1.112"],
            inventory_ips=[], prefix=None, gateway=None, bridge=None, storage=None,
            windows_iso=None, ubuntu_iso=None, vm_ids=None,
        )
        self.assertGreaterEqual(len(blockers), 8)
        self.assertTrue(any("quorate" in x.lower() for x in blockers))
        self.assertTrue(any("guest ip" in x.lower() for x in blockers))

    def test_invalid_gateway_is_reported_as_a_blocker(self):
        blockers = deployment_blockers(
            preflight_passed=True, cluster_quorate=True, both_nodes_online=True,
            guest_ips=["192.168.1.150", "192.168.1.151"], node_ips=["192.168.1.111", "192.168.1.112"],
            inventory_ips=[], prefix=24, gateway="not-an-ip", bridge="vmbr0", storage="local-lvm",
            windows_iso="win.iso", ubuntu_iso="ubuntu.iso", vm_ids=[9100, 9101], existing_vm_ids=[],
        )
        self.assertTrue(any("gateway" in item.lower() for item in blockers))

    def test_guest_ip_conflict_and_valid_input(self):
        blockers = deployment_blockers(
            preflight_passed=True, cluster_quorate=True, both_nodes_online=True,
            guest_ips=["192.168.1.111", "192.168.1.150"], node_ips=["192.168.1.111", "192.168.1.112"],
            inventory_ips=[], prefix=24, gateway="192.168.1.1", bridge="vmbr0", storage="local-lvm",
            windows_iso="win.iso", ubuntu_iso="ubuntu.iso", vm_ids=[9100, 9101], existing_vm_ids=[],
        )
        self.assertTrue(any("conflict" in x.lower() for x in blockers))


if __name__ == "__main__":
    unittest.main(verbosity=2)
