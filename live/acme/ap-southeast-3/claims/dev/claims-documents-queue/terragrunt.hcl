include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "${get_repo_root()}/modules//sqs-queue"
}

dependency "alerts" {
  config_path = "../alerts"

  mock_outputs = {
    topic_arn = "arn:aws:sns:ap-southeast-3:111111111111:claims-alerts-dev"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  name                        = "claims-documents-dev"
  visibility_timeout_seconds  = 300
  max_receive_count           = 5
  alarm_age_threshold_seconds = 3600

  alarm_actions = [dependency.alerts.outputs.topic_arn]
}
