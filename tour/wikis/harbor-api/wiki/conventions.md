---
title: Conventions for harbor-api
summary: Rules for this project's code and how agents work on it.
tags: [conventions]
sources: [raw/2025-06-02-140000-retries.md]
updated: @TODAY@
verified: @TODAY@
---

# Conventions for harbor-api

## For agents

- Run `go test ./...` before calling a change done. [raw/2025-06-02-140000-retries.md]

## For this project's code

- Never log a webhook's payload. It holds customers' data. [raw/2025-06-02-140000-retries.md]
