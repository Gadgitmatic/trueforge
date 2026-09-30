---
'@truefoundry/trueforge': minor
---

Add delete for configured skills and model providers

Skills could be added and replaced but never removed, so a mistake in a skill
manifest was permanent short of direct database access. `DELETE
/api/v1/settings/skills/{name}` removes a configured skill, scoped to the
tenant and idempotent when the skill is already gone.

The settings UI already rendered a Remove button for each skill, gated on the
catalog port exposing `deleteSkill`; the adapter omitted that method because no
route existed. It is now implemented, which is what makes the existing button
live.

TrueFoundry-managed tenants get 424, matching create/upsert.
