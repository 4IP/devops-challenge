locals {
  oidc_issuer = replace(var.oidc_provider_arn, "/^.*oidc-provider\\//", "")

  # Kubernetes identities allowed to assume this role. Normally exactly one; additional names are
  # for renaming a service account without an outage (trust both, switch the workload, remove the
  # old one). Exposed as an output so what ends up in the trust policy is visible in plans and tests.
  trusted_subjects = [
    for sa in distinct(concat([var.service_account], var.additional_service_accounts)) :
    "system:serviceaccount:${var.namespace}:${sa}"
  ]
}

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = local.trusted_subjects
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.name
  assume_role_policy = data.aws_iam_policy_document.assume.json

  tags = var.tags
}

data "aws_iam_policy_document" "this" {
  dynamic "statement" {
    for_each = var.policy_statements

    content {
      sid       = statement.value.sid
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_role_policy" "this" {
  count = length(var.policy_statements) > 0 ? 1 : 0

  name   = var.name
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.this.json
}
