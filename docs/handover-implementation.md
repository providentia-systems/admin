# Handover implementation record — 22 September 2026

## Delivered scope

This branch is a tested subset of the supplied complete handover, not a claim
that all cross-repository requirements or historical recovery are finished.
The starting Admin commit was f8d189a99f9e824840994b9595d4c06779d40a09.
The older catalog-button branch had no unique commits ahead of main.

### Catalog actions and pagination

Workbench records explicitly distinguish proposals, consent-bound contributions,
missing-icon products, identity conflicts and merge history. Products needing
icons retain real product target IDs and can never invoke proposal approval.
The action fetches the current product/icon revision and reuses the existing
icon editor. Submitted-image review remains a separate consent-bound,
bounded, digest-verified preview and explicit publication workflow.

Workbench, category, contribution, conflict and merge lists use the backend's
supported offset contract. Tests cover 101 same-name targets, later/empty pages,
malformed records and action-specific controls. Queue/request generation and
permission epoch guards remain in place.

### Direct catalog maintenance

Manage catalog entities is a primary filled action. Products and Categories
have direct entries, searchable paged lists, Add actions and row-to-editor
navigation. Existing advanced identity types and product-scoped relationships
remain available. Queries run on the backend before offset pagination, not on
just the visible page. Switching entity types preserves each query and page.
Fields use spaced, bounded scrollable forms. Changed editors require an explicit
discard choice. Revision and uncertain-mutation reload guards remain active.

Routine changes use visible contextual audit reasons. Other requires actual
nonblank text, bounded to 500 characters. This does not bypass authorization,
revision checking or the backend audit trail.

## Paired contract

The optional maintenance-list q parameter is mirrored from the backend-owned
contract. All paired repositories use JSON SHA-256
13ccdc2d37e73955394a7b7c52da6d9ff7aeefdfd763ac809876737867d15c44.
Deploy the companion backend change before relying on cross-page search.
Generated Admin operations and existing privacy allowlists are retained.

## Verification

Branch validation run 35718161132 passed structure/contract verification,
strict analysis, the complete Admin test suite and the existing coverage gate
against source commit 037157bfdb3c50785d550829c574650e428d5f27.
Temporary editing/validation scripts are removed from the final change tree.
The original PR quality, packaging and security workflows must pass on the
final head; the earlier result is not evidence for an untested later commit.

## Explicitly outstanding handover work

The complete effective household product projection and its tenant-safe joins,
operator household override editor with catalog deep-link return context,
unified inherit/none/local/global category workflows, local-category publication,
private name/unit/pack customization, historical queue recovery, complete
sanitized diagnostic exports, and the remaining contextual-reason surfaces
are not implemented by this Admin change. The companion synchronization work
must not be mistaken for completed owner-data recovery.

No production database, installed executable, live home or deployment was
changed or verified. No merge was performed. Back up the real native database
before any owner recovery; do not clear or silently rebind its pending work.
