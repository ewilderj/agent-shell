# Agent Notes for agent-shell Development

This file is kept in my fork only - not submitted upstream.

## Git Workflow

```
origin  → xenodium/agent-shell (upstream, read-only)
fork    → ewilderj/agent-shell (my fork, push branches here)
```

**Triangular workflow:**
1. Pull from `origin` (upstream)
2. Create feature branches locally
3. Push to `fork`
4. Create PRs from fork → upstream

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
