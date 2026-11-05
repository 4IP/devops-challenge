include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "${get_repo_root()}/modules//irsa-role"
}

dependency "eks" {
  config_path = "../../../platform/dev/eks"

  mock_outputs = {
    oidc_provider_arn = "arn:aws:iam::111111111111:oidc-provider/oidc.eks.ap-southeast-3.amazonaws.com/id/MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "queue" {
  config_path = "../claims-documents-queue"

  mock_outputs = {
    queue_arn = "arn:aws:sqs:ap-southeast-3:111111111111:claims-documents-dev"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "documents" {
  config_path = "../claims-documents-bucket"

  mock_outputs = {
    bucket_arn  = "arn:aws:s3:::acme-claims-documents-dev"
    kms_key_arn = "arn:aws:kms:ap-southeast-3:111111111111:key/MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  name              = "claims-worker-dev"
  oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  namespace         = "claims"
  # Must match serviceAccount.name in apps/acme-dev-cluster/values/claims-worker.yaml (CI checks).
  service_account = "claims-worker"

  policy_statements = [
    {
      sid    = "Queue"
      effect = "Allow"
      actions = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility",
        "sqs:GetQueueAttributes",
      ]
      resources = [dependency.queue.outputs.queue_arn]
    },
    {
      # OCR reads submitted documents only. It never writes to the bucket and cannot see tmp/.
      sid       = "ReadDocuments"
      effect    = "Allow"
      actions   = ["s3:GetObject"]
      resources = ["${dependency.documents.outputs.bucket_arn}/claims/*"]
    },
    {
      sid       = "DocumentsKey"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = [dependency.documents.outputs.kms_key_arn]
    },
  ]
}
