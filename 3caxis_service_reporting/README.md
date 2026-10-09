# 3cAxis Home Assistant Service Reporting

Production Home Assistant App catalog **under development** for 3cAxis-managed Home Assistant installations.

The tested reporting application produces a customer-facing monthly PDF and an internal technician PDF. Source code and image build definitions are maintained in the private `cullenchris/3c-proxmox-deployment` repository. This public repository contains the customer-facing App catalog metadata.

## Release status

**Not ready for customer installation.** The catalog references `ghcr.io/cullenchris/3caxis-service-reporting`. Successful amd64/aarch64 build tests, GHCR publication, runtime installation, and a real end-to-end report have not yet been confirmed.

## Customer identity

The Proxmox deployment must supply a validated customer identity in `/ha_config/3caxis_audit/customer.json` before production reporting starts. Missing identity must prevent production reports rather than use synthetic development values.

## Nextcloud credentials

The App expects a Nextcloud app password in its **Supervisor App options**. The manifest's `null` default does **not** provide a password, and does not refer to Home Assistant `secrets.yaml`. A supported secure runtime provisioning process remains to be implemented and tested. Never commit passwords to GitHub or include them in customer metadata, container images, shell command lines, or logs.

## App access and deployment safety

The App uses a read-only Home Assistant configuration mount and persistent private App data. No Home Assistant API, Supervisor API, Docker API, or privileged host access is required for the filesystem-first reporting path.

The reporting installer is still a development draft. QEMU Guest Agent transport, Home Assistant App install commands, HAOS paths, and retry behavior are not validated. Do not run it on a customer or live system before a controlled test. Do not merge the feature branch to `main` without approval.
