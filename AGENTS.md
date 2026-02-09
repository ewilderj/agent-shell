# Agent Notes for agent-shell Development

This file is kept in my fork only - not submitted upstream.

## Git Remotes

```
origin    → ewilderj/agent-shell (my fork)
upstream  → xenodium/agent-shell (upstream, read-only)
```

## Development Workflow

**For each feature/fix:**
```bash
# 1. Start from upstream's main (clean base for PRs)
git fetch upstream
git checkout -b feature-name upstream/main

# 2. Make changes, commit
git add -p && git commit

# 3. Push to your fork
git push origin feature-name

# 4. Create PR
gh pr create --repo xenodium/agent-shell

# 5. Merge into your local main (so you can use it immediately)
git checkout main
git merge feature-name
git push origin main
```

**When upstream merges your PR:**
```bash
git fetch upstream
git rebase upstream/main    # removes duplicate commits automatically
git push origin main
```

**Key principle:** Feature branches start clean from `upstream/main` for PRs. 
Your `main` accumulates all in-progress work for daily use.

## Emacs Dev Setup

My `~/.emacs.d/personal/agent-shell.el` auto-detects `~/git/agent-shell`:
- If present: loads from local git (dev mode)
- If absent: uses ELPA packages (stable mode)

**Reload without restart:** `M-x ewj/reload-agent-shell`

ELPA-only patches (advice) are gated with `(unless ewj/agent-shell-dev-p ...)` - 
implement features directly in the code when developing.

## Contributing Guidelines

Per upstream README:
- File a feature request first for new features
- Use **alists** with `:keywords` (not plists/hashtables)
- Use **seq.el** for list operations
- Use **map.el** for alist access (`map-elt`)
- Limit **cl-lib** to `cl-defun` with `&key`
- Run `M-x checkdoc` and `M-x byte-compile-file` before PRing

## Open PRs

- #272: Update ASCII art to match official CLI banner
