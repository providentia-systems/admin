# Canonical API contract source

`providentia-v1.json.gz` is a deterministic (`gzip -n`) transport of the
Providentia backend API 1.19.0 OpenAPI contract. The uncompressed contract is
generated locally by `tool/materialize_contract.sh` and is intentionally not
stored twice in Git.

The materializer verifies both the archive and uncompressed SHA-256 digests
before any contract drift or generated-client check runs. This avoids connector
or line-ending corruption while keeping agent and CI setup self-contained.
