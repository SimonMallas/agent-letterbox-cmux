# Webhook bridge e2e proof (filesystem oracle)

## Why this exists

A local Hermes webhook can start a **real agent turn** with a fixed prompt such as “check your Agent Letterbox inbox.” That is not enough.

**Prior failure mode (hallucinated completion):** the turn ran, the model wrote that it had handled the inbox, and **no** Letterbox `ack`/`result` was delivered and the original letter was **not** moved to `processed/`. Operator confidence based on chat prose was wrong.

**Rule:** completion is proven only by **on-disk Letterbox evidence**, never by model text.

```text
PASS only if ALL hold:
  1. original message absent from <agent>/inbox/
  2. original message present in <agent>/processed/ (same id:)
  3. peer inbox holds ack|nack|result with re: = original id, from: = agent
```

## Artifacts in this repo

| Path | Role |
|------|------|
| [`tests/webhook_e2e_oracle.sh`](../tests/webhook_e2e_oracle.sh) | Pure checker. Exit 0/1 from filesystem only. |
| [`tests/webhook_e2e_harness.sh`](../tests/webhook_e2e_harness.sh) | Disposable letterbox + mock agent behaviors. **No** Hermes webhooks, watchers, or config changes. |

### Run (no Hermes required)

```bash
chmod +x tests/webhook_e2e_oracle.sh tests/webhook_e2e_harness.sh
./tests/webhook_e2e_harness.sh
# expect: webhook e2e harness: PASS
```

Harness scenarios:

| ID | Simulated agent behavior | Oracle must |
|----|--------------------------|-------------|
| A | Honest: `letterbox reply` (publish + archive) | **PASS** |
| B | Hallucinated: session note “I handled it”, no letterbox ops | **FAIL** |
| C | Partial: `letterbox send` ack to peer, original left in inbox | **FAIL** |

## Live Hermes gate (manual; optional)

When you *do* exercise a real loopback webhook (outside this harness):

1. Use a **disposable** `LETTERBOX_DIR` (never production inboxes for FTU).
2. `letterbox send` a `delegate` with `--ack` from a peer agent into `hermes`.
3. Trigger the turn however you normally would (fixed-prompt webhook POST). **Do not** put letter bodies in the HTTP payload.
4. After the turn, run:

```bash
export LETTERBOX_DIR=/path/to/disposable-box
./tests/webhook_e2e_oracle.sh \
  --agent hermes \
  --peer planner \
  --message-id '<id from the delegate frontmatter>'
```

5. **PASS** = exit 0. Chat claims without exit 0 are ignored.
6. Rollback subscriptions/watchers separately; the oracle does not touch Hermes.

## What this does *not* prove

- That HMAC, loopback bind, or webhook auth are correct (threat model / Hermes ops).
- That the HTTP request omitted letter bodies (inspect the POST separately).
- That the model understood the task quality—only that protocol completion artifacts exist.

## CI

`tests/webhook_e2e_harness.sh` is dependency-free Bash and safe for CI next to `tests/smoke.sh`.
