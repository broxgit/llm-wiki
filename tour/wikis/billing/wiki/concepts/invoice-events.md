---
title: Invoice events
summary: Billing charges per successful delivery, from the delivery.succeeded event harbor-api sends. It ignores retries.
tags: [invoices, events]
sources: [raw/2025-08-05-110000-invoice-events.md]
updated: @TODAY@
verified: @TODAY@
---

# Invoice events

Billing charges per successful delivery. It counts `delivery.succeeded` events from harbor-api, one for each delivery however many attempts it took. It needs `customer_id` and `delivered_at` on every event, and an event without them stops the invoice run. [raw/2025-08-05-110000-invoice-events.md]
