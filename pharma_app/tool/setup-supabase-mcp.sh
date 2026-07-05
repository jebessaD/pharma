#!/usr/bin/env bash
# One-time setup for Supabase MCP in Cursor (Pharma Shelf project).
# Creates ~/.cursor/supabase-pharma-mcp.env with your Personal Access Token.
set -euo pipefail

ENV_FILE="${HOME}/.cursor/supabase-pharma-mcp.env"
TOKEN_URL="https://supabase.com/dashboard/account/tokens"

echo "Supabase MCP setup for project jyscupmaxarzzscilvvg"
echo ""
echo "1. Open: ${TOKEN_URL}"
echo "2. Generate a new token (e.g. name: Cursor MCP Pharma Shelf)"
echo "3. Paste the token below (input hidden):"
echo ""

read -r -s -p "Supabase PAT: " PAT
echo ""

if [[ -z "${PAT}" ]]; then
  echo "Error: empty token." >&2
  exit 1
fi

mkdir -p "${HOME}/.cursor"
printf 'SUPABASE_ACCESS_TOKEN=%s\n' "${PAT}" > "${ENV_FILE}"
chmod 600 "${ENV_FILE}"

echo ""
echo "Saved: ${ENV_FILE}"
echo "Restart Cursor, then check Settings → Tools & MCP → supabase-pharma-shelf."
echo "Do not commit or share this file."
