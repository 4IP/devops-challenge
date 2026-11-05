include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "${get_repo_root()}/modules//sqs-queue"
}

dependency "alerts" {
  config_path = "../alerts"

  mock_outputs = {
    topic_arn = "arn:aws:sns:ap-southeast-3:111111111111:claims-alerts-prod"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  name                        = "claims-documents"
  visibility_timeout_seconds  = 300
  max_receive_count           = 5
  alarm_age_threshold_seconds = 900

  # Until 2026-10-14 this was empty: the oldest-message-age alarm fired 8 hours before anyone
  # noticed the claims-worker outage. Alarm and OK transitions now go to email + #claims-alerts.
  alarm_actions = [dependency.alerts.outputs.topic_arn]
}
