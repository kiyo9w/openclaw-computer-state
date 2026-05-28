# WINDOWS_MCP.md

Hướng dẫn vận hành lớp computer-use trên máy Windows hiện tại. File này tồn tại để các phiên sau không phải dò lại từ đầu vì `windows-mcp` chỉ cung cấp capability, không lưu kiến trúc, workaround, hay verified workflow.

---

## Mục tiêu

Cho Pikachu khả năng dùng và quản lý **apps + desktop + browser** trên máy Windows, không chỉ browser.

Hiện trạng đúng:
- Browser control: dùng được qua wrapper `scripts/winbrowser`
- Desktop/app primitive control: dùng được qua wrapper `scripts/wincontrol`
- Semantic desktop control: dùng được qua `windows-mcp`
- Đường tích hợp đúng hiện tại: **WSL/OpenClaw -> PowerShell Windows -> windows-mcp localhost**
- Verified lại ngày 28/5/2026: `wincontrol`, `winbrowser`, và `windows-mcp-call` đều usable; `windows-mcp-call` now self-heals by starting `windows-mcp.exe serve --transport streamable-http --host 127.0.0.1 --port 8001` when the endpoint is down.

---

## Vì sao cần bridge thay vì gọi thẳng từ WSL

`windows-mcp` đang chạy ở Windows side và bind vào:
- `http://127.0.0.1:8001/mcp`

Quan sát đã verify:
- Gọi từ **Windows PowerShell** vào endpoint này: thành công
- Gọi từ **WSL** vào cùng endpoint: `Connection refused`

Kết luận:
- `127.0.0.1:8001` này thuộc Windows localhost namespace
- WSL hiện tại không chạm được trực tiếp endpoint đó
- Vì vậy integration đúng là gọi qua **PowerShell Windows bridge**, không phải HTTP trực tiếp từ WSL

---

## Thành phần hiện tại

### 1) Primitive wrappers

- `scripts/wincontrol`
  - gọi `C:\Users\ngoka\OpenClawTools\windows-control.ps1`
  - dùng cho: list windows, screenshot, focus, click, type, hotkey, start app

- `scripts/winbrowser`
  - gọi `C:\Users\ngoka\OpenClawTools\browser-control.mjs`
  - dùng cho: browser/CDP operations với Chrome Windows
  - tự `ensure` Chrome CDP profile riêng nếu CDP port chưa sống
  - readiness probe qua `/json/version` trước khi connect bằng Playwright CDP

### 2) Semantic wrapper

- `scripts/windows-mcp-call`
  - smart CLI wrapper từ WSL sang PowerShell Windows
  - tự handshake MCP, parse SSE response, normalize output
  - tự start `windows-mcp.exe` nếu endpoint `127.0.0.1:8001` đang down, poll readiness trên port, rồi retry một lần
  - hỗ trợ ledger bằng `--ledger-run <id>` / `CONTROL_LEDGER_RUN`
  - chặn sensitive actions mặc định; dùng `--allow-sensitive` chỉ khi đã có approval rõ
  - hỗ trợ subcommands rõ ràng như `tools`, `snapshot`, `clipboard`, `app`, `click`, `type`, `shortcut`, `process`
  - có nhiều output mode: text / compact / json
  - không gọi HTTP trực tiếp từ WSL

### 3) Windows-side bridge script

- `C:\Users\ngoka\OpenClawTools\windows_mcp_bridge.ps1`
  - file này được `scripts/windows-mcp-call` tự ghi lại khi chạy
  - không nên edit tay trừ khi biết rõ đang làm gì

### 4) MCP server

- binary/server path đã verify:
  - `C:\Users\ngoka\.local\bin\windows-mcp.exe`
- endpoint:
  - `http://127.0.0.1:8001/mcp`
- version đã verify:
  - `windows-mcp 3.3.1`

---

## Những điều đã verify thật

### MCP handshake

Đã thành công:
- `initialize`
- lấy `mcp-session-id`
- `notifications/initialized`
- `tools/list`

### Tool classes đã enumerate

