# A role humans (or other roles) assume for short-lived credentials, instead of an IAM user with
# long-lived access keys. Every AssumeRole call lands in CloudTrail with the caller's identity,
# which is what the regulator will ask for. Credentials expire; keys in a laptop script do not.

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = var.trusted_principal_arns
    }

    dynamic "condition" {
      for_each = var.require_mfa ? [1] : []
      content {
        test     = "Bool"
        variable = "aws:MultiFactorAuthPresent"
        values   = ["true"]
      }
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.name
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = var.max_session_duration

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
