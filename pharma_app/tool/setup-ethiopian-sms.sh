#!/usr/bin/env bash
# Configure Ethiopian SMS (SMSEthiopia) for Supabase phone OTP.
#
# Prerequisites:
#   1. SMSEthiopia account: https://smsethiopia.com → Console → API Keys
#   2. Supabase Auth → Hooks → Send SMS enabled → copy v1,whsec_... secret
#   3. Hook URL: https://jyscupmaxarzzscilvvg.supabase.co/functions/v1/send-sms-hook
#
set -euo pipefail

PROJECT_REF="jyscupmaxarzzscilvvg"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$HOME/.cursor/supabase-pharma-mcp.env" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/.cursor/supabase-pharma-mcp.env"
fi
export SUPABASE_ACCESS_TOKEN="${SUPABASE_ACCESS_TOKEN:-}"

if [[ -z "$SUPABASE_ACCESS_TOKEN" ]]; then
  echo "Error: SUPABASE_ACCESS_TOKEN not set." >&2
  echo "Add it to ~/.cursor/supabase-pharma-mcp.env or export it." >&2
  exit 1
fi

echo "=== Pharma Shelf — Ethiopian SMS setup ==="
echo ""
echo "Two different secrets (do NOT paste the same value twice):"
echo "  A) Hook secret     → starts with v1,whsec_  (Auth → Hooks → Send SMS)"
echo "  B) SMSEthiopia key → from smsethiopia.com Console → API Keys"
echo ""

read -r -s -p "A) Hook secret (v1,whsec_...): " HOOK_SECRET
echo ""
if [[ ! "$HOOK_SECRET" == v1,whsec_* ]]; then
  echo "Error: hook secret must start with v1,whsec_" >&2
  exit 1
fi

read -r -s -p "B) SMSEthiopia API key: " SMSETHIOPIA_KEY
echo ""
if [[ -z "$SMSETHIOPIA_KEY" ]]; then
  echo "Error: SMSEthiopia API key is required." >&2
  exit 1
fi
if [[ "$SMSETHIOPIA_KEY" == v1,whsec_* ]]; then
  echo "Error: that looks like the hook secret, not an SMSEthiopia key." >&2
  exit 1
fi
if [[ "$HOOK_SECRET" == "$SMSETHIOPIA_KEY" ]]; then
  echo "Error: hook secret and SMSEthiopia key must be different." >&2
  exit 1
fi

echo ""
echo "Optional: Textlocal fallback (press Enter to skip)"
read -r -s -p "Textlocal API key (optional): " TEXTLOCAL_KEY
echo ""

echo ""
echo "Deploying send-sms-hook..."
cd "$APP_DIR"
supabase functions deploy send-sms-hook --project-ref "$PROJECT_REF" --no-verify-jwt

SECRET_ARGS=(
  "SEND_SMS_HOOK_SECRET=$HOOK_SECRET"
  "SMSETHIOPIA_API_KEY=$SMSETHIOPIA_KEY"
  "SMS_PROVIDER=smsethiopia"
  "TEXTLOCAL_SENDER=Pharma Shelf"
)
if [[ -n "${TEXTLOCAL_KEY:-}" ]]; then
  SECRET_ARGS+=("TEXTLOCAL_API_KEY=$TEXTLOCAL_KEY")
fi

echo "Setting secrets..."
supabase secrets set "${SECRET_ARGS[@]}" --project-ref "$PROJECT_REF"

HEALTH_URL="https://${PROJECT_REF}.supabase.co/functions/v1/send-sms-hook"
echo ""
echo "Running health check..."
sleep 2
HTTP_STATUS="$(curl -sS -o /tmp/pharma-sms-health.json -w '%{http_code}' "$HEALTH_URL" || true)"
echo "HTTP $HTTP_STATUS"
cat /tmp/pharma-sms-health.json
echo ""

if [[ "$HTTP_STATUS" == "200" ]]; then
  echo "✓ SMS hook is configured. Retry phone signup in the app."
else
  echo "✗ Configuration issues remain. Fix the issues above and re-run this script."
  exit 1
fi
