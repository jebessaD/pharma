# Busy Sales QA Checklist

## POS quick sell
- Search by manual code and add first result with Enter.
- Scan medicine barcode with camera and verify item is added.
- Scan same item repeatedly and verify quantity increases instead of duplicate rows.
- Use `+` and `-` controls on a selected row and verify qty updates.
- Verify checkout bar remains visible when cart has many lines.

## POS bulk add
- Open `Bulk add` and paste:
  - `AMOX500 2`
  - `PARA 4`
- Confirm valid lines are added and unresolved lines are reported without blocking valid lines.

## Stock-in parity
- In single stock-in tab, scan barcode and ensure medicine field fills.
- In bulk stock-in tab, scan into a row and ensure medicine is selected.
- Paste CSV/tab rows (`lookup,batch,expiry,qty`) and verify rows are created.
- Use duplicate row action and verify fields are copied.

## Stock-in hybrid UX
- Confirm scan/search header is visible in both tabs and accepts barcode, manual code, and name.
- In bulk tab, select a compact row and verify detail panel edits the selected row only.
- Check row status chips (`Ready`, `Missing`, `Invalid`, `Empty`) update as fields change.
- Save with mixed rows and verify only ready rows are saved while invalid/missing rows remain for correction.
- In single tab, use `Save and continue` and verify page stays open with focus returning to search.

## Offline and sync behavior
- While offline, perform POS checkout and verify offline save message appears.
- Reconnect and run sync; verify pending count drops.

## Session continuity
- Login, disconnect network, restart app, verify session remains active.
- Manual sign-out clears session and requires login again.
