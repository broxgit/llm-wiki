# Sync

Read this to commit and push by hand, or when a pull hits a conflict or a commit is refused. `wiki.sh sync` does the usual case in one call.

This section applies in two cases. One: this folder is the top level of a git repo. Two: this folder's parent is a wiki collection, meaning a git repo whose top level holds a `WIKIS.md` file. In a collection, commit only the wiki folders you changed. If this wiki sits inside any other repo, or has no git, skip this section and leave commits to the user.

- `wiki.sh sync <wiki> -m "<message>"` does the commit and push below for one wiki: it commits only that wiki's folder and pushes. It pulls, with a merge, only when the push is refused because the remote has commits you don't, or when there was nothing to push. It prints `synced:` when something was pushed and `up to date:` when it only pulled. Use it when you have the script.
- Pull before any write, if the repo has a remote. Pull with a merge (`git pull --no-rebase`), never a rebase or a stash: other sessions may have uncommitted notes in other wikis, and a rebase refuses to run while they're there.
- Commit at each compile: every changed file, waiting captures included, in one commit per wiki. Don't commit each capture by itself. If you captured and no compile follows before the user's current request is done, commit the captures then.
- Start commit messages with the wiki's name: `<wiki>: ingest <title>`, `<wiki>: ingest 6 notes`, `<wiki>: capture 3 notes`, `<wiki>: lint`.
- Push after each commit if the repo has a remote. If the push is rejected, pull and push again, once.
- On a merge conflict in `index.md` or `log.md`, keep the lines from both sides. On a conflict inside a page, stop and ask the user.

## A page changed on two machines

`wiki.sh sync` joins what needs no judgment by itself: edits to different parts of a page, two additions at one spot, the later date, the sources of both, and every open item. When it can't, it undoes the pull, names the files, and stops. Nothing of it is left half done, your commits are still there, and nothing is pushed from this machine until it is settled. `wiki.sh status` says so until then.

1. Tell the user which files, and ask what to keep: one machine's version, the other's, or both. Don't choose for them, unless they have already said.
2. Start the merge again: `git -C <the collection> pull --no-rebase`. It stops on the same files.
3. Edit each file so it reads as the user said, with none of git's markers left. For a page, that means one `summary`, the `sources` of both, and the later `updated`.
4. Finish the merge by hand: `git -C <the collection> add <those files>`, then `git -C <the collection> commit --no-edit`. `wiki.sh sync` won't run in the middle of a merge, so it can't do this step.
5. Read `index.md` and `log.md` before you push. Git joins them a line at a time, which can leave two lines for one page, or an entry a line short. Run `wiki.sh index <wiki>`, and mend the log by hand.
6. `wiki.sh sync <wiki>` pushes it.
- If a commit is refused because it holds a secret, replace the secret with `[REDACTED]` in that file, even in `raw/`, and commit again. Tell the user. If you think it is not a secret, ask the user before allowing it. Never skip the check with `--no-verify`.

