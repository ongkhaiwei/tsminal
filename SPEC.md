# Tsminal — Product Specification

## Overview

**Tsminal** is a self-hosted, browser-based terminal application built as a single Docker container.  
It is designed for engineers who need a persistent command-line environment alongside a scratchpad for commands, notes, and snippets.

No authentication is required. The application is intended for use on a trusted local network or behind an existing reverse proxy.

---

## Application Identity

| Property | Value |
|---|---|
| Application name | **Tsminal** |
| Browser tab title | `Tsminal — Designed by KW` |
| Favicon | Carbon `Terminal` icon (32px SVG, inline data URI, `#f4f4f4` fill) |
| UI icon | Carbon `Terminal` 32px icon scaled to 16px, inlined next to the "Notes" toolbar heading |

---

## Architecture

| Layer | Technology |
|---|---|
| Container base | Alpine Linux (latest stable) |
| Terminal backend | [ttyd](https://github.com/tsl0922/ttyd) |
| Markdown parser | [marked.js](https://github.com/markedjs/marked) v11 — vendored into the image at build time via `curl` |
| Note panel frontend | Single-page HTML/JS served by Nginx on Alpine |
| Container shell | `/bin/sh` (Alpine default), running as `root` |

The container exposes **two internal ports**, of which only one is published:

| Port | Service | Visibility |
|---|---|---|
| `7681` | ttyd WebSocket terminal | Internal only — proxied by Nginx; not published to the host |
| `8080` | Static frontend (the split-panel UI) | Published (`-p 8080:8080`) |

The frontend at port `8080` embeds the ttyd terminal in an `<iframe src="/ttyd/">` on the left panel and renders the notes editor on the right panel. Nginx proxies all `/ttyd/` traffic (HTTP + WebSocket) to ttyd on port `7681`.

### Request flow

```
Browser (port 8080)
  │
  ├─ GET /          → Nginx → frontend/index.html
  ├─ GET /marked.min.js → Nginx → /usr/share/nginx/html/marked.min.js
  └─ /ttyd/*  (HTTP + WS) → Nginx proxy_pass → ttyd :7681
                                                  │
                                                  └─ /bin/sh  (root pty)
```

### Nginx proxy rule (critical implementation detail)

```nginx
location /ttyd/ {
    proxy_pass http://127.0.0.1:7681;   # NO trailing slash — preserves /ttyd/ prefix
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
}
```

> **Warning:** a trailing slash on `proxy_pass` rewrites the URI path and breaks the ttyd WebSocket handshake.

### ttyd startup flag (critical implementation detail)

ttyd must be launched with `--base-path /ttyd` so its internal routing matches what Nginx forwards:

```sh
ttyd --base-path /ttyd -p 7681 /bin/sh &
```

### Terminal input injection (critical implementation detail)

The notes panel sends code to the terminal via the iframe's existing WebSocket session — no second connection is opened:

```js
const iframe = document.querySelector('#terminal-frame');
iframe.contentWindow.term.input(code + '\n');
```

`window.term` is the xterm.js instance exposed by ttyd. The iframe is same-origin (`localhost:8080`), so no cross-origin restrictions apply.

---

## Features

### 1. Web Terminal (Left Panel)
- Occupies **70%** of the viewport width.
- Powered by ttyd; renders a full interactive terminal in the browser via an `<iframe src="/ttyd/">`.
- The default shell is `/bin/sh` running as `root`.
- The terminal must fill the full height of the viewport.
- Terminal resize (SIGWINCH) must work correctly when the browser window is resized.

### 2. Notes Panel (Right Panel)
- Occupies the remaining **30%** of the viewport width.
- Contains a **toolbar** (40px, Carbon UI Shell action bar style) and a **content area** below it.
- The content area toggles between **Edit mode** (markdown textarea) and **Preview mode** (rendered HTML), controlled by a toolbar button.

#### 2a. Toolbar
The toolbar is always visible at the top of the notes panel. Left to right:

| Element | Description |
|---|---|
| Carbon `Terminal` icon + **Notes** label | App identity; uses Carbon `$heading-compact-01` type token (14px / 600 weight) |
| Save indicator | `Saving…` / `Saved` status text in Carbon `$label-01` (12px), positioned immediately to the right of the title |
| Flexible spacer | Pushes action buttons to the right edge |
| **Preview toggle** | Carbon `View` 16px icon (ghost button); toggles between Edit and Preview mode |
| **Theme toggle** | Carbon `AsleepFilled` 32px (dark mode) / `Awake` 16px (light mode) icon (ghost button); switches the notes panel theme |

All toolbar action buttons use the Carbon **ghost icon button** pattern: 32×32px square, transparent background at rest, `$icon-hover-bg` on hover, `2px solid $focus` inset focus ring, Carbon `fast-02` motion (70 ms).

#### 2b. Edit Mode (default)
- A full-height `<textarea>` styled as a Carbon TextArea:
  - Background `$field-01`, `1px $border-strong-01` bottom border, no border on other sides.
  - Focus: `2px solid $focus` inset outline.
  - Hover: background transitions to `$field-hover-01`.
  - Font: IBM Plex Mono, 14px (`$body-compact-01`), 16px (`$spacing-05`) horizontal padding.
- Placeholder text: `"Write markdown here…"`.
- Supports GFM (GitHub-Flavoured Markdown): fenced code blocks, tables, blockquotes, inline code.

#### 2c. Preview Mode
- Activated by clicking the **View** toolbar button (`aria-pressed="true"` when active).
- Renders the textarea content as HTML using **marked.js** (GFM + soft line breaks enabled).
- Clicking the button again returns to Edit mode and restores focus to the textarea.
- All rendered elements are styled with Carbon tokens (see token table in §2e).

##### Code block "Run in terminal" button
Every fenced code block (`<pre><code>`) in the preview renders a **"⌥ Run in terminal"** button:
- Positioned `absolute` top-right of the `<pre>` block; hidden (`opacity:0`) until the block is hovered.
- On click: reads `code.innerText`, appends `\n` if absent, and calls `iframe.contentWindow.term.input()` to send the text directly to the pty via the iframe's existing ttyd WebSocket session.
- Confirmation: button text changes to `"✓ Sent"` with Carbon `$support-success` colour for 1.5 s, then resets.
- Uses Carbon ghost button styling: 24px height, `$border-subtle-00` border, `$text-secondary` text.

#### 2d. Auto-save
- Note content is automatically saved to `localStorage` (key: `tsminal_notes`) using a **500 ms debounce** after each keystroke.
- On page load, previously saved content is restored from `localStorage`.
- The save indicator in the toolbar shows `Saving…` while the debounce is pending, then `Saved` (in `$support-success` green) for 2 seconds, then clears.
- Auto-save runs in Edit mode only; switching to Preview mode does not trigger a save.

#### 2e. Dark / Light Theme
The notes panel colour system follows the **IBM Carbon Design System v11**.

**Dark mode (default) — Carbon Gray 100 theme:**

| Role | Carbon token | Hex |
|---|---|---|
| Page / toolbar background | `$background` | `#161616` |
| Panel / field background | `$layer-01` / `$field-01` | `#262626` / `#393939` |
| Primary text | `$text-primary` | `#f4f4f4` |
| Secondary / helper text | `$text-secondary` / `$text-helper` | `#c6c6c6` / `#8d8d8d` |
| Placeholder text | `$text-placeholder` | `#6f6f6f` |
| Divider / subtle border | `$border-subtle-00` | `#393939` |
| Field bottom border | `$border-strong-01` | `#6f6f6f` |
| Focus ring | `$focus` (inverted) | `#ffffff` |
| Save success colour | `$support-success-inverse` | `#42be65` |

**Light mode — Carbon White theme:**

| Role | Carbon token | Hex |
|---|---|---|
| Page / toolbar background | `$background` | `#ffffff` |
| Panel / field background | `$layer-01` / `$field-01` | `#f4f4f4` |
| Primary text | `$text-primary` | `#161616` |
| Secondary / helper text | `$text-secondary` / `$text-helper` | `#525252` / `#6f6f6f` |
| Placeholder text | `$text-placeholder` | `#a8a8a8` |
| Divider / subtle border | `$border-subtle-00` | `#e0e0e0` |
| Field bottom border | `$border-strong-01` | `#8d8d8d` |
| Focus ring | `$focus` | `#0f62fe` |
| Save success colour | `$support-success` | `#24a148` |

**Theme behaviour:**
- The page body background is always `#161616` (Carbon Gray 100 `$background`).
- On first load with no saved preference, the OS `prefers-color-scheme` is checked; dark is the fallback.
- Theme preference is persisted to `localStorage` (key: `tsminal_theme`) and restored on the next page load.
- Theme toggle icon: **`AsleepFilled`** (crescent moon, 32px) shown in dark mode → click to go light; **`Awake`** (sun with rays, 16px) shown in light mode → click to go dark. Both are Carbon icons inlined as SVG.
- Theme switching affects only the notes panel and its toolbar; the terminal iframe is unaffected.

**Typography:**
- UI chrome (toolbar, preview body): IBM Plex Sans → Helvetica Neue → Arial.
- Notes textarea and code blocks: IBM Plex Mono → Menlo → Consolas.
- Base font size: **110%** of the browser default (scales all `rem`-based sizes for improved readability during presentations).

### 3. Layout
- The two panels are displayed side-by-side on a single page with no visible gap or overlap.
- A **1px** vertical divider (`$border-subtle-00`) separates the terminal (left) and notes (right) panels.
- The notes panel includes a 40px toolbar row at the top; this is part of the 30% panel width.
- No additional header, footer, sidebar, or navigation chrome is present.
- Scroll is contained within each panel independently; no outer page scroll.

---

## Acceptance Criteria

| # | Criterion | Pass condition |
|---|---|---|
| AC-1 | Terminal panel width | Terminal occupies exactly 70% of the viewport width at any viewport size ≥ 1024 px wide. |
| AC-2 | Notes panel width | Notes panel occupies exactly 30% of the viewport width at the same breakpoint. |
| AC-3 | Full-height panels | Both panels extend to 100% of the viewport height with no outer scroll. |
| AC-4 | Terminal is functional | An interactive shell session opens automatically on page load with no additional user action. |
| AC-5 | Default user is root | The shell session runs as the `root` user (`whoami` returns `root`). |
| AC-6 | Notes panel is editable | Text can be freely typed and deleted inside the notes panel. |
| AC-7 | Single container | The application runs with a single `docker run` command and no external dependencies. |
| AC-8 | Deterministic startup | The container starts cleanly with a single `docker run -p 8080:8080 tsminal` command. |
| AC-9 | No authentication | No login screen, token, or password prompt is presented to the user. |
| AC-10 | Terminal resize | The terminal columns/rows update correctly when the browser window is resized. |
| AC-11 | Notes auto-save | Typing in the notes panel persists content to `localStorage`; content is restored after a page refresh. |
| AC-12 | Save status indicator | The toolbar shows `Saving…` during the debounce window and `Saved` briefly after the write completes. |
| AC-13 | Dark mode default | The notes panel renders in Carbon Gray 100 theme by default when no OS or saved preference exists. |
| AC-14 | Theme toggle | Clicking the toolbar toggle switches between Carbon Gray 100 (dark) and White (light) and persists the choice across refreshes. |
| AC-15 | OS theme detection | On first load with no saved preference, the panel adopts the OS `prefers-color-scheme` setting. |
| AC-16 | Carbon typography | The notes textarea uses IBM Plex Mono; toolbar and UI chrome uses IBM Plex Sans. |
| AC-17 | Markdown preview | Clicking the View toolbar button renders the textarea content as GFM HTML. |
| AC-18 | Code block run button | Every `<pre>` block in the preview shows a "Run in terminal" button on hover; clicking it sends the code to the terminal pty and shows a "✓ Sent" confirmation. |
| AC-19 | Carbon icons | The preview toggle uses the Carbon `View` icon; the theme toggle uses `AsleepFilled` (dark) / `Awake` (light); the Notes title uses the `Terminal` icon. |
| AC-20 | Application title | The browser tab reads `Tsminal — Designed by KW`; the favicon is the Carbon `Terminal` SVG icon. |
| AC-21 | Presentation zoom | The entire notes panel UI is rendered at 110% of the browser's default base font size. |

---

## Docker / Build Requirements

- **Base image**: `alpine:latest` (or a pinned stable version).
- **Dockerfile** is the single source of truth for the runtime environment; no `docker-compose` or external orchestration is required.
- `ttyd`, `nginx`, and `curl` are installed via `apk add --no-cache`.
- **marked.js** is downloaded from jsDelivr (`cdn.jsdelivr.net/npm/marked/marked.min.js`) at image build time using `curl` and placed in `/usr/share/nginx/html/marked.min.js`. No CDN dependency at runtime.
- Nginx serves the frontend assets on port `8080` and proxies `/ttyd/` (HTTP + WebSocket) to ttyd on `127.0.0.1:7681`.
- Both ttyd and Nginx are started by a single `start.sh` entrypoint script inside the container.
- The container requires no volumes, bind mounts, or environment variables to start.

### Project file layout

```
tsminal/
├── Dockerfile              # Single-stage Alpine build
├── nginx.conf              # Serves :8080, proxies /ttyd/ → ttyd :7681
├── start.sh                # Entrypoint: starts ttyd then nginx
├── frontend/
│   └── index.html          # Entire single-page UI (HTML + CSS + JS, no build step)
├── deploy/
│   └── openshift.yaml      # Namespace + Deployment + Service + Route manifests
├── SPEC.md                 # This file — full product specification
├── README.md               # User-facing documentation
├── .gitignore
└── .dockerignore
```

### Build and run commands

```bash
# Build the image
docker build -t tsminal .

# Run locally
docker run --rm -p 8080:8080 tsminal

# Open in browser
open http://localhost:8080
```

---

## Deployment — OpenShift / Kubernetes

### Overview

The application is deployed via [`deploy/openshift.yaml`](deploy/openshift.yaml), which contains four manifests applied in a single `oc apply`:

| # | Kind | Name | Purpose |
|---|---|---|---|
| 1 | `Namespace` | `tsterminal` | Project isolation; omit if deploying into an existing namespace |
| 2 | `Deployment` | `tsterminal` | Runs the container (1 replica) |
| 3 | `Service` | `tsterminal` | Cluster-internal ClusterIP on port 8080 |
| 4 | `Route` | `tsterminal` | OpenShift router; TLS edge termination, HTTP→HTTPS redirect |

### Security context

ttyd requires a real login shell and opens a pty as `root`. OpenShift's default `restricted` SCC blocks this. The following is required before deploying:

```bash
# Grant the anyuid SCC to the default service account in the target namespace
oc adm policy add-scc-to-serviceaccount anyuid \
    -z default -n tsterminal
```

The pod security context is set as follows:

```yaml
securityContext:
  runAsUser: 0           # root — required by ttyd
  runAsNonRoot: false
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

`allowPrivilegeEscalation: false` and `capabilities.drop: ALL` are compatible with `runAsUser: 0` and are included for defence-in-depth.

### Image registry

The `Deployment` manifest defaults to `tsterminal:latest`. Before deploying to a cluster, replace this with a fully qualified registry path:

```yaml
image: quay.io/<your-org>/tsterminal:latest
```

Push the image before applying the manifests:

```bash
docker build -t quay.io/<your-org>/tsterminal:latest .
docker push quay.io/<your-org>/tsterminal:latest
```

### Apply the manifests

```bash
# 1. Grant SCC (one-time, requires cluster-admin)
oc adm policy add-scc-to-serviceaccount anyuid \
    -z default -n tsterminal

# 2. Apply all manifests
oc apply -f deploy/openshift.yaml

# 3. Watch rollout
oc rollout status deployment/tsterminal -n tsterminal

# 4. Get the Route URL
oc get route tsterminal -n tsterminal -o jsonpath='{.spec.host}'
```

### Resource limits

The `Deployment` defines conservative resource requests and limits suitable for a single-user demo environment:

| | CPU | Memory |
|---|---|---|
| Request | `100m` | `64Mi` |
| Limit | `500m` | `256Mi` |

Adjust these values in [`deploy/openshift.yaml`](deploy/openshift.yaml) for higher concurrency or larger shell workloads.

### Health probes

Both readiness and liveness probes perform an HTTP GET on port `8080 /`:

| Probe | Initial delay | Period | Failure threshold |
|---|---|---|---|
| Readiness | 5 s | 10 s | 3 |
| Liveness | 10 s | 30 s | 3 |

### Plain Kubernetes (non-OpenShift)

Replace the `Route` with a standard `Ingress` resource and handle TLS at the ingress controller level. The `Namespace`, `Deployment`, and `Service` manifests are fully compatible with vanilla Kubernetes.

---

## Out of Scope

- Authentication or authorisation of any kind.
- Server-side or database-backed note storage (notes are persisted client-side via `localStorage` only).
- Multiple simultaneous terminal sessions or session multiplexing.
- Mobile or touch-screen layout optimisation.
- HTTPS / TLS termination (handle externally if needed).
- Resizable panel divider (drag-to-resize).
- Theming of the terminal panel (terminal colours are controlled by ttyd).
- Syntax highlighting inside code blocks in the markdown preview.

---

## Implementation Constraints

- Do not add features, libraries, or configuration that are not listed in this specification.
- marked.js must be vendored into the Docker image at build time; it must not be loaded from an external CDN at runtime.
- All colour values in the notes panel must trace to a named IBM Carbon v11 token.
- The frontend is a single `frontend/index.html` file — no bundler, no build step, no npm dependencies.
- The `deploy/openshift.yaml` manifest must remain self-contained; no Helm chart or Kustomize overlay is required.
