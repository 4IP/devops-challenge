mock_provider "aws" {
  # The mock provider fills computed attributes with random strings, but resources that consume
  # them still validate the format (ARN, JSON). Give them realistic values.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:ap-southeast-3:111111111111:test-alerts"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111111111111:role/test-alerts-chatbot"
    }
  }
}

variables {
  name            = "test-alerts"
  email_endpoints = ["oncall@example.com", "lead@example.com"]
}

run "creates_topic_and_email_subscriptions" {
  command = apply

  assert {
    condition     = aws_sns_topic.this.name == "test-alerts"
    error_message = "Topic should use the given name"
  }

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 2
    error_message = "One email subscription per endpoint"
  }

  assert {
    condition     = length(aws_chatbot_slack_channel_configuration.this) == 0
    error_message = "No Slack configuration when var.slack is null"
  }
}

run "slack_is_optional_but_wired_when_set" {
  command = apply

  variables {
    slack = {
      team_id    = "T0ACME"
      channel_id = "C0CLAIMSALERTS"
    }
  }

  assert {
    condition     = length(aws_chatbot_slack_channel_configuration.this) == 1
    error_message = "Slack configuration should be created when var.slack is set"
  }

  assert {
    condition     = aws_chatbot_slack_channel_configuration.this[0].slack_channel_id == "C0CLAIMSALERTS"
    error_message = "Slack channel id should be passed through"
  }
}
