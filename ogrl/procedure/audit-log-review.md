# Audit Log Review Procedure

| | |
|---|---|
| Owner | {{ ssp_signer_name }}, {{ ssp_signer_title }} |
| Approved by | [approver name and title] |
| Effective date | [YYYY-MM-DD] |
| Review interval | Annual |
| Version | [0.1-draft] |

> Template only, not legal advice. {{ company_name }} must review, edit, and adopt it before it takes effect.

Carries out the Audit and Accountability Policy, statements 3, 5, and 6.

## Weekly review

1. The named reviewer opens a ticket titled with the week.
2. Run the saved queries for AWS (CloudTrail and security tooling) and Google Workspace (admin and login activity): unauthorized privileged actions, unusual sign-in patterns, and disabled or changed security controls.
3. Check the logging health dashboard for gaps. Any gap is a logging failure (see policy statement 7).
4. Note findings, or "none", with the date in the ticket.
5. Send findings to the security lead and affected system owners. Open an incident if warranted. After any incident, widen the scope for the next review.
6. Close the ticket.

## Quarterly content check

1. Sample application logs and recent SSM session records on CUI hosts for CUI. Record the sample and result. Any hit is an incident.
2. Review the lists of logging administrators and log readers with the access review.

## Annual event review

1. Compare the logged event list with the system and recent incidents. Add or drop event types.
2. Record the date, the decision, and the resulting Terraform or runbook change.
3. Run the log query and report test across AWS and Workspace logs, and the logging failure alert test. File the results.
