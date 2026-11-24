# Security Assessment Policy

| | |
|---|---|
| Owner | {{ ssp_signer_name }}, {{ ssp_signer_title }} |
| Approved by | [approver name and title] |
| Effective date | [YYYY-MM-DD] |
| Review interval | Annual |
| Version | [0.1-draft] |

> Template only, not legal advice. {{ company_name }} must review, edit, and adopt it before it takes effect. Confirm the CMMC program rules in 32 CFR Part 170 and the contract before relying on the statements below.

## Purpose

Describe the system, test its controls, track gaps, and meet the CMMC Level 2 assessment and affirmation duties.

## Scope

The enclave, its SSP, and every gap against the 110 requirements of NIST SP 800-171 Rev 2.

## Policy statements

1. A system security plan (SSP) describes the boundary, environment, how each requirement is met, and connections to other systems. It is generated from the OGRL graph, approved by {{ ssp_signer_name }}, and distributed to the people the system owner names. (3.12.4)
2. The SSP is reviewed at least annually and after significant system change or assessment findings. Review history is kept. (3.12.4)
3. Controls are assessed at least annually (CMMC Level 2 self-assessment or C3PAO assessment, using NIST SP 800-171A procedures) by someone independent of the control operators. A written plan is approved first, and the report goes to leadership. (3.12.1)
4. Control health is monitored at least daily through automated checks. A named owner triages each failure within 2 business days. Control health goes to leadership monthly. (3.12.3)
5. Every gap or failed objective goes on a plan of action and milestones (POA&M) with owner, milestones, and due date. Items are fixed by their due dates and closed with evidence. The security lead reviews open items monthly. (3.12.2)
6. **POA&M rules (32 CFR 170.21).** At CMMC Level 2 (Self), a POA&M is allowed only when (a) the assessment score is at least 80 percent of the maximum (88 of 110 points), (b) no item on it is worth more than 1 point under the DoD Assessment Methodology, except 3.13.11 where encryption is used but is not FIPS-validated, and (c) none of these is on it: 3.1.20 External Connections, 3.1.22 Control Public Information, 3.12.4 System Security Plan, 3.10.3 Escort Visitors, 3.10.4 Physical Access Logs, 3.10.5 Manage Physical Access ([32 CFR 170.21](https://www.ecfr.gov/current/title-32/subtitle-A/chapter-I/subchapter-G/part-170/subpart-C/section-170.21)). (3.12.2)
7. Open POA&M items are closed within 180 days of the Conditional status date. Items not closed in time make the Conditional status lapse, so the 180-day date is tracked from the first day. (3.12.2)
8. {{ company_name }} completes the CMMC assessment its DoD contracts require, at least every three years, and enters the result in SPRS (level, status date, scope, CAGE codes, score, POA&M). (3.12.1)
9. The Affirming Official affirms continuing compliance in SPRS after each assessment and annually. A reminder is set 30 days before the due date. (3.12.1)

## Roles

- **{{ ssp_signer_name }} ({{ ssp_signer_title }}):** approves the SSP.
- **Security lead:** runs monitoring and POA&M reviews.
- **Assessor:** independent of control operators.
- **Affirming Official:** the senior official designated for CMMC compliance who affirms in SPRS.

## Exceptions

None for statements 6 to 9, which are program rules. Others need written approval from {{ ssp_signer_name }}.
