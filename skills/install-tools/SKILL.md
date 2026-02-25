---
name: install-tools
description: Install and configure the Gravitee APIM development environment — Homebrew, Java, Maven, Node, Docker, and dev tools
user-invocable: true
disable-model-invocation: true
allowed-tools: Bash, Read, Write
---

# Install Tools — Gravitee APIM Dev Environment Setup

You are running the `/gravitee-dev-workflow:install-tools` skill. Follow these instructions to perform a guided, fail-safe installation of the Gravitee APIM development environment.

## General Rules

- **Check before installing**: always verify if a tool is already present before attempting to install it
- **Continue on failure**: if a step fails, log the failure and move to the next step — no step blocks the rest
- **Report everything**: after each step, tell the Dev what you found or installed
- **Ask before optional steps**: steps marked **(ask Dev first)** require explicit confirmation before proceeding
- **Never overwrite existing config** without asking the Dev first
- Track every step outcome for the summary: installed / already present / skipped / failed

## Resources Directory

Resource files referenced below are located relative to this SKILL.md:

```
resources/
├── settings.xml.template       # Maven settings for Gravitee repos
├── gravitee_aliases.sh         # Shell aliases for APIM dev
└── nvm-auto.sh                 # NVM auto-switching script
```

To locate these files, Glob for `**/gravitee-dev-workflow/skills/install-tools/resources/` to find the absolute path, then Read each file from there.

## Steps

### Step 1 — Check OS

Confirm the Dev is running macOS by checking `uname -s`. If not macOS, warn:

> This skill is designed for macOS. Some steps may not work on your OS. Continue anyway?

If the Dev says no, stop here.

### Step 2 — Homebrew

```bash
brew --version
```

If missing, install via the official script:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### Step 3 — Shell Tools

Install via brew if not already present:

```bash
brew install wget fzf shellcheck
```

`shellcheck` provides static analysis for bash scripts — used by test-hooks.sh to verify hook quality.

### Step 4 — Oh My Zsh + Powerlevel10k

Check if `~/.oh-my-zsh` exists. If missing:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
```

Install Powerlevel10k theme:

```bash
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
```

Install plugins:

```bash
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/djui/alias-tips ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/alias-tips
```

Tell the Dev to set `ZSH_THEME="powerlevel10k/powerlevel10k"` in `~/.zshrc` and add `zsh-autosuggestions` and `alias-tips` to the plugins list.

### Step 5 — NVM + Node

```bash
brew install nvm
```

Ensure `~/.zshrc` contains the NVM initialization block:

```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$(brew --prefix nvm)/nvm.sh" ] && \. "$(brew --prefix nvm)/nvm.sh"
[ -s "$(brew --prefix nvm)/etc/bash_completion.d/nvm" ] && \. "$(brew --prefix nvm)/etc/bash_completion.d/nvm"
```

Read `resources/nvm-auto.sh` and append its contents to `~/.zshrc` if not already present (check for the `load-nvmrc` function).

### Step 6 — Yarn

```bash
brew install yarn
```

### Step 7 — SDKMAN + Java + Maven

Check if SDKMAN is installed (`~/.sdkman/bin/sdkman-init.sh` exists). If missing:

```bash
curl -s "https://get.sdkman.io" | bash
```

Then source SDKMAN and install Java and Maven:

```bash
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk install maven
```

For Java, run `sdk list java | grep -i tem` to find the latest Temurin 21.x identifier, then install it:

```bash
sdk install java <latest-21.x-tem-identifier>
```

If a Temurin 21.x version is already installed, skip it.

### Step 8 — Angular CLI

```bash
brew install angular-cli
```

### Step 9 — Docker

```bash
brew install docker
brew install --cask rancher
```

### Step 10 — Maven Settings

Check if `~/.m2/settings.xml` exists. If it does, ask the Dev before overwriting.

If proceeding:

```bash
mkdir -p ~/.m2
```

Read `resources/settings.xml.template` and write it to `~/.m2/settings.xml`.

Remind the Dev:

> **Action required**: Edit `~/.m2/settings.xml` and replace `YOUR_JFROG_USERNAME` and `YOUR_JFROG_ENCRYPTED_PASSWORD` with your Gravitee Artifactory credentials. Ask your team lead if you don't have them yet.

### Step 11 — Gravitee Aliases

Read `resources/gravitee_aliases.sh` and write it to `~/.gravitee_aliases`.

Check if `~/.zshrc` already sources this file. If not, append:

```bash
# Gravitee APIM dev aliases
source ~/.gravitee_aliases
```

### Step 12 — Gravitee Workspace

```bash
mkdir -p ~/workspace/Gravitee
```

### Step 13 — Prettier

```bash
yarn global add prettier prettier-plugin-java
```

Create `~/.config/prettier/prettier.config.js` if it doesn't exist:

```javascript
module.exports = {
    printWidth: 140,
    tabWidth: 4,
};
```

### Step 14 — IDEs (ask Dev first)

Ask the Dev which IDEs they want to install:

- **IntelliJ IDEA Ultimate**: `brew install --cask intellij-idea`
- **VS Code**: `brew install --cask visual-studio-code`

Only install what the Dev selects.

### Step 15 — Applications (ask Dev first)

Ask the Dev which apps they want to install:

- **iTerm2**: `brew install --cask iterm2`
- **Postman**: `brew install --cask postman`
- **Chrome**: `brew install --cask google-chrome`
- **Slack**: `brew install --cask slack`
- **MongoDB Compass**: `brew install --cask mongodb-compass`
- **Azure CLI**: `brew install azure-cli`

Only install what the Dev selects.

### Step 16 — Rosetta (Apple Silicon only)

Check if running on Apple Silicon (`uname -m` returns `arm64`). If so:

```bash
softwareupdate --install-rosetta --agree-to-license
```

### Step 17 — Summary

Print a checklist of all steps with their outcomes:

```
## Installation Summary

- [x] Homebrew — already present (v4.x.x)
- [x] Shell Tools (wget, fzf, shellcheck) — installed
- [ ] Oh My Zsh — skipped (already installed)
- [x] NVM + Node — installed
...
```

Then list post-install actions:

> ### Post-Install Actions
>
> 1. **Restart your terminal** (or run `source ~/.zshrc`) for all changes to take effect
> 2. **Configure Maven credentials** in `~/.m2/settings.xml` — replace the placeholder values
> 3. **Run `p10k configure`** to set up your Powerlevel10k prompt theme

Then suggest the next step in the journey:

> **Next step**: Run `/gravitee-dev-workflow:install-plugins` to add Claude Code plugins for code intelligence, code review, and testing.

## Constraints

- Never run `sudo` without asking the Dev first
- Never modify system files outside of `$HOME`
- Always check before installing — never reinstall something that's already present
- If a brew install fails, suggest the Dev run `brew doctor` and retry
