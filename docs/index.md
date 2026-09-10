# Providentia Admin documentation

- [Ubuntu setup](setup-ubuntu.md) — beginner-safe source build, backend origin,
  ports, firewall boundary, first sign-in, AI handoff and troubleshooting.
- [Agent and developer environment](development/agent-environment.md) — pinned
  toolchain, complete validation lane and release requirements.
- [Product and access decisions](unification-decision-record.md) — adopted
  identity, authorization, privacy, AI and release rules shared by all three
  repositories.

The backend repository owns server deployment and secret configuration. Start
with its `docs/deployment/server-quick-start.md`; Admin receives only the public
HTTPS API origin.
