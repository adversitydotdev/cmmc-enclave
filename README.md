# cmmc-enclave

A baseline CMMC Level 2 enclave you can deploy yourself, split between Google Workspace and AWS, written in Terraform and documented in [OGRL](https://ogrl.adversity.dev).

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

## Tiers

| Tier | AWS | Google Workspace | For |
|---|---|---|---|
| Standard (default) | Commercial US East/West (FedRAMP Moderate) | Commercial edition on FedRAMP High services | CUI without export controlled data |
| ITAR | AWS GovCloud (US) (FedRAMP High, US citizen operated) | Enterprise Plus with Assured Controls Plus and client-side encryption | ITAR or EAR controlled technical data |

Details, sources, and the open decisions are in [docs/SCOPE.md](docs/SCOPE.md).

## License

Apache 2.0. See [LICENSE](LICENSE).
