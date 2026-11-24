# Scope: CMMC Level 2 enclave on Google Workspace and AWS

Draft, November 23, 2026. This is the plan, not the build. Every claim about a vendor feature or authorization below links to the vendor's own page. Where vendor sources disagree with each other or with current DoD guidance, it says so in [Where the sources disagree](#where-the-sources-disagree).

## 1. Goal

Ship a baseline that a small defense contractor can deploy into their own AWS organization and Google Workspace tenant and end up with:

1. A CUI enclave whose technical controls are set to the vendors' published CMMC Level 2 guidance.
2. Fathom running in AWS, loaded with OGRL objects that describe that enclave: the system and boundary, components, one implementation per control and component with its responsibility (provider, shared, subservice), tests that check the settings, and the gaps left for the company.
3. A clear list of what the company still owns: policies, people, physical sites, endpoints.

It is a baseline others build on. Each company's contracts, CUI categories, and existing tools will add to it.

### Deploy-time objective (D3, [#3](https://github.com/adversitydotdev/cmmc-enclave/issues/3))

**Under an hour, a couple of hours at most,** from no enclave to a baselined one. This is an objective and a proof of concept, not a hard requirement. The clock is wizard fill time plus Terraform provisioning.

Not on the clock: buying Workspace licenses and add-ons, Google provisioning Assured Controls, GovCloud account signup, DNS propagation. Manual runbook steps are timed and reported separately (#39 records time per stage).

"Working" means everything in our baseline is applied and functioning. It does not mean the company is done; their policies, people, endpoints, and any runbook steps they haven't finished remain. The end to end test (M7) checks:

- [ ] Users sign in to Workspace and, through Identity Center, to AWS with security keys
- [ ] CUI OU locked down: only FedRAMP High services on, sharing restricted
- [ ] Workspace hardening from the baseline applied and passing its Policy API checks
- [ ] AWS hardening applied: SCPs, CloudTrail, Config with the CMMC conformance pack, GuardDuty, Security Hub, FIPS endpoints, KMS keys, network boundary
- [ ] AWS and Workspace logs flowing to the log archive
- [ ] Fathom up behind SSO with the enclave bundle loaded and the SSP rendered as far as the baseline covers
- [ ] Fathom's automated tests for baseline controls passing

## 2. Where CMMC stands (verified November 23, 2026)

- **Level 2 is NIST SP 800-171 Rev 2, 110 requirements.** 32 CFR 170.14(c)(3): "The security requirements in CMMC Level 2 are identical to the requirements in NIST SP 800-171 R2." The assessment objectives come from NIST SP 800-171A (320 objectives). Source: [eCFR 32 CFR Part 170](https://www.ecfr.gov/current/title-32/subtitle-A/chapter-I/subchapter-G/part-170).
- **Phase 2 is suspended.** On July 13, 2026 the Department of War suspended the Phase 2 move to third party (C3PAO) Level 2 assessments that was due November 10, 2026. Phase 1 self assessments stay in place, and DFARS 252.204-7012 still applies. Source: [DoW CIO, About CMMC](https://dowcio.war.gov/CMMC/About/) and the CIO implementing memo [26-P-1023](https://dowcio.war.gov/Portals/0/Documents/Library/ImplementingSuspensionCMMC-PhaseII.pdf).
- **Rev 3 is not the DoD standard.** DoD still enforces Rev 2 through DFARS 7012 and SPRS scoring. ogrl-library already carries Rev 3 (`framework--nist-sp-800-171-r3`) and the Rev 3 to 800-53 mappings, so we map to Rev 2 now. A Rev 3 view is possible but not free (see below).
- **Status of the rest, checked November 23, 2026.** The reform task force report (due to the CIO around September 11) has not been published that we could find: nothing at the [Federal Register](https://www.federalregister.gov/documents/search?conditions%5Bterm%5D=CMMC), and the eCFR shows Part 170 last amended 2024-12-16 ([eCFR versioner](https://www.ecfr.gov/api/versioner/v1/versions/title-32.json?part=170)). The DFARS 7012 clause on [acquisition.gov](https://www.acquisition.gov/dfars/252.204-7012-safeguarding-covered-defense-information-and-cyber-incident-reporting.) is dated May 2024 and says only that NIST SP 800-171 "in effect at the time the solicitation is issued" applies. We could not confirm from a primary source that DoD pins Rev 2 by class deviation (2024-O0013), nor the class deviation that implements the suspension (2026-O0025 Rev 3, said to be dated September 3; see the [DARS page](https://www.acq.osd.mil/dpap/dars/dfars_far_overhaul_class_deviations.html), which failed TLS for us). We found no DFARS case moving 7012 to Rev 3. The FAR CUI re-proposal of June 23, 2026 ([2026-12559](https://www.federalregister.gov/documents/2026/06/23/2026-12559/federal-acquisition-regulation-revolutionary-federal-acquisition-regulation-overhaul-parts-1-2-4-33)) is where Rev 3 appears; its Rev 3 content was read only through a [law firm summary](https://www.mayerbrown.com/en/insights/publications/2026/07/far-council-proposes-revised-cui-safeguarding-and-incident-reporting-framework-while-dow-pauses-cmmc-implementation).
- **If CMMC moves to Rev 3** it needs a change to 32 CFR 170.14, which today names R2 (a rulemaking, not a memo). Effect on our mapping: ogrl-library has no Rev 2 to Rev 3 crosswalk (no mapping object has an R2 requirement as its source; checked [ogrl-library](https://github.com/adversitydotdev/ogrl-library) `main`, November 23, 2026). Its OGRL controls map to R2 (134 mappings covering all 110 requirements) and to R3 only thinly (9 mappings covering 8 requirements; `baseline--ogrl-nist-800-171-r3` lists 6 requirements), and R3 requirements map to 800-53. So a Rev 3 view is not free: we would add `ogrl-*` to R3 mappings, build a Rev 3 baseline, and re-map every enclave `implementation`. Rev 3 restructures the requirement set (NIST publishes the differences in its [Rev 2 to Rev 3 change analysis](https://csrc.nist.gov/pubs/sp/800/171/r3/final); we have not read it, and it could seed the crosswalk). The responsibility matrix in section 7 is Rev 2 shaped and would need redoing. The AWS and Google guides are Rev 2 too.
- **POA&Ms at Level 2 (Self)** are allowed under 32 CFR 170.21(a)(2) and must close within 180 days. Fathom's POA&M view should follow those rules.

What this means for the project: the enclave is still worth building (7012 and self assessments are live, and the requirement set is stable), but the README and wizard must not promise "certification ready" language tied to C3PAO dates.

## 3. Primary vendor sources

These are the documents the mapping and the shared responsibility matrix are built from.

### AWS

| Source | What it gives us | Notes |
|---|---|---|
| [AWS CMMC compliance page](https://aws.amazon.com/compliance/cmmc/) | Says the AWS CMMC Customer Package (in [AWS Artifact](https://aws.amazon.com/artifact/), both standard and GovCloud) breaks down the Level 2 controls customers inherit "by using the AWS Landing Zone Accelerator in the AWS GovCloud (US)". | Page is stale. See section 9. |
| AWS CMMC Customer Package / CRM (AWS Artifact, needs an AWS login) | The authoritative per requirement inheritance table. | Can't be fetched anonymously. Likely under NDA or Artifact terms: not obtained or used until AWS confirms what's permitted ([#5](https://github.com/adversitydotdev/cmmc-enclave/issues/5)). This repo builds from public sources only. |
| AWS Prescriptive Guidance, "Preparation guide for CMMC Level 2 on AWS" (`docs.aws.amazon.com/prescriptive-guidance/latest/cmmc-level-2-compliance-on-aws/`) | Summarizes the CRM: 21 inheritable, 79 partial, 10 customer only. Says both GovCloud and US East/West meet the 7012 FedRAMP Moderate requirement, and ITAR or EAR workloads go to GovCloud. | Every URL under that path returned 404 or 403 when checked on November 23, 2026. Figures here come from the indexed copy. Re-verify before citing in shipped docs. |
| [AWS DFARS page](https://aws.amazon.com/compliance/dfars/) | Standard regions are FedRAMP Moderate, GovCloud is FedRAMP High, and both satisfy 7012's CSP requirement. | |
| [AWS Config: Operational Best Practices for CMMC 2.0 Level 2](https://docs.aws.amazon.com/config/latest/developerguide/operational-best-practices-for-cmmc_2.0_level_2.html) and [for NIST 800-171](https://docs.aws.amazon.com/config/latest/developerguide/operational-best-practices-for-nist_800-171.html) | Managed Config rules mapped to each practice. This is our starting set of automated tests. | |
| [GovCloud vs standard regions](https://docs.aws.amazon.com/govcloud-us/latest/UserGuide/govcloud-differences.html), [GovCloud compliance](https://docs.aws.amazon.com/govcloud-us/latest/UserGuide/govcloud-compliance.html) | GovCloud is run by US citizens, supports ITAR, and uses FIPS 140-3 modules on all service endpoints unless noted. | |
| [AWS FIPS endpoints](https://aws.amazon.com/compliance/fips/) | In standard regions FIPS endpoints are opt in, so 3.13.11 needs us to turn them on. | |
| [Landing Zone Accelerator on AWS](https://awslabs.github.io/landing-zone-accelerator-on-aws/latest/) | AWS's own multi account baseline with CMMC aligned sample configs. | It's CDK, not Terraform. Not used; we borrow controls from it (D5, [#4](https://github.com/adversitydotdev/cmmc-enclave/issues/4)). |
| [IAM Identity Center with Google Workspace](https://docs.aws.amazon.com/singlesignon/latest/userguide/gs-gwp.html), [Identity Center in GovCloud](https://docs.aws.amazon.com/govcloud-us/latest/UserGuide/govcloud-sso.html) | SAML plus SCIM from Google Workspace into AWS. | SCIM from Google syncs **users only**: "Automatic group provisioning is not supported at this time." |

### Google Workspace

| Source | What it gives us | Notes |
|---|---|---|
| [Google Workspace CMMC Level 2 Configuration Guide](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf) (February 2025, 176 pages) | Per requirement guidance for all 110. Puts each in one of three buckets: 47 the customer configures in Workspace, 42 Workspace implements natively, 21 live outside Workspace. | Scoped to **Enterprise Plus with Assured Controls Plus**. Linked copy is the one from Google's CMMC page (labeled FINAL, no "Google Confidential" footer; same content as the `helpcenter` copy). We link to it and don't copy it into the repo. |
| Google Workspace CMMC CRM | The full inheritance matrix. | Only available by asking a Google rep. Same rule as the AWS package: not used until Google confirms what's permitted ([#5](https://github.com/adversitydotdev/cmmc-enclave/issues/5)). |
| [Google CMMC compliance page](https://cloud.google.com/security/compliance/cmmc) | Workspace holds FedRAMP High. "For Google Workspace, you must use FedRAMP High authorized services for CMMC compliance, as well as Assured Controls Plus to enable data storage exclusively within the United States." Links to a C3PAO attestation letter for Workspace. | |
| [Google DFARS compliance page](https://cloud.google.com/security/compliance/dfars) | Google accepts the 7012 flowdown for FedRAMP Moderate and High services, and says data location and Assured Controls "are not explicitly required" for 7012. | Disagrees with the CMMC page. See section 9. |
| [Workspace FedRAMP configuration guide](https://knowledge.workspace.google.com/admin/compliance/google-workspace-fedramp-configuration-guide) | FedRAMP High covers Enterprise Plus and Standard, Business Plus and Standard, Frontline Plus, and Workspace for Government. Lists the covered services (Gmail, Drive, Docs, Sheets, Slides, Forms, Calendar, Chat, Meet, Keep, Sites, Vault, some Gemini). | |
| [Assured Controls and Assured Controls Plus](https://knowledge.workspace.google.com/admin/security/about-assured-controls-and-assured-controls-plus) | Paid add-ons on Enterprise Plus or Frontline Plus. Plus adds Access Management, which can limit Google support access to US based personnel. | |
| [Google ITAR page](https://cloud.google.com/security/compliance/itar) | Workspace supports ITAR data through client-side encryption, which can meet the ITAR end-to-end encryption carve-out at 22 CFR 120.54(a)(5). | |
| [Google FIPS 140 page](https://cloud.google.com/security/compliance/fips-140-validated) | BoringCrypto is FIPS 140-3 validated and used for encryption in transit and at rest. | Page covers Google Cloud and doesn't mention Workspace. For Workspace we rely on the CMMC guide marking 3.13.11 Google implemented. |
| [Cloud Identity Policy API, supported settings](https://cloud.google.com/identity/docs/concepts/supported-policy-api-settings) | Read access to most Admin console settings, and writes for a growing subset (DLP rules and detectors, Drive general access default, multi-party approval, passkeys restriction, some Meet settings). | `scripts/workspace-dlp` and `scripts/workspace-policy` set the writable ones; the rest are runbook steps (`docs/runbook/workspace.md`). |

## 4. Impact tiers

| | Standard (default) | ITAR |
|---|---|---|
| Data | CUI, no export controlled technical data | CUI including ITAR or EAR technical data |
| AWS | Commercial `us-east-1`/`us-east-2`/`us-west-2`, FedRAMP Moderate, FIPS endpoints forced on | AWS GovCloud (US), FedRAMP High, US citizen operated, FIPS by default |
| Google Workspace | Enterprise Plus with Assured Controls Plus (D1). Assured Controls without Plus as a documented fallback. Only FedRAMP High services on for CUI users. | Enterprise Plus plus Assured Controls Plus (US person support access), plus client-side encryption with a customer held key service |
| Fathom | Dedicated `grc` account, commercial | Dedicated `grc` account, commercial (an SPA, holds no ITAR data). Reads GovCloud accounts via IAM Roles Anywhere. ITAR kept out of uploads by policy |
| Rough sign | Cheapest path that still meets 7012 | More expensive, and GovCloud needs its own account signup tied to a commercial account |

Facts behind the table:

- **Commercial AWS US East/West is fine for CUI** under 7012. AWS: "AWS services in the AWS standard cloud region services are authorized at the FedRAMP Moderate baseline and AWS GovCloud (US) region services are authorized at the FedRAMP High baseline." ([AWS DFARS](https://aws.amazon.com/compliance/dfars/))
- **Commercial Workspace is FedRAMP High** for Enterprise, Business Standard and Plus, and Frontline Plus editions ([FedRAMP configuration guide](https://knowledge.workspace.google.com/admin/compliance/google-workspace-fedramp-configuration-guide)). So the "expensive gov version" isn't needed for CUI. We still default to Enterprise Plus with Assured Controls Plus (D1): the guide's configure steps rely on Enterprise Plus features, and Google's 72 hour incident notice under 7012 (c) applies only to customers with Assured Controls ([Google DFARS](https://cloud.google.com/security/compliance/dfars)).
- **ITAR on AWS means GovCloud.** AWS has written about a customer running ITAR data in commercial regions on encryption alone after legal review ([AWS blog](https://aws.amazon.com/blogs/publicsector/evaluating-itar-workloads/)), but that's legal judgment, not a baseline. We won't offer it.
- **ITAR on Workspace means client-side encryption.** Google's ITAR support for Workspace is the CSE carve-out, not data location alone. CSE needs Enterprise Plus (or Frontline Plus) and an external key service, either a Google partner or one we build with the CSE API.

## 5. Architecture

### AWS

- **Organization and accounts:** management, log archive, security tooling, one enclave workload account, and a `grc` account in its own OU for Fathom (D7). Plain Terraform on AWS Organizations, no Control Tower or LZA (D5).
- **Guardrails:** SCPs that deny regions outside the tier's allowed list, deny disabling CloudTrail, Config, GuardDuty, and deny non-FIPS endpoints where condition keys allow it.
- **Logging:** organization CloudTrail to an immutable (Object Lock) bucket in log archive, Config in every account with the CMMC 2.0 Level 2 conformance pack, GuardDuty, Security Hub, VPC flow logs. Workspace audit logs also land here (see below).
- **Encryption:** customer managed KMS keys per data class. FIPS endpoints set at the provider level (`use_fips_endpoint`). TLS 1.2+ policies on every listener.
- **Network:** no inbound internet except the Fathom load balancer. VPC endpoints for AWS APIs. No NAT unless a feature needs it.
- **Identity (D2):** IAM Identity Center with Google Workspace as the SAML IdP in both tiers ([AWS docs](https://docs.aws.amazon.com/singlesignon/latest/userguide/gs-gwp.html)). Google auto-provisioning syncs users only; groups and memberships are Terraform (`aws_identitystore_group*`) changed by reviewed PR. MFA (3.5.3) is enforced in Workspace (2SV, security keys only for AWS users), since Identity Center MFA doesn't apply to external IdPs. Permission sets for admin, auditor (read only), and Fathom operator, 1 hour sessions. Break-glass: IAM user in management with two FIDO keys, no access keys, alert on use; root sealed. The ITAR tier gets its own Identity Center in GovCloud and a second Workspace SAML app; the Workspace directory is an SPA and holds no ITAR data.

### Google Workspace

- **Org units** for CUI users and non-CUI users. Only FedRAMP High services on in the CUI OU. Everything else off.
- **Authentication:** 2-Step Verification enforced, security keys only for admins, session length limits, login challenges.
- **Sharing:** external sharing off or allowlisted for CUI OU, DLP rules for CUI markings, trust rules for Drive.
- **Retention and eDiscovery:** Vault retention rules.
- **Data regions / Assured Controls** per tier and D1.
- **Audit:** Reports API pulled on a schedule into the AWS log archive so one place holds the audit trail for 3.3.x.
- **Endpoints:** context-aware access can require a managed device, but managing the device is out of scope.

The ordered manual steps, with expected values and checks, are in [docs/runbook/workspace.md](runbook/workspace.md).

### How much of Workspace can Terraform do

Less than we'd like. HashiCorp archived its `googleworkspace` provider on June 30, 2025 ([repo](https://github.com/hashicorp/terraform-provider-googleworkspace)). Two community forks are maintained; we use `macadmins/googleworkspace` (D5), pinned to an exact version. Both cover users, groups, OUs, roles, role assignments, schemas, and Chrome policy, not security settings. Neither can create a SAML app or turn services on or off per OU. The Cloud Identity Policy API reads most Admin console settings, including per-OU service status, and writes a growing subset: DLP rules and detectors, Drive general access default, Meet settings, multi-party approval, passkeys restriction ([supported settings](https://cloud.google.com/identity/docs/concepts/supported-policy-api-settings)). Most `security.*` settings stay read-only. The per-setting breakdown is in `workspace/settings.yaml` (#27): 56 settings, 10 Terraform, 4 Policy API write, 42 manual. So the plan is:

1. Terraform (fork provider) for OUs, groups, and admin roles.
2. Policy API writes where supported (DLP, Drive general access, multi-party approval, passkeys).
3. A short, ordered manual runbook for everything else (including the AWS SAML app and per-OU service access), with each step paired to a Policy API read so Fathom can test that it stuck.

That last part matters: even when we can't set it, we can check it, and the check is what the assessor cares about.

### Fathom in the enclave

Fathom already ships a CloudFormation template (`fathom/deploy/aws/template.yaml`: one Fargate task, single AZ Postgres, private S3, SSM). For the enclave it needs to:

- Run in Terraform (wrap the stack or port it) in the `grc` account. It's a Security Protection Asset, so it's in assessment scope and we build it to address all 110 requirements (D6).
- Sit behind Identity Center or Workspace SSO, with FIPS endpoints, KMS keys from the enclave, and logs into the log archive. No public task IPs, a CMK on the bucket, partition-aware ARNs, and the AI assistant off by default.
- Boot with the pinned ogrl-library release, the `baseline--ogrl-cmmc-l2` baseline, and an enclave bundle: one `system`, `component`s for AWS, Workspace, Fathom, and endpoints, `party` objects for AWS and Google with their FedRAMP authorizations, and an `implementation` per control.
- Run tests: the AWS read-only integration (`fathom-aws`) plus a new Workspace integration that reads the Policy and Reports APIs.

The idle cost of Fathom's production shape is about $26 a month in us-east-1 per the [fathom README](https://github.com/adversitydotdev/fathom#estimated-monthly-cost). The enclave version adds a load balancer, KMS keys, and logging.

### Wizard

A static web app that runs locally (`npx` or a single HTML file), asks questions, and writes:

- `terraform.tfvars` for the AWS and Workspace stacks,
- OGRL parameter values for the system bundle (company name, CUI types, user counts, sites, review frequencies),
- a checklist of the manual Workspace steps and vendor purchases for their tier.

Nothing goes over the network. Questions cover: company and domain, existing Workspace tenant or new, user count, ITAR yes or no, CUI categories, offices and remote work, existing MDM and EDR, who signs the SSP.

## 6. Control family overview

Counts are requirements per family in NIST SP 800-171 Rev 2. "GW guide" counts are the Google Workspace CMMC guide's buckets (configure in Workspace / native / outside Workspace). "AWS CRM" is from the AWS prescriptive guidance summary of the CMMC Customer Package (inheritable / partial / customer only).

| Family | Reqs | AWS features | Google Workspace features | GW guide | AWS CRM notes |
|---|---|---|---|---|---|
| AC Access Control | 22 | Identity Center permission sets, SCPs, IAM Access Analyzer, session policies, VPC endpoints | OUs, admin roles, service on/off per OU, sharing controls, context-aware access, session length | 15 / 4 / 3 | 3.1.16, 3.1.17 inheritable. 3.1.8, 3.1.18, 3.1.19, 3.1.21 customer only |
| AT Awareness and Training | 3 | none | none | 0 / 0 / 3 | Policy and people. Fathom tracks evidence. |
| AU Audit and Accountability | 9 | CloudTrail org trail, Object Lock, Config, CloudWatch, Security Hub | Admin and Reports audit logs, alert center, Vault | 6 / 3 / 0 | Partial |
| CM Configuration Management | 9 | Config + conformance pack, SCPs, SSM, Terraform itself as baseline config | Service on/off, app access control, Marketplace allowlist | 8 / 0 / 1 | Partial |
| IA Identification and Authentication | 11 | Identity Center, MFA, IAM password policy for break-glass | 2SV, security keys, password policy, SAML IdP | 7 / 3 / 1 | 3.5.7, 3.5.8, 3.5.9 customer only |
| IR Incident Response | 3 | GuardDuty, Security Hub, EventBridge to notifications | Alert center, investigation tool | 1 / 0 / 2 | Policy, plus 7012's 72 hour DIBNet reporting |
| MA Maintenance | 6 | AWS managed | Google managed | 0 / 6 / 0 | 5 inheritable (not 3.7.5) |
| MP Media Protection | 9 | S3/EBS encryption, KMS | Google managed media | 0 / 6 / 3 | 8 inheritable (3.8.1 to 3.8.8). See section 9. |
| PS Personnel Security | 2 | none | Account suspend on termination (3.9.2) | 1 / 0 / 1 | Mostly people process |
| PE Physical Protection | 6 | AWS data centers | Google data centers | 0 / 5 / 1 | All 6 inheritable. See section 9. |
| RA Risk Assessment | 3 | Inspector, Security Hub | Google scanning | 0 / 2 / 1 | Risk assessment itself is customer |
| CA Security Assessment | 4 | Config, Audit Manager | none | 0 / 0 / 4 | SSP (3.12.4) and POA&M (3.12.2) come out of Fathom |
| SC System and Communications Protection | 16 | VPC design, security groups, KMS, FIPS endpoints, TLS policies, WAF | Google managed TLS and FIPS crypto, Meet encryption, CSE | 6 / 9 / 1 | 3.13.7, 3.13.12, 3.13.14 customer only |
| SI System and Information Integrity | 7 | GuardDuty, Inspector, Security Hub | Gmail malware and phishing protection, security center | 3 / 4 / 0 | Partial |

Totals: GW guide 47 / 42 / 21 = 110. AWS CRM 21 / 79 / 10 = 110.

## 7. Shared responsibility matrix

Every one of the 110 requirements gets one row in OGRL terms: an `implementation` per component (AWS, Google Workspace, Fathom, Endpoints, Organization) with `responsibility` set to `subservice` (AWS or Google carries it, with `subservice_ref` to the party and its FedRAMP authorization), `shared` (we configure our part, the vendor carries the rest), or `provider` (the company does it: policies, people, sites, endpoints), plus a narrative and a test where one exists. OGRL writes `responsibility` from the bundle author's side, and the author is the company, so what CMMC matrices call "customer" is `provider` here; `customer` would mean the company's own downstream customers and evaluates as out of scope ([RFC 0001](https://ogrl.adversity.dev/rfcs/0001-object-model/)). The bundle lives in `ogrl/org/`: 232 implementations across 80 controls, with sources in each row's `external_references`. The rule when sources disagree is: take the more conservative answer, record both sources, and say why.

Buckets we expect to land in the "still on you" column regardless of tier:

- **Policies and procedures** behind every family (each requirement's "examine" objectives).
- **People:** training (AT), screening and termination (PS), incident handling roles (IR).
- **Physical:** offices and alternate work sites (3.10.6), paper CUI, visitors.
- **Endpoints:** device management, encryption on laptops and phones, removable media, split tunneling, collaboration device controls. Out of scope for this repo, but the enclave assumes a managed endpoint and Fathom models it as an `Endpoints` component with every relevant control marked customer and `planned` until they bring their own.

## 8. SSP and POA&M story

- The SSP is rendered from the OGRL graph (system, program, components, implementations), per RFC 0001 section 7.11. ogrl-rs already renders to OSCAL 1.2.3.
- Gaps become POA&M items in Fathom, scored with the DoD Assessment Methodology weights (SPRS score) and the 32 CFR 170.21 rules on what can go on a POA&M and the 180 day closeout.
- Annual affirmation reminders and three year reassessment dates live in Fathom.

## 9. Where the sources disagree

1. **Is Assured Controls Plus required?** Google's CMMC page and the Workspace CMMC guide assume Enterprise Plus with Assured Controls Plus. Google's DFARS page says data location and Assured Controls are not explicitly required for 7012, and the FedRAMP guide covers cheaper editions. Resolved in D1: the same DFARS page limits Google's 72 hour notice to customers with Assured Controls, so we default to Enterprise Plus with Assured Controls Plus.
2. **Media and physical inheritance.** AWS lists 3.8.1 to 3.8.8 and all of 3.10.1 to 3.10.6 as fully inheritable. Google puts 3.8.1, 3.8.2, 3.8.4, and 3.10.6 outside Workspace. Paper CUI, USB drives, laptops, and home offices exist in every real enclave, so we treat those as customer with the cloud piece inherited.
3. **Split tunneling (3.13.7) and voice/video (3.13.14).** AWS calls both customer only. Google calls both native. Meet's encryption covers 3.13.14 for Meet, but split tunneling is an endpoint and VPN control. We mark 3.13.7 customer (endpoint) and 3.13.14 subservice for Meet only.
4. **FIPS (3.13.11).** Google marks it native. AWS commercial regions only use FIPS modules if you call the FIPS endpoints, so it's shared on AWS and the Terraform has to force it. GovCloud uses FIPS endpoints by default.
5. **AWS's own pages disagree.** The AWS CMMC page still describes CMMC 2.0 as pending rulemaking "9-24 months from November 2021" and ties the Customer Package to Landing Zone Accelerator in GovCloud. The prescriptive guidance treats commercial US East/West as fine for Level 2. The prescriptive guidance URLs are currently returning 404 or 403.
6. **Both vendor guides predate the Phase 2 suspension** and talk about C3PAO certification as the next step. Ours shouldn't.
7. **Google's guide disagrees with itself on audit (3.3.1, 3.3.4).** The core Workspace section calls 3.3.1 shared ([p.40](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=40)) and 3.3.4 Google ([p.89](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=89)); the Chrome section calls both customer ([p.143](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=143), [p.145](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=145)). We mark both shared and alarm our own Workspace log collector.
8. **Password reuse and lockout (3.5.8, 3.1.8).** The Config pack's `iam-password-policy` enforces 24 generations of reuse prevention ([pack](https://docs.aws.amazon.com/config/latest/developerguide/operational-best-practices-for-cmmc_2.0_level_2.html)), but Workspace "cannot set the password history" ([Google](https://knowledge.workspace.google.com/admin/users/enforce-and-monitor-password-requirements-for-users)), and IAM has no lockout policy ([AWS](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_passwords_account-policy.html)). **Decision (2026-11-24, #42): documented exception**, not a POA&M item. Security-key-only sign-in makes the password secondary; break-glass failed-login alarms compensate on AWS; the Workspace activity rule covers lockout.
9. **Key management with CSE (3.13.10).** Google's guide calls it native, but with client-side encryption the keys move into the customer's boundary ([p.107](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=107)). Subservice for the standard tier; the ITAR tier's key service is ours.
10. **Collaboration devices (3.13.12).** Shared: admins can remotely join Meet hardware and no setting prevents it, so a policy prohibits it ([p.79](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=79)).
11. **Malicious code (3.14.2, 3.14.4, 3.14.5).** The Config pack maps GuardDuty to these ([pack](https://docs.aws.amazon.com/config/latest/developerguide/operational-best-practices-for-cmmc_2.0_level_2.html)), but GuardDuty foundational is threat detection, not file scanning ([AWS](https://docs.aws.amazon.com/guardduty/latest/ug/what-is-guardduty.html)); Google calls them native ([p.112](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=112)). AWS shared, file scanning on Endpoints.
12. **Vulnerability scanning (3.11.2, 3.11.3).** Google says Google, nothing to configure ([p.103](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=103)). The pack has customer checks for 3.11.2 only. Google is subservice for its systems; we scan our AWS workloads (Inspector, ECR scan on push) and endpoints.
13. **Process families (AT, PS 3.9.1, RA 3.11.1, CA).** Google's summary puts them outside Workspace, but each control page ticks "Shared" with no features ([pp.117 to 127](https://services.google.com/fh/files/misc/google_workspace_cmmc_implementation_guide_2025.pdf#page=117)). We treat them as the company's alone.
14. **Deprovisioning (3.9.2).** Google's SCIM sync offers suspend and delete delays of 24 hours up to 30 days ([AWS](https://docs.aws.amazon.com/singlesignon/latest/userguide/gs-gwp.html)). We set 24 hours; a disabled user can keep an Identity Center session for up to 1 more hour.
15. **FIPS applies only where cryptography protects CUI (3.13.11).** We scope it the same way as the rest of 800-171: a component needs FIPS-validated crypto only if it stores, processes, or transmits CUI. Identity and control-plane services (IAM, IAM Identity Center, identitystore, Organizations, the AWS Backup API) carry no CUI, so the requirement doesn't apply to them; backup data itself is encrypted with our KMS keys (FIPS 140 validated HSMs). We still set `use_fips_endpoint` everywhere as defense in depth, and pin standard endpoints only where no FIPS endpoint exists (botocore `endpoints.json` 1.44.10): Backup everywhere, sso-admin and identitystore in commercial. In the no-egress workload VPC only STS, KMS, S3 and DynamoDB have FIPS PrivateLink services (S3's is the `s3-fips` *interface* endpoint; whether the S3 gateway endpoint carries `s3-fips` traffic is undocumented and must be tested, #46) ([PrivateLink services](https://docs.aws.amazon.com/vpc/latest/privatelink/aws-services-privatelink-support.html)). Of the rest, ECR and Secrets Manager carry no CUI; **CloudWatch Logs and SSM Session Manager can**, if applications log CUI or admins open sessions on CUI hosts. Those two are the real 3.13.11 gap on AWS commercial: keep CUI out of logs and sessions (policy, plus log-content review), or document it. No IAM or SCP condition key reveals which endpoint a request used, so FIPS is enforced client-side, not by SCP.
16. **Single-region keys and backups.** KMS keys, EBS default encryption, and AWS Backup are configured in the home region only. Using another allowed region for CUI needs keys and backup plans there too.

## 10. Out of scope

- Endpoints: MDM, EDR, disk encryption on devices, removable media control, mobile. Listed as a dependency.
- Writing company policies for them. We ship templates as OGRL documents.
- On-prem networks, OT, and labs.
- CMMC Level 3 (800-172).
- Google Cloud (GCP). Only Workspace.
- Any claim that deploying this makes you compliant.

## 11. Phases

| Milestone | Outcome |
|---|---|
| M0 Decisions and research | Decisions D1 to D8 made, vendor CRMs pulled, regulatory status tracked |
| M1 Control mapping and OGRL content | 110 row SRM, enclave OGRL bundle, policy templates, SSP and POA&M rendering |
| M2 AWS baseline (Terraform) | Org, guardrails, logging, crypto, network, identity modules for the standard tier |
| M3 Google Workspace baseline | Terraform for what's possible, Policy API checks, manual runbook, log pipeline |
| M4 Fathom in the enclave | Hardened Fathom module, preloaded bundle, Workspace integration |
| M5 Wizard and one-click deploy | Local wizard, bootstrap, under an hour deploy |
| M6 ITAR tier | GovCloud variant, Workspace CSE with a key service |
| M7 Validation and release | CI, end to end test deploy, assessment evidence package (not a certification), v0.1.0 |

## 12. Decisions

- **D1** ([#1](https://github.com/adversitydotdev/cmmc-enclave/issues/1)) Decided: Enterprise Plus with Assured Controls Plus by default, Assured Controls as fallback. Business and Enterprise Standard unsupported in v0.1.
- **D2** ([#2](https://github.com/adversitydotdev/cmmc-enclave/issues/2)) Decided: Google Workspace is the IdP in both tiers. Groups managed in Terraform.
- **D3** ([#3](https://github.com/adversitydotdev/cmmc-enclave/issues/3)) Decided: under an hour objective (not hard), wizard plus Terraform on the clock, "working" checklist in section 1.
- **D4** Repo name (`cmmc-enclave` proposed) and whether it sits under the Fathom name.
- **D5** ([#4](https://github.com/adversitydotdev/cmmc-enclave/issues/4)) Decided: HashiCorp Terraform, `macadmins/googleworkspace`, plain Terraform on AWS Organizations (no LZA, no AFT).
- **D6** ([#7](https://github.com/adversitydotdev/cmmc-enclave/issues/7)) Decided: Fathom is a Security Protection Asset, in scope, hardened to all 110.
- **D7** ([#7](https://github.com/adversitydotdev/cmmc-enclave/issues/7)) Decided: dedicated `grc` account in its own OU, commercial partition in both tiers.
- **D8** Whether we offer the ITAR tier in v0.1 or after.

## 13. Cost

Monthly USD, list prices, no discounts, no tax, no labor. Modeled November 23, 2026. AWS rates are from the public Price List offer files (CLI creds were expired); the usage volumes are our assumptions, not measurements, and should be replaced once a pilot runs.

| Monthly | 10 users | 25 users | 100 users |
|---|---|---|---|
| **Standard tier** | | | |
| AWS fixed (10 workload interface endpoint-AZs, 8 CMKs) | 81 | 81 | 81 |
| AWS usage (Config, GuardDuty, Security Hub, log storage, flow logs, KMS requests, Lambda) | 83 | 116 | 246 |
| Fathom (template idle + ALB + grc endpoints + NAT + logs) | 136 | 136 | 156 |
| **AWS total** | **300** | **333** | **483** |
| Workspace Enterprise Plus + Assured Controls Plus (reseller list, $65/user, not a Google quote) | 650 | 1,625 | 6,500 |
| **Standard total** | **~950** | **~1,960** | **~6,980** |
| Fallback: Enterprise Plus + Assured Controls (reseller list, $55/user), total | ~850 | ~1,710 | ~5,980 |
| **ITAR tier** | | | |
| AWS fixed (GovCloud endpoints $0.0125/hr) | 99 | 99 | 99 |
| AWS usage in GovCloud (GovCloud rates) | 101 | 142 | 304 |
| Commercial remnant (mgmt, log archive, grc; 40% of standard usage lines + 3 CMKs) | 36 | 50 | 101 |
| Fathom (commercial, same as standard) | 136 | 136 | 156 |
| **AWS total** | **372** | **426** | **661** |
| Workspace EP + ACP (same list) | 650 | 1,625 | 6,500 |
| **ITAR total before CSE** | **~1,020** | **~2,050** | **~7,160** |
| CSE key service, Flowcrypt published list (EUR) | 67 | 117 | 217 |
| CSE key service, Thales, Virtru, Fortanix and others | quote | quote | quote |
| CSE key service, self-built (our estimate, unsourced) | 100 to 300 infra plus engineering | same | same |

Where the money goes: Workspace is about 68% of the Standard total at 10 users and 93% at 100. AWS is mostly fixed: roughly $220 a month before the first user (endpoints, keys, Fathom with NAT, Config baseline). Per-user AWS cost is about $1.50 to $2 a month, almost all log and Config volume.

### Workspace

Enterprise Plus, Assured Controls, and Assured Controls Plus are quote based. Only reseller list prices are public, from Hiview Solutions (checked November 1, 2026): Enterprise Plus $35 annual ($42 flexible), Assured Controls add-on $20 annual, Assured Controls Plus add-on $30 annual ($36 flexible), Business Plus $22 annual ($26.40 flexible). Treat the table as a ceiling for planning; the reseller notes real prices may be lower. Carahsoft lists a GSA OneGov Enterprise Plus plus ACP promotion at $257.40 per user per year through December 31, 2026, federal buyers only, not used here.

### Usage assumptions (10 / 25 / 100 users)

- Management events across all accounts: 0.5M / 0.8M / 2M a month. One org trail, so the first copy is free. No data events, no CloudTrail Lake.
- Config items recorded: 4k / 6k / 12k. Conformance pack evaluations: 40k / 50k / 80k. The CMMC 2.0 Level 2 pack has 130 rules ([pack](https://github.com/awslabs/aws-config-rules/blob/master/aws-config-conformance-packs/Operational-Best-Practices-for-CMMC-2.0-Level-2.yaml)). Evaluations are the least certain line and the largest usage cost.
- GuardDuty: management events as above at $4 per million, plus 5 / 10 / 40 GB a month of flow and DNS data at $1 per GB (first 500 GB tier). Foundational only: no S3, EKS, runtime, or malware protection. 30 day free trial ignored.
- Security Hub CSPM: 15k / 20k / 40k security checks a month across accounts at $0.001. The newer Essentials plan prices by resource and is not modeled.
- VPC flow logs to S3: 5 / 10 / 40 GB a month at $0.25 per GB delivered.
- Log archive growth: 6.5 / 13 / 49 GB a month (CloudTrail, Config, flow logs, and Workspace audit logs at 0.05 GB per user), kept 12 months in S3 Standard with Object Lock (no extra Object Lock fee).
- Workspace audit collector: 5 minute schedule, Lambda and logs about $2.
- KMS: 8 customer managed keys at $1 each, 1M / 2M / 5M requests a month at $0.03 per 10k. Rotation fees not modeled.
- Interface endpoints at $0.01 per endpoint-AZ-hour ($7.30 a month): workload account 5 endpoints in 2 AZs, grc account 6 endpoints in 1 AZ (in the Fathom line). Endpoint data $0.01 per GB, assumed negligible.
- Fathom: [template](https://github.com/adversitydotdev/fathom/blob/main/deploy/aws/template.yaml) idle $26.26, plus ALB $23.73 and one LCU ($5.84), plus 6 grc endpoints ($43.80), plus $3 for logs and DNS. At 100 users the task goes to medium (+$8.51) and the database to `db.t4g.small` (+$11.68). Evidence S3 is 5 GB, then 20 GB.
- ITAR commercial remnant: GovCloud holds management, log archive, security, and workload accounts. Commercial keeps a management, log archive, and grc account for Fathom, at 40% of the commercial usage lines. This split is our assumption.
- Inspector (ECR image and Lambda scanning for 3.11.2): a few dollars a month at this scale (tens of images, a handful of functions), not broken out in the table; see [Inspector pricing](https://aws.amazon.com/inspector/pricing/).
- Free: Organizations, IAM Identity Center, IAM Roles Anywhere with an external CA trust anchor. A Private CA trust anchor adds $50 a month (short-lived mode) or $400 (general purpose).
- Not included: AWS Support plan, WAF, Macie, backups, SES, data transfer out, Route 53, domain, a SIEM, EDR and MDM, the model provider for Fathom, and any labor or assessor fees.

### GovCloud deltas (us-gov-west-1 vs us-east-1)

Config item $0.0036 vs $0.003, conformance evaluation $0.0012 vs $0.001, GuardDuty events $4.80 vs $4.00 per million, GuardDuty flow data $1.20 vs $1.00 per GB, Security Hub check $0.0012 vs $0.001, S3 $0.039 vs $0.023 per GB-month, VPC endpoint hour $0.0125 vs $0.01, KMS requests $0.04 vs $0.03 per 10k, vended logs to S3 $0.338 vs $0.25 per GB. Unchanged: KMS key $1, CloudTrail, Lambda requests, public IPv4 $0.005 per hour. GovCloud-priced lines run about 20 to 25% higher, and the split adds the remnant.

### Open points

- **NAT.** Fathom must reach Google APIs and the GovCloud endpoints over the internet, and neither has PrivateLink. Section 5 says no public task IPs, so the table includes one NAT gateway in the grc account: +$32.85 a month net of the dropped IPv4, plus $0.045 per GB processed.
- **Interface endpoints are the largest fixed line** ($117 a month in the table). Fewer endpoints or one AZ halves it; the workload account's real endpoint list is not designed yet.
- **CSE vendor.** An ITAR key service must be operated under ITAR rules; check where each partner operates and who has access before counting Flowcrypt as viable. Flowcrypt also publishes a second, package-based scheme (free up to 100 users with limits), and the two pages disagree. Prices are EUR, not converted.
- **Not sourced:** Google's own Enterprise Plus, Assured Controls, and Assured Controls Plus quotes; Thales, Virtru, Fortanix, Futurex, and Stormshield CSE pricing; real log and Config volumes.

### Sources (retrieved November 23, 2026)

- AWS Price List offer files, published about November 8, 2026: `https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/{AWSCloudTrail,AWSConfig,AmazonGuardDuty,AWSSecurityHub,awskms,AmazonVPC,AmazonCloudWatch,AmazonS3,AWSLambda,AWSCertificateManager}/current/index.json`, regions us-east-1 and us-gov-west-1.
- Fathom idle bill and add-on prices: [fathom README](https://github.com/adversitydotdev/fathom#estimated-monthly-cost), prices as of November 9, 2026.
- Workspace reseller list prices: [Hiview Solutions](https://hiviewsolutions.com/google-workspace-plans/), checked by them November 1, 2026. Federal promo: [Carahsoft](https://www.carahsoft.com/google/gsa-onegov/workspace).
- CSE partners and Flowcrypt tiers: [Flowcrypt Workspace Key Manager terms and pricing](https://flowcrypt.com/docs/technical/workspace-key-manager/usage/terms-and-pricing.html) (undated).
- Roles Anywhere trust anchors: [AWS docs](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/getting-started.html).
