# Step 3: catalog contribution publication

This extends existing Admin PR #11 on `fix/step-2-response-configuration`, paired
with backend #23 and household Client #19. Earlier Step 2 work remains intact.
Implementation is committed; the paired release remains draft. Passing isolated
widgets is not a claim of complete three-application production acceptance.

## Implemented journey

The normal Contributions pending queue now retains the selected identity or
image contribution after approval, changes to the approved/publication queue,
and retrieves the current revision. Approved, rejected and withdrawn states
remain reachable through the status filter and bounded page navigation.
Approval of a contribution is explicitly distinguished from publication.

A curator can select a published category and link a product proposal, open the
linked proposal in the workbench, approve it for actual publication, and return
to the originating contribution. Reviewer-only users cannot approve a proposal
that publishes globally; the paired backend enforces the same boundary.

Image publication requires a verified no-store sanitized preview for the
selected contribution revision, a selected published product and a second
confirmation carrying both contribution and icon revisions. Queue reload,
selection change and stale responses invalidate previews. Unauthorized or
stale responses cannot replace the current view. Private extra fields fail
closed before presentation; neither household IDs nor private quantities are
made global catalog facts.

Approval-dialog lifetime and toolbar overflow regressions were reproduced by
the new ordinary-page widget tests and repaired. Explicit mounted checks are
retained across asynchronous category and product dialogs.

## Contract and commands

Canonical API version remains 2.1.0. Canonical document digest (SHA-256):

```
f6591ae866efbcc9e661528c7f595da0d7093d959d64c66c09b0c5be1dcb7c58
```

The backend-owned canonical source, archived source, materializers, generated
facade, lock and all enforced checks were updated together. No dependency
upgrade or database migration was introduced for Step 3.

Run the existing pinned SDK setup, then:

```sh
bash tool/materialize_contract.sh
node tool/verify_contract.mjs
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub --fatal-infos --fatal-warnings
flutter test --no-pub --coverage
```

Executed source-validation run 34901033775 passed all 162 tests, including
`test/features/catalog_publication_workflow_test.dart`, with handwritten
coverage 3988/5402 (73.82%). That run identified two analyzer lifetime warnings;
the subsequent source commit adds mounted guards rather than suppressing them.
Use the current normal Admin quality run, including Linux build/package and
clean-host launch, for the final branch status. Historical Step 2 native build
results do not certify a new Step 3 head.

## Remaining acceptance boundary

The new tests exercise actual Admin page navigation and strict production
parsers, but their API fixture is not the complete live Admin-to-backend-to-second
household-device publication journey. That full identity and sanitized-image
journey, concurrent withdrawal/consent changes and second-device visibility
remain required release acceptance evidence. Existing backend publication,
privacy, withdrawal and revision tests are complementary, not substitutes.

## Rollout and rollback

No merge, deployment or production repair is performed by this change. Keep the
three PRs draft until their outstanding paired acceptance and earlier Step 1
outbox/provenance/cache-lifecycle blockers are resolved. Obtain deployment
authorization separately, then deploy the paired backend before new clients.

The pre-Step-3 Admin reference is d73f3658d2ecce3852ae56ed88167718368d6815.
Rollback application builds as a compatible set, preserve the database and
published revisions, and never remove backend curator/consent/privacy guards
to make an old UI work. Publication is a persisted user operation; reverting
this UI does not undo or duplicate it. No destructive migration is needed.
