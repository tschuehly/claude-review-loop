---
description: "Disable stress-test in the review loop"
allowed-tools:
  - Bash
---

Disable stress-test for the review loop by removing the toggle file:

```bash
rm -f .claude/stress-test.enabled && echo "Stress-test disabled. Future /review-loop runs will skip plan verification."
```
