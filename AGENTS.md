# Contributor contract

Read `README.md`, `docs/development/agent-environment.md`, and the authoritative
OpenAPI lock before changing runtime behavior.

- Admin is a separate Linux-only Flutter client. Do not add household-client
  platforms or reuse homeowner storage, database, installation, or credentials.
- The backend owns authorization and domain rules. UI visibility is defense in
  depth; every privileged request must remain backend-authorized.
- A 401 or 403 from a privileged request must synchronously purge navigation,
  cached privileged state and capabilities before asynchronous cleanup.
- The system owner may inspect all application data and delegate access through
  administrator groups. Use dedicated operator endpoints authorized by the
  backend. Viewing household records is independent of public catalog sharing.
  Preserve tenant isolation in the homeowner client and never display stored
  credentials, session proofs, or private AI provider tokens.
- Preserve revision-bound mutations and reload after conflicts. Do not invent a
  second catalog publication or role store.
- Update backend runtime and contract first, then copy the exact contract and
  lock here. Handwritten endpoint drift is rejected by CI.
- Run `bash tools/agent-check.sh` before declaring work complete. It is the
  canonical format, contract, analysis, test, coverage, package verification
  and Xvfb Linux launch gate.
