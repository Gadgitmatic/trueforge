# Settings delete features — progress & goals

**Status:** in progress
**Testing URL:** https://t.agents.ts.gadgitmatic.com (Dokploy `TrueForge (testing)`, auto-deploys on push to `deploy/dokploy`)
**Production URL:** https://agents.ts.gadgitmatic.com (manual deploy only — do not touch without asking)

---

## Goals

Add the missing **delete** affordances in Settings, reusing the model-provider
delete pattern that already ships on `deploy/dokploy`.

| #   | Feature                             | Difficulty                            | Why it matters                                                               |
| --- | ----------------------------------- | ------------------------------------- | ---------------------------------------------------------------------------- |
| 1   | **Delete a skill**                  | Easy — UI is already written and dead | Skills can be added but never removed. Rows accumulate in the `skill` table. |
| 2   | **Delete a connector (MCP server)** | Medium — needs new UI                 | Connectors can be added/edited/disconnected but never removed.               |

Non-goals for this work: no changes to production, no changes to the approval
flow, no model-provider changes (that pattern already exists).

---

## Key finding: these are not UI-only changes

Both features need a full stack, because **the delete button for skills already
exists in the UI and is dead code** — `SkillSettings.tsx:197-209` renders a
`Remove` button gated on `skillCatalog.deleteSkill`, and the adapter omits that
method with the comment _"Delete omitted (no BE route)."_ There is no backend
route to call. So the UI is the last 10% of each feature, not the whole thing.

Layer-by-layer, mirroring `deleteProvider`:

| Layer                        | Model providers (done) | Skills                    | MCP servers               |
| ---------------------------- | ---------------------- | ------------------------- | ------------------------- |
| `DeleteXInput` type          | ✅                     | ❌                        | ❌                        |
| `deleteX` on store interface | ✅                     | ❌                        | ❌                        |
| Postgres impl                | ✅                     | ❌                        | ❌                        |
| SQLite impl                  | ✅                     | ❌                        | ❌                        |
| TrueFoundry 424 impl         | ✅                     | ❌                        | ❌                        |
| Inline delegating impl       | ✅                     | ❌                        | ❌                        |
| OpenAPI DELETE route         | ✅                     | ❌                        | ❌                        |
| Route handler                | ✅                     | ❌                        | ❌                        |
| `DeleteXResponseSchema`      | ✅                     | ❌                        | ❌                        |
| Fern SDK `delete()`          | ✅                     | ❌                        | ❌                        |
| Runtime port method          | ✅                     | declared, not implemented | declared, not implemented |
| UI button                    | ✅                     | **present but dead**      | ❌ none                   |
| Confirmation dialog          | ❌ none in repo        | ❌                        | ❌                        |

---

## Branching recommendation: **separate branches, merged sequentially**

The instinct to put both on one branch is reasonable — they are both
"Settings UI" and they share the delete pattern. But I'd split them, for three
concrete reasons:

1. **Both regenerate the Fern SDK.** `pnpm openapi:write` + `pnpm sdk:generate`
   rewrite the same generated `index.ts` barrels. Two branches each regenerating
   the SDK will conflict on merge every time.
2. **They are separate upstream PRs.** The repo convention (`.custom/README.md`)
   is `contrib/<feature>` → PR to `truefoundry/trueforge`. "Delete skills" and
   "delete MCP servers" are two independently reviewable upstream changes and
   will land at different times.
3. **Different risk profiles.** Skills is a leaf table, essentially free.
   Connectors cascades `oauth_token` and `oauth_pending_authorization` for every
   user — that deserves its own review and its own deploy to testing.

**Sequencing matters more than the branch count.** Do skills first, land it in
`deploy/dokploy`, verify on testing, _then_ start connectors. That keeps the SDK
regeneration conflict-free and means a broken connectors change can't take
skills down with it.

Proposed branches:

