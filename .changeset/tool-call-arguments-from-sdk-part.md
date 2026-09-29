---
"@truefoundry/trueforge-core": patch
---

Fix tool calls reaching a tool with empty or malformed arguments. The LLM stream adapter discarded the SDK's `tool-call` part and rebuilt every call's arguments from raw `tool-input-delta` fragments, so a dropped or truncated delta stream produced an empty argument bag. On the deferred `call_tool` wrapper that surfaced as `mcp_server: expected string, received undefined`, which read as a routing bug. The SDK's parsed input is now authoritative, a call whose `tool-input-start` never arrived is still executed, and an empty or non-object argument payload now fails with the tool name and cause instead of defaulting to `{}`.
