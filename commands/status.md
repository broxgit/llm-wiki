---
description: What needs attention in your wikis - notes waiting, lint due, patterns ready, handbooks behind, setup gaps
allowed-tools: Bash
---

The state of the user's wikis, from `wiki.sh status`:

!`"${CLAUDE_PLUGIN_ROOT}/wiki.sh" status`

Tell the user, in a few lines, only what needs attention: the items under To do. Each ends with its fix, `Run:` a command, `Ask an agent:` a request, or `Do:` a step. Keep the fix. A request to an agent is one you can do now, so offer to. If there is no To do, say nothing needs attention, in one line. Don't paste the table.
