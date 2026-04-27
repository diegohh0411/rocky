# Rocky Docker Compose Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a single `docker compose up -d` that starts opencode serve behind a Cloudflare tunnel with Cloudflare Access auth and a self-hosted Firecrawl instance wired via MCP.

**Architecture:** Six services on an internal Docker network (`rocky-net`): `opencode` (custom-built Node image), `cloudflared` (tunnel), `firecrawl-api` (pre-built GHCR image), `playwright-service`, `redis`, and `rabbitmq`. No host ports exposed. cloudflared routes external HTTPS traffic to opencode; opencode launches `npx firecrawl-mcp` as a subprocess pointed at the internal firecrawl-api container.

**Tech Stack:** Docker Compose v2, Node Alpine (opencode), cloudflare/cloudflared, ghcr.io/firecrawl/firecrawl, ghcr.io/firecrawl/playwright-service, redis:alpine, rabbitmq:3-management.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `.gitignore` | Create | Ignore `.env`, Docker build artifacts |
| `.env.example` | Create | Template with all required keys, empty values |
| `opencode/Dockerfile` | Create | Build opencode image from node:alpine |
| `opencode/opencode.jsonc` | Create | Rocky's isolated opencode config: Firecrawl MCP pointing at internal container |
| `docker-compose.yml` | Create | All 6 services, volumes, network |

---

## Task 1: Project skeleton

**Files:**
- Create: `.gitignore`
- Create: `.env.example`

- [ ] **Step 1: Create `.gitignore`**

```
.env
```

- [ ] **Step 2: Create `.env.example`**

```bash
# Cloudflare — get token from Zero Trust > Networks > Tunnels
CLOUDFLARE_TUNNEL_TOKEN=

# Subdomain you configured in the tunnel's Public Hostnames tab
TUNNEL_HOSTNAME=opencode.yourdomain.com

# Optional: only needed for Firecrawl's AI extract feature, not basic scraping
FIRECRAWL_OPENAI_API_KEY=
```

- [ ] **Step 3: Commit**

```bash
git add .gitignore .env.example
git commit -m "chore: add project skeleton"
```

---

## Task 2: opencode Dockerfile

**Files:**
- Create: `opencode/Dockerfile`

- [ ] **Step 1: Create `opencode/Dockerfile`**

```dockerfile
FROM node:alpine
RUN npm install -g opencode && mkdir -p /root/.config/opencode
```

`mkdir -p /root/.config/opencode` is required so Docker can bind-mount `opencode.jsonc` into that directory at runtime.

- [ ] **Step 2: Build the image to verify it works**

```bash
docker build ./opencode -t rocky-opencode-test
```

Expected: build completes, final line shows `Successfully built <id>` or similar. No errors.

- [ ] **Step 3: Verify opencode is installed in the image**

```bash
docker run --rm rocky-opencode-test opencode --version
```

Expected: prints a version string like `1.14.28`.

- [ ] **Step 4: Remove test image**

```bash
docker rmi rocky-opencode-test
```

- [ ] **Step 5: Commit**

```bash
git add opencode/Dockerfile
git commit -m "feat: add opencode Dockerfile"
```

---

## Task 3: opencode config

**Files:**
- Create: `opencode/opencode.jsonc`

- [ ] **Step 1: Create `opencode/opencode.jsonc`**

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

`FIRECRAWL_API_KEY` is required by the MCP package's schema but ignored by self-hosted Firecrawl — `"self-hosted"` is a safe placeholder. `FIRECRAWL_API_URL` points at the internal container hostname.

- [ ] **Step 2: Validate JSON syntax**

```bash
node -e "JSON.parse(require('fs').readFileSync('opencode/opencode.jsonc','utf8').replace(/\/\/.*/g,''))"
```

Expected: no output (exit 0). Any error means malformed JSON.

- [ ] **Step 3: Commit**

```bash
git add opencode/opencode.jsonc
git commit -m "feat: add opencode config with self-hosted Firecrawl MCP"
```

