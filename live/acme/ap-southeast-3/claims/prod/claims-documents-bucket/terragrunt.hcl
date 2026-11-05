include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "${get_repo_root()}/modules//s3-bucket"
}

# Customer claim documents: KTP photos, hospital receipts, medical records. Personal data under
# UU PDP and OJK rules. See docs/claims-documents.md for the layout, access model and open
# questions on retention.
inputs = {
  name          = "acme-claims-documents-prod"
  versioning    = true
  kms_key_arn   = "create"
  force_destroy = false

  lifecycle_rules = [
    {
      # Uploads land here first (presigned PUT). Backend moves them under claims/<claim-id>/ once the
      # claim is submitted; whatever is left is an abandoned upload.
      id                              = "abandoned-uploads"
      prefix                          = "tmp/"
      expiration_days                 = 7
      abort_incomplete_multipart_days = 7
    },
    {
      # No expiration on claims/: product has not defined "as long as needed for the claim" yet
      # (see docs/claims-documents.md). Old versions of overwritten objects are not needed.
      id                                 = "claims"
      prefix                             = "claims/"
      noncurrent_version_expiration_days = 30
      abort_incomplete_multipart_days    = 7
    },
  ]

  tags = {
    DataClassification = "personal-sensitive"
    Owner              = "claims"
  }
}
