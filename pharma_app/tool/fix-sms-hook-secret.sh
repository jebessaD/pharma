#!/usr/bin/env bash
# Sets ONLY SEND_SMS_HOOK_SECRET — does not touch SMS provider keys.
set -euo pipefail

PROJECT_REF="jyscupmaxarzzscilvvg"

if [[ -f "$HOME/.cursor/supabase-pharma-mcp.env" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/.cursor/supabase-pharma-mcp.env"
fi
export SUPABASE_ACCESS_TOKEN="${SUPABASE_ACCESS_TOKEN:-}"

if [[ -z "$SUPABASE_ACCESS_TOKEN" ]]; then
  echo "Error: SUPABASE_ACCESS_TOKEN not set." >&2
  exit 1
fi

echo "Paste the Send SMS hook secret from:"
echo "  Supabase Dashboard → Authentication → Hooks → Send SMS"
echo "It must start with: v1,whsec_"
echo ""
echo "This is NOT your Textlocal or SMSEthiopia API key."
echo ""
read -r -s -p "Hook secret: " HOOK_SECRET
echo ""

if [[ ! "$HOOK_SECRET" == v1,whsec_* ]]; then
  echo "Error: secret must start with v1,whsec_" >&2
  exit 1
fi

supabase secrets set \
  SEND_SMS_HOOK_SECRET="$HOOK_SECRET" \
  --project-ref "$PROJECT_REF"

echo ""
echo "Done. Run ./tool/setup-ethiopian-sms.sh for full setup, or retry signup."
