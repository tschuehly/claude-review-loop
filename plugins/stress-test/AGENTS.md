# stress-test Plugin — Agent Guidelines

## What this is

A Claude Code skill that adversarially stress-tests technical plans before implementation. It verifies claims against real documentation, runs proof-of-concept code, and updates the plan with findings.

## Conventions

- All POC work MUST happen inside `.poc-stress-test/` — create at start, `rm -rf` at end
- Use sub-agents (Task tool) for parallel verification and POC execution
- Batch shell commands with `&&` to minimize permission prompts
- Never run POCs without explicit user approval (use AskUserQuestion)
- Be adversarial and evidence-based — search real docs, don't reason from memory
- Each POC gets its own subdirectory: `.poc-stress-test/<poc-name>/`

## Modularity

This plugin is independent from `review-loop`. Install or uninstall it separately:
- Install: `claude plugin install stress-test@hamel-review`
- Uninstall: `claude plugin uninstall stress-test`

Both plugins can be used together or independently within the same marketplace.
