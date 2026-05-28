# COMPUTER_STATE.md

Unified state-first desktop control facade for OpenClaw.

## Entrypoint

```bash
scripts/computer-state surfaces
scripts/computer-state tools
scripts/computer-state healthcheck --surface mac
scripts/computer-state healthcheck --surface win
scripts/computer-state app --surface mac focus --name "ChatGPT Atlas"
scripts/computer-state app --surface win switch --name Brave
```

MCP stdio wrapper:

```bash
scripts/computer-state-mcp
```

Surfaces:

- `mac`: wraps `scripts/maccomputer`, which wraps `MacControl` on `macbox`.
- `win`: wraps `scripts/windows-mcp-call` plus `scripts/wincontrol` for screenshot file capture.

## Rule

For GUI work, call `get-state` first:

```bash
scripts/computer-state get-state --surface mac --app "ChatGPT Atlas" --copy-screenshot-default
scripts/computer-state get-state --surface win --copy-screenshot-default --max-chars 20000
```

For context-efficient verification, save and diff state captures instead of repeatedly dumping full UI trees:

```bash
scripts/computer-state get-state --surface win --max-chars 12000 --save-state /tmp/before.json
scripts/computer-state get-state --surface win --max-chars 12000 --diff-from /tmp/before.json --diff-limit 20
```

For visual grounding on macOS, generate an annotated screenshot with Accessibility ids and roles:

```bash
scripts/computer-state annotate-state --surface mac --app "ChatGPT Atlas" --out /tmp/chatgpt-annotated.png
```

If Pillow is unavailable, `annotate-state` writes an SVG overlay next to the requested PNG path. Install Pillow only if PNG output is required.

Then act using semantic targets whenever possible:

```bash
scripts/computer-state find --surface mac --app "ChatGPT Atlas" --query Help --role MenuBarItem
scripts/computer-state click --surface mac --app "ChatGPT Atlas" --id 437
scripts/computer-state set-value --surface mac --app "ChatGPT Atlas" --id 437 --text "hello"
scripts/computer-state select-text --surface mac --app TextEdit --query AXTextArea --role TextArea --text beta --prefix "gamma " --suffix " omega" --mode select
scripts/computer-state perform-action --surface mac --app "ChatGPT Atlas" --query Help --role MenuBarItem --action AXPress
scripts/computer-state applescript --surface mac --script 'return "hello"'
scripts/computer-state scroll --surface mac --dy -600
scripts/computer-state drag --surface mac --x1 400 --y1 400 --x2 700 --y2 700
scripts/computer-state wait-for --surface mac --app "ChatGPT Atlas" --query Help --role MenuBarItem --timeout-ms 3000

scripts/computer-state find --surface win --query "Message" --limit 5
scripts/computer-state click --surface win --x 948 --y 987
scripts/computer-state type-text --surface win --x 948 --y 987 --text "hello"
scripts/computer-state scroll --surface win --dy -120 --x 948 --y 987
scripts/computer-state drag --surface win --x1 500 --y1 500 --x2 700 --y2 700
scripts/computer-state wait-for --surface win --query Message --timeout-ms 3000
```

For action-level repair loops, use `act`. It captures state before and after, returns a compact diff, optionally verifies that an expected query appears, and retries boundedly:

```bash
scripts/computer-state act --surface mac click --app "ChatGPT Atlas" --query Help --role MenuBarItem --expect Help --retries 1
scripts/computer-state act --surface win type-text --x 948 --y 987 --text "hello" --expect hello --retries 1
```

For repeatable workflows, use `computer-workflow`. This stores a small JSON recipe and replays every step through `act`, so each step still gets before/after state diff, expectation checks, and bounded retry:

```bash
scripts/computer-workflow init --file /tmp/open-repo.json --name open-repo --surface win
scripts/computer-workflow add --file /tmp/open-repo.json press-key --key "CTRL+L" --step-name address-bar
scripts/computer-workflow add --file /tmp/open-repo.json type-text --text "https://github.com/kiyo9w/openclaw-computer-state" --enter --expect "openclaw-computer-state" --step-name navigate
scripts/computer-workflow validate --file /tmp/open-repo.json
scripts/computer-workflow replay --file /tmp/open-repo.json --report /tmp/open-repo-report.json
```

