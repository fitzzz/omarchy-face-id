#!/usr/bin/python3

from __future__ import annotations

import sys
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "lib"))

from face_unlock_preflight import validate_config, validate_pam_service


SAFE_CONFIG = {
    "security": {"level": "medium"},
    "liveness": {"enabled": True, "threshold": 0.8},
    "auth": {"require_confirmation_lock_screen": False},
}

SAFE_PAM = """\
#%PAM-1.0
auth       [success=done default=ignore]   pam_gaze.so
auth       required                        pam_deny.so
account    required                        pam_permit.so
"""


class ConfigValidationTest(unittest.TestCase):
    def test_accepts_minimum_safe_profile(self) -> None:
        self.assertEqual(validate_config(SAFE_CONFIG), [])

    def test_rejects_disabled_liveness(self) -> None:
        config = {**SAFE_CONFIG, "liveness": {"enabled": False, "threshold": 0.8}}
        self.assertIn("liveness must be enabled", validate_config(config))

    def test_rejects_weak_threshold(self) -> None:
        config = {**SAFE_CONFIG, "liveness": {"enabled": True, "threshold": 0.79}}
        self.assertTrue(any("threshold" in blocker for blocker in validate_config(config)))

    def test_rejects_confirmation_without_protocol(self) -> None:
        config = {**SAFE_CONFIG, "auth": {"require_confirmation_lock_screen": True}}
        self.assertTrue(any("confirmation" in blocker for blocker in validate_config(config)))

    def test_rejects_unknown_security_level(self) -> None:
        config = {**SAFE_CONFIG, "security": {"level": "low"}}
        self.assertTrue(any("security level" in blocker for blocker in validate_config(config)))


class PamValidationTest(unittest.TestCase):
    def test_accepts_isolated_face_service(self) -> None:
        self.assertEqual(validate_pam_service(SAFE_PAM), [])

    def test_rejects_password_stack_include(self) -> None:
        pam = SAFE_PAM + "auth include system-auth\n"
        self.assertTrue(validate_pam_service(pam))

    def test_rejects_face_success_without_deny_fallback(self) -> None:
        pam = SAFE_PAM.replace("auth       required                        pam_deny.so\n", "")
        self.assertTrue(validate_pam_service(pam))

    def test_rejects_extra_module_arguments(self) -> None:
        pam = SAFE_PAM.replace("pam_gaze.so", "pam_gaze.so debug")
        self.assertTrue(validate_pam_service(pam))


if __name__ == "__main__":
    unittest.main()
