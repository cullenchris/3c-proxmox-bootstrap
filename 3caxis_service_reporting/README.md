# 3cAxis Home Assistant Service Reporting

Production Home Assistant App for 3C Technologies managed Home Assistant systems.

The App runs locally on the customer's Home Assistant installation and produces two monthly reports:

- Customer service report
- Internal technician report

Customer identity is supplied by the 3C Technologies Proxmox deployment through:

/config/3caxis_audit/customer.json

The Nextcloud password is supplied through Home Assistant's local secrets mechanism and is never stored in this repository.

The production image is published as a multi-architecture GHCR image for amd64 and aarch64.

The App uses a read-only Home Assistant configuration mount and requires no Home Assistant API, Supervisor API, Docker API, host networking, or privileged access.