Workflow text fields support variables for data entry and environment-specific values:

```json
{"name": "navigate", "action": "type-text", "args": {"text": "${URL}", "enter": true}, "expect": "${EXPECT}"}
```

```bash
scripts/computer-workflow replay --file /tmp/open-repo.json --var URL=https://github.com/kiyo9w/openclaw-computer-state --var EXPECT=openclaw-computer-state
```

Windows snapshots are capped at 20k chars by default to avoid agent context overflow. Use `--max-chars 0` only when the full UI tree is explicitly needed. Windows `find` caps each matched line at 500 chars by default for the same reason.

Use raw `--x/--y` only when semantic targets are unavailable.

## Why this exists

Codex Computer Use is strong because it has a state model: screenshot plus Accessibility/UI tree before actions. Previously OpenClaw had strong primitives, but operators needed to remember separate commands:

- `scripts/maccontrol`
- `scripts/maccomputer`
- `scripts/wincontrol`
- `scripts/windows-mcp-call`

`scripts/computer-state` is a thin facade so agents can reason in one vocabulary:

- `get-state`
- `annotate-state`
- `find`
- `act`
- `computer-workflow replay`
- `click`
- `set-value`
- `type-into`
- `perform-action`
- `select-text`
- `applescript`
- `type-text`
- `press-key`
- `scroll`
- `drag`
- `wait-for`
- `list-apps`
- `app`
- `healthcheck`

`scripts/computer-state-mcp` exposes the same vocabulary as MCP tools:

- `computer_surfaces`
- `computer_healthcheck`
- `computer_list_apps`
- `computer_app`
- `computer_get_state`
- `computer_annotate_state`
- `computer_find`
- `computer_act`
- `computer_replay_workflow`
- `computer_click`
- `computer_set_value`
- `computer_type_into`
- `computer_perform_action`
- `computer_select_text`
- `computer_run_applescript`
- `computer_type_text`
- `computer_press_key`
- `computer_scroll`
- `computer_drag`
- `computer_wait_for`

The MCP server supports both newline-delimited JSON-RPC for smoke tests and `Content-Length` framing for MCP stdio clients. Keep it local/test-only until wiring it into OpenClaw/Codex config intentionally.

Smoke test:

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"computer_healthcheck","arguments":{"surface":"mac"}}}' \
  | scripts/computer-state-mcp
```

Run the cross-surface eval suite when changing control behavior:

```bash
scripts/eval-computer-state
```

The eval writes a JSON report under `.control-runs/evals/` with per-case latency and pass/fail status.

## Verification

Verified on 2026-05-28:

```bash
python3 -m py_compile scripts/computer-state
python3 -m py_compile scripts/computer-state-mcp
scripts/computer-state healthcheck --surface mac
scripts/computer-state healthcheck --surface win
scripts/computer-state get-state --surface mac --app "ChatGPT Atlas" --copy-screenshot-default
scripts/computer-state get-state --surface win --copy-screenshot-default --max-chars 20000
scripts/computer-state get-state --surface win --max-chars 3000 --save-state /tmp/computer-state-before.json
scripts/computer-state get-state --surface win --max-chars 3000 --diff-from /tmp/computer-state-before.json --diff-limit 5
scripts/computer-state find --surface mac --app "ChatGPT Atlas" --query Help --role MenuBarItem
scripts/computer-state find --surface win --query Brave --limit 3
scripts/computer-state list-apps --surface mac
scripts/computer-state list-apps --surface win --limit 5
scripts/computer-state scroll --surface mac --dy 0
scripts/computer-state perform-action --surface mac --app "ChatGPT Atlas" --query Help --role MenuBarItem --action AXPress
scripts/computer-state applescript --surface mac --script 'return "applescript-ok"' --timeout 5
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"computer_find","arguments":{"surface":"win","query":"Brave","limit":2}}}' | scripts/computer-state-mcp
```

## Safety

This facade does not remove the existing safety gates in `windows-mcp-call`. For GUI actions, still apply the Computer Use confirmation policy: confirm before delete/send/purchase/security-setting/API-key/install/sensitive-data transmission steps.