`windows-mcp` hiện trả về các tool class chính như:
- `App`
- `Snapshot`
- `Screenshot`
- `Click`
- `Type`
- `Scroll`
- `Move`
- `Shortcut`
- `Clipboard`
- `Process`
- `FileSystem`
- `PowerShell`
- `Registry`
- `Notification`

### End-to-end semantic flow đã verify

Flow đã chạy thật:
1. Launch Notepad
2. Snapshot desktop/UI tree
3. Click vào editor
4. Type text vào app thật
5. `ctrl+a`
6. `ctrl+c`
7. đọc clipboard lại qua MCP

Verification string đã thấy trả về đúng:
- `Pikachu semantic bridge verified via Windows-MCP.`

Kết luận: desktop computer-use qua semantic bridge **đã usable thật**.

### Visual screenshot + vision đã verify

Flow đã chạy thật trên host WSL/Linux hiện tại:
1. Chụp screenshot Windows bằng `scripts/wincontrol`
2. Lưu ảnh ở `C:\\Users\\ngoka\\OpenClawTools\\last-screenshot.png`
3. Copy ảnh sang workspace để vision tool đọc được
4. Gọi `openclaw_image` để mô tả màn hình

Kết quả đã verify ngày 18/5/2026:
- screenshot trả về ảnh thật kích thước `1920x1080`
- vision đọc được màn hình Brave đang mở ChatGPT login modal + cookie banner
- các UI element lớn/rõ đủ để dùng cho coordinate-based interaction

Kết luận: visual screenshot path **đã usable thật** để verify màn hình và làm fallback thao tác theo toạ độ.

---

## Known quirks / pitfalls

### 1) `windows-mcp` không phải memory

Nó chỉ là capability server. Nó không tự nhớ:
- vì sao kiến trúc hiện tại là bridge
- pitfalls của WSL/localhost
- bug của PowerShell 5.1
- wrapper nào đang dùng
- flow nào đã verify

Muốn giữ continuity thì phải ghi file như file này + log memory.

### 2) PowerShell Windows ở máy này là bản cũ

Đã gặp lỗi:
- `ConvertFrom-Json : A parameter cannot be found that matches parameter name 'Depth'`

Kết luận:
- không dùng `ConvertFrom-Json -Depth` trong PowerShell bridge hiện tại
- giữ tương thích với Windows PowerShell 5.1

### 2.1) Endpoint có thể down sau reboot/session cleanup

Nếu `scripts/windows-mcp-call` thấy lỗi connect như `Unable to connect to the remote server`, wrapper sẽ tự bật lại:

```text
C:\Users\ngoka\.local\bin\windows-mcp.exe serve --transport streamable-http --host 127.0.0.1 --port 8001
```

Wrapper poll readiness trên `127.0.0.1:<port>` trước khi retry đúng một lần; không sleep cứng. Set `WINDOWS_MCP_NO_AUTOSTART=1` nếu muốn tắt self-heal để debug thủ công.

### 2.2) Sensitive action gate

`scripts/windows-mcp-call` chặn mặc định:

- raw `PowerShell`
- raw `Registry`
- raw `FileSystem`
- `app launch`
- `process kill`
- message send qua `send-composed-message --send` hoặc `focus-message-box-send --send`

Tool name được normalize case/punctuation trước khi gate, nên các biến thể như `powershell`, `POWERSHELL`, hoặc `PowerShell.exe` vẫn bị block. Muốn chạy các action này phải thêm `--allow-sensitive`, và chỉ làm sau khi Trung đã approve rõ. Ledger sẽ ghi failure nếu bị block khi có `--ledger-run`.

### 3) Encoding Windows/WSL có thể bẩn

Khi snapshot/UI tree có text tiếng Việt hoặc ký tự đặc biệt, decode output có thể lỗi hoặc méo ký tự.

Đã fix một phần trong `scripts/windows-mcp-call` bằng decode fallback, nhưng:
- output text của UI tree vẫn có thể xấu
- đừng assume mọi label tiếng Việt sẽ sạch đẹp 100%

### 4) `Type` không tự gõ vào focused control

Tool `Type` của `windows-mcp` yêu cầu:
- `loc`, hoặc
- `label`

