---
description: "Enable stress-test in the review loop"
allowed-tools:
  - Bash
---

Enable stress-test for the review loop by creating the toggle file:

```bash
mkdir -p .claude && touch .claude/stress-test.enabled && echo "Stress-test enabled. Future /review-loop runs will include plan verification before implementation."
```
