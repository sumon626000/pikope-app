# Docker deployment (behind Traefik / Coolify)

Used on the client's VPS, where Coolify's Traefik proxy already owns ports
80/443. The stack (API, WebSocket server, cleanup loop, MySQL) runs as its own
compose project and only attaches to the proxy network; nothing else on the
server is touched.

```
/opt/billiard-poker/                 the backend/ folder (rsync, without .env)
/opt/billiard-poker/deploy/docker/.env   settings and secrets (chmod 600)
```

`.env` next to `docker-compose.yml`:

```
HOST_RULE=Host(`api.example.com`)     # Traefik rule; use || for several hosts
PROXY_NETWORK=coolify
DB_PASS=...            DB_ROOT_PASS=...
APP_URL=https://api.example.com
WS_PUBLIC_URL=wss://api.example.com/ws
ADMIN_USER=admin       ADMIN_PASS=...
MAIL_FROM=no-reply@example.com
APP_DEBUG=0  APP_TEST_HOOKS=0  RATE_LIMIT_FACTOR=1
```

Update after a code change:

```
rsync -az --delete --exclude .env --exclude dist --exclude tests \
  --exclude 'public/uploads/avatars/*' --exclude 'deploy/docker/.env' \
  backend/ root@SERVER:/opt/billiard-poker/
ssh root@SERVER 'cd /opt/billiard-poker/deploy/docker && docker compose up -d --build \
  && docker compose exec -T api php bin/migrate.php && docker compose exec -T api php bin/doctor.php'
```

Data lives in the `billiard-poker_db-data` and `billiard-poker_uploads` volumes.
The container has no mail transport, so password-reset mail is not delivered
until an SMTP relay is added.
