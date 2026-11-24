# GRC Data Handling Policy

| | |
|---|---|
| Owner | {{ ssp_signer_name }}, {{ ssp_signer_title }} |
| Approved by | [approver name and title] |
| Effective date | [YYYY-MM-DD] |
| Review interval | Annual |
| Version | [0.1-draft] |

> Template only, not legal advice. {{ company_name }} must review, edit, and adopt it before it takes effect. Have counsel confirm export-control treatment.

## Purpose

Keep CUI and export-controlled technical data out of the Fathom governance, risk, and compliance (GRC) system, which holds compliance records and not CUI.

## Scope

Anything uploaded to or typed into Fathom: evidence files, screenshots, tickets, policies, training records, POA&M entries, and notes. Fathom runs in a dedicated commercial AWS account.

## Policy statements

1. Fathom holds compliance records only: configuration exports, test results, tickets, policy documents, training and acknowledgment records, and POA&M entries. (3.1.3)
2. **No CUI** goes into Fathom uploads or fields. Redact or summarize before upload. Cite a CUI document by title and location, never its content. (3.1.3)
3. **No ITAR or EAR technical data** goes into Fathom uploads, on either the standard or the ITAR tier. Fathom's commercial account is not built for it, so this is enforced by this policy. (3.1.3)
4. The uploader checks each file before upload for CUI markings, controlled technical data, and credentials. Logs and screenshots are checked for stray CUI. (3.1.3, 3.3.1)
5. Anyone who finds CUI or export-controlled data in Fathom tells the security lead immediately. The file is removed, backups and logs are checked, and the event is handled as an incident under the Incident Response Policy. (3.6.1, 3.6.2)
6. The security lead samples uploads quarterly for compliance with this policy. (3.1.3, 3.3.5)
7. Training for anyone who can upload covers this policy. (3.2.1, 3.2.2)

## Roles

- **Uploaders:** check before upload.
- **Security lead:** samples uploads and runs removal.
- **{{ ssp_signer_name }}:** owns the policy.

## Exceptions

None. If a compliance record cannot be kept without CUI, store it in the CUI enclave and link to it.
