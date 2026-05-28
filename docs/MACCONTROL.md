# MACCONTROL.md

Hướng dẫn vận hành lớp primitive computer-use trên máy Mac `macbox`.

Last verified: 2026-05-28

## Current architecture

Path đúng hiện tại:

```text
WSL/OpenClaw -> scripts/maccontrol -> SSH macbox -> local MacControl server -> macOS GUI session
```

Không gọi trực tiếp binary qua SSH để click/type/screenshot. macOS TCC dễ coi đó là process lẻ không có quyền. `MacControl.app` phải chạy persistent qua LaunchAgent trong GUI session.

## Files

WSL workspace:

- `scripts/maccontrol`
- `scripts/macbrowser`
- `tools/maccontrol/MacControl.swift`
- `tools/maccontrol/Info.plist`
- `tools/maccontrol/build-maccontrol.sh`
- `tools/maccontrol/maccontrol-client.py`
- `tools/maccontrol/app.openclaw.maccontrol.plist`
- `tools/macbrowser/macbrowser-control.mjs`

Mac side:

- App: `/Users/ngotrung/Applications/MacControl.app`
- Binary: `/Users/ngotrung/Applications/MacControl.app/Contents/MacOS/MacControl`
- Source deploy dir: `/Users/ngotrung/OpenClawTools/MacControl`
- LaunchAgent: `/Users/ngotrung/Library/LaunchAgents/app.openclaw.maccontrol.plist`
- Logs:
  - `/Users/ngotrung/OpenClawTools/maccontrol.log`
  - `/Users/ngotrung/OpenClawTools/maccontrol.err`
- Local server: `127.0.0.1:17891` on macbox only
- Browser CDP: `127.0.0.1:18801` on macbox only
- Browser profile: `/Users/ngotrung/OpenClawTools/chrome-cdp-profile`
- Browser controller: `/Users/ngotrung/OpenClawTools/macbrowser-control.mjs`

## Permissions

Required macOS permissions:

- Accessibility: `/Users/ngotrung/Applications/MacControl.app`
- Screen & System Audio Recording: `/Users/ngotrung/Applications/MacControl.app`

If permissions do not take effect:

1. Do not rebuild the app again unless necessary; rebuilding/re-signing can stale the TCC entry.
2. Remove old `MacControl` entries in System Settings.
3. Add `/Users/ngotrung/Applications/MacControl.app` again.
4. Restart LaunchAgent.

## Restart

```bash
ssh macbox 'PL="$HOME/Library/LaunchAgents/app.openclaw.maccontrol.plist"; launchctl bootout gui/$(id -u) "$PL" >/dev/null 2>&1 || true; pkill -f "/Applications/MacControl.app/Contents/MacOS/MacControl" >/dev/null 2>&1 || true; sleep 1; launchctl bootstrap gui/$(id -u) "$PL"; launchctl kickstart -k gui/$(id -u)/app.openclaw.maccontrol'
```

## Commands

```bash
scripts/maccontrol check
scripts/maccontrol screenshot --out /Users/ngotrung/OpenClawTools/shot.png
scripts/maccontrol clipboard --mode set --text 'hello'
scripts/maccontrol clipboard --mode get
scripts/maccontrol type --text 'hello'
scripts/maccontrol hotkey --keys cmd+a
scripts/maccontrol click --x 100 --y 100
scripts/maccontrol move --x 100 --y 100
scripts/maccontrol scroll --dy -400 --dx 0
scripts/maccontrol drag --x1 100 --y1 100 --x2 200 --y2 200
scripts/maccontrol applescript --script 'return "hello"'
scripts/maccontrol app --action list
scripts/maccontrol app --action open --name TextEdit
scripts/maccontrol app --action focus --name TextEdit
scripts/maccontrol app --action quit --name TextEdit
scripts/maccontrol windows
scripts/maccontrol process --action list
scripts/maccontrol process --action kill --pid 12345
scripts/maccontrol file --action reveal --path /Users/ngotrung/OpenClawTools/shot.png
scripts/maccontrol healthcheck
scripts/maccontrol ax-snapshot --name TextEdit --max-depth 5 --max-nodes 120
scripts/maccontrol ax-find --name TextEdit --role CheckBox --query underline --limit 5
scripts/maccontrol ax-click --name TextEdit --role CheckBox --query underline
scripts/maccontrol ax-click --name TextEdit --id 26
scripts/maccontrol ax-type --name TextEdit --role TextArea --query AXTextArea --text 'hello'
scripts/maccontrol ax-type --name TextEdit --id 4 --text 'hello'
scripts/maccontrol ax-set-value --name TextEdit --id 4 --text 'hello'
scripts/maccontrol ax-action --name "ChatGPT Atlas" --role MenuBarItem --query Help --action AXPress
scripts/maccontrol ax-select-text --name TextEdit --role TextArea --query AXTextArea --text beta --prefix 'gamma ' --suffix ' omega' --mode select
scripts/maccontrol ax-wait-for --name TextEdit --role TextArea --query AXTextArea --timeout-ms 3000
```

Browser lane:

```bash
scripts/macbrowser --action status
scripts/macbrowser --action ensure
scripts/macbrowser --action tabs
scripts/macbrowser --action navigate --url https://example.com
scripts/macbrowser --action screenshot --out /Users/ngotrung/OpenClawTools/macbrowser-example.png
scripts/macbrowser --action capture-state --out /Users/ngotrung/OpenClawTools/macbrowser-state.png
scripts/macbrowser --action eval --expr 'document.title'
```

Intent lane:

