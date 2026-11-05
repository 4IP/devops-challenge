# GitHub Actions → AWS without access keys. Each job gets a short-lived token whose subject names
# the repo, the event and the branch/environment; the trust policy pins which of those may assume
# the role. Every assumption lands in CloudTrail with that subject, which is the "who changed
# prod" answer for the regulator.

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.oidc_provider_arn
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # GitHub's token signing certificates; AWS validates against its own trust store since 2023,
  # but the API still requires a thumbprint value.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = var.tags
}

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for s in var.subjects : "repo:${var.github_repository}:${s}"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.name
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

data "aws_iam_policy_document" "inline" {
  count = length(var.policy_statements) > 0 ? 1 : 0

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

resource "aws_iam_role_policy" "inline" {
  count = length(var.policy_statements) > 0 ? 1 : 0

  name   = var.name
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.inline[0].json
}
