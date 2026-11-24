# Cyber Incident Reporting Procedure (DFARS 252.204-7012)

| | |
|---|---|
| Owner | {{ ssp_signer_name }}, {{ ssp_signer_title }} |
| Approved by | [approver name and title] |
| Effective date | [YYYY-MM-DD] |
| Review interval | Annual, and after every real report or drill |
| Version | [0.1-draft] |

> Template only, not legal advice. {{ company_name }} must review, edit, and adopt it before it takes effect. Confirm current DIBNet and DC3 submission steps at dibnet.dod.mil before use.

Carries out the Incident Response Policy, statements 6 to 8.

## Before an incident

1. The security lead and one alternate each hold a DoD-approved medium assurance certificate. Check both quarterly and record the check date and expiry. (3.6.2)
2. Keep a current list of DoD contract numbers, CAGE codes, and contracting officer and prime contact details for {{ company_name }}.

## When a cyber incident is suspected

1. Open an incident ticket. Note the **discovery time**: the 72-hour clock starts there. (3.6.1)
2. Contain the incident per the incident response plan. Do not wipe or rebuild affected systems yet.
3. Review the systems and data affected. Decide whether covered defense information (CUI) or the ability to perform a DoD contract is affected. If unsure, report. (3.6.2)
4. Preserve images of affected systems and relevant logs and packet captures. Keep them **90 days from the DIBNet report**. Record where they are and who has custody. (3.6.2)
5. File the report at dibnet.dod.mil within **72 hours of discovery** using the medium assurance certificate. Include the contract and CAGE details. Save the incident report number and a copy of the submission in the ticket. If details are missing at 72 hours, report what is known and update later.
6. If malicious software was found, isolate a copy and submit it to the DoD Cyber Crime Center (DC3) using the DC3 malware submission process. Do not send it to the contracting officer. Record the submission.
7. Tell affected primes and customers as their contracts require. Subcontractors also give the prime the DIBNet incident report number.
8. If DoD asks for access to equipment or images for forensic analysis, give it. Route all such requests through the security lead.
9. After the incident, rebuild and restore. Run the after-action review, update the plan, and record follow-ups in the ticket. Keep the ticket at least 3 years. (3.6.1, 3.6.2)

## Drill

Run this procedure as a tabletop at least annually, including a mock DIBNet report that stops short of submission. (3.6.3)
