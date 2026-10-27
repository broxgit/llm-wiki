# Journal

Read this when the work journal is on and you reach a stopping point, or when the user asks what they did: a standup, a daily or weekly summary, a status report.

The journal is personal to the user. It lives in the `journal/` folder beside the wikis, not inside any wiki. Its `config` file holds the settings. Read it once per session.

## Settings that matter to you

- `enabled`: `no` means do nothing in this file.
- `entries`: `yes` means write one-line entries, below.
- `commit`: `yes` means commit journal files. `no` means never commit them.
- `format`: the default report shape. The user can ask for another.
- `exclude`: repositories and wikis to leave out of entries and reports.
- `save`: `yes` means save each report you write.

## Entries

Write an entry for work that leaves no commit: an investigation, reviewing someone else's code, a meeting outcome the user mentioned, a dead end, a deploy, a question answered for someone. Commits are already picked up by reports, so don't repeat them.

A journal line records that the work happened. It doesn't replace a wiki capture. When the same work also established something worth keeping, such as a root cause, capture that in the wiki as usual.

- One line per project per stopping point, not per message. A few a session at most.
- When the user reports work they did themselves, that is a stopping point.
- Say what was done and how it ended: "Investigated the flaky login test, no fix yet, suspect a timing race." Not "worked on tests."
- Name the project the line belongs to. Use the repository name, or the wiki name for a project that spans several.
- Nothing off the record, no secrets, no customer data, nothing about other people that the user would not say at standup.

Write it with `wiki.sh journal note <project> "<text>"`. The script lives in the template repo, the folder the user-level wiki instruction names. It picks the right day and does nothing when entries are off. Without the script, append one line to `journal/YYYY-MM-DD.md` for the local date, or the day before when the local time is earlier than `day_starts`. Create the file with a `# Journal YYYY-MM-DD` heading if it is missing. The line looks like:

```
- 14:05 [project] What was done and how it ended.
```

Only ever append. Don't edit or reorder earlier lines.

## Backfill

When the user asks to fill in the journal for past days:

1. Get a digest. `wiki.sh journal backfill --since <range>` reads past Claude Code sessions and writes `journal/backfill.md`: one block per project per day, with the user's prompts, files changed, whether it committed, and the last reply. The session files are in `~/.claude/projects` on the user's machine. If you can't reach them, ask the user to run the command. A `backfill.md` that is already there is the digest to use.
2. For each block, write one to three entries by the same bar as live ones: work that left no commit, said as what was done and how it ended. Use `wiki.sh journal note --day <date> --at <time> <project> "<text>"`, with the date and a time from the block. Write each day in time order.
3. Use only what the digest shows. Where it doesn't show how something ended, say so: "no result recorded". Don't guess.
4. Skip blocks that only committed code, did wiki bookkeeping, or worked on the journal. Skip a project on a day whose file already has entries for it.
5. A block named after the wikis folder or the template repo is wiki or tooling work. Name the entry after the project the prompts were about.
6. Delete `backfill.md` when done. Tell the user how many entries you wrote for each day.

## Reports

When the user asks what they did, or for a standup, summary, or status report:

1. Run `wiki.sh standup` from the template repo. It gathers commits by the user across their repositories, journal entries, wiki notes and log entries, work in progress, and open checks. Pass options when the user names a range, a project, or a shape: `--since week` for this week, `--since lastweek`, `--day DATE`, `--only GLOB`, `--exclude GLOB` to leave something out of this one report, `--format`. Without options it covers the last workday through now. Change the `exclude` setting only when the user wants something left out for good.
2. Without the script, gather the same by hand: `git log` in the repositories you can reach, filtered to the user's email and the range; the journal day files; and `raw/` files and `log.md` entries in the range.
3. Write the report in the requested format, or the configured one:
   - `standup`: three short sections, **Yesterday**, **Today**, **Blockers**. Three to six bullets each at most.
   - `summary`: one short section per project, a few bullets each.
   - `detailed`: one section per project, with commit hashes and links to wiki pages.
4. Save it to `journal/YYYY-MM-DD-<format>.md` when `save` is `yes` or the user asks.

Rules for every report:

- Group by project, not by repository. A wiki that covers several repositories is one project.
- Write for a teammate. Outcomes over activity. Plain words, no commit hashes outside `detailed`.
- Merge related commits and entries into one bullet.
- **Yesterday** covers everything before today's start. **Today** covers work already done today, marked done, then work in progress: uncommitted files, unpushed commits, open branches, and "no fix yet" entries. Say the in-progress items are inferred. The user knows their plan better than you do.
- **Blockers** come only from evidence: open `Check` or `Conflict` lines, entries that say the user is waiting on someone, failing work. With none, write "None".
- Leave out anything excluded, and anything off the record.
- Wiki notes and changes tell you what was learned. Report that, not the wiki work itself. Compiling and linting are bookkeeping.
- A report for someone else, such as a manager, is about work. If a project looks personal and the user hasn't excluded it, ask once whether to include it.

Reports are read in place. Don't paste the raw `standup` output to the user unless they ask for it.

## Committing

With `commit=yes`, include changed journal files in your next wiki commit, or commit them alone as `journal: <date>`. With `commit=no`, never commit or push journal files.
