# Teams

A team shares one collection: one git repo holding a wiki per project, so what one person's agent learns about a service, every other person's agent can find. Each person still sets up their own machine. The same steps work for one person with two machines.

## Start a shared collection

One person does this once.

1. Run `wiki setup`, or `wiki init --git` for no questions. Either makes `~/wikis` a git repo.
2. Create an empty repository for it on your git host, and add it as the remote when setup asks, or run `git -C ~/wikis remote add origin <url>`.
3. Push: `git -C ~/wikis push -u origin HEAD`.

Keep work and personal knowledge apart. A team collection holds work only. For personal notes, keep a second collection somewhere else and point `WIKIS_DIR` at it when you want it.

## Join a shared collection

Everyone else, on each machine:

1. Clone the collection: `git clone <url> ~/wikis`.
2. Follow your setup guide, [Claude Code](claude-code.md) or [another agent](other-agents.md). Setup finds the cloned collection and asks only about this machine: commit email, SSH key, the journal.

## Offer the plugin in a repository

To have Claude Code offer the plugin to everyone who works in a repository, commit this to that repository's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "llm-wiki": {
      "source": { "source": "github", "repo": "broxgit/llm-wiki" },
      "autoUpdate": true
    }
  },
  "enabledPlugins": { "llm-wiki@llm-wiki": true }
}
```

Each person who opens the repository and trusts the folder is asked to install it, with auto-update already on. They still run `wiki setup` once per machine. Installing it for everyone with no prompt takes admin-managed settings.

## How sharing works

- **Agents sync on their own.** They pull before writing, commit after compiling, and push, touching only the wiki folders they changed.
- **Merges mostly take care of themselves.** Each wiki's `.gitattributes` has git keep both sides' lines in `index.md` and `log.md`, the two files every compile touches. A conflict inside a page stops the agent, and it asks you.
- **Secrets are blocked.** A pre-commit hook runs [gitleaks](https://github.com/gitleaks/gitleaks) on every commit to the collection and refuses one that holds a key, token or password. The agent then redacts it and tells you. Everyone needs gitleaks installed: `brew install gitleaks`. Without it, commits go through with a warning, and `wiki status` says they aren't scanned.
- **Skills are shared.** A skill in a wiki's `skills/` folder reaches everyone who syncs the collection. See [Team skills](using.md#team-skills).
- **Some things stay on each machine:** the journal, `delegation.md`, and setup answers. Git ignores them.
- **Handbook versions.** When one person upgrades the shared wikis to a newer handbook, `wiki status` tells everyone else their template is behind. Plugin users with auto-update get the new version on their own. Clone users pull the template.

## Things to agree on

- **What goes in.** Work knowledge only, nothing about people that you wouldn't say in standup, and no customer data. The agent never stores secrets, and the scan backs that up.
- **Who reviews.** Agents push straight to the collection's default branch. There's no review step yet; it's on the roadmap. If your team needs one before changes land, hold off on a shared collection for now.
- **Wiki names.** A wiki is named after its repository, so two repositories with the same name in different orgs share one wiki. The tool can't tell them apart yet. If that happens, keep their knowledge on separate pages inside that wiki.
