"""Small standard-library tests for deployment input validation."""
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "validate_env.py"

class ValidateEnvTests(unittest.TestCase):
    def run_validator(self, stage, extra):
        env = os.environ.copy()
        for key in [
            "PROXMOX_USER", "PROXMOX_TOKEN_ID", "PROXMOX_TOKEN_SECRET",
            "PROXMOX_MASTER_PASSWORD", "ENVIR_WORKBOOK", "PVE_VM_STORAGE",
            "PVE_ISO_STORAGE", "PVE_BRIDGE", "WINDOWS_ISO_NAME",
            "WINDOWS_VIRTIO_ISO_NAME", "UBUNTU_ISO_NAME", "WINDOWS_GUEST_IP",
            "UBUNTU_GUEST_IP", "IP_RESERVATIONS_CONFIRMED", "WINRM_USER",
            "WINRM_PASSWORD", "UBUNTU_SSH_USER", "UBUNTU_SSH_KEY",
        ]:
            env.pop(key, None)
        env.update(extra)
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--stage", stage],
            env=env, text=True, capture_output=True, check=False,
        )

    def test_preflight_needs_no_secret(self):
        result = self.run_validator("preflight", {})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_deploy_blocks_missing_inputs(self):
        result = self.run_validator("deploy", {})
        self.assertEqual(result.returncode, 2)
        self.assertIn("BLOCKED", result.stdout)

    def test_deploy_blocks_node_ip_reuse(self):
        with tempfile.NamedTemporaryFile(suffix=".xlsx") as workbook:
            env = {
                "PROXMOX_USER": "root@pam",
                "PROXMOX_TOKEN_ID": "ansible",
                "PROXMOX_TOKEN_SECRET": "dummy-not-a-secret",
                "ENVIR_WORKBOOK": workbook.name,
                "PVE_VM_STORAGE": "local-lvm",
                "PVE_ISO_STORAGE": "local",
                "PVE_BRIDGE": "vmbr0",
                "WINDOWS_ISO_NAME": "windows.iso",
                "WINDOWS_VIRTIO_ISO_NAME": "virtio.iso",
                "UBUNTU_ISO_NAME": "ubuntu.iso",
                "WINDOWS_GUEST_IP": "192.168.1.111",
                "UBUNTU_GUEST_IP": "192.168.1.50",
                "IP_RESERVATIONS_CONFIRMED": "true",
            }
            result = self.run_validator("deploy", env)
        self.assertEqual(result.returncode, 2)
        self.assertIn("overlaps a Proxmox node IP", result.stdout)

if __name__ == "__main__":
    unittest.main()
