<?php
declare(strict_types=1);

require dirname(__DIR__) . '/src/bootstrap.php';

// Smoke: Cors class loads (headers tested in integration / manual browser).
assert(class_exists(App\Cors::class));
echo "cors_test ok\n";
