# Household editing and Stock compatibility

The supported backend revision, API version and exact contract digests are pinned
in [`contracts/backend-compatibility.json`](../contracts/backend-compatibility.json).
Admin copies the backend's canonical lock and compressed artifact byte for byte
and regenerates its existing 92-operation operator facade. It adds no homeowner
APIs. See [paired release acceptance](admin-release-acceptance.md) for the real
HTTP compatibility lane, package provenance and installed acceptance procedure.

## Effective household product values

Homes → selected home → Products displays effective Product, Brand, Pack and
Category before raw identity and override fields. Household names and packs take
precedence over linked catalog values; an unset override remains unset and does
not receive a copied catalog value. Unresolved and archived references keep their
original identifiers for authorized diagnosis.

The product editor exposes household name/pack overrides for linked and private
products. Linked products explain that blank overrides fall back to their catalog
values; private products require a meaningful name. These commands retain product
identity and history and do not rewrite or publish shared catalog records.

Category selection distinguishes a local household override, an explicit global
override and the inherited catalog category. The editor preserves both raw IDs
and the resolved label. Saving an unchanged category omits both override fields,
including when the current reference is archived or unavailable. Switching scope
sends both fields atomically; clearing sends both as null and explains the catalog
fallback. The UI does not promise an uncategorized result where the catalog still
provides a category. Backend validation can reject edits that retain an archived
local reference; the operator can choose a valid category explicitly.

Stock units (units, g, kg, ml, l) are labels, with no implied quantity conversion.
The backend may reject a unit change when stock history or other evidence exists.
The editor displays that failure and does not project success. Audit reasons,
expected revisions, authorization epochs and conflict reloads remain required.

## Readable Stock balances

Stock consumes the backend's resolved `OperatorStockRecord` metadata directly.
It leads with Product, Pack, Stock unit, Quantity, evidence status and Balance
revision, while retaining household/product IDs, movement IDs and timestamps for
diagnosis. It never joins a possibly incomplete Products page. Missing product
references, unspecified packs and absent units have explicit labels. Archived
household/catalog states remain visible.

Balances retain exact decimal strings, including zero, negative and fractional
values. Uncertain balances and pending quantities remain identified. Metadata
failure does not remove a balance row. Stable 100-row paging and horizontal
scrolling remain available at small window sizes. A balance-row count is not a
household-product count. This table is read-only and does not repair quantities.

## Source data and deployment

For a reported incorrect category or pack, inspect household overrides,
product/pack references and any available authorized import/AI provenance before
changing source data. Similar names with different packs do not establish a
duplicate. Public catalog sharing remains independent of operator household
inspection, which is backend-authorized and audited.

Deploy the supported backend and apply its normal migrations before installing
this paired Admin release. Preserve backups and existing records. Source,
authenticated synthetic HTTP and Linux package gates are separate from actual
installed-environment acceptance; none deploys a server or recovers household
data. Record those results using the release acceptance procedure.
