"""Pure validation helpers for the root-installed face-unlock preflight.

This module never authenticates. It decides only whether starting the dedicated
face PAM context is eligible. Every unknown value returns one or more blockers.
"""

from __future__ import annotations

import re
from collections.abc import Mapping
from typing import Any

MIN_LIVENESS_THRESHOLD = 0.8
ALLOWED_SECURITY_LEVELS = frozenset({"medium", "high", "maximum", "custom"})


def validate_config(config: Mapping[str, Any]) -> list[str]:
    blockers: list[str] = []

    liveness = config.get("liveness")
    if not isinstance(liveness, Mapping):
        return ["missing liveness configuration"]

    if liveness.get("enabled") is not True:
        blockers.append("liveness must be enabled")

    threshold = liveness.get("threshold")
    if isinstance(threshold, bool) or not isinstance(threshold, (int, float)):
        blockers.append("liveness threshold must be numeric")
    elif not MIN_LIVENESS_THRESHOLD <= float(threshold) <= 1.0:
        blockers.append(f"liveness threshold must be between {MIN_LIVENESS_THRESHOLD} and 1.0")

    security = config.get("security")
    level = security.get("level") if isinstance(security, Mapping) else None
    if level not in ALLOWED_SECURITY_LEVELS:
        blockers.append("security level must be medium, high, maximum, or a validated custom profile")

    auth = config.get("auth")
    if not isinstance(auth, Mapping):
        blockers.append("missing authentication configuration")
    elif auth.get("require_confirmation_lock_screen", False) is not False:
        blockers.append("lock-screen confirmation is unsupported by provider API v1")

    return blockers


_PAM_RULES = (
    re.compile(r"^auth\s+\[success=done\s+default=ignore\]\s+pam_gaze\.so$"),
    re.compile(r"^auth\s+required\s+pam_deny\.so$"),
    re.compile(r"^account\s+required\s+pam_permit\.so$"),
)


def validate_pam_service(text: str) -> list[str]:
    lines = [
        re.sub(r"\s+", " ", line.strip())
        for line in text.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]

    if len(lines) != len(_PAM_RULES):
        return ["face PAM service must contain exactly three non-comment rules"]

    blockers: list[str] = []
    for index, (line, expected) in enumerate(zip(lines, _PAM_RULES, strict=True), start=1):
        if not expected.fullmatch(line):
            blockers.append(f"unexpected PAM rule at position {index}")
    return blockers
