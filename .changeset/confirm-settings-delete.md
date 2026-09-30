---
'@truefoundry/trueforge-ui': patch
---

Confirm every destructive Settings delete, not just connectors

Connector delete shipped with a confirmation dialog while skill and model
provider delete fired on the first click, so the same gesture was
recoverable for one resource type and not the next. All three now route
through a shared `ConfirmDeleteDialog`, and skill and model provider delete
gain a success toast they were missing.

Each caller states its own consequences rather than the dialog assuming one:
deleting a connector revokes every user's authorization for it, and deleting a
model provider drops every model on it, so those copy differs from the plain
"This skill will be removed from this workspace."

Also gives the model provider Remove button an `aria-label` naming its
provider, matching the connector and skill buttons. With several providers
listed, "Remove" alone did not identify its target to a screen reader.
