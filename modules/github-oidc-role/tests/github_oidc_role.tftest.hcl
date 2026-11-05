mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111111111111:role/gha-test"
    }
  }

  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
    }
  }
}

variables {
  name                 = "gha-test"
  github_repository    = "acme-insure/devops-challenge"
  subjects             = ["pull_request", "environment:prod"]
  create_oidc_provider = true
}

run "subjects_are_scoped_to_the_repo" {
  command = apply

  assert {
    condition = output.trusted_subjects == [
      "repo:acme-insure/devops-challenge:pull_request",
      "repo:acme-insure/devops-challenge:environment:prod",
    ]
    error_message = "Every subject must be prefixed with repo:<owner/repo>:"
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 1
    error_message = "Provider should be created when requested"
  }
}

run "reuses_existing_provider" {
  command = apply

  variables {
    create_oidc_provider = false
    oidc_provider_arn    = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
    managed_policy_arns  = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0
    error_message = "No provider when create_oidc_provider is false"
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.managed) == 1
    error_message = "Managed policy should be attached"
  }
}
