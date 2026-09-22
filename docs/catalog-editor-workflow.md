# Direct catalog maintenance

The existing Manage catalog entities screen provides direct Products and
Categories choices, server-side search, paged results and row-to-editor access.
Add product/category uses the same existing revision-checked maintenance API.
Switching entity types retains each type's query and page; saving returns to
that list rather than a different search workflow. Packs, variants, aliases,
barcodes, units and rules remain available without duplicating editor logic.

Editor fields have 16-pixel spacing, bounded scrollable content and the existing
wrapping dialog actions. Closing a changed editor requires an explicit discard
choice. Unknown mutation outcomes still require reload before retrying.

Catalog reasons use contextual choices; Other requires a nonblank explanation,
limited to the existing 500-character contract. These controls do not weaken
revision, authorization or audit requirements. Unchanged global identities and
household products remain separate resources.
