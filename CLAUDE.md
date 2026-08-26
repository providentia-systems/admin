# Agent environment guide — Providentia Admin

Read `AGENTS.md` first; it is the contributor contract. This file adds the
practical bootstrap for coding-agent sandboxes so a session can build, test,
and debug locally from the first minute.

## Fast start

```bash
bash tools/agent-setup.sh
source .agent-env
bash tools/agent-check.sh   # canonical format/contract/analysis/test/package/launch gate
```

The bootstrap is idempotent and proven inside managed agent sandboxes: it
installs the checksum-pinned Flutter and Node toolchains into `.agent-tools/`
and prepares the Linux-only build. Downloads come from `pub.dev` and
`storage.googleapis.com`, both reachable through sandbox egress proxies.
`tools/agent-check.sh` is the canonical completion gate — run it (and check
its exit code) before declaring any change done.

## Boundaries that gates enforce

- Linux-only: no other platform directories may exist.
- The generated facade allowlists exactly the operator operations; every
  `/api/v1/homes/**` household route is excluded and CI rejects drift.
- `tools/verify-structure.sh` pins workflow action SHAs (a Dependabot bump
  must update the pin in the same change), the app-link identity, and the
  contract version/hash.

## Contract synchronization

Update the backend runtime and contract first, then copy the exact contract
and lock here and regenerate. Handwritten endpoint drift is rejected by CI.