---

## Task 4: docker-compose.yml — opencode + cloudflared

**Files:**
- Create: `docker-compose.yml`

- [ ] **Step 1: Create `docker-compose.yml` with opencode and cloudflared only**

```yaml
networks:
  rocky-net:
    driver: bridge

volumes:
  opencode-data:

services:
  opencode:
    build: ./opencode
    command: "opencode serve --hostname 0.0.0.0 --port 4096 --print-logs --cors https://${TUNNEL_HOSTNAME}"
    volumes:
      - ./opencode/opencode.jsonc:/root/.config/opencode/opencode.jsonc:ro
      - opencode-data:/root/.local/share/opencode
    networks:
      - rocky-net
    restart: unless-stopped

  cloudflared:
    image: cloudflare/cloudflared:latest
    command: tunnel run --token ${CLOUDFLARE_TUNNEL_TOKEN}
    networks:
      - rocky-net
    restart: unless-stopped
    depends_on:
      - opencode
```

- [ ] **Step 2: Validate compose file syntax**

```bash
docker compose config --quiet
```

Expected: exits 0 with no output. Any error means invalid YAML or unresolved variable references.

Note: if you haven't created `.env` yet, create it now by copying `.env.example` and filling in real values — `docker compose config` needs the file to exist (values can be empty for this syntax check).

```bash
cp .env.example .env
```

- [ ] **Step 3: Build the opencode image via compose**

```bash
docker compose build opencode
```

Expected: `=> exporting to image` line at the end, exits 0.

- [ ] **Step 4: Commit**

```bash
git add docker-compose.yml
git commit -m "feat: add docker-compose with opencode and cloudflared services"
```

---

## Task 5: docker-compose.yml — Firecrawl stack

**Files:**
- Modify: `docker-compose.yml`

- [ ] **Step 1: Add `redis-data` volume and all four Firecrawl services to `docker-compose.yml`**

Replace the entire file with:

```yaml
networks:
  rocky-net:
    driver: bridge

volumes:
  opencode-data:
  redis-data:

services:
  opencode:
    build: ./opencode
    command: "opencode serve --hostname 0.0.0.0 --port 4096 --print-logs --cors https://${TUNNEL_HOSTNAME}"
    volumes:
      - ./opencode/opencode.jsonc:/root/.config/opencode/opencode.jsonc:ro
      - opencode-data:/root/.local/share/opencode
    networks:
      - rocky-net
    restart: unless-stopped
    depends_on:
      - firecrawl-api

  cloudflared:
    image: cloudflare/cloudflared:latest
    command: tunnel run --token ${CLOUDFLARE_TUNNEL_TOKEN}
    networks:
      - rocky-net
    restart: unless-stopped
    depends_on:
      - opencode

  firecrawl-api:
    image: ghcr.io/firecrawl/firecrawl:latest
    environment:
      ENV: local
      HOST: "0.0.0.0"
      PORT: "3002"
      REDIS_URL: redis://redis:6379
      REDIS_RATE_LIMIT_URL: redis://redis:6379
      PLAYWRIGHT_MICROSERVICE_URL: http://playwright-service:3000/scrape
      NUQ_RABBITMQ_URL: amqp://rabbitmq:5672
      USE_DB_AUTHENTICATION: "false"
      OPENAI_API_KEY: ${FIRECRAWL_OPENAI_API_KEY:-placeholder}
    networks:
      - rocky-net
    restart: unless-stopped
    depends_on:
      redis:
        condition: service_started
      playwright-service:
        condition: service_started
      rabbitmq:
        condition: service_healthy

  playwright-service:
    image: ghcr.io/firecrawl/playwright-service:latest
    environment:
      PORT: "3000"
    networks:
      - rocky-net
    restart: unless-stopped

  redis:
    image: redis:alpine
    command: redis-server --bind 0.0.0.0
    volumes:
      - redis-data:/data
    networks:
      - rocky-net
    restart: unless-stopped

  rabbitmq:
    image: rabbitmq:3-management
    command: rabbitmq-server
    networks:
      - rocky-net
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "-q", "check_running"]
      interval: 5s
      timeout: 5s
      retries: 3
      start_period: 5s
```

