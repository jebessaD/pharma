# Product roadmap (version 1 first)

## Vision

Pharmacy operations app for Ethiopia:
- less expiry loss
- faster checkout
- better stock visibility

## Phase 1 — version 1 (now)

- platform owner basics
- team setup and branches
- user roles (`admin`, `pharmacist`, `cashier`)
- medicine + batch + conversion
- inventory in/out/adjustment
- expiry checks and blocked expired sales
- POS with cash/bank transfer
- purchases receive-to-stock
- basic dashboard, notifications, reports, audit logs

### Phase 1 Technical Milestones

- M1: auth, roles, team isolation, RLS baseline
- M2: medicine catalog + inventory engine
- M3: POS + expiry enforcement
- M4: purchases + dashboard + reports + audit UI

### Exit criteria for version 1 release

- at least one pharmacy can run daily sales with real data
- no cross-team data leaks under RLS tests
- inventory and sales totals reconcile for test scenarios
- core pages are stable on mobile/tablet Flutter targets

## Phase 2

- branch transfer workflow
- PDF/Excel export
- richer analytics and charts
- optional SMS/email notifications

## Phase 3

- accounting integrations
- advanced compliance workflows
- enterprise-grade extensions