Nó không tự hiểu “focused control” là target để gõ. Flow đúng là:
1. snapshot
2. lấy target
3. click/type vào target có `loc` hoặc `label`

### 5) `App switch` có thể quirk

Có lúc `App switch` qua wrapper mới trả lỗi kiểu:
- `expected string or bytes-like object, got 'NoneType'`

Đây có vẻ là quirk/bug theo đường input cụ thể, không phải toàn hệ thống hỏng. Vì các path khác như launch/snapshot/click/type vẫn chạy được.

### 6) Save dialog automation vẫn brittle hơn clipboard verification

Verify bằng:
- select all
- copy
- read clipboard

ổn định hơn cố ép flow Save dialog trong giai đoạn hiện tại.

### 7) Browser CDP phải validate riêng trước khi assume

`scripts/winbrowser` phụ thuộc Chrome/Brave CDP port Windows, hiện thường là:
- `127.0.0.1:18800`

Đã có thời điểm ngày 18/5/2026 lệnh status trả:
- `connect ECONNREFUSED 127.0.0.1:18800`

Sau research external best practice cùng ngày, `browser-control.mjs` đã được vá để có managed CDP path:
- `scripts/winbrowser --action status`: chỉ probe, không tự start
- `scripts/winbrowser --action ensure`: start Chrome profile riêng nếu CDP chưa sống
- các action như `tabs`, `navigate`, `screenshot`, `eval`: tự ensure CDP trước khi chạy
- profile riêng: `C:\Users\ngoka\OpenClawTools\chrome-cdp-profile`
- readiness check: gọi `http://127.0.0.1:18800/json/version`, không sleep mù

Validation thật sau patch:
- status trước ensure: `ok:false`, `fetch failed`
- ensure: start `chrome.exe` với `--remote-debugging-port=18800`, probe pass
- navigate `https://example.com`: title `Example Domain`
- browser screenshot: vision xác nhận đúng trang Example Domain

Kết luận:
- desktop/screenshot/semantic control có thể vẫn hoạt động dù CDP chết
- browser CDP là một lane riêng, phải probe/ensure trước khi dựa vào nó
- nếu CDP chết thì dùng `scripts/winbrowser --action ensure` thay vì assume Chrome người dùng đang mở đúng mode

---

## Khi nào dùng tool nào

### Dùng `scripts/winbrowser` khi:
- task chủ yếu là browser navigation/CDP
- muốn deterministic hơn cho browser tab/page operations
- không cần desktop semantic layer

### Dùng `scripts/wincontrol` khi:
- cần primitive desktop actions nhanh
- biết rõ window title/toạ độ/action
- muốn screenshot/focus/click/hotkey nhanh, ít ceremony

### Dùng `scripts/windows-mcp-call` khi:
- cần semantic desktop understanding
- cần snapshot UI tree
- cần thao tác app ngoài browser theo kiểu computer-use
- cần clipboard/process/registry/tool orchestration qua MCP

Nguyên tắc thực dụng:
- Browser-only -> ưu tiên `winbrowser`
- Primitive desktop action -> ưu tiên `wincontrol`
- Semantic app/desktop reasoning -> ưu tiên `windows-mcp`

---

## Pattern thao tác đúng cho workflow khó

Không assume một tool duy nhất giải quyết mọi case. Dùng 3 tầng theo độ chắc chắn và khả năng quan sát:

### Tầng 1) CDP / browser automation

Dùng khi task chủ yếu nằm trong browser và CDP đang sống:
- mở tab / điều hướng URL
- đọc DOM hoặc text page
- thao tác predictable qua browser surface
- cần độ deterministic cao hơn click ảnh

Trước khi dùng, validate:
```bash
scripts/winbrowser --action status
```

Nếu port CDP trả `ECONNREFUSED`, không coi browser automation là available trong phiên đó.

### Tầng 2) Semantic desktop / UI tree

Dùng khi:
- app không chỉ là browser
- cần focus đúng cửa sổ
- cần tìm control qua label, role, UI tree, opened windows, taskbar
- cần thao tác text-entry có thể verify bằng clipboard

