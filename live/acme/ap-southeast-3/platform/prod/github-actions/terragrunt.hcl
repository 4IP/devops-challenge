include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "${get_repo_root()}/modules//github-oidc-role"
}

# First step of docs/design-deploy.md: a read-only role GitHub Actions assumes to run
# `terragrunt plan` on pull requests. No access keys anywhere. The apply role (stage 2) is a
# separate stack with `subjects = ["environment:prod"]` so only jobs that passed the prod
# environment's required-reviewer gate can assume it.
inputs = {
  name                 = "gha-plan"
  github_repository    = "acme-insure/devops-challenge" # replace with the real org/repo
  subjects             = ["pull_request"]
  create_oidc_provider = true

  managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]

  policy_statements = [
    {
      # Plan reads state and takes the lock; it never writes state.
      sid       = "StateRead"
      effect    = "Allow"
      actions   = ["s3:GetObject", "s3:ListBucket"]
      resources = ["arn:aws:s3:::acme-terraform-state-111111111111", "arn:aws:s3:::acme-terraform-state-111111111111/*"]
    },
    {
      sid       = "StateLock"
      effect    = "Allow"
      actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
      resources = ["arn:aws:dynamodb:ap-southeast-3:111111111111:table/acme-terraform-locks-111111111111"]
    },
  ]
}
