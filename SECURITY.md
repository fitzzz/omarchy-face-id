# Security policy

## Supported versions

No version is currently supported for real authentication. Releases remain pre-alpha until the documented release blockers are resolved and the recovery test matrix passes.

## Reporting a vulnerability

Do not publish an authentication bypass, PAM misconfiguration, biometric-data exposure, or lockout reproduction in a public issue. Contact the repository owner privately through GitHub's security-advisory feature once the public repository is available.

Include:

- Omarchy and plugin versions
- camera type
- whether Gaze and PAM were involved
- reproduction steps that avoid biometric images or templates
- whether password unlock remained available

Never attach face images, embeddings, PAM secrets, or captured passwords.

## Recovery rule

Authentication testing must use a disposable account or virtual machine with TTY, SSH, snapshot, or console recovery available. Never make the first test on the user's only working unlock path.