Pattern:
1. snapshot hoặc window-find
2. resolve target theo label/role/focused/window scope
3. click/type/shortcut
4. verify bằng clipboard, process, hoặc snapshot mới

### Tầng 3) Visual screenshot + coordinate fallback

Dùng khi CDP/UI tree không đủ hoặc cần xác nhận bằng mắt:
- web phức tạp, modal lạ, canvas, custom control
- avatar / hình ảnh / trạng thái layout cần visual verification
- UI tree không expose label đúng
- cần xác định vị trí nút/ô input bằng ảnh thật

Pattern:
1. chụp screenshot bằng `scripts/wincontrol`
2. copy ảnh vào workspace nếu vision tool cần path local allowed
3. dùng vision để mô tả màn hình và ước lượng target
4. click theo toạ độ bằng `wincontrol` hoặc `windows-mcp-call click --loc`
5. đợi UI settle
6. chụp screenshot lại để verify state sau thao tác

Coordinate fallback đủ tốt cho:
- button lớn/rõ
- input field rõ
- modal/dialog rõ
- avatar/layout cần xác nhận thị giác

Không coi coordinate fallback là pixel-perfect cho:
- element rất nhỏ
- UI đang animate/chuyển trạng thái nhanh
- vùng click sát cạnh nguy hiểm
- hành động destructive chưa có verify rõ ràng

Nguyên tắc chốt:
- **CDP/UI tree trước**
- **screenshot để verify hoặc khi semantic path thiếu dữ liệu**
- **coordinate click là fallback cuối, luôn verify sau thao tác quan trọng**

---

## Đối chiếu external best practice

Research ngày 18/5/2026 từ OpenAI/Codex, Anthropic, OSWorld, OmniParser và cộng đồng browser-agent cho thấy workflow hiện tại của mình đang đi đúng hướng: **hybrid harness**, không phải pure pixel-clicking.

### Những điểm khớp best practice

- OpenAI Computer Use mô tả vòng lặp chuẩn: model nhìn screenshot, trả action, harness execute, rồi gửi screenshot mới để model đánh giá state tiếp theo. Pattern `action -> screenshot verify -> next action` của mình khớp.
- OpenAI cũng khuyến nghị custom harness có thể trộn visual interaction và programmatic UI interaction như Playwright/Selenium/VNC/MCP. Ba tầng `CDP -> UI tree -> screenshot coordinate` của mình đúng hướng này.
- Codex app computer-use khuyến nghị dùng computer-use khi structured integration không đủ, và nếu app có plugin/MCP riêng thì ưu tiên structured integration. Quy tắc `CDP/UI tree trước, coordinate fallback cuối` của mình khớp.
- Anthropic computer-use nhấn mạnh screenshot + mouse/keyboard control, nhưng cũng cảnh báo rủi ro prompt injection từ web/app content và cần human confirmation cho hành động có hậu quả thật. Doc này giữ nguyên yêu cầu verify và không tự làm hành động nhạy cảm.
- OSWorld cho thấy benchmark desktop-agent tốt phải có real environment, cross-app workflow, execution-based verification. Mình đã bắt đầu đi theo hướng đó bằng validate thật trên Notepad, browser, clipboard, screenshot thay vì chỉ mô tả.
- OmniParser chứng minh pure screenshot sẽ tốt hơn nhiều nếu có bước parse interactable regions / bounding boxes / local semantics. Vì vậy visual layer của mình nên phát triển theo hướng structured screen parsing, không chỉ hỏi vision "click đâu".

### Gap còn lại so với best practice

1. **Chưa có screen parser / set-of-marks layer**
   - Hiện vision chỉ mô tả ảnh và ước lượng target.
   - Nên thêm bước annotate UI screenshot thành numbered boxes/interactable regions trước khi hỏi model chọn target.

2. **Chưa có action ledger chuẩn**
   - Nên log mỗi bước: observation, intended target, action, expected result, verification result.
   - Việc này giúp debug workflow dài và tránh lặp misclick.

3. **Verification còn thủ công theo từng helper**
   - Cần chuẩn hóa verifier theo intent: URL/title/DOM cho browser, clipboard/text cho editor, screenshot diff hoặc state text cho visual flow.

