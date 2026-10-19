<?php
declare(strict_types=1);

namespace App;

/** Operator signals: suspicious redeem, transfer abuse, game integrity. */
final class AdminAlert
{
    private const KINDS = ['redeem_abuse', 'transfer_abuse', 'game_integrity', 'security'];

    public static function ensureTable(): void
    {
        Db::run(
            'CREATE TABLE IF NOT EXISTS admin_alerts (
                id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                kind VARCHAR(32) NOT NULL,
                title VARCHAR(120) NOT NULL,
                detail TEXT NULL,
                user_id BIGINT UNSIGNED NULL,
                read_at DATETIME NULL,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                KEY idx_admin_alerts_unread (read_at, created_at),
                KEY idx_admin_alerts_kind (kind, created_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
        );
    }

    public static function signal(string $kind, string $title, string $detail = '', ?int $userId = null): void
    {
        if (!in_array($kind, self::KINDS, true)) {
            $kind = 'security';
        }
        self::ensureTable();
        $title = mb_substr(trim($title), 0, 120);
        $detail = mb_substr(trim($detail), 0, 2000);
        if ($title === '') {
            return;
        }
        $bucket = 'admin-alert:' . $kind . ':' . ($userId ?? 0);
        try {
            RateLimit::hit($bucket, 8, 3600);
        } catch (ApiError) {
            return;
        }
        Db::run(
            'INSERT INTO admin_alerts (kind, title, detail, user_id) VALUES (?, ?, ?, ?)',
            [$kind, $title, $detail === '' ? null : $detail, $userId]
        );
    }

    public static function unreadCount(): int
    {
        self::ensureTable();
        return (int) Db::one('SELECT COUNT(*) AS n FROM admin_alerts WHERE read_at IS NULL')['n'];
    }

    /** @return list<array<string,mixed>> */
    public static function listRecent(int $limit = 80): array
    {
        self::ensureTable();
        $limit = max(1, min(200, $limit));
        $rows = Db::all(
            "SELECT a.*, u.display_name FROM admin_alerts a
             LEFT JOIN users u ON u.id = a.user_id
             ORDER BY a.id DESC LIMIT $limit"
        );
        return array_map(static fn (array $r): array => [
            'id' => (int) $r['id'],
            'kind' => $r['kind'],
            'title' => $r['title'],
            'detail' => $r['detail'],
            'userId' => $r['user_id'] === null ? null : (int) $r['user_id'],
            'playerName' => $r['display_name'] ?? null,
            'read' => $r['read_at'] !== null,
            'createdAt' => strtotime((string) $r['created_at']) * 1000,
        ], $rows);
    }

    public static function markAllRead(): void
    {
        self::ensureTable();
        Db::run('UPDATE admin_alerts SET read_at = NOW() WHERE read_at IS NULL');
    }
}
