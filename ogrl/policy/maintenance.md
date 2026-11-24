# Maintenance Policy

| | |
|---|---|
| Owner | {{ ssp_signer_name }}, {{ ssp_signer_title }} |
| Approved by | [approver name and title] |
| Effective date | [YYYY-MM-DD] |
| Review interval | Annual |
| Version | [0.1-draft] |

> Template only, not legal advice. {{ company_name }} must review, edit, and adopt it before it takes effect.

## Purpose

Keep maintenance on systems controlled, recorded, and safe for CUI.

## Scope

Systems {{ company_name }} owns outside the cloud providers (offices at {{ sites }}, network gear, printers, endpoints), plus any maintenance on systems that process, store, or transmit CUI. Cloud provider maintenance is covered by the providers.

## Policy statements

1. Maintenance on in-scope systems is approved by the system owner or IT lead and recorded: date and time, component, work done, tools used, who did it, approver, and parts removed or replaced. Records are reviewed quarterly. (3.7.1)
2. Maintenance tools and diagnostic software come from an approved tool register, which is reviewed annually. (3.7.2)
3. Before equipment leaves the site for service, media is sanitized per NIST SP 800-88 or removed and kept, and this is noted in the maintenance record. (3.7.3)
4. Vendor or technician media (USB drives, discs, bootable tools) is scanned for malware on the designated scanning workstation outside the CUI enclave before it touches any CUI system. The result goes in the maintenance record. (3.7.4)
5. Each remote maintenance session by an outside vendor is approved in advance by the IT lead, uses an approved tool with MFA, is logged (person, target, purpose, start and end), ends after 30 minutes idle, and vendor access is disabled when the work ends. (3.7.5)
6. An authorized maintenance personnel list is kept and reviewed annually. Anyone not on the list is escorted and supervised by a named workforce member for the whole visit, and the supervisor is recorded. The supervisor must be able to understand and stop the work. (3.7.6)

## Roles

- **IT lead:** approves maintenance and sessions, keeps the register and lists.
- **Security lead:** reviews records.
- **Supervisor:** escorts unlisted personnel.

## Exceptions

Written approval from {{ ssp_signer_name }}. Emergency repairs may start first but are recorded and approved within 1 business day.
