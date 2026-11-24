output "bundle_uri" {
  description = "s3:// URI of the seed artifact. Pass to the fathom module as seed_bundle_uri (FATHOM_SEED_BUNDLE_URI)."
  value       = "s3://${aws_s3_bucket.seed.bucket}/${aws_s3_object.bundle.key}"
}

output "bucket_name" {
  description = "Seed bucket."
  value       = aws_s3_bucket.seed.bucket
}

output "bundle_sha256" {
  description = "sha256 of the uploaded artifact."
  value       = filesha256(var.bundle_path)
}

output "ogrl_library_ref" {
  description = "ogrl-library commit the artifact is declared to pin."
  value       = var.ogrl_library_ref
}