```bash
scripts/mac-intent capture-state
scripts/mac-intent open-resource https://example.com 'Example Domain'
scripts/mac-intent --ledger-run demo open-resource https://example.com 'Example Domain'
scripts/mac-intent focus-write-verify TextEdit 'hello from mac intent'
```

## Verified on 2026-05-20

After Trung re-added `MacControl.app` to Accessibility and Screen Recording:

- LaunchAgent running with `state = running`
- `scripts/maccontrol check` returned `accessibilityTrusted:true`
- Screenshot created a real PNG at `/Users/ngotrung/OpenClawTools/maccontrol-accessibility-shot.png`
- TextEdit typing test inserted and read back:
  - `MacControl accessibility type works 2026-05-20`
- Hotkey test `cmd+a` plus type replaced TextEdit content with:
  - `MacControl hotkey replace works`
- Click command returned OK for coordinate click.

Parity expansion verified later on 2026-05-20:

- `macbrowser` verified:
  - `status` reports CDP dead/alive.
  - `ensure` starts Chrome 148 on `127.0.0.1:18801` with profile `/Users/ngotrung/OpenClawTools/chrome-cdp-profile`.
  - `navigate` loaded `https://example.com/` and title `Example Domain`.
  - `tabs` listed the CDP tab.
  - `screenshot` created `/Users/ngotrung/OpenClawTools/macbrowser-example.png` (`2400x1884`).
  - `eval` returned `Example Domain|example.com`.
- `maccontrol` parity verified:
  - `app --action list/focus`
  - `windows`
  - `process --action list`
  - `file --action reveal`
  - `move`
  - `click`
  - `scroll`
  - `drag`
  - `hotkey`
  - `type`
  - `screenshot`

Semantic AX expansion verified later on 2026-05-20:

- `ax-snapshot` reads real macOS Accessibility trees, including role/title/description/value/frame/actions.
- TextEdit snapshot includes `AXTextArea`, toolbar checkboxes, font controls, windows, and frames.
- Chrome snapshot reads menu/window tree. Chrome page DOM should still be handled by `macbrowser` CDP when possible.
- `ax-click` verified on TextEdit toolbar checkboxes such as bold/italic/underline.
- `ax-type` verified on TextEdit `AXTextArea`, with readback:
  - `AX durability final pass`

Signing/TCC durability fix verified later on 2026-05-20:

- Previous ad-hoc signature produced designated requirements tied to `cdhash`, so every rebuild changed app identity and broke Accessibility trust.
- `tools/maccontrol/build-maccontrol.sh` now signs ad-hoc with explicit designated requirement:
  - `designated => identifier "app.openclaw.maccontrol"`
- Verified by rebuilding `MacControl.app`, restarting LaunchAgent, and checking:
  - `scripts/maccontrol check` still returned `accessibilityTrusted:true`.

Polish expansion verified later on 2026-05-20:

- `healthcheck` verifies Accessibility, screenshot, clipboard, frontmost AX snapshot, and signing requirement in one call.
- `ax-find` returns concise top matches instead of dumping the full AX tree.
- `ax-click --id` clicks an exact node id from snapshot/find output.
- `ax-type --id` types into an exact node id from snapshot/find output.
- `ax-wait-for` waits until a query/role appears.
- Verified `healthcheck` all green.
- Verified `ax-find --role CheckBox --query underline`.
- Verified `ax-wait-for --role TextArea --query AXTextArea`.
- Verified `ax-click --id 26`.
- Verified `ax-type --id 4`, with readback:
  - `AX click-by-id and wait-for polish pass`

## Known limitations

- Phase 1 uses `screencapture` for screenshot. Later consider ScreenCaptureKit.
- Server is intentionally simple. A failing command may still affect the server process; LaunchAgent `KeepAlive` mitigates this for now.
- Build script now uses a stable designated requirement by bundle id. If TCC ever drops again, first verify `codesign -dr - /Users/ngotrung/Applications/MacControl.app`; it should print `designated => identifier "app.openclaw.maccontrol"`.
- Browser CDP lane uses a separate Chrome profile and does not attach to Trung's normal Chrome profile by default.

## Verified on 2026-05-28

- `scripts/maccontrol healthcheck` passed after rebuilding and restarting the LaunchAgent on `macbox`.
- `scripts/maccontrol screenshot` created `/Users/ngotrung/OpenClawTools/audit-maccontrol-20260528.png`.
- `scripts/macbrowser --action ensure/eval/screenshot` verified Chrome CDP on `127.0.0.1:18801` and created `/Users/ngotrung/OpenClawTools/audit-macbrowser-20260528.png`.
- `MacControl.swift` server read loop was fixed to read socket input until EOF instead of a single 8KB read. Verification used a 20,024-character clipboard payload through `scripts/maccontrol`, then read it back successfully.
- `MacControl.swift` now exposes `ax-set-value` for direct Accessibility value setting and `ax-action` for named AX actions such as `AXPress`.
- `MacControl.swift` now exposes `ax-select-text` for `AXSelectedTextRange` and `applescript` through `/usr/bin/osascript` with an internal timeout so a blocked Apple Event does not hang the MacControl server.
- `tools/macbrowser/macbrowser-control.mjs` gained shared screenshot helper with CDP fallback, PNG integrity check, `viewport`, and `capture-state`.
- `scripts/mac-intent capture-state` verifies remote screenshots with retry, stable file size, non-trivial size, and PNG magic bytes.
- `scripts/mac-intent open-resource https://example.com 'Example Domain'` verified navigation, text evidence, remote screenshot integrity, and wrote a ledger event.
