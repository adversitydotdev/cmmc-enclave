# Personnel Offboarding Procedure

| | |
|---|---|
| Owner | {{ ssp_signer_name }}, {{ ssp_signer_title }} |
| Approved by | [approver name and title] |
| Effective date | [YYYY-MM-DD] |
| Review interval | Annual |
| Version | [0.1-draft] |

> Template only, not legal advice. {{ company_name }} must review, edit, and adopt it before it takes effect.

Carries out the Personnel Security Policy, statements 2 to 6. Use one checklist ticket per person.

## Trigger

HR (or the manager) opens the ticket on the day a termination or role change is decided. The ticket records the effective date and time. Involuntary terminations: do steps 1 to 4 before or at the moment the person is told.

## Termination checklist

1. Suspend the Google Workspace account. Identity Center access ends through the sync. Target: within 24 hours of the event, sooner for involuntary exits. Record the time. (3.9.2)
2. Check for remaining sessions (Identity Center sessions can last up to 1 hour). Revoke them. Remove from privileged rosters and from groups.
3. Revoke keys, tokens, and credentials the person held: security keys, API tokens, SSH and CI keys, shared secrets, SCIM or break-glass credentials they knew. Rotate shared ones.
4. Disable physical access: badges, keys, alarm codes, and the site access list (within 1 business day). (3.10.1)
5. Recover company devices, security keys, media, and paper CUI. Wipe or reassign devices per the media sanitization rules. For devices not recovered, remote wipe.
6. Transfer ownership of the person's files, repositories, tickets, and service accounts. Preserve data needed for investigations.
7. Hold an exit briefing: continuing confidentiality duties, return of company property, no retained CUI. Record it.
8. Update inventories (accounts, devices, privileged roster, training roster).
9. Security lead closes the ticket after confirming steps 1 to 8 with evidence.

## Internal transfer checklist

1. Manager and system owner list access the new role needs.
2. Within 5 business days, remove access that is no longer needed and add approved access. Rescreen if the new role is privileged or high-risk.
3. Record the review in the ticket. (3.9.2)

## Records

Keep checklists. Each year the security lead compares them to HR termination dates and account disable times and reports misses.