4. **Chưa có policy rõ cho sensitive actions**
   - Computer-use với account đang đăng nhập phải coi web/app content là untrusted.
   - Payment, account/security setting, gửi tin nhắn nhạy cảm, xoá dữ liệu, chấp nhận điều khoản: phải hỏi Trung hoặc có verify gate rõ.

5. **Browser profile đã managed nhưng lifecycle còn tối giản**
   - Đã có `ensure`, nhưng chưa có `restart`, `logs`, cleanup profile, hoặc endpoint status giàu thông tin.

### Hướng cải thiện ưu tiên

Ưu tiên theo impact:
1. Managed CDP readiness: **đã làm** trong `browser-control.mjs`.
2. Thêm visual target annotation: screenshot -> detect/mark interactable boxes -> model chọn box id -> click center.
3. Thêm action ledger cho workflow khó.
4. Chuẩn hóa verifier per intent.
5. Tách Windows computer-use thành skill riêng khi pattern ổn định và dùng lặp lại nhiều.

---

## Cách gọi hiện tại

### Interface mới

Wrapper đã được refactor từ thin wrapper thành smart CLI. Cú pháp ưu tiên bây giờ là subcommand rõ ràng, không phải chỉ gọi raw tool + JSON.

Pattern ưu tiên hiện tại của wrapper theo hướng community best practice là:
- **intent-first**: người gọi nêu outcome như `open-resource`, `send-composed-message`, `fill-search-surface`
- **semantic-first**: snapshot / target / action
- **family-adapter second**: browser-search family có thể dùng affordance chung như `Ctrl+L`; composition/editor family cần adapter riêng mạnh hơn thay vì ép một generic path yếu
- **verify-after-action**: sau thao tác quan trọng thì verify lại bằng clipboard, process, hoặc snapshot
- **settle-and-retry at intent layer**: outcome verify không nên snapshot đúng một lần ngay sau action; nên cho phép settle/retry ngắn ở tầng intent
- **fallback-last**: chỉ lùi về coordinate hoặc primitive path khi semantic path không đủ tốt
- **window-aware first** cho desktop apps: focus window bằng opened-windows/taskbar match trước, rồi mới thao tác bên trong app

### Ví dụ

```bash
python3 scripts/windows-mcp-call tools --output names
python3 scripts/windows-mcp-call --ledger-run demo fill-search-surface Chrome 'query' --adapter browser-search --verify-input
python3 scripts/windows-mcp-call clipboard
python3 scripts/windows-mcp-call clipboard --set 'hello from pikachu'
python3 scripts/windows-mcp-call process list --limit 5 --sort-by name
python3 scripts/windows-mcp-call app launch --name notepad
python3 scripts/windows-mcp-call snapshot --output text
python3 scripts/windows-mcp-call snapshot-find 'Notepad|Text editor|Untitled'
python3 scripts/windows-mcp-call window-find 'Notepad' --output json
python3 scripts/windows-mcp-call focus-window 'Brave' --output json
python3 scripts/windows-mcp-call resolve-target --prefer-focused --control-type edit --output json
python3 scripts/windows-mcp-call click --loc 800 500
python3 scripts/windows-mcp-call type 'hello' --loc 800 500
python3 scripts/windows-mcp-call shortcut ctrl+c
python3 scripts/windows-mcp-call write-verify 'hello' --loc 800 500 --verify --output json
python3 scripts/windows-mcp-call focus-write-verify 'Notepad' 'hello from phase 5' --method paste --verify --output json
python3 scripts/windows-mcp-call focus-address-bar-open 'Brave' 'https://example.com' --output json
python3 scripts/windows-mcp-call open-resource 'Brave' 'https://example.com' 'Example Domain' --verify-input --output json
python3 scripts/windows-mcp-call send-composed-message 'Telegram' 'hello world' --verify-input --output json
python3 scripts/windows-mcp-call fill-search-surface 'Brave' 'telegram' --target-pattern 'Search' --verify-input --output json
scripts/winbrowser --action status
scripts/winbrowser --action ensure
scripts/winbrowser --action navigate --url https://example.com
scripts/winbrowser --action screenshot --out 'C:\Users\ngoka\OpenClawTools\browser-shot.png'
```