- [ ] **Step 2: Validate the full compose file**

```bash
docker compose config --quiet
```

Expected: exits 0, no output.

- [ ] **Step 3: Pull all pre-built images**

```bash
docker compose pull firecrawl-api playwright-service redis rabbitmq cloudflared
```

Expected: each image shows `Pull complete` or `Image is up to date`. If `firecrawl-api` pull fails with a 404/manifest error, the image name has changed upstream — check `https://github.com/mendableai/firecrawl/blob/main/docker-compose.yaml` for the current name and update it in `docker-compose.yml`.

- [ ] **Step 4: Start infrastructure services only to verify they come up**

```bash
docker compose up -d redis rabbitmq playwright-service
```

Expected: all three show `Started` or `Running`. Verify rabbitmq passes its healthcheck:

```bash
docker compose ps rabbitmq
```

Expected: `STATUS` column shows `healthy`.

- [ ] **Step 5: Stop infrastructure services**

```bash
docker compose down
```

- [ ] **Step 6: Commit**

```bash
git add docker-compose.yml
git commit -m "feat: add Firecrawl stack to docker-compose"
```

---

## Task 6: Full integration smoke test

**Prerequisites:** `.env` must have real values for `CLOUDFLARE_TUNNEL_TOKEN` and `TUNNEL_HOSTNAME` (Cloudflare dashboard setup must be complete per the spec's prerequisites).

- [ ] **Step 1: Start all services**

```bash
docker compose up -d
```

Expected: all 6 services show `Started` or `Running`.

- [ ] **Step 2: Verify all services are running**

```bash
docker compose ps
```

Expected: all 6 services in `running` state. `rabbitmq` should show `healthy`.

- [ ] **Step 3: Check opencode logs for successful startup**

```bash
docker compose logs opencode --tail 30
```

Expected: no fatal errors. Look for a line indicating the server is listening on `0.0.0.0:4096`.

- [ ] **Step 4: Check cloudflared logs for tunnel connection**

```bash
docker compose logs cloudflared --tail 20
```

Expected: a line containing `Connection registered` or `Registered tunnel connection`. If it shows `failed to authenticate`, the `CLOUDFLARE_TUNNEL_TOKEN` in `.env` is wrong.

- [ ] **Step 5: Check firecrawl-api logs for startup**

```bash
docker compose logs firecrawl-api --tail 20
```

Expected: no fatal errors. If you see `ECONNREFUSED` for rabbitmq, wait 10 seconds and re-check — rabbitmq can be slow to start.

- [ ] **Step 6: Verify Firecrawl API responds internally**

```bash
docker compose exec opencode wget -qO- http://firecrawl-api:3002/health 2>/dev/null || \
  docker compose exec opencode wget -qO- http://firecrawl-api:3002/ 2>/dev/null | head -5
```

Expected: JSON response or HTML indicating the API is up. A connection refused means firecrawl-api isn't healthy yet — give it 30 seconds and retry.

- [ ] **Step 7: Open the tunnel URL in a browser**

Navigate to `https://<TUNNEL_HOSTNAME>`. Expected: Cloudflare Access login page. After logging in, the opencode interface should load.

- [ ] **Step 8: Connect an AI provider in opencode**

In the opencode TUI, run `/connect` and follow the prompts to add your OpenRouter (or other) provider. Credentials are saved to the `opencode-data` volume.

- [ ] **Step 9: Verify Firecrawl MCP is available**

In opencode, ask it to scrape a URL (e.g., "use Firecrawl to scrape https://example.com"). Expected: it calls the Firecrawl MCP tool successfully.

- [ ] **Step 10: Final commit**

```bash
git add .
git commit -m "chore: complete Rocky docker-compose setup"
```
