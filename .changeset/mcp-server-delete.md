---
'@truefoundry/trueforge': minor
---

Add delete for configured MCP servers

Connectors could be added, edited, and disconnected, but never removed, so a
mistyped URL or an abandoned integration stayed in the settings list forever.
`DELETE /api/v1/settings/mcp-servers/{name}` removes one, scoped to the tenant
and idempotent when it is already gone.

Unlike skill delete, this one is destructive beyond the row: `oauth_token` and
`oauth_pending_authorization` reference `mcp_server(id)` with
`ON DELETE CASCADE`, so removing a connector also revokes every user's
authorization for it. The settings UI states that in the confirmation dialog,
which every removal goes through — the first confirm-gated destructive action in
Settings, and the pattern later deletes should follow.

Mirrors deleteProvider across the store interface, the postgres and sqlite
implementations, the auth-decorating `McpServerWithAuthStore`, a 424 for
TrueFoundry-managed tenants, and a delegating `InlineMcpServerStore`.
