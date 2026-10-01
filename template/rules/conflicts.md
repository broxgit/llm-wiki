# Conflicts

Read this when a source disagrees with an existing page, or when you doubt a claim you are filing. Three cases.

**Correction.** A later source says outright that an earlier claim was wrong, or answers a question that was still open. Later means later in filename order. A note recording that you checked a claim against the code and found it false is a correction. The later source wins. State the current claim, add one sentence on what it replaced, and cite both sources. No flag.

**Contradiction.** Sources disagree and neither says it corrects the other. Keep both claims and flag it on the page where the claim lives:

```markdown
> **Conflict:** raw/2026-01-15-093000-a.pdf says X. raw/2026-03-02-141500-b.md says Y. Unresolved.
```

Only the user resolves a contradiction. When they do, keep the winning claim, note the superseded one in a sentence, and log it.

**Doubt.** You have good reason to think a claim you are filing is wrong or incomplete, but no source says so and you can't check it. File the claim as given. Add one line under it:

```markdown
> **Check:** what you doubt and why, in one sentence. (agent note)
```

Tell the user in your reply as well. Remove the line once a source settles it.

**Source summaries.** Pages under `wiki/sources/` describe only their own source, so don't rewrite or flag them. When a later source corrects or contradicts one, add a single line to that summary linking to the page with the current claim. Bump its `updated` date and list it in the log entry.
