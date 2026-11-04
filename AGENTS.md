# Threadlight development

- Keep UI in Threadlight and file adapters/state transitions in ThreadlightCore.
- All monitored application data is read-only. No network, hooks, injected code, transcript parsing, or edits to Codex/Claude settings.
- Never commit real conversation metadata, account identifiers, local paths, tokens, caches, or screenshots containing private chats. Use synthetic fixtures.
- Bound every log read and preserve a previously confirmed state on incomplete input. Do not infer completion from inactivity.
- Do not rebuild menu structure while AppKit tracks it. Resizing must preserve title truncation and the left status marker.
- Run `swift test`, `./scripts/build-app.sh`, and `./scripts/smoke.sh` for app changes. Test meaningful state transitions and IO budgets.
- Do not publish, push, change account permissions, or interrupt the monitored applications without the user's instruction.
