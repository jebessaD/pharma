# 06 - Expiry (version 1)

## Version 1 scope (build now)

- near-expiry list
- expired list
- block selling expired batches

## Out of Scope (Do Not Build)

- predictive expiry analytics
- automatic supplier claim workflows

## AI Implementation Directive

- Flutter screens: `NearExpiryList`, `ExpiredList`
- Use `medicine_batches.expiry_date` as source of truth
- Default near-expiry threshold: 90 days
- Enforce sale validation against batch expiry

## Query Logic

- near-expiry: `expiry_date <= current_date + interval '90 days'` and `expiry_date >= current_date`
- expired: `expiry_date < current_date`
- only include batches with positive stock

## Suggested Job

- run daily scheduler (or app-triggered check) to create/update expiry notifications
- avoid duplicate notification rows for same batch/day

## Validation Rules

- POS must validate expiry at checkout time, not only when loading cart
- oldest non-expired batch should be prioritized in selection (FEFO)

## Acceptance Criteria

- expired batches cannot be added to POS cart
- near-expiry list updates daily
- branch filter works for expiry views
