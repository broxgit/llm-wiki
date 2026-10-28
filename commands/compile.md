---
description: Compile waiting notes into wiki pages now, in this wiki or one you name
argument-hint: "[wiki name]"
allowed-tools: Bash
---

Waiting notes per wiki, from `wiki.sh status`:

!`"${CLAUDE_PLUGIN_ROOT}/wiki.sh" status`

Compile now. With a wiki name ($ARGUMENTS), compile that wiki. Without one, compile this session's wiki and any shared wiki with notes waiting. Follow `rules/compile.md` in each wiki: take its lock, ingest every pending file in order, update the index and log, check whether lint is due, and release the lock. Commit as the handbook's Sync section says. If another session holds a lock, skip that wiki and say so.

Report in one line per wiki: pages created, pages updated, corrections, conflicts.
