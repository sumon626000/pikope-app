# Balance / double-send security audit (2026-11-14)

Defense-only hardening against double balance, double tap, and duplicate coin transfer.

## Fixed this pass

| Risk | Fix |
|------|-----|
| P2P transfer double POST | Server `idempotency_key` UNIQUE per sender; wallet reasons `transfer_out:{id}` / `transfer_in:{id}`; row locks both users |
| Transfer double-tap UI | Client `_busy` **before** confirm dialog |
| Transfer spam | Rate limit 15/hour + burst 2 / 15s |
| Deposit / redeem double-tap | Early `if (_busy) return` |
| Free pack spam | Per-pack busy flag |
| Challenge accept/decline double | Early `_busy` guard |

## Already strong (unchanged)

- Daily claim: `FOR UPDATE` + `daily_claimed_on`
- Cue/board ownership: primary key
- ZiniPay credit: `credited` + `FOR UPDATE`
- Manual deposit TrxID unique
- Challenge accept atomic status claim
- Match finish CAS

## Deploy

Requires **backend** + **APK** + **web** (same `lib/` + `backend/`).
