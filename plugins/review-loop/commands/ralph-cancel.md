---
description: "Cancel an active Ralph plan loop"
allowed-tools:
  - Bash(test -f .claude/ralph-loop.local.md *)
  - Bash(rm -f .claude/ralph-loop.local.md)
  - Read
---

Check if a review loop is active:

```bash
test -f .claude/ralph-loop.local.md && echo "ACTIVE" || echo "NONE"
```

If active, read `.claude/ralph-loop.local.md` to get the current phase and review ID.

Then remove the state file:

```bash
rm -f .claude/ralph-loop.local.md
```

Report: "Ralph loop cancelled (was at phase: X, review ID: Y)"

If no Ralph loop was active, report: "No active Ralph loop found."
