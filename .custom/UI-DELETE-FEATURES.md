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
- [x] Verify on testing URL — clicked **Remove** on `wiki-qa` in the browser,
      watched it go 3 → 2, restored it

**SDK note — settled, and not the way we expected.** With Docker running,
`fern generate --group ts-sdk` reports success but writes only **2 of 897 files**
into `packages/trueforge-sdk/src` (`events.ts`, `index.ts`). The Windows host /
Linux container volume mount silently drops the rest. The `python-sdk` group
fails outright (`/fern/ir.json` not found) _after_ wiping the TS SDK, so
`pnpm sdk:generate` is a **destructive no-op on this machine — do not run it.**
Run it from WSL2 or a Linux host if a real regen is ever needed.

The `delete()` client method and the two `DeleteSkillResponse` type files are
therefore hand-written, mirroring generated `modelProviders.delete()` exactly.
That is not merely cosmetic: the hand-written method is what the deployed app
executed during the live test, so it is verified end-to-end rather than just
typechecked. Consequence for sequencing — the "both branches regenerate the SDK"
conflict that motivated splitting these branches does not apply here, but a
future regen still has to land separately.

**Test gap — closed.** The store contract suite was first run under SQLite only,
while production and testing both run Postgres. Re-run with Docker up:
`PASS tests/db/postgres/skill-store/contract.test.ts`.

**Pre-existing flake spotted.** `PostgresSessionStore ... orders by updated_at
so later activity ranks ahead of create order` fails intermittently. It seeds
three sessions, waits **5 ms**, then bumps one, so `updated_at` ties and the
`ORDER BY` becomes ambiguous — it passed on 2 of 3 runs. Unrelated to this work;
worth its own fix.

### Phase 2 — Connector delete (`contrib/connector-delete`) — CODE DONE, VERIFYING

- [x] `db/mcpServerStore.ts` — `DeleteMcpServerInput` + `deleteServer()`
- [x] Postgres + SQLite impls; `McpServerWithAuthStore` passthrough; Inline
      delegate; TrueFoundry 424
- [x] Cascade confirmed in schema, not assumed: `oauth_token` and
      `oauth_pending_authorization` are `ON DELETE CASCADE` on `mcp_server(id)`.
      SQLite client sets `PRAGMA foreign_keys = ON` (`db/sqlite/client.ts:118`),
      so the cascade fires on both engines.
- [x] `schemas/mcpServer.ts` — `DeleteMCPServerResponseSchema`
- [x] `routes/mcpServerRoutes.ts` — `DELETE /api/v1/settings/mcp-servers/{name}`
      (no collision with the existing `DELETE /{name}/authorize`)
- [x] `apis/mcpServers.ts` — handler + register
- [x] SDK `delete()` + `DeleteMCPServerResponse` (hand-written; see SDK note)
- [x] `connectorCatalog.ts` — implement `deleteConnector`
- [x] **New UI**: Remove button on the configured row + `CenteredModal` confirm
- [x] Tests: 45 unit, store contract on postgres + sqlite, 3 UI (incl. cancel
      and confirm)
- [x] Verify on testing URL — created a probe connector, confirmed the Remove
      button appears on all 5 rows, opened the dialog, confirmed, and watched it
      return to 4. Composio still `authenticated`; skills untouched.

**Differences from skill delete, worth knowing:**

1. **This one is destructive beyond the row.** Deleting a connector revokes
   every user's authorization for it via the FK cascade. The confirm dialog says
   so explicitly. That is also why it is the first _confirm-gated_ action in
   Settings — skills and model providers delete immediately with no prompt.
2. **MCP names are not `NameSchema`.** `McpServerNameParamsSchema` is
   `z.string().min(1)`, so `DELETE /Not%20A%20Name` returns 200, not 400. A test
   asserting 400 here would be wrong; skills do use `NameSchema` and do 400.
3. `McpServerWithAuthStore` is a decorator over `IMcpServerStore` and needed its
   own `deleteServer` passthrough — the type check caught it.

### Phase 3 — Confirmation dialog (both)

- [ ] No reusable confirm component exists in the repo. Build one from
      `CenteredModal` + `Button.Primary`/`Button.Ghost`, matching the footer
      pattern in `ConnectorSettings.tsx:520-527`.
- [ ] Success toast on delete (currently create/update toast, delete does not)
- [ ] Decide whether to also add a confirm to the model-provider Remove button
      for consistency, or leave it as-is to keep the diff small

---

## Both phases shipped to testing

- `deploy/dokploy` is at `97625fd0` (+ the connector feature).
- Production is still on `ebd0bbdf` and has **not** been touched.
- Testing auto-deploy is still not firing on push; both deploys were triggered
  by hand via Dokploy. Worth fixing before the next sync.

## Correction to an earlier note

