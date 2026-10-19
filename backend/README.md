# PikoPe — PHP API + Admin (Hostinger)

Backend and web admin for the PikoPe / DuelX Android app. Works on **shared hosting** (HTTP polling; no WebSocket required).

## Hostinger quick setup

1. **Upload** this repo into `public_html/pikope/` (File Manager, Git deploy, or download ZIP from GitHub → extract).
2. **Document root** (hPanel → Subdomains → `pikope`):

   ```text
   .../public_html/pikope/public
   ```

3. **Environment:** copy `.env.example` → `.env` in the `pikope` folder (next to `public/`, not inside it). Set `DB_*`, `APP_URL`, `ADMIN_USER`, `ADMIN_PASS`. Use `APP_DEBUG=0` in production.
4. **Database:** phpMyAdmin → import `sql/schema.sql`, or SSH: `php bin/migrate.php`
5. **Test:** `https://pikope.bet369win.com/health` → JSON `ok`
6. **Admin:** `https://pikope.bet369win.com/admin` (HTTP Basic)
7. **Cron (every 5 min):** `php .../pikope/bin/cleanup.php`

See `deploy/HOSTINGER-PIKOPE.txt` for the full checklist.

## APK

Release builds need `android/key.properties` (see `duelx/android/key.properties.example` in the Flutter repo).

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://pikope.bet369win.com
```

## Requirements

- PHP **8.1+** (64-bit), extensions: `pdo_mysql`, `json`, `mbstring`, `fileinfo`
- MySQL 8+
- Writable: `public/uploads/avatars`

Check server: `php bin/doctor.php`

Wallet audit (read-only): `php bin/reconcile_wallet.php` — exit 1 if balance ≠ ledger.

Push notifications: set `FCM_SERVER_KEY` in `.env` (Firebase console → Cloud Messaging).
Replace the placeholder `google-services.json` in the Flutter app with your Firebase Android app file (`com.pikope.piko`).

## Layout

```text
pikope/
  .env              ← secrets (not in git)
  public/           ← web document root
  src/              ← API + Admin.php
  sql/
  bin/
  deploy/
```
