# Tsminal

> A self-hosted, browser-based terminal with a markdown notes panel — built for engineers, designed by KW.

Tsminal runs as a single Docker container. Open it in a browser and you get a full interactive shell on the left and a persistent markdown scratchpad on the right. Write commands in your notes, preview them as formatted markdown, and send any code block directly to the terminal with one click.

---

## Screenshot

```
┌─────────────────────────────────────────────────────────────────┐
│                              │  ▣ Notes          Saved   👁  🌙  │
│                              │──────────────────────────────────│
│   / #                        │  ## Deploy                       │
│   / # echo hello             │                                  │
│   hello                      │  ```                             │
│   / #                        │  kubectl apply -f deploy.yaml    │
│                              │  ```          ⌥ Run in terminal  │
│   (ttyd terminal)            │                                  │
│                              │  (markdown notes)                │
└─────────────────────────────────────────────────────────────────┘
```

---

## Features

| | Feature |
|---|---|
| 🖥️ | Full interactive terminal powered by [ttyd](https://github.com/tsl0922/ttyd) |
| 📝 | Markdown notes panel with live preview (GFM via [marked.js](https://github.com/markedjs/marked)) |
| ▶️ | **One-click "Run in terminal"** — sends any code block directly to the shell |
| 💾 | Auto-save to `localStorage` with debounce — notes survive a page refresh |
| 🎨 | IBM Carbon Design System v11 — Gray 100 (dark) / White (light) themes |
| 🌙☀️ | Theme toggle with `AsleepFilled` / `Awake` Carbon icons; persisted preference |
| 🔒 | No login, no auth — designed for trusted local / internal networks |
| 📦 | Single Docker image, single `docker run` command, zero external dependencies at runtime |

---

## Quick Start

```bash
# Build
docker build -t tsminal .

# Run
docker run -p 8080:8080 tsminal
```

Open **http://localhost:8080** in your browser.

---

## Architecture

```
Browser
  │
  │  http://localhost:8080
  ▼
┌─────────────────────────────────────┐
│  Nginx :8080  (Alpine container)    │
│                                     │
│  /          → index.html            │
│  /marked.min.js → marked.min.js     │
│  /ttyd/*    → proxy → ttyd :7681    │
└──────────────────┬──────────────────┘
                   │ WebSocket
                   ▼
             ttyd :7681
             (127.0.0.1 only)
                   │
                   ▼
             /bin/sh  (root)
```

| Component | Technology |
|---|---|
| Base image | `alpine:latest` |
| Terminal backend | ttyd 1.7.x |
| Markdown parser | marked.js (vendored at build time) |
| Static server / proxy | Nginx |
| Shell | `/bin/sh` as `root` |

---

## Project Structure

```
tsminal/
├── Dockerfile          # Single-stage Alpine build
├── nginx.conf          # Serves :8080, proxies /ttyd/ → ttyd :7681
├── start.sh            # Entrypoint: starts ttyd then nginx
├── frontend/
│   └── index.html      # Entire single-page UI (HTML + CSS + JS, no build step)
├── deploy/
│   └── openshift.yaml  # Namespace + Deployment + Service + Route manifests
├── SPEC.md             # Full product specification
├── README.md           # This file
├── .gitignore
└── .dockerignore
```

---

## How the Notes Panel Works

### Edit mode (default)
Type markdown directly into the textarea. Content is auto-saved to `localStorage` 500 ms after each keystroke. Closing and reopening the tab restores your notes.

### Preview mode
Click the **View** (👁) icon in the toolbar to render your markdown as formatted HTML. Click again to return to editing.

### Run in terminal
In preview mode, hover over any fenced code block. A **"⌥ Run in terminal"** button appears in the top-right corner of the block. Clicking it sends the code to the terminal shell via `iframe.contentWindow.term.input()` — the same WebSocket session the terminal panel already holds. No second connection is opened.

```markdown
# Example note

Install dependencies:

```sh
apk add curl jq
```
```

Hover the code block in preview → click **⌥ Run in terminal** → the command runs in the terminal on the left.

---

## Theme

The notes panel is styled using **IBM Carbon Design System v11** colour tokens.

| Mode | Theme | Key background |
|---|---|---|
| Dark (default) | Carbon Gray 100 | `#161616` / `#262626` |
| Light | Carbon White | `#ffffff` / `#f4f4f4` |

Toggle with the moon / sun icon in the toolbar. Choice is saved to `localStorage`.

---

## Configuration

The container has no required configuration. All defaults are built in:

| Setting | Value |
|---|---|
| Published port | `8080` |
| Default shell | `/bin/sh` |
| Default user | `root` |
| Auth | None |

To use a different shell (e.g. bash), rebuild after editing [`start.sh`](start.sh):

```sh
# start.sh — change /bin/sh to /bin/bash
ttyd ... /bin/bash &
```

---

## Deploying on OpenShift

### Prerequisites

Tsminal runs as `root` inside the container (ttyd requires a real login shell). OpenShift blocks this by default with the `restricted` SCC. Before applying the manifests, grant `anyuid` to the default service account in the target namespace:

```bash
oc adm policy add-scc-to-serviceaccount anyuid \
    -z default -n tsterminal
```

> This command requires cluster-admin privileges and only needs to be run once per namespace.

### Push your image

The manifest defaults to `tsterminal:latest`. Replace it with a fully qualified registry path before deploying:

```bash
docker build -t quay.io/<your-org>/tsterminal:latest .
docker push quay.io/<your-org>/tsterminal:latest

# Edit deploy/openshift.yaml and update the image: field, then:
oc apply -f deploy/openshift.yaml
```

### Deploy

```bash
# 1. Grant SCC (one-time, cluster-admin required)
oc adm policy add-scc-to-serviceaccount anyuid \
    -z default -n tsterminal

# 2. Apply all resources (Namespace, Deployment, Service, Route)
oc apply -f deploy/openshift.yaml

# 3. Watch the rollout
oc rollout status deployment/tsterminal -n tsterminal

# 4. Get the public URL
oc get route tsterminal -n tsterminal -o jsonpath='{.spec.host}'
```

The Route uses **TLS edge termination** — HTTPS is handled by the OpenShift router; HTTP requests are automatically redirected to HTTPS.

### Plain Kubernetes (non-OpenShift)

Replace the `Route` resource with a standard `Ingress`. The `Namespace`, `Deployment`, and `Service` manifests are vanilla Kubernetes-compatible.

---

## Requirements

- Docker (any recent version)
- Internet access at **build time only** — marked.js is fetched from jsDelivr during `docker build` and vendored into the image; no CDN calls at runtime.

---

## Security Note

Tsminal provides **unauthenticated root shell access**. It is designed for:

- Local development machines
- Internal / air-gapped lab environments
- Demo and presentation setups

**Do not expose port 8080 directly to the public internet.**  
Place a reverse proxy with authentication (e.g. Nginx + basic auth, Cloudflare Access) in front of it if remote access is needed.

---

## License

MIT
