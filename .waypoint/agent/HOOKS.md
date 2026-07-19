# Optional Cursor hooks (not enabled by install)

To soft-enforce WPT-first, add a sessionStart hook that reminds agents to call `agent_brief` and prefer locate|query when `force_indexed_tools` is true (see agent/mcp.json). Do not enable automatically — opt-in only.