```
contrib/skill-delete        -> PR upstream, then merge into deploy/dokploy
contrib/connector-delete    -> PR upstream, then merge into deploy/dokploy
```

---

## Task list

### Phase 0 — Sync (DONE)

- [x] `scripts/fork-sync.sh sync` — merged 23 upstream commits
- [x] Resolve 6 merge conflicts
- [x] Re-apply `x-opencode-session` header at upstream's new `getModelDetails()` site
- [x] Add missing `deleteProvider` delegate to `InlineModelProviderStore`
- [x] `tsc --noEmit` clean
- [x] Pushed to `deploy/dokploy` (auto-deploys to testing)

### Phase 1 — Skill delete (`contrib/skill-delete`) — CODE DONE, VERIFYING

- [x] `db/skillStore.ts` — add `DeleteSkillInput` + `deleteSkill()` to `ISkillStore`
- [x] Postgres + SQLite `skill-store` impls
- [x] `TrueFoundrySkillStore` → 424; `InlineSkillStore` → delegate
- [x] `schemas/skill.ts` — `DeleteSkillResponseSchema`
- [x] `routes/skillRoutes.ts` — `deleteSkillRoute` (`DELETE /{name}`)
- [x] `apis/skills.ts` — handler + register
- [x] Contract test (store suite) + API test — 16 unit + 10 store tests pass
- [x] OpenAPI regenerated (`pnpm openapi:write` — 53 paths, route present)
- [x] `skillCatalog.ts` — implement `deleteSkill` (**lights up the existing button**)
- [ ] Verify on testing URL

**SDK note:** `pnpm sdk:generate` cannot run here — it needs `jq` (absent on
Windows) and a Docker daemon for `fern --local` (Docker Desktop not running).
The client `delete()` method and the two `DeleteSkillResponse` type files were
hand-written to match the generated shape exactly, then validated with
`pnpm sdk:types`. A real regen should produce an equivalent file; worth
re-running where Docker is available before opening the upstream PR.

### Phase 2 — Connector delete (`contrib/connector-delete`)

- [ ] `db/mcpServerStore.ts` — `DeleteMcpServerInput` + `deleteServer()`
- [ ] Postgres + SQLite impls; Inline delegate; TrueFoundry 424
- [ ] Cascade: `oauth_token` / `oauth_pending_authorization` are already
      `ON DELETE CASCADE` on `mcp_server(id)`. Store keys on `name`, FK is on
      `id` (ULID) — must resolve name → id first. SQLite needs
      `PRAGMA foreign_keys = ON` for the cascade to fire.
- [ ] `schemas/mcpServer.ts` — `DeleteMcpServerResponseSchema`
- [ ] `routes/mcpServerRoutes.ts` — `DELETE /api/v1/settings/mcp-servers/{name}`
      (no collision with the existing `DELETE /{name}/authorize`)
- [ ] `apis/mcpServers.ts` — handler + register
- [ ] Regenerate SDK
- [ ] `connectorCatalog.ts` — implement `deleteConnector`
- [ ] **New UI**: Remove button in `ConnectorSettings.tsx` + `ConnectorDetails.tsx`

### Phase 3 — Confirmation dialog (both)

- [ ] No reusable confirm component exists in the repo. Build one from
      `CenteredModal` + `Button.Primary`/`Button.Ghost`, matching the footer
      pattern in `ConnectorSettings.tsx:520-527`.
- [ ] Success toast on delete (currently create/update toast, delete does not)
- [ ] Decide whether to also add a confirm to the model-provider Remove button
      for consistency, or leave it as-is to keep the diff small

---

## Open questions

- Should deleting a skill warn if an agent still references it? `ISkillStore`
  has `validateAgentSkills` for admission, but no reverse lookup exists.
- Should connector delete be blocked while a session is mid-turn, or is the
  FK cascade enough?
- Does `require_approval_for_tools` need resetting on delete? (No — it lives on
  the manifest, which goes with the row.)
