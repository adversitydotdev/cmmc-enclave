# First-boot seed for Fathom (#32): the rendered enclave bundle, staged in grc and restored
# by Fathom into its empty database. Contract with the wizard (#34):
#   1. the wizard renders ogrl/ (org, policy, procedure) and re-pins document digests
#   2. scripts/package-fathom-seed <rendered ogrl dir> <path>.tar.gz --library-ref <ogrl_library_ref>
#   3. fathom_seed_bundle_path = <path>.tar.gz
# Empty path: nothing is staged and Fathom starts unseeded (import by hand).
# Needs a fathom_ref whose template has SeedBundleUri (fathom branch seed-org-bundle).
# First apply with fathom_enable_services = false: the task role's read policy lands after
# the stack, and a task that boots before it starts unseeded (the next boot retries).

variable "fathom_seed_bundle_path" {
  description = "Path of the artifact from scripts/package-fathom-seed. Empty disables seeding."
  type        = string
  default     = ""
}

variable "ogrl_library_ref" {
  description = "ogrl-library commit pinned in the seed artifact. Keep equal to OGRL_LIBRARY_REF in .github/workflows/ogrl.yml."
  type        = string
  default     = "5c0987730e2af897d0071cd3826f1c3c4faf8926"
}

module "fathom_seed" {
  count  = var.fathom_seed_bundle_path == "" ? 0 : 1
  source = "../../modules/fathom_seed"
  providers = {
    aws = aws.grc
  }

  name_prefix     = var.name_prefix
  tier            = var.tier
  allowed_regions = var.allowed_regions
  tags            = var.tags

  kms_key_arn      = module.kms.kms_key_arns["grc"]
  bundle_path      = var.fathom_seed_bundle_path
  ogrl_library_ref = var.ogrl_library_ref
  fathom_stack_id  = module.fathom.stack_id
}

output "fathom_seed_bundle_uri" {
  description = "Seed artifact URI passed to Fathom, or empty when seeding is off."
  value       = try(module.fathom_seed[0].bundle_uri, "")
}
