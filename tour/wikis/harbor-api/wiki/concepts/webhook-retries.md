---
title: Webhook retries
summary: A failed delivery is tried 6 times, doubling the wait from 30 seconds, then goes to the dead letter table.
tags: [delivery, retries]
sources: [raw/2025-06-02-140000-retries.md]
updated: 2025-06-02
verified: 2025-06-02
commit: @COMMIT@
---

# Webhook retries

A failed delivery is tried 6 times. The wait doubles each time, starting at 30 seconds. After the last attempt it goes to the dead letter table, where support can send it again by hand. [raw/2025-06-02-140000-retries.md]

The code is `delivery/retry.go`. Deliveries wait in [the queue](../decisions/postgres-queue.md).
