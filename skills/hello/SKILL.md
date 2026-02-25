---
name: hello
description: Introduce the Gravitee Dev Workflow plugin, show available skills and project context
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Glob
---

# Hello — Gravitee Dev Workflow

You are running the `/gravitee-dev-workflow:hello` skill. Follow these instructions exactly.

## Step 1 — Welcome

Greet the Dev with a brief welcome:

> **Welcome from Gravitee.io!**
> This plugin helps you set up and work with the Gravitee API Management platform.

## Step 2 — Discover Available Skills

Glob for `**/gravitee-dev-workflow/skills/*/SKILL.md` to find all sibling skill directories.

For each SKILL.md found, use Read to extract the `name` and `description` fields from the YAML frontmatter. Present them in a table:

| Skill | Description |
|-------|-------------|
| `/gravitee-dev-workflow:<name>` | `<description>` |

## Step 3 — Suggest Next Steps

Use Glob to check whether these files exist:

- `~/.m2/settings.xml` — Maven settings for Gravitee Artifactory
- `~/.sdkman/bin/sdkman-init.sh` — SDKMAN (Java/Maven version manager)
- `~/.oh-my-zsh` — Oh My Zsh
- `~/.gravitee_aliases` — Gravitee shell aliases

**If any are missing**, suggest:

> Some dev environment pieces may not be set up yet. Run `/gravitee-dev-workflow:install-tools` to get everything configured.

**If all are present**, say:

> Your dev environment looks ready. Next up: run `/gravitee-dev-workflow:install-plugins` to add Claude Code plugins for code intelligence, code review, and testing.

## Constraints

- Do NOT install anything — this skill is read-only
- Do NOT run Bash commands — only use Read and Glob
- Keep the output concise — no more than ~40 lines of visible output
