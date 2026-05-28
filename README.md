<div align="center">

# OpenClaw Computer State

**State-first desktop control for OpenClaw agents across macOS and Windows.**

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS-black.svg)](#surfaces)
[![Platform: Windows](https://img.shields.io/badge/platform-Windows-0078D4.svg)](#surfaces)
[![MCP](https://img.shields.io/badge/MCP-tools-blue.svg)](#mcp-tools)
[![Status: usable](https://img.shields.io/badge/status-usable-brightgreen.svg)](#status)

Give desktop agents eyes, hands, and a record of what changed.

</div>

---

## TL;DR

OpenClaw Computer State is a standalone desktop-control toolkit for OpenClaw-style agents that need to inspect and operate real macOS and Windows machines through one MCP vocabulary.

It combines:

- macOS screenshots, Accessibility-tree inspection, AX actions, AppleScript, app/window control
- Windows-MCP snapshots, UI actions, screenshots, Win32 mouse/keyboard helpers
- state diffing to avoid repeatedly dumping huge UI trees into an agent context
- action wrappers that capture before/after state, verify expectations, and retry boundedly
- workflow replay so repeated GUI procedures become auditable JSON recipes
- a cross-surface eval suite for Mac and Windows control health

```bash
git clone git@github.com:kiyo9w/openclaw-computer-state.git
cd openclaw-computer-state

python3 -m py_compile scripts/computer-state scripts/computer-state-mcp scripts/computer-workflow
scripts/computer-state surfaces
scripts/computer-state healthcheck --surface mac
scripts/computer-state healthcheck --surface win
scripts/eval-computer-state
```

---

## Why This Exists

Desktop agents fail when they click blind.

This project started as a set of local bridge scripts for controlling macOS and Windows from an OpenClaw workspace. The primitives worked, but they lived behind separate commands and mental models:

- `scripts/maccontrol`
- `scripts/maccomputer`
- `scripts/wincontrol`
- `scripts/windows-mcp-call`

This repo turns those primitives into a single state-first facade:

1. Capture the current UI state.
2. Find semantic targets when possible.
3. Act through a bounded wrapper.
4. Return a compact diff and verification result.
5. Replay known workflows instead of rediscovering the same UI every time.

The goal is not to be a giant computer-use framework. The goal is a small, inspectable layer that gives agents enough state, safety, and repeatability to operate real desktops without turning every task into guesswork.

---

## Surfaces

| Surface | Backend | State Model | Action Model |
|---|---|---|---|
| `mac` | `scripts/maccomputer` -> `MacControl.app` on `macbox` | screenshot + macOS Accessibility tree | AX press/set/select, mouse, keyboard, AppleScript, app/window helpers |
| `win` | `scripts/windows-mcp-call` + `scripts/wincontrol` | Windows-MCP semantic snapshot + optional screenshot | label/coordinate click, type, shortcuts, scroll, drag, app/window helpers |

Both surfaces are exposed through the scripts in this repository:

- CLI: `scripts/computer-state`
- MCP stdio server: `scripts/computer-state-mcp`
- workflow runner: `scripts/computer-workflow`

---

## Features

- **State-first capture**: screenshot metadata plus a semantic tree where available.
- **Bounded context output**: Windows snapshots and find results are capped by default to avoid context overflow.
- **Semantic targeting**: prefer ids from the latest capture, queries, roles, labels, and UI tree matches before raw coordinates.
- **Visual grounding**: `annotate-state` draws target ids onto screenshots. macOS uses Accessibility frames; Windows uses UIA snapshot coordinates from `windows-mcp`. Both return click centers and fall back to SVG when Pillow is unavailable.
- **State diffing**: save state snapshots and compare later captures as compact added/removed line deltas.
- **Action repair loop**: `act` captures before/after state, verifies expected UI text, and retries within a small bound.
- **Workflow replay**: JSON workflows replay through `act`, so every step still gets diff, verification, and retry.
- **MCP tool surface**: agents can call the same capabilities through structured MCP tools.
- **Cross-surface evals**: one command checks syntax, MCP listing, Mac health, Windows health, state diff, action loop, workflow replay, and annotation.
- **Safety stance**: risky GUI actions still require explicit confirmation by the calling agent/operator.

---

## Architecture

```text
+-------------------------------------------------------------+
| Agent / Codex / OpenClaw                                    |
|                                                             |
|  MCP tools                                                  |
|  `-- scripts/computer-state-mcp                             |
|        |                                                    |
|        v                                                    |
|  Unified facade                                             |
|  `-- scripts/computer-state                                 |
|        |-- get-state                                        |
|        |-- find                                             |
|        |-- act                                              |
|        |-- annotate-state                                   |
|        `-- wait-for                                         |
|                                                             |
|  Workflow layer                                             |
|  `-- scripts/computer-workflow                              |
|        `-- replay JSON steps through computer-state act     |
+-------------------------------------------------------------+
            |                                      |
            v                                      v
+-----------------------------+      +------------------------------+
| macOS surface               |      | Windows surface              |
| scripts/maccomputer         |      | scripts/windows-mcp-call     |
| MacControl.app              |      | scripts/wincontrol           |
| AX tree + screenshot        |      | MCP snapshot + Win32 helpers |
+-----------------------------+      +------------------------------+
```

---

## Quickstart

### 1. Check available surfaces

```bash
scripts/computer-state surfaces
scripts/computer-state tools
```

### 2. Run healthchecks

```bash
scripts/computer-state healthcheck --surface mac
scripts/computer-state healthcheck --surface win
```

### 3. Capture UI state

```bash
scripts/computer-state get-state --surface mac --app "ChatGPT Atlas" --copy-screenshot-default
scripts/computer-state get-state --surface win --copy-screenshot-default --max-chars 20000
```

### 4. Find a target

```bash
scripts/computer-state find --surface mac --app "ChatGPT Atlas" --query Help --role MenuBarItem
scripts/computer-state find --surface win --query "Message" --limit 5
```

### 5. Act with verification

```bash
scripts/computer-state act \
  --surface mac \
  click \
  --app "ChatGPT Atlas" \
  --query Help \
  --role MenuBarItem \
  --expect Help \
  --retries 1
```

```bash
scripts/computer-state act \
  --surface win \
  press-key \
  --key ESC \
  --retries 0 \
  --max-chars 3000
```

---

## State Diff

Repeated full UI dumps are expensive for agents. Save a state once, then ask for the delta:

```bash
scripts/computer-state get-state \
  --surface win \
  --max-chars 12000 \
  --save-state /tmp/before.json

scripts/computer-state get-state \
  --surface win \
  --max-chars 12000 \
  --diff-from /tmp/before.json \
  --diff-limit 20
```

The diff reports:

- added lines
- removed lines
- total added/removed counts
- whether anything changed
- before/after line counts

---

## Visual Grounding

Generate an annotated screenshot from the current UI state. The numeric ids are generated by this wrapper for the current capture; use them with the matching fresh state, not as durable OS-level identifiers.

```bash
scripts/computer-state annotate-state \
  --surface mac \
  --app "ChatGPT Atlas" \
  --out /tmp/chatgpt-annotated.png
```

On Windows, `annotate-state` maps `windows-mcp` UIA snapshot coordinates into visual target markers:

```bash
scripts/computer-state annotate-state \
  --surface win \
  --limit 80 \
  --out /tmp/windows-annotated.png
```

If Pillow is installed, the output is a PNG. If Pillow is not installed, the command writes an SVG overlay next to the requested PNG path.

---

## Workflows

Use workflows when a GUI procedure is worth replaying.

Workflows are JSON recipes. Each step replays through `computer-state act`, so replay still captures before/after state, returns a diff, checks expectations, and retries within a bound.

### Create a workflow

```bash
scripts/computer-workflow init \
  --file /tmp/open-repo.json \
  --name open-repo \
  --surface win

scripts/computer-workflow add \
  --file /tmp/open-repo.json \
  press-key \
  --key "CTRL+L" \
  --step-name address-bar

scripts/computer-workflow add \
  --file /tmp/open-repo.json \
  type-text \
  --text "https://github.com/kiyo9w/openclaw-computer-state" \
  --enter \
  --expect "openclaw-computer-state" \
  --step-name navigate

scripts/computer-workflow validate --file /tmp/open-repo.json
```

### Replay a workflow

```bash
scripts/computer-workflow replay \
  --file /tmp/open-repo.json \
  --report /tmp/open-repo-report.json
```

### Use variables

Workflow text fields support `${NAME}` placeholders:

```json
{
  "name": "navigate",
  "action": "type-text",
  "args": {
    "text": "${URL}",
    "enter": true
  },
  "expect": "${EXPECT}"
}
```

```bash
scripts/computer-workflow replay \
  --file /tmp/open-repo.json \
  --var URL=https://github.com/kiyo9w/openclaw-computer-state \
  --var EXPECT=openclaw-computer-state
```

### Built-in example

```bash
scripts/computer-workflow validate --file examples/workflows/win-esc-smoke.json
scripts/computer-workflow replay --file examples/workflows/win-esc-smoke.json --dry-run
scripts/computer-workflow replay --file examples/workflows/win-esc-smoke.json --report /tmp/workflow-report.json
```

---

## MCP Tools

`scripts/computer-state-mcp` exposes:

| Tool | Purpose |
|---|---|
| `computer_surfaces` | List available surfaces |
| `computer_healthcheck` | Check whether a surface is reachable |
| `computer_list_apps` | List visible/running applications |
| `computer_app` | Open/focus/quit Mac apps, launch/switch/resize Windows apps |
| `computer_get_state` | Capture UI state, optionally save/diff |
| `computer_annotate_state` | Produce annotated Mac screenshot |
| `computer_find` | Find UI elements by query |
| `computer_act` | Run one action with state diff, verification, and retry |
| `computer_replay_workflow` | Replay a JSON workflow through `act` |
| `computer_click` | Click by semantic target or coordinate |
| `computer_set_value` | Replace target value |
| `computer_type_into` | Focus target and type |
| `computer_perform_action` | Perform named Mac AX action |
| `computer_select_text` | Select target text in Mac AX text element |
| `computer_run_applescript` | Run AppleScript through MacControl |
| `computer_type_text` | Type into active or selected target |
| `computer_press_key` | Press a key/chord |
| `computer_scroll` | Scroll by deltas |
| `computer_drag` | Drag between coordinates |
| `computer_wait_for` | Poll until a UI query appears |

Smoke test:

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"computer_healthcheck","arguments":{"surface":"mac"}}}' \
  | scripts/computer-state-mcp
```

---

## OpenClaw Config

Add the MCP server to `mcp.servers`:

```json
{
  "mcp": {
    "servers": {
      "computer_state": {
        "command": "/absolute/path/to/openclaw-computer-state/scripts/computer-state-mcp",
        "args": []
      }
    }
  }
}
```

Validate after editing config:

```bash
openclaw config validate
```

---

## Eval Suite

Run the cross-surface eval suite after any control behavior change:

```bash
scripts/eval-computer-state
```

It writes both `report.json` and `report.md`, and verifies:

- Python syntax
- MCP `tools/list`
- Mac healthcheck
- Windows healthcheck
- Windows state save/diff
- Windows `act`
- workflow validate/dry-run/replay
- Mac annotated state
- Windows annotated state

Reports are written to:

```text
.control-runs/evals/<timestamp>/report.json
```

---

## Safety

This repo exposes powerful local desktop control. It intentionally stays small and auditable, but it does not make unsafe actions safe by itself.

Calling agents and operators must still confirm before actions that:

- delete or overwrite data
- send messages or emails
- purchase, transfer, or submit financial information
- change security settings
- create, export, or transmit secrets
- install software or run untrusted scripts
- affect medical, legal, account, or identity workflows

Use semantic targets and `get-state`/`act` verification before GUI actions. Use raw coordinates only when semantic targeting is unavailable.

---

## Status

Usable and fairly complete for its intended scope.

Verified on the author's local Mac/Windows setup:

- macOS Accessibility and screenshot capture through `MacControl.app`
- Windows MCP snapshots through `windows-mcp`
- Win32 screenshot/mouse/keyboard helpers
- MCP stdio wrapper
- workflow replay
- cross-surface eval suite

This is not a hosted computer-use product and it is not a native OpenClaw runtime feature. It is a local control layer made of repo-managed scripts and helper binaries for deployments that already have the Mac/Windows bridge configured.

---

## External References

The README claims are based on the repo implementation plus these upstream surfaces:

- Apple Accessibility APIs expose AX element attributes and actions through ApplicationServices.
- Microsoft UI Automation is the Windows accessibility/automation layer for interacting with UI controls in other applications.
- Windows-MCP is an external Windows desktop automation MCP server; this repo wraps it from WSL/PowerShell and adds local state/action/workflow behavior on top.
- MCP tools use `tools/list`, `tools/call`, text `content`, optional `structuredContent`, and `isError` for tool-call failures.

Useful links:

- Apple AXUIElement docs: https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue
- Microsoft UI Automation fundamentals: https://learn.microsoft.com/en-us/windows/win32/winauto/entry-uiautocore-overview
- Windows-MCP: https://github.com/CursorTouch/Windows-MCP
- MCP schema reference: https://modelcontextprotocol.io/specification/2025-06-18/schema

---

## Documentation

- [Computer State](docs/COMPUTER_STATE.md)
- [MacControl](docs/MACCONTROL.md)
- [Windows MCP](docs/WINDOWS_MCP.md)

---

## License

MIT. See [LICENSE](LICENSE).
