# Audit and Accountability Policy

| | |
|---|---|
| Owner | {{ ssp_signer_name }}, {{ ssp_signer_title }} |
| Approved by | [approver name and title] |
| Effective date | [YYYY-MM-DD] |
| Review interval | Annual |
| Version | [0.1-draft] |

> Template only, not legal advice. {{ company_name }} must review, edit, and adopt it before it takes effect.

## Purpose

Record, protect, and review system activity so actions trace to a person and misuse is found.

## Scope

All systems that process, store, or transmit CUI, including AWS, Google Workspace, Fathom, and workforce endpoints.

## Policy statements

1. The logged event list covers authentication attempts, privilege changes, execution of privileged functions, configuration changes, and access to CUI. Each record shows event type, time, source, outcome, and a unique user identity, so each action traces to one user. (3.3.1, 3.3.2)
2. Audit logs are kept 365 days. (3.3.1)
3. The logged event types are reviewed at least annually and after significant system changes or incidents. The review is dated and updates the list. (3.3.3)
4. **CUI stays out of application logs and out of SSM Session Manager sessions on CUI hosts.** CloudWatch Logs and SSM have no FIPS PrivateLink endpoint in commercial regions, so this rule, with the log-content review in statement 6, keeps 3.13.11 met. Developers must not log CUI payloads, and admins must not display or copy CUI in sessions. (3.13.11, 3.3.1)
5. A named reviewer reviews audit logs weekly using saved queries (privileged and admin activity, authentication, changes to security tooling). Each review creates a ticket with date and findings. Findings go to the security lead and affected system owners. Review scope grows after incidents. (3.3.5, 3.14.7)
6. At least quarterly, the reviewer samples application logs and session records for CUI and files an incident if any is found. (3.13.11)
7. Alerts for audit logging failure (a source stops sending, an agent fails, storage fills, logging is disabled) go to the security on-call team and logging platform owner within 1 hour. The response is: open a ticket, restore collection, and assess the gap. The alert path is tested at least annually. (3.3.4)
8. Only named logging administrators may manage audit logging, and only security and designated on-call engineers may read logs. Both lists are reviewed with the quarterly access review. Tampering alerts go to the security on-call team. (3.3.8, 3.3.9)
9. Alert triage, weekly review, and incident handling use one ticket and hand off to each other. Query and report capability across AWS and Workspace logs is tested at least annually. (3.3.5, 3.3.6)
10. System clocks sync to an authoritative UTC-traceable source so timestamps are comparable: the Amazon Time Sync Service for AWS compute, Google's time service for Workspace, and OS network time for endpoints. (3.3.7)

## Roles

- **Security lead:** owns the event list, reviews, and tests.
- **Log reviewer:** performs weekly review.
- **Logging platform owner:** keeps collection working.
- **Developers and admins:** follow statement 4.

## Exceptions

Written approval from {{ ssp_signer_name }}. Statement 4 has no standing exception. Any CUI found in logs is an incident.
