# Readable stock and API 2.4 compatibility

This paired change consumes the backend's read-only stock enrichment from
providentia-systems/backend#36 and adopts its canonical API 2.4 contract for
providentia-systems/backend#38.

- [ ] Lead stock rows with resolved product, pack, unit and exact signed quantity.
- [ ] Preserve balance identities, chronology, revisions and timestamps for diagnosis.
- [ ] Cover linked, private, archived and unresolved rows without changing Products rendering or paging.
- [ ] Copy the exact backend contract/lock and regenerate the existing Admin facade.
- [ ] Verify local contract and formatting checks, then review required CI.

Installed operator sessions and native-window acceptance remain separate from CI.
