mock_provider "aws" {
  # The mock provider fills computed attributes with random strings, but resources that consume
  # them still validate the format (ARN, JSON). Give them realistic values.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111111111111:role/claims-worker-test"
    }
  }
}

variables {
  name              = "claims-worker-test"
  oidc_provider_arn = "arn:aws:iam::111111111111:oidc-provider/oidc.eks.ap-southeast-3.amazonaws.com/id/MOCK"
  namespace         = "claims"
  service_account   = "claims-worker"
}

run "trust_is_bound_to_exactly_one_service_account" {
  command = apply

  assert {
    condition     = output.trusted_subjects == ["system:serviceaccount:claims:claims-worker"]
    error_message = "Trust policy subject must be system:serviceaccount:<namespace>:<service_account>"
  }

  assert {
    condition     = aws_iam_role.this.name == "claims-worker-test"
    error_message = "Role should use the given name"
  }
}

run "rename_window_trusts_old_and_new_name" {
  command = apply

  variables {
    additional_service_accounts = ["claims-worker-sa"]
  }

  assert {
    condition = output.trusted_subjects == [
      "system:serviceaccount:claims:claims-worker",
      "system:serviceaccount:claims:claims-worker-sa",
    ]
    error_message = "Additional service accounts should be added to the trust policy, old name first"
  }
}

run "no_inline_policy_without_statements" {
  command = apply

  assert {
    condition     = length(aws_iam_role_policy.this) == 0
    error_message = "No inline policy should be created when policy_statements is empty"
  }
}
