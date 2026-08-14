bootstrap-v1.0.1.sh


#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

# ============================================================================
# 3C Technologies - Proxmox Deployment Bootstrap
# Version: 1.0.1
#
# Purpose:
#   - Run on a fresh Proxmox VE host as root.
#   - Prompt securely for the read-only GitHub deployment token.
#   - Download the private 3C Home Assistant deployment script.
#   - Validate the downloaded Bash script.
#   - Clear the GitHub token from memory.
#   - Launch the deployment automatically.
#
# This bootstrap contains NO passwords, tokens, customer data, or other secrets.
# ============================================================================

BOOTSTRAP_VERSION="1.0.1"

GITHUB_OWNER="cullenchris"
GITHUB_REPO="3c-proxmox-deployment"
GITHUB_REF="main"
DEPLOY_SCRIPT_PATH="scripts/deploy-home-assistant.sh"

DEPLOY_SCRIPT="/root/3c-ha-deploy.sh"
TEMP_SCRIPT="/root/.3c-ha-deploy.$$.tmp"

GITHUB_TOKEN=""

cleanup() {
    unset GITHUB_TOKEN || true
    rm -f "$TEMP_SCRIPT" || true
}

fail() {
    echo
    echo "[ERROR] $1" >&2
    cleanup
    exit 1
}

trap cleanup EXIT
trap 'fail "Bootstrap failed near line ${LINENO}."' ERR

echo
echo "============================================================================"
echo "3C Technologies Proxmox Deployment Bootstrap v${BOOTSTRAP_VERSION}"
echo "============================================================================"
echo

[[ $EUID -eq 0 ]] ||
    fail "Run this bootstrap as root on the Proxmox VE host."

command -v pveversion >/dev/null 2>&1 ||
    fail "This system does not appear to be a Proxmox VE host."

command -v curl >/dev/null 2>&1 ||
    fail "curl is not installed on this Proxmox host."

command -v bash >/dev/null 2>&1 ||
    fail "bash is not available on this Proxmox host."

echo "Proxmox detected:"
pveversion | head -n1
echo

[[ -r /dev/tty ]] ||
    fail "No interactive terminal is available for secure credential entry."

while [[ -z "$GITHUB_TOKEN" ]]; do
    read -r -s -p "Paste 3C GitHub deployment token: " GITHUB_TOKEN </dev/tty
    echo

    if [[ -z "$GITHUB_TOKEN" ]]; then
        echo "[WARNING] A GitHub token is required."
    fi
done

echo
echo "[INFO] Authenticating to the private 3C deployment repository..."

API_URL="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/contents/${DEPLOY_SCRIPT_PATH}?ref=${GITHUB_REF}"

HTTP_CODE="$(
    curl \
        --silent \
        --show-error \
        --location \
        --connect-timeout 20 \
        --max-time 120 \
        --output "$TEMP_SCRIPT" \
        --write-out '%{http_code}' \
        --config - <<EOF
header = "Accept: application/vnd.github.raw+json"
header = "Authorization: Bearer ${GITHUB_TOKEN}"
header = "X-GitHub-Api-Version: 2022-11-28"
url = "${API_URL}"
EOF
)"

# Clear the token as soon as GitHub authentication is complete.
unset GITHUB_TOKEN

if [[ "$HTTP_CODE" != "200" ]]; then
    rm -f "$TEMP_SCRIPT"

    case "$HTTP_CODE" in
        401)
            fail "GitHub rejected the token. Verify that you pasted the correct token."
            ;;
        403)
            fail "GitHub denied access. Verify the token has read access to the private repository."
            ;;
        404)
            fail "The deployment repository or script was not found, or the token cannot access it."
            ;;
        *)
            fail "GitHub download failed with HTTP status ${HTTP_CODE}."
            ;;
    esac
fi

[[ -s "$TEMP_SCRIPT" ]] ||
    fail "GitHub returned an empty deployment script."

FIRST_LINE="$(head -n1 "$TEMP_SCRIPT" || true)"
[[ "$FIRST_LINE" == '#!/usr/bin/env bash' || "$FIRST_LINE" == '#!/bin/bash' ]] ||
    fail "Downloaded content does not look like the expected Bash deployment script."

echo "[INFO] Private deployment script downloaded."

if ! bash -n "$TEMP_SCRIPT"; then
    fail "Downloaded deployment script failed Bash syntax validation."
fi

echo "[INFO] Bash syntax validation passed."

chmod 700 "$TEMP_SCRIPT"
mv -f "$TEMP_SCRIPT" "$DEPLOY_SCRIPT"
chmod 700 "$DEPLOY_SCRIPT"

echo
echo "[INFO] Deployment script installed at:"
echo "       ${DEPLOY_SCRIPT}"
echo
echo "[INFO] Launching 3C Home Assistant deployment..."
echo

# Replace the bootstrap process with the deployment process.
# The GitHub token has already been cleared and is not passed to the deployment.
# Reattach standard input to the interactive console. This is required when
# the bootstrap itself was launched with "curl ... | bash"; otherwise the
# deployment script would inherit the exhausted curl pipe as stdin and its
# customer/password prompts would not work.
exec "$DEPLOY_SCRIPT" </dev/tty