Current validation status:
- `open-resource`: pass
- `fill-search-surface`: pass with browser-search family adapter
- `send-composed-message`: pass after fixing two real bridge issues discovered during validation
  - UTF-8/Unicode roundtrip bug between WSL -> PowerShell -> windows-mcp
  - race condition from shared JSON args path across concurrent wrapper invocations

Most important interpretation:
- the intent is still universal
- browser/resource-open and browser-search already have stable family behavior
  - composition/message-send is now proven workable when the flow explicitly gates on recipient identity before send and verifies post-send in-thread

### Validation 2026-05-28

- `scripts/wincontrol -Action windows`: passed, saw real Windows app windows.
- `scripts/wincontrol -Action screenshot`: created `C:\Users\ngoka\OpenClawTools\audit-wincontrol-20260528.png` at `1920x1080`.
- `scripts/winbrowser --action status/eval/screenshot`: passed on Chrome CDP `127.0.0.1:18800`; screenshot created `C:\Users\ngoka\OpenClawTools\audit-winbrowser-20260528.png`.
- `python3 scripts/windows-mcp-call tools --output names`: initially found endpoint down, self-started `windows-mcp 3.3.1`, then listed tools successfully.
- `python3 scripts/windows-mcp-call clipboard --set ...` and `clipboard`: passed through the MCP bridge.

### Validation 2026-05-28 Phase B/D

- `--ledger-run` verified on `fill-search-surface`; ledger records intent, expected text, steps, result, verification.
- `open-resource` verifier hardened: it no longer accepts a match from another browser/window family or a same-family fallback window. A previous test exposed a false-positive risk where Chrome intent matched `Example Domain` in Brave; the verifier now fails honestly instead.
- Sensitive gate verified: raw `PowerShell`, lowercase `powershell`, uppercase `POWERSHELL`, and `app launch` are blocked unless `--allow-sensitive` is passed.
- Ledger redaction now covers common secret keys/headers, JSON-string token fields, clipboard/text snippets, and URLs with sensitive query parameters.

### Phase E: Reliability runner

`scripts/control-flow` chạy workflow JSON restartable cho các task control dài hơi. Mục tiêu là giảm lỗi âm thầm, không phải thêm security framework.

Nó hỗ trợ:
- `pre` condition trước step
- `action`
- `post` condition sau step
- retry ngắn theo step/default
- checkpoint ở `.control-runs/<run-id>/state.json`
- resume bằng `--resume`
- idempotency skip cho step có `idempotent: true` hoặc `idempotency_key`
- failure artifact pack ở `.control-runs/<run-id>/artifacts/`
- ledger chung ở `.control-runs/<run-id>/ledger.jsonl`

Ví dụ smoke:

```bash
scripts/control-flow examples/control-flow-smoke.json --run-id flow-smoke
scripts/control-flow examples/control-flow-smoke.json --run-id flow-smoke --resume
```

Condition types hiện có:
- `returncode`
- `stdout_contains`
- `stdout_regex`
- `json_ok`
- `file_exists`

Failure artifacts hiện có:
- `windows-snapshot`
- `windows-screenshot`
- `winbrowser-status`
- `mac-capture`
- `macbrowser-status`

Khi workflow cần gọi action có khả năng double-run như send/submit/create/kill/launch, đặt `idempotency_key` rõ ràng để retry/resume không chạy lại ngoài ý muốn.

### Raw escape hatch

Khi cần gọi tool bất kỳ chưa có helper subcommand riêng:

```bash
python3 scripts/windows-mcp-call call Clipboard '{"mode":"get"}'
python3 scripts/windows-mcp-call call App '{"mode":"launch","name":"notepad"}'
```

### Operating pattern đúng

Đối với app/desktop semantic task:
1. `Snapshot` hoặc `snapshot-find`
2. đọc UI tree / xác định target
3. `Click` / `Type` / `Shortcut`
4. verify bằng `Clipboard`, `Process`, hoặc snapshot tiếp

