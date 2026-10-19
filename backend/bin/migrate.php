<?php
declare(strict_types=1);

// Creates the tables: php bin/migrate.php
require dirname(__DIR__) . '/src/bootstrap.php';

$sql = file_get_contents(dirname(__DIR__) . '/sql/schema.sql');
// Drop comment lines, then run statement by statement.
$sql = preg_replace('/^\s*--.*$/m', '', $sql);
foreach (array_filter(array_map('trim', explode(';', $sql))) as $statement) {
    App\Db::pdo()->exec($statement);
}
// Columns added after the first release: CREATE TABLE IF NOT EXISTS leaves
// an existing table alone, so they are added here when missing.
$columns = [
    'users' => [
        'gems' => 'INT NOT NULL DEFAULT 0',
        'xp' => 'INT NOT NULL DEFAULT 0',
        'cue' => "VARCHAR(32) NOT NULL DEFAULT 'classic'",
        'name_set' => 'TINYINT(1) NOT NULL DEFAULT 0',
        'daily_claimed_on' => 'DATE NULL',
        'daily_streak' => 'INT NOT NULL DEFAULT 0',
        'is_bot' => 'TINYINT(1) NOT NULL DEFAULT 0',
        'referral_code' => 'CHAR(6) NULL',
        'referred_by' => 'BIGINT UNSIGNED NULL',
        'phone' => 'CHAR(13) NULL',
        'name_changed_at' => 'DATETIME NULL',
    ],
    'room_players' => [
        'joined_at' => 'DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP',
    ],
    'games' => [
        'has_bots' => 'TINYINT(1) NOT NULL DEFAULT 0',
    ],
    'rooms' => [
        'level' => 'TINYINT NULL',
        'stake' => 'INT NOT NULL DEFAULT 0',
        'fee' => 'INT NOT NULL DEFAULT 0',
        'prize' => 'INT NOT NULL DEFAULT 0',
        'multiplier' => 'INT NULL',
    ],
    'match_results' => [
        'stake' => 'INT NOT NULL DEFAULT 0',
        'prize' => 'INT NOT NULL DEFAULT 0',
    ],
    'wallet_tx' => [
        'ref_user_id' => 'BIGINT UNSIGNED NULL',
    ],
];
$pdo = App\Db::pdo();
foreach ($columns as $table => $defs) {
    $have = $pdo->query("SHOW COLUMNS FROM `$table`")->fetchAll(PDO::FETCH_COLUMN);
    foreach ($defs as $name => $def) {
        if (!in_array($name, $have, true)) {
            $pdo->exec("ALTER TABLE `$table` ADD COLUMN `$name` $def");
            echo "added $table.$name\n";
        }
    }
}
$enumFixes = [
    'rooms' => ["ENUM('poker','eight','nine','ten','billiard','ludo2','ludo4','carrom') NOT NULL", 'carrom'],
    'games' => ["ENUM('poker','eight','nine','ten','ludo2','ludo4','carrom') NOT NULL", 'carrom'],
    'match_results' => ["ENUM('poker','eight','nine','ten','ludo2','ludo4','carrom') NOT NULL", 'carrom'],
    'challenges' => ["ENUM('eight','nine','ten','billiard','ludo2','carrom') NOT NULL", 'carrom'],
];
foreach ($enumFixes as $table => [$def, $needle]) {
    $type = $pdo->query("SHOW COLUMNS FROM `$table` LIKE 'game'")->fetch(PDO::FETCH_ASSOC)['Type'];
    if (!str_contains($type, $needle)) {
        $pdo->exec("ALTER TABLE `$table` MODIFY game $def");
        echo "widened $table.game\n";
    }
}
$hasCode = $pdo->query("SHOW INDEX FROM users WHERE Key_name = 'uq_users_referral'")->fetch();
if ($hasCode === false) {
    $pdo->exec('ALTER TABLE users ADD UNIQUE KEY uq_users_referral (referral_code)');
    echo "added users.uq_users_referral\n";
}
$hasRef = $pdo->query("SHOW INDEX FROM users WHERE Key_name = 'idx_users_referred'")->fetch();
if ($hasRef === false) {
    $pdo->exec('ALTER TABLE users ADD KEY idx_users_referred (referred_by)');
    echo "added users.idx_users_referred\n";
}
$hasPhone = $pdo->query("SHOW INDEX FROM users WHERE Key_name = 'uq_users_phone'")->fetch();
if ($hasPhone === false) {
    $pdo->exec('ALTER TABLE users ADD UNIQUE KEY uq_users_phone (phone)');
    echo "added users.uq_users_phone\n";
}
echo "Schema is up to date.\n";
