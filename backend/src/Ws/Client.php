<?php
declare(strict_types=1);

namespace App\Ws;

/** One WebSocket connection. */
final class Client
{
    public string $in = '';
    public string $out = '';
    public string $fragment = '';
    public bool $open = false;
    public bool $closing = false;
    public float $lastSeen;

    /** @var array<string,mixed>|null the signed-in user row */
    public ?array $user = null;
    /** @var array<int,true> matches this connection plays in */
    public array $games = [];

    /** @var array<int,int> gameId => this player's seat */
    public array $seats = [];

    public float $lastChat = 0.0;
    /** @var array<int,string> waiting rooms watched: id => hash of what was last sent */
    public array $rooms = [];

    /** @param resource $socket */
    public function __construct(public $socket)
    {
        $this->lastSeen = microtime(true);
    }
}
