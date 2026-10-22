-- Billiard Poker backend schema (MySQL 8 / MariaDB 10.5+).
-- Apply with: php bin/migrate.php   (or: mysql billiard_poker < sql/schema.sql)

CREATE TABLE IF NOT EXISTS users (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  email         VARCHAR(190) NULL UNIQUE,
  phone         CHAR(13)     NULL UNIQUE,
  password_hash VARCHAR(255) NULL,
  display_name  VARCHAR(24)  NOT NULL,
  avatar        VARCHAR(255) NOT NULL DEFAULT 'asset:avatar_1',
  table_skin    VARCHAR(32)  NOT NULL DEFAULT 'pro_teal',
  coins         INT          NOT NULL DEFAULT 0,
  redeemable_coins INT       NOT NULL DEFAULT 0,
  gems          INT          NOT NULL DEFAULT 0,
  xp            INT          NOT NULL DEFAULT 0,
  cue           VARCHAR(32)  NOT NULL DEFAULT 'classic',
  name_set      TINYINT(1)   NOT NULL DEFAULT 0,
  name_changed_at DATETIME   NULL,
  daily_claimed_on DATE      NULL,
  daily_streak  INT          NOT NULL DEFAULT 0,
  wins          INT          NOT NULL DEFAULT 0,
  games         INT          NOT NULL DEFAULT 0,
  is_guest      TINYINT(1)   NOT NULL DEFAULT 1,
  is_bot        TINYINT(1)   NOT NULL DEFAULT 0,
  banned        TINYINT(1)   NOT NULL DEFAULT 0,
  referral_code CHAR(6)      NULL UNIQUE,
  referred_by   BIGINT UNSIGNED NULL,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_users_rank (wins, coins),
  KEY idx_users_referred (referred_by)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Bearer tokens. Only the SHA-256 of a token is stored.
CREATE TABLE IF NOT EXISTS auth_tokens (
  id           BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id      BIGINT UNSIGNED NOT NULL,
  token_hash   CHAR(64)        NOT NULL UNIQUE,
  created_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_used_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at   DATETIME        NOT NULL,
  CONSTRAINT fk_tokens_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS rooms (
  id           BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  code         CHAR(6)         NOT NULL UNIQUE,
  game         ENUM('poker','eight','nine','ten','billiard','ludo2','ludo4','carrom') NOT NULL,
  host_id      BIGINT UNSIGNED NOT NULL,
  status       ENUM('waiting','playing','closed') NOT NULL DEFAULT 'waiting',
  is_private   TINYINT(1)      NOT NULL DEFAULT 0,
  shot_seconds SMALLINT        NOT NULL DEFAULT 30,
  level        TINYINT         NULL,
  stake        INT             NOT NULL DEFAULT 0,
  fee          INT             NOT NULL DEFAULT 0,
  prize        INT             NOT NULL DEFAULT 0,
  multiplier   INT             NULL,
  game_id      BIGINT UNSIGNED NULL,
  next_room_id BIGINT UNSIGNED NULL,
  created_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_rooms_open (status, game, is_private)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS room_players (
  room_id      BIGINT UNSIGNED NOT NULL,
  user_id      BIGINT UNSIGNED NOT NULL,
  seat         TINYINT         NOT NULL,
  joined_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_seen_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (room_id, user_id),
  KEY idx_room_players_user (user_id),
  CONSTRAINT fk_rp_room FOREIGN KEY (room_id) REFERENCES rooms (id) ON DELETE CASCADE,
  CONSTRAINT fk_rp_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- One row per match. `state` is the full authoritative state as JSON text
-- (hidden cards, penalty pile, exact ball positions); clients only ever
-- receive a filtered view of it. Kept as text, not a JSON column, so floats
-- are stored exactly as written.
CREATE TABLE IF NOT EXISTS games (
  id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  room_id     BIGINT UNSIGNED NOT NULL,
  game        ENUM('poker','eight','nine','ten','ludo2','ludo4','carrom') NOT NULL,
  status      ENUM('active','finished') NOT NULL DEFAULT 'active',
  version     INT UNSIGNED    NOT NULL DEFAULT 1,
  state       LONGTEXT        NOT NULL,
  aim         TEXT            NULL,
  has_bots    TINYINT(1)      NOT NULL DEFAULT 0,
  winner_id   BIGINT UNSIGNED NULL,
  created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  finished_at DATETIME        NULL,
  KEY idx_games_room (room_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS game_players (
  game_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  seat    TINYINT         NOT NULL,
  PRIMARY KEY (game_id, user_id),
  CONSTRAINT fk_gp_game FOREIGN KEY (game_id) REFERENCES games (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Shot log: what was played and how the server ruled it.
CREATE TABLE IF NOT EXISTS game_shots (
  id         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  game_id    BIGINT UNSIGNED NOT NULL,
  seq        INT             NOT NULL,
  user_id    BIGINT UNSIGNED NOT NULL,
  params     JSON            NOT NULL,
  outcome    JSON            NULL,
  result     JSON            NULL,
  created_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_shot (game_id, seq),
  CONSTRAINT fk_shots_game FOREIGN KEY (game_id) REFERENCES games (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS match_results (
  id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  game_id     BIGINT UNSIGNED NULL,
  user_id     BIGINT UNSIGNED NOT NULL,
  game        ENUM('poker','eight','nine','ten','ludo2','ludo4','carrom') NOT NULL,
  mode        ENUM('online','bots') NOT NULL,
  won         TINYINT(1)      NOT NULL,
  coins_delta INT             NOT NULL,
  stake       INT             NOT NULL DEFAULT 0,
  prize       INT             NOT NULL DEFAULT 0,
  created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_results_user (user_id, created_at),
  CONSTRAINT fk_results_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Failed sign-ins, for throttling password guessing.
CREATE TABLE IF NOT EXISTS login_attempts (
  id         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  email      VARCHAR(190) NOT NULL,
  ip         VARCHAR(45)  NOT NULL,
  created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_attempts (email, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- One-time codes for resetting a password by email. Only a hash is stored.
CREATE TABLE IF NOT EXISTS password_resets (
  id         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id    BIGINT UNSIGNED NOT NULL,
  code_hash  CHAR(64)        NOT NULL,
  attempts   TINYINT         NOT NULL DEFAULT 0,
  expires_at DATETIME        NOT NULL,
  created_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_resets_user (user_id),
  CONSTRAINT fk_resets_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Fixed-window request counters (sign-up, sign-in, reset throttling).
CREATE TABLE IF NOT EXISTS rate_limits (
  bucket       VARCHAR(120) NOT NULL,
  window_start INT UNSIGNED NOT NULL,
  hits         INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (bucket, window_start)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Coin shop purchases (in-app coin packs; price is always in coins).
CREATE TABLE IF NOT EXISTS coin_deposit_requests (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id       BIGINT UNSIGNED NOT NULL,
  provider      VARCHAR(24)     NOT NULL,
  payer_number  VARCHAR(16)     NOT NULL,
  trx_id        VARCHAR(24)     NOT NULL,
  bdt_amount    INT             NOT NULL,
  coins         INT             NOT NULL,
  status        ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
  admin_note    VARCHAR(255)    NULL,
  created_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  reviewed_at   DATETIME        NULL,
  UNIQUE KEY uq_deposit_trx (provider, trx_id),
  KEY idx_deposit_user (user_id, created_at),
  KEY idx_deposit_status (status, created_at),
  CONSTRAINT fk_deposit_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS redeem_requests (
  id              BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id         BIGINT UNSIGNED NOT NULL,
  coins           INT             NOT NULL,
  bdt_amount      INT             NOT NULL,
  wallet_provider VARCHAR(24)     NOT NULL,
  wallet_number   VARCHAR(16)     NOT NULL,
  status          ENUM('pending','approved','rejected','cancelled') NOT NULL DEFAULT 'pending',
  admin_note      VARCHAR(255)    NULL,
  created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  reviewed_at     DATETIME        NULL,
  KEY idx_redeem_user (user_id, created_at),
  KEY idx_redeem_status (status, created_at),
  CONSTRAINT fk_redeem_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS coin_shop_purchases (
  id           BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id      BIGINT UNSIGNED NOT NULL,
  pack_id      VARCHAR(32)     NOT NULL,
  coins        INT             NOT NULL,
  price_coins  INT             NOT NULL,
  created_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_coin_shop_user (user_id, pack_id),
  CONSTRAINT fk_coin_shop_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Operator settings (JSON), e.g. the economy: fee, bet levels, jackpot odds.
CREATE TABLE IF NOT EXISTS settings (
  k VARCHAR(40) NOT NULL PRIMARY KEY,
  v TEXT        NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Every movement of coins or gems, with the balance it left behind.
CREATE TABLE IF NOT EXISTS wallet_tx (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id       BIGINT UNSIGNED NOT NULL,
  currency      ENUM('coins','gems') NOT NULL DEFAULT 'coins',
  amount        INT             NOT NULL,
  balance_after INT             NOT NULL,
  reason        VARCHAR(40)     NOT NULL,
  room_id       BIGINT UNSIGNED NULL,
  ref_user_id   BIGINT UNSIGNED NULL,
  created_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_tx_user (user_id, id),
  KEY idx_tx_reason (reason, created_at),
  CONSTRAINT fk_tx_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Things a player owns (cues).
CREATE TABLE IF NOT EXISTS user_items (
  user_id    BIGINT UNSIGNED NOT NULL,
  kind       VARCHAR(16)     NOT NULL,
  item       VARCHAR(32)     NOT NULL,
  created_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, kind, item),
  CONSTRAINT fk_items_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 1v1 challenge invites between online players.
CREATE TABLE IF NOT EXISTS challenges (
  id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  from_user   BIGINT UNSIGNED NOT NULL,
  to_user     BIGINT UNSIGNED NOT NULL,
  game        ENUM('eight','nine','ten','billiard','ludo2','carrom') NOT NULL,
  level       TINYINT         NULL,
  stake       INT             NOT NULL DEFAULT 0,
  fee         INT             NOT NULL DEFAULT 0,
  status      ENUM('pending','accepted','declined','cancelled','expired') NOT NULL DEFAULT 'pending',
  room_id     BIGINT UNSIGNED NULL,
  created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at  DATETIME        NOT NULL,
  KEY idx_ch_to (to_user, status),
  KEY idx_ch_from (from_user, status),
  CONSTRAINT fk_ch_from FOREIGN KEY (from_user) REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_ch_to FOREIGN KEY (to_user) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- FCM device tokens (APK push).
CREATE TABLE IF NOT EXISTS push_tokens (
  id         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id    BIGINT UNSIGNED NOT NULL,
  token      VARCHAR(512)    NOT NULL,
  platform   ENUM('android','ios','web') NOT NULL DEFAULT 'android',
  updated_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_push_token (token(191)),
  KEY idx_push_user (user_id),
  CONSTRAINT fk_push_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Per-player notification inbox (also shown in-app when push is off).
CREATE TABLE IF NOT EXISTS user_notifications (
  id         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id    BIGINT UNSIGNED NOT NULL,
  kind       VARCHAR(32)     NOT NULL,
  title      VARCHAR(80)     NOT NULL,
  body       VARCHAR(500)    NOT NULL,
  event_key  VARCHAR(80)     NULL,
  read_at    DATETIME        NULL,
  created_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_notif_event (user_id, event_key),
  KEY idx_notif_user (user_id, read_at, id),
  CONSTRAINT fk_notif_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Operator announcements shown in the app (a home banner and/or the inbox).
CREATE TABLE IF NOT EXISTS notices (
  id         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  title      VARCHAR(80)  NOT NULL,
  body       VARCHAR(500) NOT NULL,
  kind       ENUM('news','banner') NOT NULL DEFAULT 'news',
  active     TINYINT(1)   NOT NULL DEFAULT 1,
  created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at DATETIME     NULL,
  KEY idx_notices_active (active, kind)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ZiniPay auto coin add (WebView checkout).
CREATE TABLE IF NOT EXISTS zinipay_deposits (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NOT NULL,
  bdt_amount INT NOT NULL,
  coins INT NOT NULL,
  invoice_id VARCHAR(64) NULL,
  zini_status VARCHAR(24) NOT NULL DEFAULT 'pending',
  zini_transaction_id VARCHAR(64) NULL,
  credited TINYINT(1) NOT NULL DEFAULT 0,
  pack_id VARCHAR(32) NULL,
  base_coins INT NOT NULL DEFAULT 0,
  bonus_coins INT NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at DATETIME NULL,
  KEY idx_zini_user (user_id, created_at),
  KEY idx_zini_invoice (invoice_id),
  CONSTRAINT fk_zini_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Player-to-player Pico coin transfer by game ID.
CREATE TABLE IF NOT EXISTS coin_transfers (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  from_user_id BIGINT UNSIGNED NOT NULL,
  to_user_id BIGINT UNSIGNED NOT NULL,
  amount INT NOT NULL,
  fee INT NOT NULL,
  received INT NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_transfer_from (from_user_id, created_at),
  KEY idx_transfer_to (to_user_id, created_at),
  CONSTRAINT fk_transfer_from FOREIGN KEY (from_user_id) REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_transfer_to FOREIGN KEY (to_user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Admin security / abuse signals.
CREATE TABLE IF NOT EXISTS admin_alerts (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  kind VARCHAR(32) NOT NULL,
  title VARCHAR(120) NOT NULL,
  detail TEXT NULL,
  user_id BIGINT UNSIGNED NULL,
  read_at DATETIME NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_admin_alerts_unread (read_at, created_at),
  KEY idx_admin_alerts_kind (kind, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
