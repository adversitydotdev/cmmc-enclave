# Access Control and Acceptable Use Policy

| | |
|---|---|
| Owner | {{ ssp_signer_name }}, {{ ssp_signer_title }} |
| Approved by | [approver name and title] |
| Effective date | [YYYY-MM-DD] |
| Review interval | Annual |
| Version | [0.1-draft] |

> Template only, not legal advice. {{ company_name }} must review, edit, and adopt it before it takes effect.

## Purpose

Limit who and what can reach {{ company_name }} systems and Controlled Unclassified Information (CUI), and set the rules every user follows.

## Scope

All workforce members, contractors, and service accounts, and all systems that process, store, or transmit CUI ({{ cui_categories }}), including Google Workspace, AWS, Fathom, and workforce endpoints.

## Policy statements

1. Every user and service account request is approved by the system owner or the requester's manager before the account is created. Accounts are tied to a named person or owner. (3.1.1)
2. Each role has documented permitted functions and transaction types. Role assignments are approved and reviewed quarterly. Users get least privilege. (3.1.2, 3.1.5)
3. Privileged roles go only to the named roster of infrastructure and security staff. Admin assignments in AWS Identity Center and Workspace are reconciled against the roster monthly. Admins use a separate non-privileged account for daily work. Non-privileged users cannot run privileged functions, and attempts are logged. (3.1.5, 3.1.6, 3.1.7)
4. Conflicting duties are held by different people: authoring and approving production changes, requesting and approving access, administering systems and reviewing their logs. If the team is too small, record an exception with after-the-fact review. (3.1.4)
5. Accounts are disabled within 24 hours of termination or role change (see Personnel Security Policy). (3.1.1)
6. CUI moves only between systems on the authorized flow list. The system owner approves any new flow. Boundary and data flow diagrams in the SSP are updated when the architecture changes. (3.1.3)
7. Each sign-in screen or login banner shows the approved system use notice. Counsel approves one text and it is reviewed annually. (3.1.9)
8. Remote access is allowed only through the documented methods (Workspace sign-in, Identity Center, Session Manager). Each is authorized before it is enabled and reviewed annually. Remote use of privileged commands needs documented approval. (3.1.12, 3.1.13, 3.1.14, 3.1.15)
9. Wireless: home and public networks are untrusted. Office access points are inventoried and authorized, use WPA2 or WPA3 Enterprise with AES, and guest wireless is kept apart. Wireless access is reviewed quarterly. (3.1.16, 3.1.17)
10. Only managed mobile devices may reach CUI. Each is authorized, uses FIPS-validated full-disk encryption, locks after 15 minutes or less, and can be remotely wiped. Access is revoked and company data wiped within 24 hours of a loss report. Mobile and desktop connections are logged through Workspace sign-in and device records and reviewed in the weekly log review. (3.1.18, 3.1.19)
11. External systems (cloud services, partner portals, MSPs) are inventoried and approved by the information security lead only after verifying FedRAMP authorization or equivalency, CMMC status, or a documented assessment. Reviewed annually. Personal devices and unapproved cloud services must not handle CUI. (3.1.20)
12. CUI on portable storage or any external system needs prior written approval from the security owner that names the device, the CUI, the system, and the purpose, plus FIPS-validated encryption. (3.1.21)
13. Only people on the publisher roster may post to public sites, and they get approval first. Public content is reviewed quarterly. Improperly posted CUI is removed within 24 hours and reported as an incident. (3.1.22)
14. Remote joining of Google Meet hardware to calls by administrators is prohibited. Meet rooms are joined only from the room. (3.13.12)
15. Acceptable use: users handle CUI only on approved systems, never move it to personal accounts or unapproved SaaS, keep credentials private, report suspected incidents within 24 hours, and follow the rules in this policy. Each person acknowledges these rules before accounts are provisioned and again annually. The rules are reviewed at least annually. (3.2.1)
16. Endpoints lock after 15 minutes of inactivity, require re-authentication, and show a pattern-hiding display. Sessions end automatically on any of these conditions: 30 minutes of inactivity where the platform has an inactivity timer, 12 hours total, termination or role change, or loss of device compliance. Where Workspace or Identity Center cannot enforce inactivity, session length plus the endpoint lock applies. (3.1.10, 3.1.11)

## Roles

- **System owner:** approves accounts, roles, flows, remote methods.
- **Security lead:** keeps the privileged roster, runs reviews, approves CUI on external systems.
- **Information security lead:** approves external systems.
- **Users:** follow statement 15 and sign the acknowledgment.

## Exceptions

Written approval from {{ ssp_signer_name }}, naming the statement, the compensating measures, and an end date no more than one year out. Exceptions are recorded and reviewed at each annual policy review.
