# Rocky — Docker Compose Design

**Date:** 2026-04-27
**Status:** Approved

## Overview

A single `docker compose up -d` spins up a self-contained environment with:
- `opencode serve` running as a headless AI coding server
- Firecrawl (self-hosted) wired to opencode via MCP
- A Cloudflare tunnel exposing opencode externally, protected by Cloudflare Access

---

## Architecture

```
Internet
   │
   ▼
[Cloudflare Edge]  ← Access policy enforces auth (configured once in dashboard)
   │  (encrypted tunnel)
   ▼
[cloudflared]  ← routes to opencode via internal Docker network
   │
   ▼
[opencode]  ← opencode serve, port 4096
   │  (MCP subprocess: npx firecrawl-mcp)
   ▼
[firecrawl-api]  ← Firecrawl HTTP API, port 3002
   ├── [firecrawl-worker]  ← background job processor
   ├── [playwright]  ← headless browser for JS-heavy pages, port 3000
   └── [redis]  ← job queue
```

All services share an internal Docker network (`rocky-net`). No ports are exposed on the host. Only `cloudflared` has external connectivity via the Cloudflare tunnel. Firecrawl is invisible to the outside world.

---

## Services

| Service | Image | Role |
|---|---|---|
| `opencode` | built from `opencode/Dockerfile` | `opencode serve`, port 4096 |
| `cloudflared` | `cloudflare/cloudflared:latest` | Tunnel to Cloudflare edge |
| `firecrawl-api` | `ghcr.io/mendableai/firecrawl` ¹ | Firecrawl HTTP API |
| `firecrawl-worker` | `ghcr.io/mendableai/firecrawl` ¹ | Background job processor |
| `playwright` | `ghcr.io/mendableai/firecrawl-playwright` ¹ | Headless browser |
| `redis` | `redis:alpine` | Job queue for Firecrawl |

¹ Firecrawl image names to be verified against the current [Firecrawl self-hosted docker-compose](https://github.com/mendableai/firecrawl) during implementation.

---

## Configuration

### `.env` (gitignored)

```bash
# Cloudflare tunnel token — from Zero Trust dashboard
CLOUDFLARE_TUNNEL_TOKEN=

# Subdomain to expose opencode on
TUNNEL_HOSTNAME=opencode.yourdomain.com
```

### `.env.example` (committed)

Same structure as `.env` with empty values — serves as a template for new users.

---

## File Layout

```
rocky/
├── docker-compose.yml
├── opencode/
│   ├── Dockerfile          # node:alpine + npm install -g opencode
│   └── opencode.jsonc      # Rocky's isolated opencode config
├── .env.example
├── .env                    # gitignored
└── .gitignore
```

### `opencode/opencode.jsonc`

Rocky's own opencode config — not shared with the host. Firecrawl MCP is enabled and pointed at the internal `firecrawl-api` container:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "Firecrawl": {
      "type": "local",
      "enabled": true,
      "command": ["npx", "-y", "firecrawl-mcp"],
      "environment": {
        "FIRECRAWL_API_KEY": "self-hosted",
        "FIRECRAWL_API_URL": "http://firecrawl-api:3002"
      }
    }
  }
}
```

No provider/model config — users configure AI providers by running `opencode` and using `/connect` in the TUI after first startup.

### `opencode/Dockerfile`

```dockerfile
FROM node:alpine
RUN npm install -g opencode
```

### `docker-compose.yml` (structure)

- `opencode`: built locally, mounts `opencode.jsonc` read-only, named volume for data persistence
- `cloudflared`: runs `tunnel run --token $CLOUDFLARE_TUNNEL_TOKEN`
- `firecrawl-api` + `firecrawl-worker`: share same image and env
- `playwright` + `redis`: supporting Firecrawl services

---

## Volumes

| Volume | Purpose |
|---|---|
| `opencode-data` | Persists `/root/.local/share/opencode` — auth.json (provider API keys), sessions, history |
| `redis-data` | Persists Redis job queue |

Provider credentials configured via `/connect` in the opencode TUI survive container restarts via `opencode-data`.

---

## opencode serve flags

```
opencode serve --hostname 0.0.0.0 --port 4096 --cors ${TUNNEL_HOSTNAME}
```

- `--hostname 0.0.0.0`: required in Docker so other containers can reach it (default is 127.0.0.1)
- `--port 4096`: fixed port for cloudflared to route to
- `--cors`: allows requests from the Cloudflare tunnel hostname

---

## Cloudflare Prerequisites (one-time setup)

Before running `docker compose up -d`, perform these steps in the Cloudflare Zero Trust dashboard:

1. **Create tunnel**: Zero Trust → Networks → Tunnels → Create tunnel → copy token → paste into `.env` as `CLOUDFLARE_TUNNEL_TOKEN`
2. **Add public hostname**: in the tunnel's Public Hostnames tab, add route: `$TUNNEL_HOSTNAME` → `http://opencode:4096`
3. **Create Access application**: Zero Trust → Access → Applications → create app for `$TUNNEL_HOSTNAME`
4. **Set access policy**: e.g., allow specific email addresses or an email domain

After this one-time setup, the tunnel and auth are fully managed by Cloudflare — no further dashboard interaction needed.

---

## First Run Flow

1. Clone repo
2. Copy `.env.example` → `.env`, fill in `CLOUDFLARE_TUNNEL_TOKEN` and `TUNNEL_HOSTNAME`
3. `docker compose up -d`
4. Open `https://$TUNNEL_HOSTNAME` in browser → Cloudflare Access login prompt
5. After login, opencode TUI loads → run `/connect` to configure AI provider(s)
6. Provider credentials are saved to `opencode-data` volume — persists across restarts

---

## Restart Behavior

All services use `restart: unless-stopped`. On `docker compose up -d` after a restart:
- opencode reconnects to Firecrawl via MCP automatically
- cloudflared reconnects the tunnel automatically
- Auth credentials (auth.json) are intact in the `opencode-data` volume
