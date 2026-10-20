# Protocol reference

Letters are durable files. Doorbells are generic live-session attention signals.

For actionable work, reply before archive. Use `letterbox reply`; it publishes the reply before changing local lifecycle state. ACK leaves the original open; final result or nack files it.

Preserve urgency: add `--now` to a reply only when the original letter had `priority: now`. Acknowledgement alone does not require urgency escalation.
