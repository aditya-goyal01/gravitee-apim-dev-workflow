---
name: install-plugins
description: Recommend and install official Claude Code plugins for Gravitee APIM development
user-invocable: true
disable-model-invocation: true
allowed-tools: Bash, Read
---

# Install Plugins — Claude Code Plugins for Gravitee APIM

You are running the `/gravitee-dev-workflow:install-plugins` skill. Follow these instructions to recommend and install official Claude Code plugins.

## General Rules

- **Never install without consent**: always ask the Dev which plugins they want before installing anything
- **Continue on failure**: if a plugin install fails, log the failure and move to the next one
- **Report everything**: after each install, tell the Dev what happened

## Step 0 — Ensure Marketplace is Configured

Before listing or installing anything, check that the `claude-plugins-official` marketplace is registered:

```bash
claude plugin marketplace list 2>&1 | grep -q "claude-plugins-official" \
  || claude plugin marketplace add https://github.com/anthropics/claude-plugins-official
```

If the marketplace add fails, warn the Dev and stop:

> **Error**: Could not reach the `claude-plugins-official` marketplace. Check your internet connection and try again.

## Step 1 — Show Recommended Plugins

Present the following categorized list to the Dev:

### Code Intelligence (LSP)

| Plugin | Note |
|--------|------|
| `jdtls-lsp` | Adds Java language server support — go-to-definition, diagnostics, and refactoring for the Gravitee Java 21 backend. Requires `jdtls` binary. |
| `typescript-lsp` | Adds TypeScript language server support — essential for Angular frontend development with real-time type checking. Requires `typescript-language-server`. |

### Git & Code Review

| Plugin | Note |
|--------|------|
| `commit-commands` | Streamlines the git commit workflow — smart commit messages, push, and PR creation from within Claude Code. |
| `pr-review-toolkit` | Multi-agent PR review that checks comments, tests, error handling, type design, and code quality in parallel. |
| `security-guidance` | Adds a hook that flags potential security issues as you code — OWASP-style warnings before they reach review. |

### Quality & Testing

| Plugin | Note |
|--------|------|
| `sonatype-guide` | Analyzes Maven/Java dependencies for known vulnerabilities and license risks using Sonatype intelligence. |
| `playwright` | Browser automation for Angular E2E tests — write, run, and debug end-to-end tests from Claude Code. |

### Integrations

| Plugin | Note |
|--------|------|
| `atlassian` | Connect to Jira and Confluence — read issues, update tickets, and link PRs to Jira stories directly. |

## Step 2 — Ask the Dev

Ask the Dev which plugins they want to install. Present it as a multi-select — they can pick individual plugins, entire categories, or "all".

Do NOT proceed until the Dev has made their selection.

## Step 3 — Install Selected Plugins

For each selected plugin, run:

```bash
claude plugin install <plugin-name>@claude-plugins-official
```

Track the outcome of each install: installed / already present / failed.

## Step 4 — Summary

Print a checklist of all selected plugins with their outcomes:

```
## Plugin Installation Summary

- [x] jdtls-lsp — installed
- [x] commit-commands — already present
- [ ] playwright — failed (reason)
...
```

If any plugins require additional setup (like `jdtls-lsp` needing the `jdtls` binary or `typescript-lsp` needing `typescript-language-server`), remind the Dev:

> **Post-install**: Some plugins require external tools. Make sure you have the required binaries installed (see the notes above).

Then suggest the next step in the journey:

> **Next step**: Run `/gravitee-dev-workflow:install-mcp-servers` to connect external tools like GitHub, databases, Docker, and more.

## Constraints

- Never install a plugin without explicit Dev consent
- Never modify existing plugin configurations
- If a plugin install fails, log the error and continue — do not retry automatically
