<?php
declare(strict_types=1);

namespace App\Ws;

use App\ApiError;
use App\Auth;
use App\Db;
use App\GameService;
use App\RoomService;

/**
 * WebSocket server for live play: one long-running PHP process, no
 * extensions or packages beyond the PHP core (RFC 6455 implemented here).
 *
 * Players send their actions over the socket and every player of the match
 * receives the new state at once. Changes made elsewhere (an HTTP request,
 * the cron job, a timeout) are picked up by watching the match's version in
 * the database, so HTTP and WebSocket clients can share a match.
 *
 * Messages are JSON text frames.
 *   -> {t:"auth", token}                    <- {t:"auth_ok", userId}
 *   -> {t:"join", gameId}                   <- {t:"state", id, version, serverNow, state}
 *   -> {t:"act", gameId, n, action:{...}}   <- {t:"state", ..., re:n} to the sender and
 *                                              {t:"state", ...} to the other players
 *   -> {t:"aim", gameId, s, a, p, x, y}     <- the same, to the other players of the match
 *   -> {t:"chat", gameId, m}                <- {t:"chat", gameId, s, m} to the other players
 *                                              (m = index of a quick-chat preset)
 *   -> {t:"room", roomId}                   <- {t:"room", room} now and whenever it changes
 *   -> {t:"ping"}                           <- {t:"pong"}
 *   <- {t:"error", code, message, re?}
 */
final class Server
{
    private const MAX_FRAME = 262144;
    private const MAX_CLIENTS = 4000;
    private const IDLE_SECONDS = 75;
    private const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

    /** @var resource */
    private $listener;
    /** @var array<int,Client> */
    private array $clients = [];
    /** @var array<int,int> last version pushed, per watched game */
    private array $versions = [];
    private float $lastGamePoll = 0.0;
    private float $lastSlowPoll = 0.0;
    private bool $running = true;

    public function __construct(string $host, int $port)
    {
        $listener = @stream_socket_server("tcp://$host:$port", $errno, $error);
        if ($listener === false) {
            throw new \RuntimeException("Cannot listen on $host:$port - $error");
        }
        stream_set_blocking($listener, false);
        $this->listener = $listener;
    }

    public function stop(): void
    {
        $this->running = false;
    }

    public function run(): void
    {
        while ($this->running) {
            $read = [$this->listener];
            $write = [];
            foreach ($this->clients as $c) {
                $read[] = $c->socket;
                if ($c->out !== '') {
                    $write[] = $c->socket;
                }
            }
            $except = null;
            if (@stream_select($read, $write, $except, 0, 100000) === false) {
                continue; // interrupted by a signal
            }
            foreach ($read as $socket) {
                if ($socket === $this->listener) {
                    $this->accept();
                } else {
                    $this->read($this->clients[(int) $socket] ?? null);
                }
            }
            foreach ($write as $socket) {
                $this->flush($this->clients[(int) $socket] ?? null);
            }
            $this->periodic();
        }
        foreach ($this->clients as $c) {
            $this->close($c);
        }
        fclose($this->listener);
    }

    // ---------------------------------------------------------- sockets

    private function accept(): void
    {
        $socket = @stream_socket_accept($this->listener, 0);
        if ($socket === false) {
            return;
        }
        if (count($this->clients) >= self::MAX_CLIENTS) {
            fclose($socket);
            return;
        }
        stream_set_blocking($socket, false);
        $this->clients[(int) $socket] = new Client($socket);
    }

    private function read(?Client $c): void
    {
        if ($c === null) {
            return;
        }
        $data = @fread($c->socket, 65536);
        if ($data === false || ($data === '' && feof($c->socket))) {
            $this->close($c);
            return;
        }
        $c->in .= $data;
        $c->lastSeen = microtime(true);
        if (!$c->open) {
            $this->handshake($c);
        }
        if ($c->open) {
            $this->frames($c);
        }
    }

