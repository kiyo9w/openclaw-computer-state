# LOCAL_FRONTEND_UI_VALIDATION.md

Workflow record for validating a local web UI from the current WSL/OpenClaw host through the real Windows browser.

This is not a pure `computer-workflow` replay. It is a hybrid procedure: WSL processes provide the app/API, Windows Chrome/Brave renders the real page, and `openclaw-computer-state`/Windows CDP provide observation and interaction. Use it when a feature needs production-readiness UI validation but the full local stack is partially unavailable.

Verified on 2026-05-29 while hardening Insider's admin model settings / LiteLLM control plane.

## When To Use

- A frontend route must be checked in the real Windows browser from WSL.
- Local Docker/Postgres/full backend is not available, but a narrow mock API can reproduce the route's data contract.
- Linux Playwright browsers are unavailable or unsupported on the WSL distro.
- The task needs actual visual/layout checks, not only typecheck/build.

## Preconditions

- Windows browser CDP is reachable. Check with:

```bash
scripts/winbrowser --action status
```

- If the API runs inside WSL and the browser runs on Windows, bind the API to `0.0.0.0`, not `127.0.0.1`.
- Use the WSL IP in browser-facing API URLs:

```bash
hostname -I | awk '{print $1}'
```

- Do not store plaintext credentials in workflow records, logs, screenshots, or memory.
- If any test-only patch is made to bypass middleware/session bootstrapping, revert it before calling the result production-ready.

## Sequence

1. Pull project context first: current diff, target route, API schema, existing docs, and recent memory.
2. Try the real backend/full stack. If blocked by missing Docker/Postgres/seed state, switch to a narrow mock API that matches the actual response shapes.
3. Start the mock API on WSL, binding to all interfaces:

```bash
HOST=0.0.0.0 PORT=8000 node /tmp/local-mock-api.js
```

4. Start the frontend with a Windows-reachable API base:

```bash
NEXT_PUBLIC_API_URL=http://<WSL_IP>:8000 pnpm exec next dev -H 127.0.0.1 -p 3010
```

5. Focus the Windows browser, then use Windows browser CDP or the replayable route check. The workflow now starts with a read-only foreground assertion, so it fails before typing if another app is focused:

```bash
scripts/computer-workflow replay \
  --file examples/workflows/win-local-frontend-route-check.json \
  --var URL=http://localhost:3010/en/admin/model-settings \
  --var EXPECT="Admin Model Control Plane"
```

6. Collect objective UI evidence:

- page URL and title
- visible route heading
- console errors
- network failures
- raw i18n key scan
- horizontal overflow at desktop and mobile viewport widths
- screenshot path

7. Patch only real product issues found by the check. Do not leave mock-only or middleware-only changes in the product diff.
8. Re-run the same checks after the patch.
9. Stop local processes and verify no dev server/mock server remains running.
10. Run the smallest meaningful gates for the changed area: typecheck, scoped lint, build, backend tests, and diff hygiene.

## Remote Backend Mode

If the backend is already deployed and local backend setup is unnecessary, prefer a local browser-facing proxy instead of pointing the frontend directly at the remote API:

```bash
# Browser origin: http://localhost:3010
# Local API proxy: http://localhost:3011 -> https://insider.horseai.io
NEXT_PUBLIC_API_URL=http://localhost:3011 pnpm exec next dev -H localhost -p 3010
```

Reason: a local frontend that calls `https://insider.horseai.io` directly can be blocked by browser CORS and CSRF cookie rules even when the same deployed frontend works. The proxy keeps the browser same-site on `localhost`, forwards requests server-to-server to the remote backend, and lets CSRF/session cookies be set for the local test origin.

Also start Next with `-H localhost` when using `next-intl` `localePrefix: "never"`. Starting on `127.0.0.1` and browsing through `localhost` can produce a local-only redirect loop around `/auth/login`.

## Pitfalls

- `127.0.0.1` means different things from WSL and Windows. A Windows browser cannot reach a WSL-only API bound to WSL localhost.
- Linux Playwright browser install can fail on this host; Windows CDP is the better fallback for browser validation.
- Remote credentials can be stale or environment-specific. A 401 on remote login should not block local route validation if the local data contract is known.
- Middleware/session shortcuts are acceptable only as a temporary validation harness. Revert them immediately.
- Screenshot-only validation is not enough. Pair screenshots with DOM/text/console/network assertions.
- Mobile sync or unrelated dirty-tree changes must be quarantined from feature-readiness conclusions.

## Evidence From 2026-05-29

- Feature: Insider admin model settings / LiteLLM control plane.
- Full local stack was blocked by unavailable Docker/shared Postgres on WSL.
- Linux Playwright Chromium install was unsupported on the current WSL distro.
- Mock API plus Windows Chrome CDP rendered the route successfully.
- The validation found visible raw i18n keys for model roles; patching `frontend/messages/en.json` and `frontend/messages/vi.json` fixed them.
- Desktop and mobile viewport checks had no horizontal overflow after the fix.
- Frontend typecheck, scoped ESLint, and production build passed after the fix.
- Backend focused tests and resolver/control-plane tests passed.
- Screenshot evidence was saved in the Insider repo at `.context/ui-test-screenshots/model-settings-local-fixed.png`.
