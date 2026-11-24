# cmmc-enclave

A baseline enclave for the CMMC Level 2 (NIST SP 800-171 Rev 2) requirements that you can deploy yourself, split between Google Workspace and AWS, written in Terraform and documented in [OGRL](https://ogrl.adversity.dev).

**Status: scoping.** Nothing here deploys yet. The plan lives in [docs/SCOPE.md](docs/SCOPE.md) and the work is tracked in the issues.

## The idea

Most small defense contractors handling CUI end up with the same shape of environment: email and documents in a FedRAMP authorized SaaS, a small AWS footprint, and a pile of spreadsheets for the SSP. This repo aims to make that shape repeatable:

- **Google Workspace** for people, email, files, and meetings, configured to the vendor's CMMC Level 2 guidance.
- **AWS** for the enclave's infrastructure, logging, key management, and for hosting [Fathom](https://github.com/adversitydotdev/fathom), the self-hosted OGRL app.
- **Terraform** for everything that can be automated, plus a short manual runbook for the Google Workspace settings no API can set yet.
- **OGRL** for the documentation. Every control the enclave implements ships as OGRL objects (system, components, implementations, tests) bound to the `baseline--ogrl-cmmc-l2` baseline in [ogrl-library](https://github.com/adversitydotdev/ogrl-library). Fathom comes up already loaded with them, so the SSP, the shared responsibility matrix, and the POA&M are live from the first login.
- **A local wizard** that runs in your browser, asks about your company (users, domain, CUI types, ITAR or not), and writes the Terraform variables and OGRL parameters. Nothing leaves your machine.

## What it is not

- Not a certification. It's a baseline that covers the technical controls AWS and Google Workspace can carry, and it tells you plainly what's still on you.
- Not an endpoint solution. Laptops, phones, MDM, and EDR are out of scope here and listed as a dependency.
- Not legal advice about CUI, ITAR, or your contracts.

## Regulatory status

Last checked: 2026-11-23. This moves; check the sources.

- DoW suspended the Phase 2 move to C3PAO Level 2 assessments (was due 2026-11-10) on 2026-07-13. Phase 1 self assessments and DFARS 252.204-7012 still apply. ([DoW CIO memo 26-P-1023](https://dowcio.war.gov/Portals/0/Documents/Library/ImplementingSuspensionCMMC-PhaseII.pdf), [DoW CIO](https://dowcio.war.gov/CMMC/About/); both returned 403 to us, so not read directly.)
- CMMC Level 2 is NIST SP 800-171 Rev 2 ([32 CFR 170.14](https://www.ecfr.gov/current/title-32/subtitle-A/chapter-I/subchapter-G/part-170)). Rev 3 is proposed only for a separate FAR CUI rule ([FAR overhaul NPRM, 2026-06-23](https://www.federalregister.gov/documents/2026/06/23/2026-12559/federal-acquisition-regulation-revolutionary-federal-acquisition-regulation-overhaul-parts-1-2-4-33)).
- The reform task force report was due to DoW CIO in September. We found no public release.
- Nothing here is a certification or a promise of one. Details in [docs/SCOPE.md](docs/SCOPE.md#2-where-cmmc-stands-verified-november-23-2026).

## Tiers

| Tier | AWS | Google Workspace | For |
|---|---|---|---|
| Standard (default) | Commercial US East/West (FedRAMP Moderate) | Enterprise Plus with Assured Controls Plus, FedRAMP High services only | CUI without export controlled data |
| ITAR | AWS GovCloud (US) (FedRAMP High, US citizen operated) | Enterprise Plus with Assured Controls Plus and client-side encryption | ITAR or EAR controlled technical data |

Details, sources, and the open decisions are in [docs/SCOPE.md](docs/SCOPE.md).

## License

Apache 2.0. See [LICENSE](LICENSE).
