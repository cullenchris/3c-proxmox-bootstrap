#!/usr/bin/env bash
# 3cAxis reporting-only installer, technician-operated on existing customer PVE.
# No access to the operator's Proxmox host. No secrets embedded in GitHub.
set -Eeuo pipefail
umask 077
[[ "$EUID" -eq 0 ]] || { echo "Run as root on the customer Proxmox host." >&2; exit 1; }
for tool in qm pvesm curl tar sha256sum python3; do
  command -v "$tool" >/dev/null || { echo "Missing required command: $tool" >&2; exit 1; }
done
[[ -r /dev/tty ]] || { echo "Interactive technician terminal required." >&2; exit 1; }
[[ -r /etc/3c-technologies/customer.conf ]] || {
  echo "Original 3cAxis customer identity is missing. No changes made." >&2; exit 1;
}
mapfile -t matches < <(qm list | awk 'NR>1 && $2=="home-assistant" {print $1}')
[[ "${#matches[@]}" -eq 1 ]] || { echo "Expected exactly one VM named home-assistant. No changes made." >&2; exit 1; }
vmid="${matches[0]}"
qm guest cmd "$vmid" ping >/dev/null || { echo "HA guest agent unavailable. No changes made." >&2; exit 1; }
if [[ "$(hostname -s)" == "3ca" ]]; then
  echo "Refusing to install on the operator's protected 3ca host." >&2; exit 1
fi

# A private repo is downloaded through the GitHub API using a short-lived
# technician-supplied read-only token, not a published credential.
echo "3cAxis reporting-only installation for existing Home Assistant VM $vmid"
read -r -s -p "GitHub read-only deployment token: " token </dev/tty
echo
[[ -n "$token" ]] || { echo "No token provided." >&2; exit 1; }
work="$(mktemp -d /root/3caxis-reporting.XXXXXXXX)"
trap 'unset token; rm -rf -- "$work"' EXIT
ref="fe0eca83254745a74a76f775a1199601083bffd0"
api="https://api.github.com/repos/cullenchris/3c-proxmox-deployment/tarball/$ref"
response="$(curl -sS -L --connect-timeout 20 --max-time 180 -o "$work/source.tar.gz" -w '%{http_code}' --config - <<CURL_CONFIG
header = "Accept: application/vnd.github+json"
header = "Authorization: Bearer ${token}"
header = "X-GitHub-Api-Version: 2022-11-28"
url = "${api}"
CURL_CONFIG
)"
unset token
[[ "$response" == 200 ]] || { echo "GitHub private download failed (HTTP $response)." >&2; exit 1; }
tar -tzf "$work/source.tar.gz" >/dev/null || { echo "Invalid source archive." >&2; exit 1; }
mkdir "$work/repo"
tar -xzf "$work/source.tar.gz" -C "$work/repo" --strip-components=1
installer="$work/repo/scripts/install-existing-customer-reporting.sh"
[[ -f "$installer" ]] || { echo "Reporting installer missing." >&2; exit 1; }
bash -n "$installer"

# Credentials are created locally by the technician; they never enter GitHub.
# Reuse existing valid local credentials if present.
credential=/etc/3c-technologies/reporting-nextcloud.json
if [[ ! -f "$credential" ]]; then
  echo "Nextcloud credentials will be entered privately on this customer's host."
  python3 -c '
import getpass,json,os,pathlib,sys,tempfile
target=pathlib.Path(sys.argv[1])
target.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
pw=getpass.getpass("Nextcloud reporting app password: ")
if not pw:
    raise SystemExit("No Nextcloud password supplied; installation stopped.")
data={"nextcloud_server":"https://nextcloud.3caxis.com",
      "nextcloud_username":"3caxis-reports",
      "nextcloud_app_password":pw}
fd,tmp=tempfile.mkstemp(prefix=".reporting-",dir=str(target.parent))
try:
    os.fchmod(fd,0o600)
    with os.fdopen(fd,"w") as stream:
        json.dump(data,stream)
    os.replace(tmp,target)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
print("Local reporting credential created (password not displayed).")
' "$credential" </dev/tty
fi
CONFIRM_EXISTING_CUSTOMER_REPORTING_INSTALL=YES \
  bash "$installer" "$vmid" home-assistant
echo "3cAxis reporting installation finished on VM $vmid."
