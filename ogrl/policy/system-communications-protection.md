# System and Communications Protection Policy

| | |
|---|---|
| Owner | {{ ssp_signer_name }}, {{ ssp_signer_title }} |
| Approved by | [approver name and title] |
| Effective date | [YYYY-MM-DD] |
| Review interval | Annual |
| Version | [0.1-draft] |

> Template only, not legal advice. {{ company_name }} must review, edit, and adopt it before it takes effect.

## Purpose

Protect CUI in transit and at rest, and keep system boundaries, crypto, and collaboration tools under control.

## Scope

All systems and communications that process, store, or transmit CUI ({{ cui_categories }}), including AWS, Google Workspace, Fathom, endpoints, and conferencing devices.

## Policy statements

1. Boundaries are defined and monitored. The SSP shows external and key internal boundaries, publicly accessible components are listed, and administrative access uses authenticated paths only. Traffic is limited to what is needed. (3.13.1, 3.13.5, 3.13.6)
2. Systems are designed using documented principles (least privilege, defense in depth, secure defaults, smaller attack surface). Threat models are done for new services, new external integrations, and major architecture changes. The development lifecycle is reviewed annually and approved by {{ ssp_signer_name }}. (3.13.2)
3. User functions and system management functions are kept apart (separate consoles or paths). (3.13.3)
4. CUI is encrypted in transit (TLS 1.2 or higher, FIPS-approved cipher suites) and at rest (AES-256 in a FIPS-validated module), including remote sessions, backups, endpoints, and removable media. Alternative physical safeguards are not relied on in place of encryption. (3.13.8, 3.13.16, 3.1.13)
5. **FIPS scope.** FIPS-validated cryptography is required wherever cryptography protects CUI: the CUI data path (3.13.11). Identity and control-plane services that carry no CUI (for example IAM, Identity Center, Organizations) are out of this requirement. Cryptographic modules on the CUI path are listed in an inventory with their CMVP certificate numbers, reviewed annually against the CMVP list. Services with no FIPS endpoint, such as CloudWatch Logs and SSM Session Manager, must not carry CUI (see Audit and Accountability Policy). (3.13.11)
6. Keys for CUI are held in a FIPS-validated key management service or HSM, rotated at least annually, and recorded in a key inventory with owner and purpose across AWS KMS, client-side encryption keys, and endpoint recovery keys. Procedures cover creating, distributing, storing, and destroying keys. (3.13.10)
7. Sessions end after 30 minutes of inactivity or 12 hours total, and the network connection ends with them. (3.13.9)
8. **Split tunneling.** Remote devices must not split-tunnel to unmanaged networks. Where split tunneling is used, all non-tunneled traffic goes through a managed cloud security gateway that inspects it and enforces company network policy. (3.13.7)
9. **Collaboration devices.** Cameras, microphones, and conference-room systems must not be remotely activated, except dedicated video systems that activate only when a participant in the room places or accepts a call. Users can see when a device is active. Remote joining of Meet hardware by an administrator is prohibited. Collaboration settings are reviewed quarterly. (3.13.12)
10. Mobile code (macros, browser extensions, Java applets) is limited by documented restrictions, approved exceptions, and monitoring. Restrictions are reviewed annually. (3.13.13)
11. VoIP and video services are limited to approved services with SSO, MFA, and encrypted signaling and media, and are reviewed at least quarterly. (3.13.14)
12. CUI at rest in shared resources and data from other tenants cannot leak across tenants or sessions. (3.13.4)

## Roles

- **Security lead:** owns standards, key inventory, and reviews.
- **IT lead:** configures VPN, gateways, and Meet settings.
- **System owner:** approves architecture changes.

## Exceptions

Written approval from {{ ssp_signer_name }} with compensating controls and an end date. A gap against statement 5 goes on the POA&M only if the Security Assessment Policy allows it (3.13.11 qualifies only when encryption is used but is not FIPS-validated).
