# Handover implementation record — 22 September 2026

## Scope and baseline

This branch implements the supplied owner handover in the existing architecture.
The source baseline was admin `f8d189a99f9e824840994b9595d4c06779d40a09`,
backend `544b789a44f64c50ed5274e46c8050fdee881180`, and client
`e491419f7c1d3694303f4277204385bd4bca21e8`. The historical Admin button branch
had no changes ahead of main. Production executables and owner databases were
not supplied; source and CI results do not establish deployment or recovery.

## Catalog workbench

The workbench now distinguishes proposals, consent-bound contributions,
missing-icon products, identity conflicts, and merge history. Product targets
in the Icons queue are already published products, not pending proposals. They
retain their real target IDs and cannot invoke proposal decisions. The queue
is labelled **Products needing icons** and opens the existing icon editor only
after fetching the current product and icon revision. Actual submitted-image
review remains separate and retains its no-store, bounded, digest-verified
preview and explicit approved-revision publication path.

Workbench, contribution, category, conflict and merge lists use the backend's
existing offset contract. No client-only cursor or invented unknown identity
is sent. Selection is reset when the queue changes, and old asynchronous
responses remain guarded by request generation and authorization epoch.

The **Manage catalog entities** entry uses the existing primary filled theme.
This does not change who can review or curate catalog records.

## Verification and remaining work

`test/features/handover_workbench_test.dart` covers 101 same-name icon targets,
empty and later pages, typed action boundaries, malformed targets, icon-only
actions and category page navigation. The existing image-publication and
privacy tests remain applicable. Test results belong to the exact reported CI
head; this document does not claim unrun checks passed.

The other handover workstreams — historical synchronization recovery,
provenance/order/diagnostics, relationship repair, effective household
projections, unified categories and publication, household name/measurement
customization, contextual reasons and complete integrated delivery — are not
claimed complete by this initial change.
