#!/usr/bin/env bash
# DEVELOPMENT-ONLY: complete private 3cAxis deployment bundle bootstrap.
# No effect on the current bootstrap.sh. Never run on a live/customer host
# before an isolated integration test and explicit release approval.
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

OWNER="cullenchris"
REPO="3c-proxmox-deployment"
REF="feature/ha-service-reporting"
TARGET="/root/3caxis-deployment-feature"
GITHUB_TOKEN=""
TMP_DIR=""
cleanup() {
  unset GITHUB_TOKEN || true
  [[ -z "$TMP_DIR" ]] || rm -rf -- "$TMP_DIR"
}
trap cleanup EXIT

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

[[ "${REPORTING_BUNDLE_TEST_APPROVED:-}" == "YES" ]] ||
  die "Development bootstrap disabled. Requires an explicitly approved isolated test."
[[ $EUID -eq 0 ]] || die "Run only as root on an isolated Proxmox VE test host."
command -v pveversion >/dev/null 2>&1 || die "Proxmox VE host required"
for tool in curl python3 mktemp chmod; do
  command -v "$tool" >/dev/null 2>&1 || die "Missing required tool: $tool"
done
[[ ! -e "$TARGET" ]] || die "Refusing to overwrite previous deployment bundle at $TARGET"
[[ -r /dev/tty ]] || die "Interactive console required"

TMP_DIR="$(mktemp -d /root/.3caxis-deploy-bundle.XXXXXXXX)"
ARCHIVE="$TMP_DIR/repository.tar.gz"
STAGE="$TMP_DIR/staged"
mkdir -m 700 "$STAGE"

read -r -s -p "Read-only GitHub deployment token: " GITHUB_TOKEN </dev/tty
echo
[[ -n "$GITHUB_TOKEN" ]] || die "GitHub token is required"
echo "[INFO] Downloading feature-branch deployment archive (no secrets in URL)"

URL="https://api.github.com/repos/${OWNER}/${REPO}/tarball/${REF}"
HTTP_STATUS="$(curl --silent --show-error --location --connect-timeout 20 --max-time 180 \
  --output "$ARCHIVE" --write-out '%{http_code}' --config - <<EOF
header = "Accept: application/vnd.github+json"
header = "Authorization: Bearer ${GITHUB_TOKEN}"
header = "X-GitHub-Api-Version: 2022-11-28"
url = "${URL}"
EOF
)"
unset GITHUB_TOKEN
[[ "$HTTP_STATUS" == "200" ]] || die "Archive download failed: HTTP $HTTP_STATUS"
[[ -s "$ARCHIVE" ]] || die "Empty archive downloaded"

# Strict extraction: only normal files and directories with a single
# GitHub-generated top-level prefix; disallow links, special files, traversal
# and unexpectedly large/many files. Never use unrestricted tar extraction.
python3 - "$ARCHIVE" "$STAGE" <<'PY'
import os
from pathlib import Path, PurePosixPath
import sys
import tarfile

archive = Path(sys.argv[1])
destination = Path(sys.argv[2]).resolve()
count = 0
total = 0
with tarfile.open(archive, mode="r:gz") as tar:
    members = tar.getmembers()
    if not members or len(members) > 3000:
        raise SystemExit("Unsafe archive: missing or excessive entries")
    prefixes = {PurePosixPath(m.name).parts[0] for m in members if m.name}
    if len(prefixes) != 1:
        raise SystemExit("Unsafe archive: multiple top-level directories")
    for member in members:
        name = PurePosixPath(member.name)
        parts = name.parts
        if (name.is_absolute() or ".." in parts or not parts
                or any(part in ("", ".") for part in parts)):
            raise SystemExit("Unsafe archive member path")
        if not (member.isfile() or member.isdir()):
            raise SystemExit("Unsafe archive member type")
        if member.isfile():
            count += 1
            total += member.size
            if member.size > 2_000_000 or total > 30_000_000:
                raise SystemExit("Unsafe archive: size limit exceeded")
        if len(parts) < 2:
            continue
        output = destination.joinpath(*parts[1:])
        if not output.resolve().is_relative_to(destination):
            raise SystemExit("Unsafe archive path escape")
        if member.isdir():
            output.mkdir(parents=True, exist_ok=True, mode=0o700)
            continue
        output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        src = tar.extractfile(member)
        if src is None:
            raise SystemExit("Unable to read archive entry")
        with open(output, "xb") as handle:
            while chunk := src.read(1024 * 1024):
                handle.write(chunk)
        os.chmod(output, 0o600)
if count < 20:
    raise SystemExit("Archive does not contain expected deployment sources")
print(f"[INFO] Validated and extracted {count} files; no links or path traversal")
PY

MAIN="$STAGE/scripts/deploy-home-assistant.sh"
PREFLIGHT="$STAGE/scripts/verify-reporting-source.sh"
[[ -f "$MAIN" && -f "$PREFLIGHT" ]] || die "Required deployment scripts missing"
[[ -f "$STAGE/scripts/install-ha-service-reporting.sh" ]] || die "Reporting helper missing"
bash -n "$MAIN" || die "Main deployment script failed syntax validation"
bash -n "$STAGE/scripts/install-ha-service-reporting.sh" || die "Reporting helper syntax invalid"
bash "$PREFLIGHT" || die "Reporting source preflight failed"

# The bundle is complete before it is moved into place.
mv -- "$STAGE" "$TARGET"
chmod 700 "$TARGET/scripts/deploy-home-assistant.sh"
echo "[INFO] Feature-branch deployment bundle ready at $TARGET"
echo "[INFO] Token cleared. This bootstrap does not start the deployment."
echo "[INFO] After isolated review, invoke the deployment script manually."
