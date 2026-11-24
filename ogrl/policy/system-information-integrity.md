# System and Information Integrity Policy

| | |
|---|---|
| Owner | {{ ssp_signer_name }}, {{ ssp_signer_title }} |
| Approved by | [approver name and title] |
| Effective date | [YYYY-MM-DD] |
| Review interval | Annual |
| Version | [0.1-draft] |

> Template only, not legal advice. {{ company_name }} must review, edit, and adopt it before it takes effect.

## Purpose

Fix flaws quickly, block malicious code, and watch systems for attacks.

## Scope

All endpoints and servers in the CMMC assessment scope, plus cloud services and applications that process, store, or transmit CUI.

## Policy statements

1. Security patches follow the change process. Critical fixes are applied within 14 days, high within 30 days, other security updates within 90 days. Patches are tested first where practical. Exceptions are recorded with a risk acceptance. (3.14.1, 3.11.3)
2. Anti-malware protection runs on all endpoints and servers running general-purpose operating systems. Signatures and engines update automatically. (3.14.2, 3.14.4)
3. Systems are scanned weekly, and files from external sources are scanned when opened or downloaded. Detections are blocked and quarantined and alert the security on-call team. (3.14.5)
4. The security team checks agent coverage monthly and fixes gaps. (3.14.2)
5. Security advisories are collected from vendors of in-scope software and cloud services, the CISA Known Exploited Vulnerabilities catalog, and GitHub advisories. Each is triaged within 2 business days, sent to the service owner if it applies, and tracked to closure. (3.14.3)
6. Systems are monitored for attacks and indicators of attack, unauthorized local, network, and remote connections, and unusual activity. Alert recipients are named and on call. High severity alerts are triaged within 4 hours. (3.14.6, 3.14.7, 3.13.1)
7. Authorized use of each system is defined and unauthorized use is identified by the monitoring above. (3.14.7)

## Roles

- **Security lead:** owns monitoring, advisories, and coverage checks.
- **IT lead:** applies patches and runs the malware tooling.
- **Service owners:** act on advisories.

## Exceptions

Written approval from the security lead with a risk acceptance and end date. Anything beyond 90 days goes on the POA&M.
