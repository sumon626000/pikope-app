<?php
declare(strict_types=1);

namespace App;

/** An error the client is told about: HTTP status plus a stable code. */
final class ApiError extends \RuntimeException
{
    public function __construct(public readonly int $status, public readonly string $errorCode, string $message)
    {
        parent::__construct($message);
    }

    public static function badRequest(string $message, string $code = 'bad_request'): self
    {
        return new self(400, $code, $message);
    }

    public static function unauthorized(string $message = 'Sign in required'): self
    {
        return new self(401, 'unauthorized', $message);
    }

    public static function forbidden(string $message = 'Not allowed'): self
    {
        return new self(403, 'forbidden', $message);
    }

    public static function notFound(string $message = 'Not found'): self
    {
        return new self(404, 'not_found', $message);
    }

    public static function conflict(string $message, string $code = 'conflict'): self
    {
        return new self(409, $code, $message);
    }
}
