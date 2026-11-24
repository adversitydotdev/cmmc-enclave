# Google Workspace manual runbook

Ordered steps for the Workspace settings no API can write, each paired with the read that proves it stuck. Source of truth for values, requirement IDs and checks is [workspace/settings.yaml](../../workspace/settings.yaml) (#27); the vendor guide is the [Google Workspace CMMC implementation guide](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf). Decisions that shape it ([docs/SCOPE.md](../SCOPE.md) section 12):

- Enterprise Plus with Assured Controls Plus by default; plain Assured Controls is the fallback (section 4 skipped).
- 2-Step Verification uses security keys only.
- Workspace is the IdP for AWS (IAM Identity Center via SAML and SCIM).
- Fathom signs in through Google OIDC.

Each step lists what to set (Admin console path), the expected value, the OU, the 800-171 requirement IDs, and how it is checked. Checks are: Policy API (`cloudidentity` v1beta1 policies, setting name shown), Reports API, Directory API, DNS, or manual evidence (dated screenshot filed with the step number). Screenshot placeholders are HTML comments; replace them with the captured file name when running a real deployment.

Rules of the road:

- "CUI OU" and "non-CUI OU" are the OUs from `terraform/stacks/workspace`. Settings marked "CUI and non-CUI OUs" are applied at both.
- Some Policy API settings are writable (DLP, Drive general access default, multi-party approval, passkeys). Only DLP is scripted (`scripts/workspace-dlp`); the others are set in the console here and read back.
- The OGRL tests for the Policy API reads (`ogrl/org/test/workspace-*.yaml`) have no `run` block yet and are `required: false` until the fathom-google-workspace integration (#33) supplies it.
- Edition support per feature is not verified in `settings.yaml`; confirm in the tenant.

## Order and time

Estimates are unmeasured; #39 records real times. Per SCOPE section 1, manual runbook steps are timed separately from the wizard plus Terraform clock for the #3 objective (under an hour, a couple of hours at most). Not counted at all: license purchase, Google provisioning Assured Controls, DNS propagation.

| # | Section | When | Min |
|---|---|---|---|
| 1 | Tenant prerequisites | before workspace stage | 20 |
| 2 | Service accounts and domain-wide delegation | before workspace stage | 25 |
| 3 | Bootstrap workspace stage (Terraform) | the stage itself | on the clock |
| 4 | Assured Controls Plus (skip on plain Assured Controls) | after | 15 |
| 5 | Authentication | after | 25 |
| 6 | Session and API controls | after | 8 |
| 7 | Service status and Marketplace | after | 20 |
| 8 | Drive and DLP | after | 15 |
| 9 | Gmail and DNS | after | 25 |
| 10 | AWS IAM Identity Center SAML app and SCIM | after (needs the AWS org stack) | 30 |
| 11 | Fathom Google OAuth client | after the AWS org stack, before the Fathom apply | 10 |
| 12 | Devices | after | 10 |
| 13 | Alert Center, rules and monitoring | after | 25 |
| 14 | Evidence pass | last | 20 |
| | **Total** | before: 45, after: 203 | **248** |

Read against #3: the wizard-plus-Terraform path can meet the objective only because these 248 minutes (about 4 hours; 233 on plain Assured Controls) are off its clock. If the runbook were counted, it would miss "a couple of hours at most" by roughly two hours. The sections that could shrink: skip optional steps (marked), pre-create the service accounts while waiting on licenses, and batch the screenshots into the evidence pass.


## 1. Tenant prerequisites

*20 min. Before the bootstrap workspace stage.*

Edition decision D1: Enterprise Plus with Assured Controls Plus. Plain Assured Controls is the fallback (section 4 is then skipped).

**1.0 Edition and super admins**
- Set: Billing > Subscriptions (confirm Enterprise Plus and the Assured Controls Plus add-on). Create 2 or more named super admins, each with a security key registered (Directory > Users > Security > 2-step verification), plus a separate daily account each.
- Expected: edition shown as above; 2 or more super admins, none shared; each enrolled with a security key.
- OU: n/a (tenant-wide)
- Reqs: 3.1.5, 3.1.6, 3.4.5
- Check: Directory API `users.list` (isAdmin count, isEnrolledIn2Sv)
<!-- screenshot: edition-and-super-admins -->

**1.1 Super admin minimum**
- Set: Directory > Users (filter: Admin status); Account > Admin roles > Super Admin
- Expected: Two to a few named super admins, security keys, each also holds a separate daily account
- OU: n/a (tenant-wide)
- Reqs: 3.1.5, 3.1.6, 3.4.5 ([guide p25](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=25))
- Check: Directory API
<!-- screenshot: super-admin-minimum-na -->

**1.2 Reseller access removal**
- Set: Billing > Subscriptions (reseller access)
- Expected: No reseller admin access after onboarding (only if the tenant was resold)
- OU: n/a (tenant-wide)
- Reqs: 3.1.1 ([guide p17](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=17))
- Check: Manual evidence: dated screenshot
<!-- screenshot: reseller-access-removal-na -->


## 2. Service accounts and domain-wide delegation

*25 min. Before the bootstrap workspace stage.*

Three separate service accounts, one per scope set, so each key can be rotated or revoked on its own and a leak of one cannot do the work of another. Create all three in one Google Cloud project, enable the Admin SDK API once (APIs and services > Library > Admin SDK API), then in Admin console go to Security > Access and data control > API controls > Manage domain-wide delegation and add each numeric client ID with exactly the scopes below, nothing more.

| Service account | Used by | DWD scopes (exact) | Key goes to |
|---|---|---|---|
| `enclave-workspace-terraform` | `terraform/stacks/workspace` (macadmins provider) | `https://www.googleapis.com/auth/admin.directory.orgunit`, `https://www.googleapis.com/auth/admin.directory.user`, `https://www.googleapis.com/auth/admin.directory.group`, `https://www.googleapis.com/auth/admin.directory.rolemanagement` | `GOOGLEWORKSPACE_CREDENTIALS` on the operator machine (never committed) |
| `enclave-workspace-audit` (#30) | `collectors/workspace_audit` | `https://www.googleapis.com/auth/admin.reports.audit.readonly` | Secrets Manager secret `workspace_audit_secret_arn` |
| `enclave-workspace-idle` | `collectors/workspace_idle` (idle-account job, #51) | report mode (default): `https://www.googleapis.com/auth/admin.directory.user.readonly`; suspend mode: `https://www.googleapis.com/auth/admin.directory.user` | Secrets Manager secret `workspace_idle_secret_arn` |

**2.1 Terraform service account.** Create the service account and a JSON key, add the delegation row above, and set `impersonated_user_email` to a super admin (role management is super-admin only). This one drives the workspace stage.
<!-- screenshot: dwd-terraform-sa -->

**2.2 Audit collector service account (#30).** Run before the first baseline apply.
1. Create the service account and a JSON key.
2. Add its client ID with only `admin.reports.audit.readonly`.
3. `aws secretsmanager put-secret-value --secret-id <workspace_audit_secret_arn> --secret-string file://key.json`, then delete `key.json`.
4. Set `workspace_admin_email` in tfvars. Run `collectors/workspace_audit/build.sh` before every plan.
5. Rotate the key by hand; set a calendar reminder.

Reqs: 3.1.12, 3.3.1. Check: Reports API (collector output in the log archive); DWD page screenshot as manual evidence.
<!-- screenshot: dwd-audit-sa -->

**2.3 Idle-account job service account (#51).**
1. Run `collectors/workspace_idle/build.sh` before plan or apply.
2. Create a second, separate service account (for example `enclave-workspace-idle`) and a JSON key.
3. Add its client ID with exactly one scope: `admin.directory.user.readonly` in report mode (default), or `admin.directory.user` in suspend mode. The Terraform output `workspace_idle_delegated_scope` prints the right one.
4. Put the key JSON into the secret from output `workspace_idle_secret_arn` as SecretString, then delete the local file.
5. Set `workspace_idle_exclude_emails` (break-glass, service accounts) and `workspace_idle_exclude_org_units`. Run in report mode and review the `workspace-idle/dt=...` reports.
6. To enforce: set `workspace_idle_mode="suspend"`, apply, and replace the delegation scope with the write scope.
7. Rotate the key by hand. The `Success` alarm stays in ALARM until the first daily run; that is expected.

Reqs: 3.5.6. Check: Directory API (`lastLoginTime`, `suspended`); job reports in S3.
<!-- screenshot: dwd-idle-sa -->

**2.4 Admin SDK and delegation review.** Confirm the delegation page lists exactly these three client IDs and scopes. Reqs: 3.1.12, 3.1.15. Check: manual evidence (screenshot of the delegation page).
<!-- screenshot: dwd-page -->

## 3. Bootstrap workspace stage (Terraform)

*Not manual. Everything below this line is done after it.*

`terraform/stacks/workspace` creates the CUI and non-CUI OUs, groups, custom admin roles (including Audit and investigation viewer) and users with change-at-next-login. Run it now. Sections 4 onward need the OUs to exist.

## 4. Assured Controls Plus

*15 min. After the bootstrap workspace stage.*

**Skip this whole section if the tenant has plain Assured Controls (D1 fallback).** Record the skip in the evidence log ("Assured Controls, not Plus: section 4 not applicable"). With Assured Controls Plus, set these in order. Console paths follow Google's [Assured Controls](https://knowledge.workspace.google.com/admin/security/about-assured-controls-and-assured-controls-plus) page; no Policy API read exists for them as far as we found, so the check is manual evidence for all three.

**4.1 Data regions for the CUI OU**
- Set: Account > Account settings > Data regions > select the CUI OU (or a CUI configuration group) > Data region: United States.
- Expected: US for covered data; non-CUI OU may stay unset.
- OU: CUI OU
- Reqs: 3.1.3 (control of CUI flow; mapping is ours, Google's guide has no ACP section)
- Check: Manual evidence: dated screenshot
<!-- screenshot: acp-data-regions-cui -->

**4.2 Access Management (US personnel)**
- Set: Account > Account settings > Support/Access management > turn on so only Google personnel in the US with the required screening can access the data.
- Expected: On for the organization.
- OU: tenant-wide
- Reqs: 3.1.1 (mapping is ours)
- Check: Manual evidence: dated screenshot
<!-- screenshot: acp-access-management -->

**4.3 Access Approvals**
- Set: Account > Account settings > Access Approvals > turn on and name the approvers (2 or more).
- Expected: On; approver group is the security mailbox group.
- OU: tenant-wide
- Reqs: 3.1.1, 3.1.5 (mapping is ours)
- Check: Manual evidence: dated screenshot
<!-- screenshot: acp-access-approvals -->

Verify the exact console labels in the tenant; Google moves these pages and we could not read them without a tenant.

## 5. Authentication

*25 min. After the bootstrap workspace stage.*

Order matters: multi-party approval first (it then also protects the next steps, and needs 2 or more super admins), then 2SV methods, enroll admins, then enforce.

**5.1 Multi party approval**
- Set: Security > Authentication > Multi-party approval settings
- Expected: Require multi-party approval for sensitive admin actions: on (on by default with 2+ super admins)
- OU: n/a (tenant-wide)
- Reqs: 3.4.3 ([guide p50](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=50))
- Check: Policy API read-back (write is by hand in the console; the script covers DLP only): `multi_party_approval.require_approvals`; OGRL test `workspace-multi-party-approval`
<!-- screenshot: multi-party-approval-na -->

**5.2 2SV enrollment**
- Set: Security > Authentication > 2-step verification > Allow users to turn on 2-Step Verification
- Expected: Checked, both OUs
- OU: CUI and non-CUI OUs
- Reqs: 3.5.3 ([guide p62](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=62))
- Check: Policy API read: `security.two_step_verification_enrollment`; OGRL test `workspace-2sv-enrollment`
<!-- screenshot: 2sv-enrollment-all -->

**5.3 2SV methods**
- Set: Security > Authentication > 2-step verification > Methods
- Expected: Only security key (passkeys count). Policy API enum PASSKEY_ONLY. Decision: security keys only.
- OU: CUI and non-CUI OUs
- Reqs: 3.5.3 ([guide p62](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=62))
- Check: Policy API read: `security.two_step_verification_enforcement_factor`; OGRL test `workspace-2sv-methods`
<!-- screenshot: 2sv-methods-all -->

**5.4 Passkeys restriction** (optional)
- Set: Security > Authentication > Passkeys
- Expected: Optional. Restrict to security-key bound passkeys
- OU: CUI and non-CUI OUs
- Reqs: 3.5.3 (not in the guide (OGRL baseline))
- Check: Policy API read-back (write is by hand in the console; the script covers DLP only): `security.passkeys_restriction`; OGRL test `workspace-passkeys-restriction`
<!-- screenshot: passkeys-restriction-all -->

**5.5 Enroll admins first.** Every admin registers a security key (Security > 2-step verification, user side). Check: Reports API `user_accounts` (`is_2sv_enrolled`).
<!-- screenshot: admins-enrolled -->

**5.6 2SV enforcement**
- Set: Security > Authentication > 2-step verification > Enforcement
- Expected: On (starts immediately) for both OUs. Do this only after every admin has enrolled a security key.
- OU: CUI and non-CUI OUs
- Reqs: 3.5.3 ([guide p62](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=62))
- Check: Policy API read: `security.two_step_verification_enforcement`; OGRL test `workspace-2sv-enforcement`
<!-- screenshot: 2sv-enforcement-all -->

**5.7 2SV post sso**
- Set: Security > Authentication > Login challenges > Post-SSO verification
- Expected: Not applicable while Google is the IdP (no inbound SSO profile)
- OU: CUI and non-CUI OUs
- Reqs: 3.5.3 ([guide p63](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=63))
- Check: Manual evidence: dated screenshot (Policy API `security.login_challenges` exposes only part of it)
<!-- screenshot: 2sv-post-sso-all -->

**5.8 Password strength**
- Set: Security > Authentication > Password management > Strength
- Expected: Enforce strong password checked (allowedStrength STRONG); enforceRequirementsAtLogin true
- OU: CUI and non-CUI OUs
- Reqs: 3.5.7 ([guide p65](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=65))
- Check: Policy API read: `security.password`; OGRL test `workspace-password-strength`
<!-- screenshot: password-strength-all -->

**5.9 Password length**
- Set: Security > Authentication > Password management > Length
- Expected: Minimum 12, maximum 100 (OGRL; guide range 8 to 100)
- OU: CUI and non-CUI OUs
- Reqs: 3.5.7 ([guide p65](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=65))
- Check: Policy API read: `security.password`; OGRL test `workspace-password-length`
<!-- screenshot: password-length-all -->

**5.10 Password reuse**
- Set: Security > Authentication > Password management > Reuse
- Expected: Allow password reuse unchecked.
- OU: CUI and non-CUI OUs
- Reqs: 3.5.7, 3.5.8 ([guide p65](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=65))
- Check: Policy API read: `security.password`; OGRL test `workspace-password-reuse`
<!-- screenshot: password-reuse-all -->

**5.11 Password expiration** (optional)
- Set: Security > Authentication > Password management > Expiration
- Expected: Optional. Never expire (0 seconds) unless the password policy sets a period.
- OU: CUI and non-CUI OUs
- Reqs: 3.5.7 ([guide p65](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=65))
- Check: Policy API read: `security.password`; OGRL test `workspace-password-expiration`
<!-- screenshot: password-expiration-all -->


## 6. Session and API controls

*8 min. After the bootstrap workspace stage.*



**6.1 Web session duration**
- Set: Security > Access and data control > Google session control > Web session duration
- Expected: 12 hours or less for CUI OU (OGRL baseline); guide gives no value, default 14 days (p79)
- OU: CUI OU
- Reqs: 3.1.11, 3.13.9 ([guide p29](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=29))
- Check: Policy API read: `security.session_controls`; OGRL test `workspace-web-session-duration`
<!-- screenshot: web-session-duration-cui -->

**6.2 API controls third party apps**
- Set: Security > Access and data control > API controls > Settings > Unconfigured third-party apps
- Expected: Don't allow users to access any third-party apps (guide offers only: basic Sign in with Google scopes, or none); allow-list reviewed apps explicitly
- OU: CUI and non-CUI OUs
- Reqs: 3.1.1, 3.1.3, 3.1.20 ([guide p37](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=37))
- Check: Policy API read: `api_controls.unconfigured_third_party_apps`; OGRL test `workspace-api-controls-third-party-apps`
<!-- screenshot: api-controls-third-party-apps-all -->

**6.3 Less secure apps**
- Set: Security > Authentication > Less secure apps
- Expected: Don't allow users to use less secure apps
- OU: CUI and non-CUI OUs
- Reqs: 3.1.20 (not in the guide (OGRL baseline))
- Check: Policy API read: `security.less_secure_apps`; OGRL test `workspace-less-secure-apps`
<!-- screenshot: less-secure-apps-all -->


## 7. Service status and Marketplace

*20 min. After the bootstrap workspace stage.*

Turn off everything that is not FedRAMP High on the CUI OU, including Sites, additional Google services and system apps, then allowlist Marketplace apps.

**7.1 Service status per ou**
- Set: Apps > Google Workspace > Service status; Apps > Additional Google services
- Expected: Only FedRAMP High services On for the CUI OU; all others Off (SCOPE section 5)
- OU: CUI OU
- Reqs: 3.4.6, 3.4.7, 3.1.22 ([guide p53](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=53))
- Check: Policy API read: `service_status`; OGRL test `workspace-service-status-per-ou`
<!-- screenshot: service-status-per-ou-cui -->

**7.2 Sites publishing**
- Set: Apps > Google Workspace > Sites (service status) and Sites > New Sites
- Expected: Sites service off for the CUI OU; sites_creation_and_modification off
- OU: CUI OU
- Reqs: 3.1.22 ([guide p38](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=38))
- Check: Policy API read: `sites.sites_creation_and_modification`; OGRL test `workspace-sites-publishing`
<!-- screenshot: sites-publishing-cui -->

**7.3 Marketplace user install**
- Set: Apps > Google Workspace Marketplace apps > Apps list > User install settings
- Expected: Allow users to install only allowlisted apps (internal apps optional)
- OU: CUI OU
- Reqs: 3.4.6, 3.4.8, 3.4.9 ([guide p58](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=58))
- Check: Policy API read: `workspace_marketplace.apps_access_options`; OGRL test `workspace-marketplace-user-install`
<!-- screenshot: marketplace-user-install-cui -->

**7.4 Marketplace allowlist**
- Set: Apps > Google Workspace Marketplace apps > Apps list > Allowlist app
- Expected: Reviewed apps only; quarterly review
- OU: CUI OU
- Reqs: 3.4.6, 3.4.8, 3.4.9 ([guide p55](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=55))
- Check: Policy API read: `workspace_marketplace.apps_allowlist`; OGRL test `workspace-marketplace-allowlist`
<!-- screenshot: marketplace-allowlist-cui -->

**7.5 Web mobile apps access review**
- Set: Apps > Web and mobile apps (filter by OU or group, Access details)
- Expected: Review of per-OU app access, monitored for installs
- OU: CUI OU
- Reqs: 3.4.9 ([guide p58](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=58))
- Check: Manual evidence: dated screenshot
<!-- screenshot: web-mobile-apps-access-review-cui -->

**7.6 Mobile system apps block** (optional)
- Set: Devices > Mobile and endpoints > Settings > Universal (system apps)
- Expected: Optional. Block unneeded system apps on company-owned devices
- OU: CUI OU
- Reqs: 3.4.6 ([guide p53](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=53))
- Check: Manual evidence: dated screenshot
<!-- screenshot: mobile-system-apps-block-cui -->


## 8. Drive and DLP

*15 min. After the bootstrap workspace stage.*

DLP rules and detectors are created by script, not by hand. Needs a Cloud Identity Policy API scope (`https://www.googleapis.com/auth/cloud-identity.policies`) on the credentials you give the script; use an admin's application default credentials (`gcloud auth application-default login --scopes=https://www.googleapis.com/auth/cloud-identity.policies,https://www.googleapis.com/auth/cloud-platform`) or a delegated service account.

**8.1 Drive external sharing**
- Set: Apps > Google Workspace > Drive and Docs > Sharing settings > Sharing options
- Expected: External sharing off or allow-listed for the CUI OU; anyone-with-link off
- OU: CUI OU
- Reqs: 3.1.3, 3.1.22 (not in the guide (OGRL baseline))
- Check: Policy API read: `drive_and_docs.external_sharing`; OGRL test `workspace-drive-external-sharing`
<!-- screenshot: drive-external-sharing-cui -->

**8.2 Drive general access default**
- Set: Apps > Google Workspace > Drive and Docs > Sharing settings > General access default
- Expected: Restricted (not Anyone with the link).
- OU: CUI OU
- Reqs: 3.1.3, 3.1.22 (not in the guide (OGRL baseline))
- Check: Policy API read-back (write is by hand in the console; the script covers DLP only): `drive_and_docs.general_access_default`; OGRL test `workspace-drive-general-access-default`
<!-- screenshot: drive-general-access-default-cui -->

**8.3 DLP rules and detectors for CUI markings**
- Set: `pip install -r scripts/requirements-workspace.txt`, then a dry run, then apply:
  ```
  scripts/workspace-dlp --customer-id C0xxxxxxx --org-unit id:<CUI OU id> --categories <from wizard>
  scripts/workspace-dlp --customer-id C0xxxxxxx --org-unit id:<CUI OU id> --categories <from wizard> --apply
  ```
  (`--credentials key.json --subject admin@...` if not using application default credentials). Re-running is safe; it matches by display name.
- Expected: 5 detectors (banner, portion, specified category, selected categories, dissemination control) and 3 rules (Drive block external, Drive warn internal, Gmail block external), all ACTIVE.
- OU: CUI OU
- Reqs: 3.1.3
- Check: Policy API read: `rule.dlp`, `detector.regular_expression`; OGRL test `workspace-dlp-rules-cui`. Then send a test message and share a test file marked `CUI//SP-CTI` to an external address to see the block (not yet exercised in a tenant).
<!-- screenshot: dlp-rules-cui -->

## 9. Gmail and DNS

*25 min. After the bootstrap workspace stage (DNS propagation is not on the clock).*

MTA-STS: testing mode first, then enforce after reports look clean. DKIM and SPF are checked through DNS.

**9.1 POP and IMAP access**
- Set: Apps > Google Workspace > Gmail > End user access > POP and IMAP access
- Expected: Off for the CUI OU unless a named client is approved (guide gives no value)
- OU: CUI OU
- Reqs: 3.1.20 ([guide p36](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=36))
- Check: Policy API read: `gmail.pop_access / gmail.imap_access`; OGRL test `workspace-pop-imap-access`
<!-- screenshot: pop-imap-access-cui -->

**9.2 Gmail tls compliance**
- Set: Apps > Google Workspace > Gmail > Compliance > Secure transport (TLS) compliance
- Expected: Require TLS (CA-signed, verified host) for CUI partner domains
- OU: CUI OU
- Reqs: 3.13.1, 3.13.8 ([guide p73](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=73))
- Check: Manual evidence: dated screenshot
<!-- screenshot: gmail-tls-compliance-cui -->

**9.3 MTA-STS**
- Set: DNS (mta-sts TXT, _smtp._tls TXT) plus hosted policy file; Gmail MTA-STS guidance
- Expected: Testing mode first, then enforce; TLS reporting on
- OU: n/a (tenant-wide)
- Reqs: 3.13.1, 3.13.8 ([guide p73](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=73))
- Check: DNS: TXT `_mta-sts.<domain>` and `_smtp._tls.<domain>`, plus `https://mta-sts.<domain>/.well-known/mta-sts.txt` fetch (mode testing, then enforce)
<!-- screenshot: mta-sts-na -->

**9.4 DKIM and SPF**
- Set: Apps > Google Workspace > Gmail > Authenticate email; DNS TXT records (DKIM selector, SPF)
- Expected: DKIM signing on, 2048 bit key; SPF record published
- OU: n/a (tenant-wide)
- Reqs: 3.13.15 ([guide p80](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=80))
- Check: DNS: TXT `<selector>._domainkey.<domain>` (2048-bit) and the SPF TXT on `<domain>`
<!-- screenshot: dkim-spf-na -->

**9.5 S/MIME** (optional)
- Set: Apps > Google Workspace > Gmail > User settings > S/MIME
- Expected: Optional
- OU: CUI OU
- Reqs: 3.13.1, 3.13.8 ([guide p74](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=74))
- Check: Policy API read: `gmail.smime_encryption`; OGRL test `workspace-smime`
<!-- screenshot: smime-cui -->

**9.6 Client side encryption** (optional)
- Set: Security > Access and data control > Client-side encryption
- Expected: Optional; required for ITAR tier per OGRL. External key service configured
- OU: CUI OU
- Reqs: 3.13.1, 3.13.8 ([guide p75](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=75))
- Check: Manual evidence: dated screenshot
<!-- screenshot: client-side-encryption-cui -->


## 10. AWS IAM Identity Center SAML app and SCIM

*30 min. After the bootstrap workspace stage and the AWS org stack.*

Workspace is the IdP for AWS (D2). Steps alternate between AWS and Google Admin.

**10.1 AWS: enable Identity Center and switch the source.** Enable Identity Center (organization instance, home region). Settings > Identity source > Change > External identity provider. Copy the ACS URL, issuer URL and the SCIM endpoint.
<!-- screenshot: aws-idc-identity-source -->

**10.2 Google: add the SAML app.** Apps > Web and mobile apps > Add app > Search for apps > "Amazon Web Services (IAM Identity Center)". Name ID format EMAIL, Name ID = Primary email. Turn the app on for the CUI and non-CUI OUs (User access).
<!-- screenshot: saml-app-aws-idc-ou -->

**10.3 AWS: upload Google's IdP metadata** in the Identity Center identity source page.

**10.4 AWS: enable automatic provisioning.** Copy the SCIM endpoint and access token (shown once; expires in 1 year).
<!-- screenshot: aws-idc-scim-enabled (do not capture the token) -->

**10.5 Google: authorize auto-provisioning.** In the app's Auto-provisioning tab paste endpoint and token, map primary email to `userName`, set the scope to the intended OUs and groups, and set deprovisioning to suspend or delete after 24 hours.
<!-- screenshot: saml-app-autoprovision -->

**10.6 After the first sync**, put the users' UserNames in `group_members` (stacks/baseline tfvars) and apply Terraform.

**10.7 Identity Center session settings.** Set the session duration by hand in Identity Center Settings; the provider cannot (1 hour for permission sets per SCOPE).

**10.8 Break-glass.** Set a console password by hand with reset required, register 2 FIDO keys and store them apart, and seal root.

**10.9 Yearly:** rotate the SCIM token before it expires; calendar reminder.

- OU: CUI and non-CUI OUs
- Reqs: 3.1.1, 3.5.2, 3.5.3 (Identity Center MFA does not apply to external IdPs, so 2SV in section 5 carries it)
- Check: Manual evidence (no API reads custom SAML apps): the screenshots above plus the Identity Center identity-source page; OGRL manual test `workspace-saml-app-aws-identity-center`. Directory API confirms the synced users exist in AWS by name only through the AWS side.


## 11. Fathom Google OAuth client

*10 min. After the AWS org stack (the grc account must exist); before the baseline apply that deploys Fathom.*

Fathom signs in through Google OIDC . Create the OAuth client by hand; Terraform only reads its ID and the SSM parameter name.

**11.1 OAuth consent screen.** Google Cloud console > APIs and services > OAuth consent screen: user type Internal, scopes `openid`, `email`, `profile`.

**11.2 OAuth client.** Credentials > Create credentials > OAuth client ID > Web application. Authorized redirect URI: `https://<fathom-domain>/v1/auth/oidc/google/callback` (the provider key is `google`; it is part of the path). Copy the client ID into tfvars as `fathom_oidc_client_id`; set `fathom_bootstrap_admin_emails`.

**11.3 Secret into the grc account.** Store the client secret as an SSM SecureString at `/fathom/oidc/client-secret` in the `grc` account (the default of `fathom_oidc_client_secret_parameter`):
```
aws ssm put-parameter --name /fathom/oidc/client-secret --type SecureString --value '<secret>' --profile grc
```
Do not write the secret to a file or tfvars.

- OU: n/a (Internal means the whole Workspace organization can sign in; Fathom authorizes by its own admin and role mapping)
- Reqs: 3.5.1, 3.5.2, 3.1.1 (Fathom is a Security Protection Asset)
- Check: manual evidence (client config screenshot with the redirect URI, secret hidden); `aws ssm describe-parameters` in grc shows type SecureString.
<!-- screenshot: fathom-oauth-client (secret hidden) -->

## 12. Devices

*10 min. After the bootstrap workspace stage.*

Managing the device itself is out of scope (see SCOPE); these are the Workspace-side controls.

**12.1 Device activation approval**
- Set: Devices > Mobile and endpoints > Settings > Universal > Security > Device approvals
- Expected: Require admin approval checked; notification email set
- OU: CUI OU
- Reqs: 3.1.18 ([guide p33](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=33))
- Check: Policy API read: `devices.activation_approval`; OGRL test `workspace-device-activation-approval`
<!-- screenshot: device-activation-approval-cui -->

**12.2 Device encryption required**
- Set: Devices > Mobile and endpoints > Settings > Universal > Security > Require device encryption
- Expected: On
- OU: CUI OU
- Reqs: 3.1.19 ([guide p35](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=35))
- Check: Policy API read: `devices.encryption`; OGRL test `workspace-device-encryption-required`
<!-- screenshot: device-encryption-required-cui -->

**12.3 Device inventory endpoint mgmt**
- Set: Devices > Overview (Mobile devices, Endpoints, Company-owned)
- Expected: Endpoint Verification / advanced management on for the CUI OU; quarterly inventory export kept as evidence
- OU: CUI OU
- Reqs: 3.1.1, 3.4.1, 3.5.1 ([guide p16](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=16))
- Check: Directory API
<!-- screenshot: device-inventory-endpoint-mgmt-cui -->

**12.4 Context aware access** (optional)
- Set: Security > Access and data control > Context-Aware Access
- Expected: Optional. Access level requiring a managed device on the SAML app and CUI services
- OU: CUI OU
- Reqs: 3.1.1, 3.5.2 ([guide p62](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=62))
- Check: Manual evidence: dated screenshot
<!-- screenshot: context-aware-access-cui -->


## 13. Alert Center, rules and monitoring

*25 min. After the bootstrap workspace stage.*

System defined alerts on, the failed-login rule (more than 5 in 24 hours, suspend the user; guide p27-28) and the other reporting rules, then the monitoring subscriptions.

**13.1 Alert center notifications**
- Set: Rules > System defined rules (notifications); Security > Alert center
- Expected: System defined alerts on with notification to the security mailbox
- OU: n/a (tenant-wide)
- Reqs: 3.6.1, 3.14.3 ([guide p70](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=70))
- Check: Policy API read: `rule.system_defined_alerts`; OGRL test `workspace-alert-center-notifications`
<!-- screenshot: alert-center-notifications-na -->

**13.2 Failed login activity rule**
- Set: Rules > Create rule > Activity (data source User log events, event Failed login)
- Expected: Failed login count > 5 per 24 hours, action Suspend user, alert High, notify super admins (guide example values, p28)
- OU: CUI and non-CUI OUs
- Reqs: 3.1.8 ([guide p27](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=27))
- Check: Manual evidence: dated screenshot
<!-- screenshot: failed-login-activity-rule-all -->

**13.3 Activity reporting rules**
- Set: Rules > Create rule > Reporting / Activity
- Expected: Rules for suspicious sign-in, admin setting change, external sharing; alert center on, notify security mailbox
- OU: n/a (tenant-wide)
- Reqs: 3.3.5, 3.3.6 ([guide p42](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=42))
- Check: Manual evidence: dated screenshot; OGRL test `workspace-activity-reporting-rules`
<!-- screenshot: activity-reporting-rules-na -->

**13.4 Workspace status dashboard**
- Set: Google Workspace Status Dashboard (status.cloud.google.com) subscription
- Expected: Subscribe security mailbox to service alerts (guide: periodically check)
- OU: n/a (tenant-wide)
- Reqs: 3.14.3 ([guide p81](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=81))
- Check: Manual evidence: dated screenshot; OGRL test `workspace-workspace-status-dashboard`
<!-- screenshot: workspace-status-dashboard-na -->

**13.5 Investigation tool review**
- Set: Security > Security center > Investigation tool
- Expected: Saved searches/reports per data source (Admin, Login, Drive, Gmail, Device); reviewed on the OGRL cadence
- OU: n/a (tenant-wide)
- Reqs: 3.3.3, 3.3.5, 3.3.6, 3.1.12, 3.14.7 ([guide p41](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=41))
- Check: Manual evidence: dated screenshot; OGRL test `workspace-investigation-tool-review`
<!-- screenshot: investigation-tool-review-na -->

**13.6 Security center dashboard**
- Set: Security > Security center > Dashboard
- Expected: Reviewed on the OGRL cadence; no setting
- OU: n/a (tenant-wide)
- Reqs: 3.14.6 ([guide p83](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=83))
- Check: Manual evidence: dated screenshot
<!-- screenshot: security-center-dashboard-na -->

**13.7 Meet hardware remote join**
- Set: Devices > Google Meet hardware; Account > Admin roles (hardware admins)
- Expected: Policy prohibits remote join; Meet hardware off unless needed; short admin roster
- OU: n/a (tenant-wide)
- Reqs: 3.13.12 ([guide p79](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=79))
- Check: Manual evidence: dated screenshot; OGRL test `workspace-meet-hardware-remote-join`
<!-- screenshot: meet-hardware-remote-join-na -->

**13.8 Audit log gcp sharing** (optional)
- Set: Account > Account settings > Legal and compliance > Sharing options (data sharing with Google Cloud)
- Expected: Optional. Off while the Reports API collector is the audit store
- OU: n/a (tenant-wide)
- Reqs: 3.3.1 ([guide p41](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=41))
- Check: Policy API read: `cloud_sharing_options.cloud_data_sharing`; OGRL test `workspace-audit-log-gcp-sharing`
<!-- screenshot: audit-log-gcp-sharing-na -->


## 14. Evidence pass

*20 min. Last.*

Take dated screenshots for every manual-evidence step above (file them in the evidence store with the step number), then run Fathom's Policy API, Reports API and Directory API reads (integration #33 supplies the runner; until then the OGRL `workspace-*` tests are `required: false` and show as not run).

**14.1 Security health baseline**
- Set: Security > Security center > Security health
- Expected: Review all findings; baseline of record is this file
- OU: n/a (tenant-wide)
- Reqs: 3.4.2 ([guide p49](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=49))
- Check: Policy API: every read row in `workspace/settings.yaml` compared to the baseline; OGRL test `workspace-security-health-baseline`
<!-- screenshot: security-health-baseline-na -->

**14.2 Apps reports gmail**
- Set: Reporting > Apps reporting > Gmail
- Expected: Review inbound/outbound volumes, spam and TLS encrypted fractions
- OU: n/a (tenant-wide)
- Reqs: 3.14.6 ([guide p84](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=84))
- Check: Reports API (customerUsageReports / activities)
<!-- screenshot: apps-reports-gmail-na -->

Settings no API can read (screenshot evidence): SAML app, custom activity rules, Investigation saved searches, Gmail TLS compliance, client-side encryption, context-aware access, Meet hardware remote join (policy only), Security Center review, Status Dashboard subscription, app access review, reseller access removal, Assured Controls Plus settings. MTA-STS, DKIM and SPF are checked through DNS.