    private function flush(?Client $c): void
    {
        if ($c === null || $c->out === '') {
            return;
        }
        $written = @fwrite($c->socket, $c->out);
        if ($written === false) {
            $this->close($c);
            return;
        }
        $c->out = (string) substr($c->out, $written);
        if ($c->closing && $c->out === '') {
            $this->close($c);
        }
    }

    private function close(Client $c): void
    {
        unset($this->clients[(int) $c->socket]);
        @fclose($c->socket);
    }

    private function handshake(Client $c): void
    {
        $end = strpos($c->in, "\r\n\r\n");
        if ($end === false) {
            if (strlen($c->in) > 8192) {
                $this->close($c);
            }
            return;
        }
        $head = substr($c->in, 0, $end);
        $c->in = (string) substr($c->in, $end + 4);
        if (preg_match('/^Sec-WebSocket-Key:\s*(\S+)/mi', $head, $m) !== 1 || stripos($head, 'upgrade: websocket') === false) {
            $c->out .= "HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n";
            $c->closing = true;
            return;
        }
        $accept = base64_encode(sha1($m[1] . self::GUID, true));
        $c->out .= "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
            . "Sec-WebSocket-Accept: $accept\r\n\r\n";
        $c->open = true;
    }

    private function frames(Client $c): void
    {
        while (strlen($c->in) >= 2 && isset($this->clients[(int) $c->socket])) {
            $b0 = ord($c->in[0]);
            $b1 = ord($c->in[1]);
            $length = $b1 & 0x7F;
            $offset = 2;
            if ($length === 126) {
                if (strlen($c->in) < 4) {
                    return;
                }
                $length = unpack('n', substr($c->in, 2, 2))[1];
                $offset = 4;
            } elseif ($length === 127) {
                if (strlen($c->in) < 10) {
                    return;
                }
                $length = unpack('J', substr($c->in, 2, 8))[1];
                $offset = 10;
            }
            // Clients must mask; oversized frames are not something the app sends.
            if (($b1 & 0x80) === 0 || $length > self::MAX_FRAME) {
                $this->close($c);
                return;
            }
            if (strlen($c->in) < $offset + 4 + $length) {
                return;
            }
            $mask = substr($c->in, $offset, 4);
            $payload = substr($c->in, $offset + 4, $length);
            $c->in = (string) substr($c->in, $offset + 4 + $length);
            if ($length > 0) {
                $payload ^= substr(str_repeat($mask, intdiv($length, 4) + 1), 0, $length);
            }
            switch ($b0 & 0x0F) {
                case 0x8: // close
                    $c->out .= "\x88\x00";
                    $c->closing = true;
                    return;
                case 0x9: // ping
                    $c->out .= self::frame($payload, 0xA);
                    break;
                case 0xA: // pong
                    break;
                case 0x0:
                case 0x1:
                    $c->fragment .= $payload;
                    if (strlen($c->fragment) > self::MAX_FRAME) {
                        $this->close($c);
                        return;
                    }
                    if (($b0 & 0x80) !== 0) {
                        $message = $c->fragment;
                        $c->fragment = '';
                        $this->message($c, $message);
                    }
                    break;
                default:
                    $this->close($c);
                    return;
            }
        }
    }

    private static function frame(string $payload, int $opcode = 0x1): string
    {
        $length = strlen($payload);
        $head = chr(0x80 | $opcode);
        if ($length < 126) {
            return $head . chr($length) . $payload;
        }
        if ($length < 65536) {
            return $head . chr(126) . pack('n', $length) . $payload;
        }
        return $head . chr(127) . pack('J', $length) . $payload;
    }

