# Feedback on llm-wiki

Read this when `wiki.sh start` prints a `Feedback on llm-wiki` section. The user turned it on so that llm-wiki gets better from what agents run into. Without that section, keep no notes about llm-wiki.

## What's worth a note

Something about llm-wiki itself, with evidence you saw this session:

- **bug:** a `wiki.sh` command failed, printed something wrong, or said it worked when it didn't.
- **friction:** a step took far more effort than it should: you read `wiki.sh` to work out what a message meant, ran a command twice, or did by hand what a command should have done.
- **docs:** two handbook instructions conflicted, or one was unclear enough that you had to guess.
- **idea:** a change that would have saved real effort here, with the case that showed it.

Not worth a note: your own mistakes, a network failure, a sandbox the user set up on purpose (unless llm-wiki's message about it was wrong or unclear), and anything about the user's project rather than llm-wiki.

## How

At most one note per session, at a stopping point, never in the middle of the user's task, and without asking. Pick the one that would help most.

1. Write the details to a file, such as `feedback.md` in your scratch folder or the working folder:
   - what you were doing, and the exact command you ran;
   - what it printed, trimmed to what matters;
   - what you expected, and what you did instead;
   - what would have helped: a better message, a flag, a sentence in the handbook.
   Keep it about llm-wiki. Leave out the user's code, data and anything private. The command replaces paths and names it knows of, not everything.
2. Save it: `wiki.sh feedback add <bug|friction|docs|idea> "<one-line summary>" --agent "<your agent and model>" --file feedback.md`. A summary that matches an earlier note counts as seen again, so reuse the wording of the problem, not of your task.
3. Say it in one line in your reply: "Kept a note about llm-wiki: <summary>."

If the section says notes wait for the user to read, tell them once, at a stopping point, to run `wiki.sh feedback` in a terminal. Never run `wiki.sh feedback send`: filing an issue is the user's decision, made after reading it.
