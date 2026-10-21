#!/usr/bin/env bash
# Resume an interrupted 3cAxis reporting-only installation on existing HAOS.
set -Eeuo pipefail
umask 077
[[ $EUID == 0 && "$(hostname -s)" != 3ca ]] || exit 1
for x in qm jq curl tar python3; do command -v "$x" >/dev/null || exit 1; done
[[ -r /dev/tty && -r /etc/3c-technologies/customer.conf ]] || exit 1
vm=100
[[ "$(qm config "$vm" | sed -n 's/^name: //p')" == home-assistant ]] || exit 1
[[ -f /etc/3c-technologies/reporting-nextcloud.json ]] || { echo "Saved credential is missing." >&2; exit 1; }
r="$(qm guest exec "$vm" -- /usr/bin/ha apps info local_3caxis_service_reporting --raw-json)"
jq -e '.exited == 1 and .exitcode == 0 and (."out-data" | fromjson? | .result == "ok" and .data.slug == "local_3caxis_service_reporting" and .data.version == "1.0.0" and .data.state == "stopped")' <<<"$r" >/dev/null || { echo "Expected stopped 3cAxis v1.0.0 App not present; refusing." >&2; exit 1; }
m="$(qm guest exec "$vm" -- /bin/sh -c 'test -f /mnt/data/supervisor/apps/local/3caxis_service_reporting/.3caxis-transfer-incomplete && echo OWNED')"
jq -e '."out-data" == "OWNED\\n"' <<<"$m" >/dev/null || { echo "3cAxis incomplete transfer marker missing; refusing." >&2; exit 1; }
read -r -s -p "GitHub read-only deployment token: " token </dev/tty
echo
[[ -n "$token" ]] || exit 1
d="$(mktemp -d)"
trap 'unset token; rm -rf -- "$d"' EXIT
http="$(curl -sSL --fail-with-body --max-time 180 -o "$d/repo.tgz" -w '%{http_code}' --config - <<CONFIG
header = "Authorization: Bearer ${token}"
header = "Accept: application/vnd.github+json"
url = "https://api.github.com/repos/cullenchris/3c-proxmox-deployment/tarball/3a2a5e53dcda39b2ebcaf269f54c7c1e122307c1"
CONFIG
)"
unset token
[[ "$http" == 200 ]] || exit 1
mkdir "$d/source"
tar -xzf "$d/repo.tgz" --strip-components=1 -C "$d/source"
base="$d/source/scripts"
source "$base/lib/ha-reporting-qga.sh"
source /etc/3c-technologies/customer.conf
identity="$(qga_run "$vm" /bin/sh -c 'cat /mnt/data/supervisor/homeassistant/3caxis_audit/customer.json')"
jq -e --arg name "$CUSTOMER_NAME" --arg address "$CUSTOMER_ADDRESS" '.customer_name == $name and .service_address == $address' <<<"$identity" >/dev/null || exit 1
echo "Installing sanitized tracker..."
REPORTING_SANITIZED_INSTALL_APPROVED=YES bash "$base/install-ha-sanitized-tracker.sh" "$vm" home-assistant
echo "Configuring existing Reporting App from protected local credential..."
bash "$base/configure-reporting-options-unattended.sh" "$vm" home-assistant
echo "Starting Reporting App..."
qga_run "$vm" /usr/bin/ha apps start local_3caxis_service_reporting --raw-json >/dev/null
r="$(qm guest exec "$vm" -- /usr/bin/ha apps info local_3caxis_service_reporting --raw-json)"
jq -e '.exited == 1 and .exitcode == 0 and (."out-data" | fromjson? | .result == "ok" and .data.state == "started")' <<<"$r" >/dev/null || { echo "App startup not verified. Marker preserved." >&2; exit 1; }
qga_run "$vm" /bin/sh -c 'rm -f /mnt/data/supervisor/apps/local/3caxis_service_reporting/.3caxis-transfer-incomplete' >/dev/null
echo "Reporting App running; Nextcloud configured; sanitized tracking initialized."
