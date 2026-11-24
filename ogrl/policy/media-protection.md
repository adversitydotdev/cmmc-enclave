# Media Protection Policy

| | |
|---|---|
| Owner | {{ ssp_signer_name }}, {{ ssp_signer_title }} |
| Approved by | [approver name and title] |
| Effective date | [YYYY-MM-DD] |
| Review interval | Annual |
| Version | [0.1-draft] |

> Template only, not legal advice. {{ company_name }} must review, edit, and adopt it before it takes effect.

## Purpose

Protect CUI on paper and portable media from creation to destruction.

## Scope

Paper documents and printouts, USB drives, external drives, memory cards, optical discs, backup media, laptops, phones, and any other device that holds CUI ({{ cui_categories }}).

## Policy statements

1. Paper CUI and portable media stay in an authorized user's custody while in use and in locked storage (cabinet, drawer, safe, or room) when not. Keys go only to designated custodians. The access record is reviewed quarterly. (3.8.1, 3.8.2)
2. Paper and media with CUI carry the CUI banner, category indicator, and distribution statement required by 32 CFR 2002 and DoDI 5200.48. Marking is sampled annually. (3.8.4)
3. Removable media is allowed only if issued, inventoried, and on the device allow-list. The allow-list is enforced by endpoint device control and reviewed quarterly. Unapproved and ownerless portable storage is prohibited. (3.8.7, 3.8.8)
4. Using CUI on an external system or portable storage needs prior written approval (see Access Control Policy) and FIPS-validated encryption. (3.1.21)
5. Media leaves controlled areas only with an authorized courier or tracked carrier, in sealed tamper-evident packaging, with FIPS-validated encryption for digital media and keys sent separately. Alternative physical safeguards are not used in place of encryption. Each transport is logged and open entries are reconciled monthly. (3.8.5, 3.8.6)
6. Media is sanitized or destroyed before disposal or reuse using NIST SP 800-88: cross-cut shredding or pulping for paper, clear, purge, or destroy (including cryptographic erase) for devices. Record asset, method, date, and performer. Keep vendor destruction certificates. (3.8.3)
7. Backups of CUI outside the cloud accounts (Vault or Takeout exports, paper, removable media, on-premises copies) are encrypted or locked up under this policy. Restores are tested annually. (3.8.9)

## Roles

- **Security lead:** owns the allow-list, marking sample, and reviews.
- **Media custodians:** hold keys and keep the access record.
- **Everyone:** mark, store, and transport CUI as above.

## Exceptions

Written approval from the security lead, recording the media, CUI, reason, and end date. Reviewed quarterly.
