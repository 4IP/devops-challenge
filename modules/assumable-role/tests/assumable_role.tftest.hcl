mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111111111111:role/test-role"
    }
  }
}

variables {
  name                   = "test-role"
  trusted_principal_arns = ["arn:aws:iam::111111111111:user/dimas"]
}

run "defaults_are_short_sessions_with_mfa" {
  command = apply

  assert {
    condition     = aws_iam_role.this.max_session_duration == 3600
    error_message = "Sessions should default to one hour"
  }

  assert {
    condition     = length(aws_iam_role_policy.this) == 0
    error_message = "No inline policy without statements"
  }
}

run "policy_is_attached_when_statements_given" {
  command = apply

  variables {
    policy_statements = [{
      sid       = "Upload"
      effect    = "Allow"
      actions   = ["s3:PutObject"]
      resources = ["arn:aws:s3:::test-bucket/claims/*"]
    }]
  }

  assert {
    condition     = length(aws_iam_role_policy.this) == 1
    error_message = "Inline policy should be created"
  }
}
