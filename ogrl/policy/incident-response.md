# Incident Response Policy

| | |
|---|---|
| Owner | {{ ssp_signer_name }}, {{ ssp_signer_title }} |
| Approved by | [approver name and title] |
| Effective date | [YYYY-MM-DD] |
| Review interval | Annual |
| Version | [0.1-draft] |

> Template only, not legal advice. {{ company_name }} must review, edit, and adopt it before it takes effect. Have counsel confirm contract-specific reporting duties.

## Purpose

Detect, handle, report, and learn from security incidents, including the DoD reporting required by DFARS 252.204-7012.

## Scope

All systems and people handling CUI, and any event that may compromise CUI or the systems that protect it.

## Policy statements

1. An incident response plan names roles, escalation paths, DIBNet reporting, and customer notice. It is reviewed at least annually. (3.6.1)
2. The plan is tested at least annually with a tabletop exercise or drill. An after-action report records findings, and follow-ups are tracked to closure. (3.6.3)
3. Anyone who suspects an incident reports it to the security team within 24 hours through the published channel. (3.6.2)
4. Reports are triaged within 1 hour, classified on the written severity matrix, and given an incident commander. High severity goes to the security lead and executives. (3.6.1)
5. Every incident is recorded in one ticket queue with source, timeline, severity, affected systems and data, actions, owner, and resolution. Records are kept at least 3 years. (3.6.2)
6. **DoD reporting.** A cyber incident affecting covered defense information or the contractor's ability to perform is reported at dibnet.dod.mil **within 72 hours of discovery**. The security lead and at least one alternate hold a DoD-approved medium assurance certificate, checked quarterly. Follow the Cyber Incident Reporting Procedure. (3.6.2)
7. Suspected malicious software is submitted to the DoD Cyber Crime Center (DC3) as the procedure describes. (3.6.2)
8. Images of affected systems, plus relevant logs and packet captures, are preserved for **90 days** from the DIBNet report. DoD gets access on request for forensic analysis. (3.6.2, 3.3.1)
9. Affected customers and prime contractors are notified as their contracts require. (3.6.2)
10. Improperly posted CUI, lost devices, and suspected physical break-ins are handled as incidents. (3.6.1)

## Roles

- **Security lead:** runs the plan, owns DIBNet reporting and the certificate.
- **Alternate reporter:** files if the security lead is unavailable.
- **Incident commander:** assigned per incident.
- **Executives:** receive high severity escalations and decide on external statements.
- **Everyone:** reports within 24 hours.

## Exceptions

None for statements 3, 6, 7, and 8. Others need written approval from {{ ssp_signer_name }}.
