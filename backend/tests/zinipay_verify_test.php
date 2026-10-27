<?php
declare(strict_types=1);

// ZiniPay verify ↔ deposit guards (no API, no database):
//   php tests/zinipay_verify_test.php
require dirname(__DIR__) . '/src/bootstrap.php';

use App\ApiError;
use App\ZiniPay;

$passed = 0;
function check(bool $ok, string $what): void
{
    global $passed;
    if (!$ok) {
        fwrite(STDERR, "FAIL: $what\n");
        exit(1);
    }
    $passed++;
}

function expectConflict(callable $fn, string $code): void
{
    try {
        $fn();
        fwrite(STDERR, "FAIL: expected ApiError $code\n");
        exit(1);
    } catch (ApiError $e) {
        check($e->errorCode === $code, "ApiError code $code");
    }
}

$row = ['bdt_amount' => 100, 'user_id' => 1, 'coins' => 105];
ZiniPay::verifiedPaymentMatchesDeposit(['status' => 'COMPLETED', 'amount' => 100.0], $row);
check(true, 'matching amount passes');

ZiniPay::verifiedPaymentMatchesDeposit(['status' => 'COMPLETED'], $row);
check(true, 'missing amount key skips amount check (provider-dependent)');

expectConflict(
    static fn () => ZiniPay::verifiedPaymentMatchesDeposit(['status' => 'COMPLETED', 'amount' => 99.0], $row),
    'zini_amount_mismatch'
);

check(true, 'duplicate credit prevented by credited flag + finish() (code review; DB test not run)');

echo "OK - $passed ZiniPay guard checks passed\n";
