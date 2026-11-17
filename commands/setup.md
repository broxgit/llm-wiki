---
description: Walk through llm-wiki setup with you, one topic at a time, in this session
argument-hint: "[section, such as extensions, jira, confluence or journal]"
allowed-tools: Bash, AskUserQuestion
---

The setup guide, from `wiki.sh setup --guide $ARGUMENTS`:

!`"${CLAUDE_PLUGIN_ROOT}/wiki.sh" setup --guide $ARGUMENTS`

Follow the guide with the user, as its rules say. Don't paste it. Never ask for or write a token.

If you have a tool that shows the user a question with choices, such as AskUserQuestion, ask with it, not in prose: one topic a question, its answers as the choices, in plain words, with the one you'd pick first and marked as your pick. Up to four related topics can go in one call. Keep free typing for what has no short list of answers, such as a folder.