The 37 UI type errors reported after the upstream merge (agent-list API shape)
were **not** merge fallout. They were stale SDK `.d.ts` files, and they clear on
`pnpm sdk:types` — which the UI `prebuild` already runs. The UI package
typechecks clean (exit 0, zero errors). Nothing to fix there.

## Phase 3 — Confirm UX made consistent (DONE, `fcf15b58`)

Connector delete prompted; skills and model providers fired on first click. All
three now route through a shared `ConfirmDeleteDialog`
(`atoms/primitives/ConfirmDeleteDialog.tsx`), and skills + model providers gained
the success toast they were missing.

Each caller supplies its own consequence copy rather than the dialog assuming one:

| Resource       | Copy                                                                                                               |
| -------------- | ------------------------------------------------------------------------------------------------------------------ |
| Skill          | "This skill will be removed from this workspace."                                                                  |
| Connector      | "The connector and every saved authorization for it will be removed…"                                              |
| Model provider | "The provider and all of its models will be removed… Agents still using one of its models will lose access to it." |

Also gave the model provider Remove button an `aria-label` naming its provider.

**Verified on testing:** all three dialogs open with the right copy; cancel
closes and deletes nothing; skills (3), providers (1), connectors (4) unchanged;
0 errors in the server log.

Two things surfaced while doing this:

1. **Model Remove buttons are per-model as well as per-provider.** The per-model
   trash does a `PUT` that replaces the model list, not a provider delete. Since
   `models` is `z.array(...).min(1)` (`schemas/modelProvider.ts:73`), removing the
   _last_ model should fail validation. Not tested destructively against the live
   `opencode-go` provider. PR #876 handles it by deleting the provider when its
   last model goes.
2. `closeDeleteModal` in `SkillSettings` must stay a plain function, not
   `useCallback` — it sits after the existing `if (!skillCatalog)` guard, and a
   hook after an early return breaks the rules of hooks. ESLint caught it.

## Upstream status — do not open duplicate PRs

Checked before opening anything:

- **PR #876** `innoavator` — _"allow deleting models, mcp, skills from settings"_,
  **OPEN**, +3819/−53 over 82 files, currently **CONFLICTING**. Implements all
  three deletes, a shared confirm dialog, 409 when an agent still references the
  entry, and last-model-removes-provider. Credits `@Gadgitmatic` for #880 as a
  co-author.
- **PR #880** `Gadgitmatic` — model provider delete. **OPEN** (ours).
- **PR #369** `azaanaliraza` — model provider delete. **OPEN**, overlaps #880.
- **PR #652** `jayesh9747` — _"discover a provider's models from the provider
  itself"_, related to the `contrib/opencode-go-models` work.

Open issues this work addresses:

- **#301** Cannot delete configured model providers (devandop)
- **#494** No way to fully remove/delete a configured MCP connector (kristopolous)
- **#498** No way to edit or disable a configured skill (kristopolous)

**Conclusion:** opening a new PR would duplicate #876. Rather than compete,
contributed to it instead — see below.

## Contribution to #876 (posted 2026-09-30)

Posted a conflict diagnosis on
[#876](https://github.com/truefoundry/trueforge/pull/876#issuecomment-5918000725)
and offered to do the resolution. Findings, all verified locally against a trial
merge of `upstream/main` into `allow-deletion`:

- Branch is 24 commits behind main, 2 ahead.
- 14 files conflict; 7 are generated SDK/OpenAPI output, so **7 real source
  files** matter.
- **6 of the 7 are additive** — their `deleteServer` / `deleteProvider` sit beside
  main's `resolveInvokeHeaders`. Keeping both sides resolves them.
- Only `agentStore.ts` + 3 agent-store impls + `TrueFoundryAgentStore` is a real
  two-way: `listAgentCatalogUsage` vs the pagination in #863.
- Their `delete*` returns `boolean` (`numDeletedRows > 0n`); ours returns
  `void`. Theirs is better — it is what lets the route choose between confirm
  and 409, so ours should defer.
- Flagged a silent trap: `McpServerWithAuthStore.ts` conflicts because main's
  `resolveInvokeHeaders` gained `turnMetadata?`. `sessionResources.ts:135` passes
  it via a **spread**, which defeats TypeScript's excess-property check — so
  taking "ours" there would not fail the build, it would just stop forwarding it.
  Impact today is nil (main's body ignores the param), but the signature would
  diverge from main silently.

#880 left open per decision, as a fallback until #876 lands. Nothing pushed to
anyone else's branch — the offer stands for `innoavator` to accept or decline.

## Open questions

- Should deleting a skill warn if an agent still references it? `ISkillStore`
  has `validateAgentSkills` for admission, but no reverse lookup exists.
- Should connector delete be blocked while a session is mid-turn, or is the
  FK cascade enough?
- Does `require_approval_for_tools` need resetting on delete? (No — it lives on
  the manifest, which goes with the row.)
