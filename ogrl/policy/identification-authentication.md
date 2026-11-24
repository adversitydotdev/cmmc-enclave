# Identification and Authentication Policy

| | |
|---|---|
| Owner | {{ ssp_signer_name }}, {{ ssp_signer_title }} |
| Approved by | [approver name and title] |
| Effective date | [YYYY-MM-DD] |
| Review interval | Annual |
| Version | [0.1-draft] |

> Template only, not legal advice. {{ company_name }} must review, edit, and adopt it before it takes effect.

## Purpose

Make sure every user, process, and device is identified, and every access is authenticated strongly.

## Scope

All users, service accounts, and devices that reach {{ company_name }} systems.

## Policy statements

1. Each user has one unique identity from the designated workforce identity provider (Google Workspace with single sign-on). Shared accounts are not allowed. Service and break-glass accounts are inventoried with an owner. (3.5.1, 3.5.2)
2. Identifiers are never reassigned to another person or device for at least two years. (3.5.5)
3. Multi-factor authentication is required for all users on local and network access to privileged accounts and for network access to non-privileged accounts. Phishing-resistant keys (FIDO2/WebAuthn) are preferred, with TOTP as the fallback. (3.5.3)
4. Each user registers at least two security keys. Replacement and reset need identity proofing. Admin-issued backup codes follow a documented process. (3.5.3)
5. Authentication is replay-resistant for privileged and non-privileged accounts. NTLMv1, LM, Telnet, unencrypted FTP, and basic authentication are prohibited. (3.5.4)
6. Passwords (where still used) are at least 12 characters with at least three of upper, lower, number, and special characters, change at least 4 characters from the previous password, and are never any of the last 24. Temporary passwords work once and must be changed immediately. Passwords are screened against breached and blocklisted values, updated at least monthly. (3.5.7, 3.5.8, 3.5.9)
7. After 5 failed sign-in attempts within 15 minutes, the account is locked. (3.1.8)
8. Authenticators are stored and sent protected. Passwords and keys are never sent in clear text. Temporary passwords go over a channel separate from the account notice. (3.5.10)
9. Authenticators and secrets are rotated every 90 days where used, and on suspected exposure, departure, or decommissioning. Break-glass keys are sealed with named custodians. The SCIM token has a named owner and is rotated yearly. (3.5.9)
10. Accounts inactive for 90 days are disabled. Contractor and temporary accounts have an expiry date of at most 30 days unless renewed. The inactivity report is reviewed monthly. (3.5.6)
11. Devices are identified before they connect to CUI systems: managed and registered devices only. (3.5.2)
12. Where the platform cannot enforce a rule above (for example Workspace password history or IAM lockout), the gap is recorded as an accepted risk or POA&M item. (3.5.8, 3.1.8)

## Roles

- **Security lead:** owns the standard, key issuing, and reset proofing.
- **IT lead:** operates the identity provider and inactivity review.
- **Users:** keep authenticators private and report loss immediately.

## Exceptions

Written approval from {{ ssp_signer_name }} with compensating controls and an end date. Single-factor access to CUI systems is never excepted.
