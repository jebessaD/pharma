# 09 - Multi-Branch (version 1, limited)

## Version 1 scope (build now)

- support multiple branches under one team
- show stock per branch

## Out of scope (do not build in version 1)

- branch transfer workflow (`requested/sent/received`)
- central warehouse advanced logistics

## AI Implementation Directive

- Flutter screens: `BranchList`, `BranchStockView`
- Use existing `branches` and stock tables with `branch_id`
- Keep branch selector in dashboard and POS
- Defer transfer tables until Phase 2

## Branch Context Rules

- user works in one active branch context at a time
- all POS/inventory actions write selected `branch_id`
- dashboard and reports default to current branch

## Validation Rules

- prevent transaction creation if branch is inactive
- branch switch should not reset unsaved POS cart silently
- branch selection must persist for session

## Acceptance Criteria

- users can switch branch context
- inventory and sales are branch-specific
- no transfer UI or transfer API in version 1
