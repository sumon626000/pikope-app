<?php
declare(strict_types=1);

// Front controller. Point the web server's document root at this directory.
// With PHP's built-in server (development): php -S 0.0.0.0:8080 -t public public/index.php
if (PHP_SAPI === 'cli-server') {
    $file = __DIR__ . parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
    if (is_file($file) && !str_ends_with($file, '.php')) {
        return false; // let the built-in server send uploaded images
    }
}

require dirname(__DIR__) . '/src/bootstrap.php';

App\Api::handle();