    /** @param array<string,mixed> $message */
    private function send(Client $c, array $message): void
    {
        $c->out .= self::frame(json_encode($message, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
    }

    // --------------------------------------------------------- messages

    private function message(Client $c, string $raw): void
    {
        $msg = json_decode($raw, true);
        if (!is_array($msg) || !is_string($msg['t'] ?? null)) {
            $this->send($c, ['t' => 'error', 'code' => 'bad_message', 'message' => 'Malformed message']);
            return;
        }
        $re = $msg['n'] ?? null;
        try {
            $this->dispatch($c, $msg);
        } catch (ApiError $e) {
            $this->send($c, ['t' => 'error', 'code' => $e->errorCode, 'message' => $e->getMessage(), 're' => $re]);
        } catch (\PDOException $e) {
            // The database connection may have timed out while idle: reconnect.
            Db::reset();
            error_log('[ws] database: ' . $e->getMessage());
            $this->send($c, ['t' => 'error', 'code' => 'server_error', 'message' => 'Try again', 're' => $re]);
        } catch (\Throwable $e) {
            error_log('[ws] ' . $e::class . ': ' . $e->getMessage() . ' @ ' . $e->getFile() . ':' . $e->getLine());
            $this->send($c, ['t' => 'error', 'code' => 'server_error', 'message' => 'Something went wrong', 're' => $re]);
        }
    }

    /** @param array<string,mixed> $msg */
    private function dispatch(Client $c, array $msg): void
    {
        if ($msg['t'] === 'ping') {
            $this->send($c, ['t' => 'pong']);
            return;
        }
        if ($msg['t'] === 'auth') {
            $c->user = Auth::userByToken((string) ($msg['token'] ?? ''));
            $this->send($c, ['t' => 'auth_ok', 'userId' => (int) $c->user['id']]);
            return;
        }
        if ($c->user === null) {
            throw ApiError::unauthorized();
        }
        $uid = (int) $c->user['id'];
        switch ($msg['t']) {
            case 'join':
                $gameId = (int) ($msg['gameId'] ?? 0);
                $view = GameService::get($gameId, $uid, 0); // refuses anyone not seated
                $c->games[$gameId] = true;
                $c->seats[$gameId] = (int) ($view['state']['you'] ?? -1);
                $this->versions[$gameId] = max($this->versions[$gameId] ?? 0, (int) $view['version']);
                $this->send($c, ['t' => 'state'] + $view);
                return;

            case 'act':
                $gameId = (int) ($msg['gameId'] ?? 0);
                if (!isset($c->games[$gameId]) || !is_array($msg['action'] ?? null)) {
                    throw ApiError::badRequest('Join the game first');
                }
                $view = GameService::act($gameId, $uid, $msg['action']);
                $this->send($c, ['t' => 'state', 're' => $msg['n'] ?? null] + $view);
                $this->versions[$gameId] = (int) $view['version'];
                $this->broadcast($gameId, $c);
                return;

            case 'aim':
                // Where a player's cue points while lining up: shown to the
                // others, never stored, and no part of the rules.
                $gameId = (int) ($msg['gameId'] ?? 0);
                if (!isset($c->games[$gameId])) {
                    return;
                }
                $aim = ['t' => 'aim', 'gameId' => $gameId, 's' => (int) ($msg['s'] ?? -1)];
                foreach (['a', 'p', 'x', 'y'] as $key) {
                    $value = $msg[$key] ?? null;
                    if (!is_int($value) && !is_float($value) || !is_finite((float) $value)) {
                        return;
                    }
                    $aim[$key] = round((float) $value, 4);
                }
                foreach ($this->clients as $other) {
                    if ($other !== $c && isset($other->games[$gameId])) {
                        $this->send($other, $aim);
                    }
                }
                return;

            case 'chat':
                // A quick-chat preset (index only, never free text), relayed
                // to the other players of the match; not stored.
                $gameId = (int) ($msg['gameId'] ?? 0);
                $m = $msg['m'] ?? null;
                if (!isset($c->games[$gameId]) || !is_int($m) || $m < 0 || $m > 15) {
                    return;
                }
                $now = microtime(true);
                if ($now - $c->lastChat < 1.0) {
                    return;
                }
                $c->lastChat = $now;
                $chat = ['t' => 'chat', 'gameId' => $gameId, 's' => $c->seats[$gameId] ?? -1, 'm' => $m];
                foreach ($this->clients as $other) {
                    if ($other !== $c && isset($other->games[$gameId])) {
                        $this->send($other, $chat);
                    }
                }
                return;

            case 'room':
                $roomId = (int) ($msg['roomId'] ?? 0);
                $room = RoomService::get($roomId, $c->user);
                $c->rooms[$roomId] = md5(json_encode($room));
                $this->send($c, ['t' => 'room', 'room' => $room]);
                return;

            case 'leave_room':
                unset($c->rooms[(int) ($msg['roomId'] ?? 0)]);
                return;
        }
        throw ApiError::badRequest('Unknown message');
    }

    /** Sends each seated player their own view of the match. */
    private function broadcast(int $gameId, ?Client $except = null): void
    {
        foreach ($this->clients as $c) {
            if ($c === $except || !isset($c->games[$gameId]) || $c->user === null) {
                continue;
            }
            try {
                $this->send($c, ['t' => 'state'] + GameService::get($gameId, (int) $c->user['id'], 0));
            } catch (ApiError) {
                unset($c->games[$gameId]);
            }
        }
    }

    // --------------------------------------------------------- periodic

    private function periodic(): void
    {
        $now = microtime(true);
        try {
            if ($now - $this->lastGamePoll >= 0.25) {
                $this->lastGamePoll = $now;
                $this->pushChangedGames();
            }
            if ($now - $this->lastSlowPoll >= 1.0) {
                $this->lastSlowPoll = $now;
                $this->enforceClocks();
                $this->pushChangedRooms();
                foreach ($this->clients as $c) {
                    if ($now - $c->lastSeen > self::IDLE_SECONDS) {
                        $this->close($c);
                    }
                }
            }
        } catch (\PDOException $e) {
            Db::reset();
            error_log('[ws] database: ' . $e->getMessage());
        } catch (\Throwable $e) {
            error_log('[ws] ' . $e::class . ': ' . $e->getMessage());
        }
    }

    /** @return list<int> */
    private function watchedGames(): array
    {
        $ids = [];
        foreach ($this->clients as $c) {
            $ids += $c->games;
        }
        foreach (array_keys($this->versions) as $id) {
            if (!isset($ids[$id])) {
                unset($this->versions[$id]);
            }
        }
        return array_keys($ids);
    }

    /** Pushes matches changed by someone else: an HTTP client, cron, another process. */
    private function pushChangedGames(): void
    {
        $ids = $this->watchedGames();
        if ($ids === []) {
            return;
        }
        $rows = Db::all('SELECT id, version FROM games WHERE id IN (' . implode(',', array_map('intval', $ids)) . ')');
        foreach ($rows as $row) {
            $id = (int) $row['id'];
            if ((int) $row['version'] > ($this->versions[$id] ?? 0)) {
                $this->versions[$id] = (int) $row['version'];
                $this->broadcast($id);
            }
        }
    }

    /** Shot clocks: asking for a match's state rules on an overdue turn. */
    private function enforceClocks(): void
    {
        foreach ($this->watchedGames() as $gameId) {
            foreach ($this->clients as $c) {
                if (isset($c->games[$gameId]) && $c->user !== null) {
                    try {
                        GameService::get($gameId, (int) $c->user['id'], PHP_INT_MAX);
                    } catch (ApiError) {
                        unset($c->games[$gameId]);
                    }
                    break;
                }
            }
        }
    }

    private function pushChangedRooms(): void
    {
        foreach ($this->clients as $c) {
            foreach ($c->rooms as $roomId => $hash) {
                try {
                    $room = RoomService::get($roomId, $c->user); // also the seat's heartbeat
                } catch (ApiError) {
                    unset($c->rooms[$roomId]);
                    continue;
                }
                $now = md5(json_encode($room));
                if ($now !== $hash) {
                    $c->rooms[$roomId] = $now;
                    $this->send($c, ['t' => 'room', 'room' => $room]);
                }
            }
        }
    }
}
