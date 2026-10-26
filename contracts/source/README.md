# Canonical API contract source

`providentia-v1.json.gz` is a deterministic (`gzip -n`) transport of the
Providentia backend API 2.4.0 OpenAPI contract. The uncompressed contract is
generated locally by `tool/materialize_contract.sh` and is intentionally not
stored twice in Git.

The materializer verifies both the archive and uncompressed SHA-256 digests
before any contract drift or generated-client check runs. This avoids connector
or line-ending corruption while keeping agent and CI setup self-contained.

The exact supported backend revision and artifact digests are recorded in
`../backend-compatibility.json`. `../contract.lock.json` is copied byte for byte
from that backend revision; generation never adds Admin-specific lock fields.
The paired CI lane checks out the immutable revision and compares both artifacts
and the lock before exercising backend and Admin compatibility checks.
