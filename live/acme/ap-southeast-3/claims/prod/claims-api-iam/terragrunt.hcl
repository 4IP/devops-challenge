include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "${get_repo_root()}/modules//irsa-role"
}

dependency "eks" {
  config_path = "../../../platform/prod/eks"

  mock_outputs = {
    oidc_provider_arn = "arn:aws:iam::111111111111:oidc-provider/oidc.eks.ap-southeast-3.amazonaws.com/id/MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "documents" {
  config_path = "../claims-documents-bucket"

  mock_outputs = {
    bucket_arn  = "arn:aws:s3:::acme-claims-documents-prod"
    kms_key_arn = "arn:aws:kms:ap-southeast-3:111111111111:key/MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# The claims backend (claims-api, runs in the claims namespace on EKS — assumption, see
# docs/claims-documents.md). It signs upload URLs for the mobile app and moves finished uploads
# from tmp/ to claims/<claim-id>/. It never hands credentials to the app.
inputs = {
  name              = "claims-api-prod"
  oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  namespace         = "claims"
  service_account   = "claims-api"

  policy_statements = [
    {
      sid    = "Documents"
      effect = "Allow"
      actions = [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
      ]
      resources = [
        "${dependency.documents.outputs.bucket_arn}/tmp/*",
        "${dependency.documents.outputs.bucket_arn}/claims/*",
      ]
    },
    {
      sid       = "ListDocuments"
      effect    = "Allow"
      actions   = ["s3:ListBucket"]
      resources = [dependency.documents.outputs.bucket_arn]
    },
    {
      sid       = "DocumentsKey"
      effect    = "Allow"
      actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
      resources = [dependency.documents.outputs.kms_key_arn]
    },
  ]
}
