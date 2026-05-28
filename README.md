# OpenClaw Computer State

Unified state-first desktop control facade for OpenClaw agents.

This repository packages the Mac and Windows control harness used by OpenClaw to expose a single `computer_state` MCP surface:

- macOS: screenshot + Accessibility tree through a persistent `MacControl.app` on `macbox`
- Windows: Windows-MCP semantic snapshots plus Win32 mouse/keyboard/screenshot helpers
- MCP: `scripts/computer-state-mcp` exposes the unified command vocabulary to Codex/OpenClaw agents

## Tools

The MCP server exposes:

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

## Quick Smoke

```bash
python3 -m py_compile scripts/computer-state scripts/computer-state-mcp scripts/maccomputer
scripts/computer-state surfaces
scripts/computer-state healthcheck --surface mac
scripts/computer-state healthcheck --surface win
scripts/computer-state get-state --surface win --save-state /tmp/before.json
scripts/computer-state get-state --surface win --diff-from /tmp/before.json
scripts/computer-workflow replay --file examples/workflows/win-esc-smoke.json --report /tmp/workflow-report.json
scripts/eval-computer-state
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | scripts/computer-state-mcp
```

## OpenClaw MCP Config

Add this server to `mcp.servers` in OpenClaw config:

```json
{
  "mcp": {
    "servers": {
      "computer_state": {
        "command": "/absolute/path/to/scripts/computer-state-mcp",
        "args": []
      }
    }
  }
}
```

Use `openclaw config validate` after editing config by hand.

## Safety Model

Call `computer_get_state` before GUI actions. Prefer semantic IDs, labels, or coordinates from the latest state over blind clicking.

Confirm before risky GUI actions such as deleting data, sending messages, installing software, changing security settings, creating keys, transmitting sensitive data, or financial/medical/account actions.

## Docs

- [Computer State](docs/COMPUTER_STATE.md)
- [MacControl](docs/MACCONTROL.md)
- [Windows MCP](docs/WINDOWS_MCP.md)
