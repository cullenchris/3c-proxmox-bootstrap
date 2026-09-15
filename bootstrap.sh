#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

# ============================================================================
# 3C Technologies - Modular Customer Deployment Bootstrap
# Version: 1.2.0
# ============================================================================

BOOTSTRAP_VERSION="1.2.0"
GITHUB_OWNER="cullenchris"
GITHUB_REPO="3c-proxmox-deployment"
GITHUB_REF="feature/opencode-management"
BASE_DIR="/root/3c-deployment"
GITHUB_TOKEN=""

FILES=(
    "scripts/configure-proxmox.sh"
    "scripts/install-home-assistant.sh"
    "scripts/deploy-management-vm.sh"
    "scripts/complete-ha-mcp.sh"
    "scripts/deploy-tailscale.sh"
    "scripts/deploy-customer-stack.sh"
)

cleanup() {
    unset GITHUB_TOKEN || true
    rm -f "${BASE_DIR}"/.download.*.tmp 2>/dev/null || true
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
echo "3C Technologies Modular Customer Deployment Bootstrap v${BOOTSTRAP_VERSION}"
echo "============================================================================"
echo

[[ $EUID -eq 0 ]] || fail "Run this bootstrap as root on the Proxmox VE host."
command -v pveversion >/dev/null 2>&1 || fail "This system does not appear to be a Proxmox VE host."
command -v curl >/dev/null 2>&1 || fail "curl is not installed on this Proxmox host."
command -v bash >/dev/null 2>&1 || fail "bash is not available on this Proxmox host."
[[ -r /dev/tty ]] || fail "No interactive terminal is available for secure credential entry."

echo "Proxmox detected:"
pveversion | head -n1
echo

while [[ -z "$GITHUB_TOKEN" ]]; do
    read -r -s -p "Paste 3C GitHub deployment token: " GITHUB_TOKEN </dev/tty
    echo
    [[ -n "$GITHUB_TOKEN" ]] || echo "[WARNING] A GitHub token is required."
done

mkdir -p "$BASE_DIR"
chmod 700 "$BASE_DIR"

echo
echo "[INFO] Downloading the private 3C modular deployment scripts..."

for repo_path in "${FILES[@]}"; do
    filename="$(basename "$repo_path")"
    destination="${BASE_DIR}/${filename}"
    temp_file="${BASE_DIR}/.download.${filename}.$$.tmp"
    api_url="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/contents/${repo_path}?ref=${GITHUB_REF}"

    http_code="$(
        curl \
            --silent \
            --show-error \
            --location \
            --connect-timeout 20 \
            --max-time 120 \
            --output "$temp_file" \
            --write-out '%{http_code}' \
            --config - <<EOF
header = "Accept: application/vnd.github.raw+json"
header = "Authorization: Bearer ${GITHUB_TOKEN}"
header = "X-GitHub-Api-Version: 2022-11-28"
url = "${api_url}"
EOF
    )"

    if [[ "$http_code" != "200" ]]; then
        rm -f "$temp_file"
        case "$http_code" in
            401) fail "GitHub rejected the token." ;;
            403) fail "GitHub denied access to the private deployment repository." ;;
            404) fail "Deployment file not found: ${repo_path}" ;;
            *)   fail "GitHub download failed for ${repo_path} with HTTP status ${http_code}." ;;
        esac
    fi

    [[ -s "$temp_file" ]] || fail "GitHub returned an empty file for ${repo_path}."
    first_line="$(head -n1 "$temp_file" || true)"
    [[ "$first_line" == '#!/usr/bin/env bash' || "$first_line" == '#!/bin/bash' ]] ||
        fail "Downloaded file is not the expected Bash script: ${repo_path}"

    bash -n "$temp_file" || fail "Bash syntax validation failed for ${repo_path}."
    chmod 700 "$temp_file"
    mv -f "$temp_file" "$destination"
    chmod 700 "$destination"
    echo "[INFO] Installed ${filename}"
done

unset GITHUB_TOKEN

echo
echo "[INFO] All deployment scripts downloaded and validated."
echo "[INFO] Launching the 3C modular deployment menu..."
echo

exec "${BASE_DIR}/deploy-customer-stack.sh" </dev/tty
