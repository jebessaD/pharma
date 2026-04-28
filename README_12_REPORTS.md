# 12 - Reports (version 1)

## Version 1 scope (build now)

- sales report
- stock report
- expiry report

## Out of Scope (Do Not Build)

- PDF/Excel export
- many custom report templates

## AI Implementation Directive

- Flutter screens: `ReportsHome`, `ReportViewer`
- Supabase: 3 views/RPC endpoints only for version 1 reports
- Filters: date range + branch
- Keep table-based display (no complex charts needed)

## Version 1 report endpoints

- `rpc_report_sales_summary(team_id, branch_id, from, to)`
- `rpc_report_stock_balance(team_id, branch_id)`
- `rpc_report_expiry_status(team_id, branch_id, threshold_days)`

## Output Contract

- totals at top
- tabular rows below
- consistent currency and date format

## Validation Rules

- date range must be valid (`from <= to`)
- default date range for sales: today

## Acceptance Criteria

- reports return correct totals for selected date/branch
- report query time remains acceptable on moderate data
- user can switch report type without app restart
