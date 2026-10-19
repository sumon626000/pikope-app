# Deploying the backend

You need: PHP 8.1+ (64-bit) with `pdo_mysql`, `mbstring`, `fileinfo`; MySQL 8
or MariaDB 10.5+; HTTPS on the address the app will call.

`bin/package.sh` builds `dist/billiard-poker-backend.zip` with exactly the
files a server needs (no tests, no `.env`).

## A. Shared hosting with cPanel

1. **Database** - cPanel > MySQL Databases: create a database and a user, add
   the user to the database with all privileges. Note the three names and the
   password.
2. **Subdomain** - cPanel > Domains: create `api.yourdomain.com` and set its
   document root to `billiard-poker/public` (cPanel lets you type the folder).
   Turn on SSL for it (AutoSSL / Let's Encrypt).
3. **Upload** - File Manager: upload `billiard-poker-backend.zip` to your home
   directory and extract it. You should now have `~/billiard-poker/public`,
   `~/billiard-poker/src`, ... Only `public/` is reachable from the web.
4. **Configure** - copy `billiard-poker/.env.example` to `billiard-poker/.env`
   and fill in the database names, `APP_URL=https://api.yourdomain.com`,
   `MAIL_FROM`, and an `ADMIN_USER` / `ADMIN_PASS` if you want the admin page.
5. **PHP version** - cPanel > MultiPHP Manager: PHP 8.1 or newer for the
   subdomain.
6. **Create the tables** - cPanel > Terminal (or SSH):
   `cd ~/billiard-poker && php bin/migrate.php && php bin/doctor.php`.
   No terminal? Open phpMyAdmin, pick the database, Import `sql/schema.sql`.
7. **Cron** - cPanel > Cron Jobs, every 5 minutes:
   `php /home/YOURUSER/billiard-poker/bin/cleanup.php >/dev/null 2>&1`
8. **Check** - open `https://api.yourdomain.com/health`; it must answer
   `{"ok":true,...}`.

If the host does not let you choose the document root, put the *contents* of
`public/` into `public_html/api/`, keep the rest in `~/billiard-poker/`, and
in `public_html/api/index.php` change the last `require` to
`require '/home/YOURUSER/billiard-poker/src/bootstrap.php';`. Then
`APP_URL=https://yourdomain.com/api`.

## B. A VPS (Ubuntu)

```bash
sudo apt install nginx mysql-server php8.3-fpm php8.3-mysql php8.3-mbstring unzip certbot python3-certbot-nginx
sudo mysql -e "CREATE DATABASE billiard_poker CHARACTER SET utf8mb4;
  CREATE USER 'billiard_poker'@'localhost' IDENTIFIED BY 'A-STRONG-PASSWORD';
  GRANT ALL ON billiard_poker.* TO 'billiard_poker'@'localhost';"
sudo mkdir -p /var/www/billiard-poker && sudo unzip billiard-poker-backend.zip -d /var/www/
cd /var/www/billiard-poker && sudo cp .env.example .env && sudo nano .env
sudo chown -R www-data:www-data public/uploads && sudo chmod 640 .env && sudo chown root:www-data .env
php bin/migrate.php && php bin/doctor.php
sudo cp deploy/nginx.conf.example /etc/nginx/sites-available/billiard-poker   # edit names/paths
sudo ln -s /etc/nginx/sites-available/billiard-poker /etc/nginx/sites-enabled/ && sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d api.yourdomain.com
sudo cp deploy/billiard-poker-ws.service.example /etc/systemd/system/billiard-poker-ws.service
sudo systemctl daemon-reload && sudo systemctl enable --now billiard-poker-ws   # live play
( crontab -l 2>/dev/null; echo "*/5 * * * * php /var/www/billiard-poker/bin/cleanup.php >/dev/null 2>&1" ) | crontab -
```

## Live play (WebSockets)

Matches run over a WebSocket: every move reaches the other players at once.
That needs one PHP process that stays running, `bin/ws-server.php`.

**VPS**

```bash
sudo cp deploy/billiard-poker-ws.service.example /etc/systemd/system/billiard-poker-ws.service
sudo systemctl daemon-reload && sudo systemctl enable --now billiard-poker-ws
```

The nginx / Apache examples already forward `/ws` to it. Then set in `.env`:
`WS_PUBLIC_URL=wss://api.yourdomain.com/ws` and check that
`https://api.yourdomain.com/config` shows that address.

**Shared hosting (cPanel)** usually cannot keep a process running or forward
WebSockets. Two options:

- Leave `WS_PUBLIC_URL` empty. The app then plays over HTTP, asking the server
  for news every 0.6 seconds. Everything works; moves just arrive a fraction of
  a second later.
- If the host offers "Setup Node/Python App", SSH with long-running processes,
  or a Terminal where `nohup php bin/ws-server.php &` survives, and lets you
  open a port or proxy to it, the WebSocket server can run there - ask the
  host. Most cheap shared plans do not.

The app never depends on the socket: if it cannot connect, or the connection
drops in the middle of a match, it carries on over HTTP and keeps trying to
reconnect.

## After the server answers

Build the app against it and ship that build:

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://api.yourdomain.com
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.yourdomain.com
```

Then, from the app project, play real matches against the live server:

```bash
API_BASE_URL=https://api.yourdomain.com flutter test test_online/online_match_test.dart
```

## Production checklist

- `php bin/doctor.php` says **Ready** (it checks PHP, the database, uploads,
  HTTPS, that debug and test hooks are off, and that this server's floating
  point matches the app's physics).
- `APP_DEBUG=0`, `APP_TEST_HOOKS=0`, `RATE_LIMIT_FACTOR=1`.
- `.env` is outside the document root and not world-readable.
- The cron job runs (it rules on abandoned matches and prunes old data).
- With WebSockets: `systemctl status billiard-poker-ws` is active and
  `/config` returns the `wss://` address.
- Password-reset mail arrives: use an address on your own domain for
  `MAIL_FROM` and make sure the domain has SPF/DKIM, or the mail lands in spam.
- Database backups are on (cPanel > Backup, or `mysqldump` from cron).

## Updating

Upload the new zip over the old files (your `.env` and `public/uploads` are
not in it), then run `php bin/migrate.php`. New tables are added; if a release
changes an existing table its notes will say which `ALTER` to run.

## Scale

Over WebSockets a match costs almost nothing while players think. Without
them: one request per player every 0.6 s while in a match, a few milliseconds each;
a shot costs 0.05-0.3 s of CPU to simulate. Ordinary shared hosting carries a
few dozen simultaneous matches; beyond that use a VPS with PHP-FPM and OPcache.
