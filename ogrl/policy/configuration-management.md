# Configuration and Change Management Policy

| | |
|---|---|
| Owner | {{ ssp_signer_name }}, {{ ssp_signer_title }} |
| Approved by | [approver name and title] |
| Effective date | [YYYY-MM-DD] |
| Review interval | Annual |
| Version | [0.1-draft] |

> Template only, not legal advice. {{ company_name }} must review, edit, and adopt it before it takes effect.

## Purpose

Keep systems in a known, secure state and make every change deliberate, reviewed, and traceable.

## Scope

All components that process, store, or transmit CUI or protect it: endpoints, network devices and firmware, cloud accounts, images, containers, databases, and SaaS security settings.

## Policy statements

1. The component inventory records unique ID, type, owner, environment, location or region, data classification, installed software and firmware versions, and documentation. It is updated on install and removal and reconciled quarterly. (3.4.1)
2. A written baseline standard exists for each component type, based on CIS Benchmarks or the cloud provider's guidance. It is reviewed annually. (3.4.1, 3.4.2)
3. Deviations from the baseline need approval from the security lead and go in a deviation register. Drift is detected automatically and fixed within 7 days for security settings, 30 days for others. (3.4.2)
4. Production changes need a change request (pull request or ticket), peer review, and approval by a code owner. Emergency changes follow a defined path with review afterward. PR and ticket records are kept 365 days. (3.4.3)
5. Every change to a system that processes, stores, or transmits CUI includes a **security impact analysis** section in the pull request template, scaled to risk. The security lead signs off before merge. Terraform plan output is attached. (3.4.4)
6. Only the deployment pipeline and a named set of platform engineers may change production. Branch protection and environment reviewers enforce this. Access is reviewed quarterly. (3.4.5)
7. Systems run only the functions and software needed (least functionality). Risky ports, protocols, and services are disabled. (3.4.6, 3.4.7)
8. Only software on the **approved software list** may be installed. New software needs approval from the IT lead or security lead. Users may not install their own software. The list is reviewed quarterly. (3.4.8, 3.4.9)

## Roles

- **IT lead:** keeps inventory and approved software list.
- **Security lead:** approves deviations and signs off security impact analysis.
- **Code owners:** review and approve changes.
- **System owner:** accountable for the baseline.

## Exceptions

Recorded in the deviation register with approver, reason, and end date. Policy-level exceptions need written approval from {{ ssp_signer_name }}.
