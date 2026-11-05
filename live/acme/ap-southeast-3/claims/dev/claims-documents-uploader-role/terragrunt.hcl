include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "${get_repo_root()}/modules//assumable-role"
}

dependency "documents" {
  config_path = "../claims-documents-bucket"

  mock_outputs = {
    bucket_arn  = "arn:aws:s3:::acme-claims-documents-dev"
    kms_key_arn = "arn:aws:kms:ap-southeast-3:111111111111:key/MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# For the claims team's laptop scripts during dev testing. Assumed with MFA for one hour:
#   aws sts assume-role --role-arn <role_arn> --role-session-name dimas --serial-number <mfa-arn> --token-code 123456
# Dev only, on purpose. Production documents are real customer data and are not read from laptops.
inputs = {
  name = "claims-documents-uploader-dev"

  # The engineers who asked. Replace with an SSO permission set once we have IAM Identity Center.
  trusted_principal_arns = [
    "arn:aws:iam::111111111111:user/dimas",
    "arn:aws:iam::111111111111:user/rina",
  ]
  require_mfa          = true
  max_session_duration = 3600

  policy_statements = [
    {
      sid       = "Upload"
      effect    = "Allow"
      actions   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
      resources = [dependency.documents.outputs.bucket_arn, "${dependency.documents.outputs.bucket_arn}/*"]
    },
    {
      sid       = "DocumentsKey"
      effect    = "Allow"
      actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
      resources = [dependency.documents.outputs.kms_key_arn]
    },
  ]
}