Nếu đang làm task nhập text đơn giản vào app và cần path đáng tin hơn, ưu tiên:
- `write-verify`
- `focus-write-verify`
- `open-resource` cho intent mở tài nguyên + verify outcome ✅ đã verify pass thực tế
- `fill-search-surface` cho intent nhập query vào search-like surface ✅ đã verify pass thực tế với browser-search family adapter
- `send-composed-message` cho intent nhập/gửi message trên composition surface ✅ đã verify pass thực tế sau khi fix Unicode bridge + concurrent args-file race; flow đúng là pin recipient -> verify identity -> compose -> send -> verify in-thread
- helper cũ như `focus-address-bar-open`, `focus-open-verify`, `focus-message-box-send` giữ lại chủ yếu để tương thích và debug

`write-verify` đóng gói sẵn flow:
- click target
- nếu `--clear` hoặc `--verify` thì `ctrl+a` trước khi nhập
- type hoặc paste
- `ctrl+a`
- `ctrl+c`
- verify exact text qua clipboard

`focus-write-verify` thêm một lớp trước đó:
- tìm cửa sổ theo opened-windows/taskbar match
- focus đúng app window
- resolve target theo focused/pattern/window heuristic
- rồi mới click/type-or-paste/verify

`focus-address-bar-open` là helper atomic riêng cho browser:
- focus browser window
- `ctrl+l`
- probe clipboard để pin đúng address bar/browser state
- replace/paste URL
- optional clipboard verify
- `enter`

Đây là path hiện tại tốt nhất cho desktop text-entry workflow nhiều cửa sổ. Với browser, address bar replacement trên Brave hiện đã ổn hơn rõ rệt nhờ specialized pinning; phần navigation outcome sau Enter vẫn nên được verify thêm nếu task quan trọng.

---

## Định hướng tiếp theo

### Tình trạng hiện tại sau phase 5
- `window-find` đã match được cửa sổ thật từ phần **Opened Windows**
- `focus-window` đã focus được app qua **Taskbar** button match
- `focus-write-verify` đã pass end-to-end trên Notepad với clipboard verification exact match
- resolver đã có tầng heuristic: focused token, window-scoped pattern, control-type filter, app-specific fallback
- Notepad path hiện tốt nhất là **heuristic editor + paste + ctrl+a + verify**
- đã thêm helper atomic `focus-address-bar-open` cho browser
- phase 6 đã cải thiện helper này bằng **specialized state pinning**: sau focus sẽ `Ctrl+L` rồi probe clipboard của address bar trước khi paste URL
- với path browser address bar trên Brave, flow này hiện đã pass verify thành công
- tuy vậy, verification hiện mới chứng minh **address bar replacement** ổn định hơn; navigation outcome sau Enter vẫn nên được kiểm thêm bằng browser-specific tooling nếu task quan trọng

### Nên làm tiếp
- thêm snapshot caching/state pinning trong cùng helper run thay vì snapshot lại rời rạc
- tăng độ ổn định cho browser atomic workflow, nhất là navigation outcome verification sau Enter
- cross-validate các intent đã pass trên family/app khác để chứng minh tính portable thay vì chỉ tối ưu thêm cho Facebook/Brave
- chuẩn hoá `send-composed-message` thành family pattern: pin surface -> search/select recipient -> verify recipient identity -> compose -> send -> post-send verify
- cải thiện semantic target resolution bên trong app, nhất là editor/control trung tâm
- nghiên cứu path ổn định hơn cho save/open dialog automation
- tiếp tục cải thiện snapshot post-processing vì text UI tree vẫn có mojibake ở một số glyph/chuỗi tiếng Việt

### Chưa cần làm ngay
- chưa cần tách full skill riêng cho Windows MCP khi doc/playbook này đã đủ dùng
- chỉ skill hoá khi workflow đã ổn định hơn và được dùng lặp lại thường xuyên

Khuyến nghị hiện tại:
- **doc trước, skill sau**

---

## Quy tắc cho phiên sau

Nếu task liên quan đến:
- computer-use trên Windows
- điều khiển app ngoài browser
- semantic desktop control
- `windows-mcp`
- bridge WSL -> Windows PowerShell

thì **đọc file này trước khi hành động**.
