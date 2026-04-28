# V1 Boundaries (Strict)

## Rule for AI and Developers

If a feature is not listed in a section’s version 1 scope, do not build it now.

## Hard Exclusions

- online payment gateway and card integrations
- hospital ERP modules
- insurance and government procurement flows
- advanced accounting and distributor workflows
- enterprise compliance automation
- AI forecasting
- export engine (PDF/Excel) — out of scope for version 1
- branch transfer workflow — out of scope for version 1

## Guardrail Checklist Before Merge

- does the change add a module outside the version 1 scope? if yes, reject
- does the change increase role/permission complexity? if yes, defer
- does the change require external integrations? if yes, defer
- does the change slow POS flow? if yes, redesign

## Why This Strictness

- faster launch
- easier testing
- lower support burden
- better fit for first customers
