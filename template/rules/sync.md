# Sync

Read this to commit and push by hand, or when a pull hits a conflict or a commit is refused. `wiki.sh sync` does the usual case in one call.

This section applies in two cases. One: this folder is the top level of a git repo. Two: this folder's parent is a wiki collection, meaning a git repo whose top level holds a `WIKIS.md` file. In a collection, commit only the wiki folders you changed. If this wiki sits inside any other repo, or has no git, skip this section and leave commits to the user.

- `wiki.sh sync <wiki> -m "<message>"` does the commit, pull and push below for one wiki: it commits only that wiki's folder, pulls with a merge, and pushes. Use it when you have the script.
- Pull before any write, if the repo has a remote. Pull with a merge (`git pull --no-rebase`), never a rebase or a stash: other sessions may have uncommitted notes in other wikis, and a rebase refuses to run while they're there.
- Commit at each compile: every changed file, waiting captures included, in one commit per wiki. Don't commit each capture by itself. If you captured and no compile follows before the user's current request is done, commit the captures then.
- Start commit messages with the wiki's name: `<wiki>: ingest <title>`, `<wiki>: ingest 6 notes`, `<wiki>: capture 3 notes`, `<wiki>: lint`.
- Push after each commit if the repo has a remote. If the push is rejected, pull and push again, once.
- On a merge conflict in `index.md` or `log.md`, keep the lines from both sides. On a conflict inside a page, stop and ask the user.
- If a commit is refused because it holds a secret, replace the secret with `[REDACTED]` in that file, even in `raw/`, and commit again. Tell the user. If you think it is not a secret, ask the user before allowing it. Never skip the check with `--no-verify`.

