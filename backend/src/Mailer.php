<?php
declare(strict_types=1);

namespace App;

/**
 * Plain-text mail. With SMTP_HOST set it is handed to that mail server over
 * an encrypted, authenticated connection (a mailbox on your own domain);
 * otherwise PHP's mail() is used (what shared hosting offers). With MAIL_LOG
 * set, messages are appended to that file instead - for development and
 * tests, where no mail server exists.
 */
final class Mailer
{
    public static function send(string $to, string $subject, string $body): bool
    {
        $log = Config::get('MAIL_LOG');
        if ($log !== '') {
            return file_put_contents($log, "To: $to\nSubject: $subject\n\n$body\n---\n", FILE_APPEND | LOCK_EX) !== false;
        }
        $from = Config::get('MAIL_FROM', 'no-reply@' . (parse_url(Config::get('APP_URL'), PHP_URL_HOST) ?: 'localhost'));
        // Header injection guard: addresses and subject must be single-line.
        if (preg_match('/[\r\n]/', $to . $from . $subject) === 1) {
            return false;
        }
        if (Config::get('SMTP_HOST') !== '') {
            try {
                self::smtp($from, $to, $subject, $body);
                return true;
            } catch (\Throwable $e) {
                error_log('[mail] ' . $e->getMessage());
                return false;
            }
        }
        $headers = "From: Billiard Poker <$from>\r\nContent-Type: text/plain; charset=utf-8";
        return mail($to, $subject, $body, $headers);
    }

    /** One message over SMTP: implicit TLS on 465, STARTTLS on any other port. */
    private static function smtp(string $from, string $to, string $subject, string $body): void
    {
        $host = Config::get('SMTP_HOST');
        $port = Config::int('SMTP_PORT', 465);
        $implicit = $port === 465;
        $socket = @stream_socket_client(($implicit ? 'ssl://' : 'tcp://') . "$host:$port", $errno, $error, 10);
        if ($socket === false) {
            throw new \RuntimeException("cannot reach $host:$port ($error)");
        }
        stream_set_timeout($socket, 15);
        try {
            self::expect($socket, 220);
            $hello = 'EHLO ' . (parse_url(Config::get('APP_URL'), PHP_URL_HOST) ?: 'localhost');
            self::command($socket, $hello, 250);
            if (!$implicit) {
                self::command($socket, 'STARTTLS', 220);
                if (stream_socket_enable_crypto($socket, true, STREAM_CRYPTO_METHOD_TLS_CLIENT) !== true) {
                    throw new \RuntimeException('TLS handshake failed');
                }
                self::command($socket, $hello, 250);
            }
            $user = Config::get('SMTP_USER');
            if ($user !== '') {
                self::command($socket, 'AUTH LOGIN', 334);
                self::command($socket, base64_encode($user), 334);
                self::command($socket, base64_encode(Config::get('SMTP_PASS')), 235, 'sign-in refused');
            }
            self::command($socket, "MAIL FROM:<$from>", 250);
            self::command($socket, "RCPT TO:<$to>", 250);
            self::command($socket, 'DATA', 354);
            $domain = substr((string) strrchr($from, '@'), 1) ?: 'localhost';
            $headers = [
                'Date: ' . date('r'),
                "From: Billiard Poker <$from>",
                "To: <$to>",
                'Subject: =?UTF-8?B?' . base64_encode($subject) . '?=',
                'Message-ID: <' . bin2hex(random_bytes(12)) . "@$domain>",
                'MIME-Version: 1.0',
                'Content-Type: text/plain; charset=utf-8',
                'Content-Transfer-Encoding: base64',
            ];
            $data = implode("\r\n", $headers) . "\r\n\r\n" . chunk_split(base64_encode($body), 76, "\r\n");
            self::command($socket, rtrim($data, "\r\n") . "\r\n.", 250);
            fwrite($socket, "QUIT\r\n");
        } finally {
            fclose($socket);
        }
    }

    /** @param resource $socket */
    private static function command($socket, string $line, int $expect, string $what = ''): void
    {
        fwrite($socket, $line . "\r\n");
        self::expect($socket, $expect, $what);
    }

    /** @param resource $socket */
    private static function expect($socket, int $code, string $what = ''): void
    {
        $reply = '';
        // Multi-line replies continue with "250-..." and end with "250 ...".
        while (($line = fgets($socket, 1024)) !== false) {
            $reply = $line;
            if (strlen($line) < 4 || $line[3] !== '-') {
                break;
            }
        }
        if ((int) substr($reply, 0, 3) !== $code) {
            throw new \RuntimeException(($what !== '' ? "$what: " : '') . 'expected ' . $code . ', got ' . trim($reply));
        }
    }
}
