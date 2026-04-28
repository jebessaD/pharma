# 10 - Dashboard (version 1)

## Version 1 scope (build now)

- today's sales total
- low stock count
- near expiry count
- expired count

## Out of Scope (Do Not Build)

- advanced charts and deep drill-down analytics
- heavy time-series visualizations

## AI Implementation Directive

- Flutter screen: `DashboardHome`
- Supabase: one RPC or view for daily metrics
- Default filter: current branch + today
- Add simple refresh action

## Suggested RPC Output

- `today_sales_total`
- `today_sales_count`
- `low_stock_count`
- `near_expiry_count`
- `expired_count`

## Data Integrity Rules

- metrics source only from committed transactions
- exclude inactive/deleted medicines
- display last refresh timestamp in UI

## Acceptance Criteria

- dashboard loads in under 2 seconds on normal data
- numbers match source sales/inventory tables
- branch switch updates metrics correctly
