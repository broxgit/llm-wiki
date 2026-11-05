---
title: Delivery queue in Postgres, not Redis
summary: The delivery queue is a Postgres table, because a delivery must commit with the event that caused it.
tags: [queue, postgres, delivery]
sources: [raw/2025-11-03-101500-queue-decision.md]
updated: @TODAY@
verified: @TODAY@
---

# Delivery queue in Postgres, not Redis

The queue is the `deliveries` table, read with `FOR UPDATE SKIP LOCKED`. A delivery row commits in the same transaction as the event that caused it, so no event is lost and none is sent twice for a rolled-back change. [raw/2025-11-03-101500-queue-decision.md]

Redis was tried first and turned down: a crash between the commit and the enqueue lost deliveries twice in its trial week. The cost is throughput, about 2,000 deliveries a second, which is ten times today's peak. Look again if the peak passes 1,000. [raw/2025-11-03-101500-queue-decision.md]

Billing reads the outcome of these deliveries: see `billing:wiki/concepts/invoice-events.md`.

How failed deliveries are tried again: [Webhook retries](../concepts/webhook-retries.md). What one can carry: [Payload limits](../concepts/payload-limits.md). The runbook is on [the on-call page](../howto/on-call.md).
