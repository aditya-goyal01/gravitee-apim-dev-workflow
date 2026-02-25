---
name: install-mcp-servers
description: Recommend and install MCP servers for Gravitee APIM development — GitHub, databases, Docker, and more
user-invocable: true
disable-model-invocation: true
allowed-tools: Bash, Read
---

# Install MCP Servers — External Integrations for Gravitee APIM

You are running the `/gravitee-dev-workflow:install-mcp-servers` skill. Follow these instructions to recommend and install MCP servers.

## General Rules

- **Never install without consent**: always ask the Dev which servers they want before installing anything
- **Continue on failure**: if an install fails, log the failure and move to the next one
- **Report everything**: after each install, tell the Dev what happened

## Step 1 — Show Recommended MCP Servers

Present the following categorized list to the Dev:

### Source Control (Essential)

| Server | Note |
|--------|------|
| `github` | Official GitHub MCP server — manage repos, PRs, issues, and code reviews directly from the terminal. Required for any GitHub-based workflow. |

### Databases

| Server | Note |
|--------|------|
| `mongodb` | Official MongoDB MCP server — query collections, inspect schemas, and manage data in the Gravitee persistence layer. Default APIM database. |
| `elasticsearch` | Official Elastic MCP server — search indices, analyze mappings, and query the Gravitee analytics backend. |
| `postgres` | PostgreSQL MCP server — for teams using the JDBC alternative to MongoDB. Query tables, explore schemas. |

### Containers

| Server | Note |
|--------|------|
| `docker` | Manage Docker containers from Claude Code — inspect running APIM services, view logs, restart containers without leaving the terminal. |

### Project Management

| Server | Note |
|--------|------|
| `atlassian` | Official Atlassian MCP server — read Jira issues, update ticket status, and link PRs to stories. Connects via OAuth. |

### Build Intelligence

| Server | Note |
|--------|------|
| `maven-tools` | Maven Central dependency intelligence — check dependency freshness, find latest versions, and analyze release history for Gravitee's Java dependencies. |

### Error Monitoring (Optional)

| Server | Note |
|--------|------|
| `sentry` | Connect to Sentry for real-time error monitoring — view stack traces, track regressions, and analyze production issues from Claude Code. |

## Step 2 — Ask About Database Backend

Ask the Dev:

> **Which database backend does your APIM setup use?**
>
> 1. MongoDB + Elasticsearch (default)
> 2. PostgreSQL + Elasticsearch (JDBC alternative)
> 3. All three (MongoDB, PostgreSQL, and Elasticsearch)

Pre-select the relevant database servers based on their answer for the next step.

## Step 3 — Ask Which Servers to Install

Ask the Dev which MCP servers they want to install. Present it as a multi-select with the database servers pre-selected based on Step 2. They can pick individual servers, entire categories, or "all".

Do NOT proceed until the Dev has made their selection.

## Step 4 — Install Selected Servers

For each selected server, run the corresponding install command:

**GitHub:**

```bash
claude mcp add --transport http github https://api.githubcopilot.com/mcp/
```

**MongoDB:**

```bash
claude mcp add --transport stdio mongodb --env MONGODB_URI=mongodb://localhost:27017/gravitee -- npx -y @mongodb-mcp/server
```

**Elasticsearch:**

```bash
claude mcp add --transport stdio elasticsearch --env ELASTICSEARCH_URL=http://localhost:9200 -- npx -y @elastic/mcp-server-elasticsearch
```

**PostgreSQL:**

```bash
claude mcp add --transport stdio postgres --env DATABASE_URL=postgresql://grvt:pswd@localhost:5432/gravitee -- npx -y postgres-mcp
```

**Docker:**

```bash
claude mcp add --transport stdio docker -- npx -y docker-mcp
```

**Atlassian:**

```bash
claude mcp add --transport http atlassian https://mcp.atlassian.com/mcp
```

**Maven Tools:**

```bash
claude mcp add --transport stdio maven-tools -- npx -y maven-tools-mcp
```

**Sentry:**

```bash
claude mcp add --transport http sentry https://mcp.sentry.dev/mcp
```

Track the outcome of each install: installed / already present / failed.

## Step 5 — Auth Reminders

For servers that require authentication, remind the Dev:

> **Authentication required**: The following servers need you to authenticate before they can be used. Run `/mcp` and complete the auth flow for each:

List only the servers that were actually installed and need auth (GitHub, Atlassian, Sentry).

## Step 6 — Summary

Print a checklist of all selected servers with their outcomes:

```
## MCP Server Installation Summary

- [x] github — installed (run /mcp to authenticate)
- [x] mongodb — installed
- [x] elasticsearch — installed
- [ ] docker — failed (reason)
...
```

If any servers use placeholder connection strings (like the PostgreSQL `DATABASE_URL` or MongoDB `MONGODB_URI`), remind the Dev:

> **Connection strings**: Some servers were installed with default connection strings. If your local setup uses different ports or credentials, update them via `/mcp`.

Then congratulate the Dev on completing the onboarding journey:

> **Setup complete!** You've finished the Gravitee APIM onboarding journey. Your dev environment, Claude Code plugins, and external integrations are all configured. Start coding, or run `/gravitee-dev-workflow:hello` any time to see all available skills.

## Constraints

- Never install a server without explicit Dev consent
- Never modify existing MCP server configurations
- If an install fails, log the error and continue — do not retry automatically
- For database servers, always ask about the backend before pre-selecting
