include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "${get_repo_root()}/modules//alert-topic"
}

inputs = {
  name = "claims-alerts-dev"

  email_endpoints = [
    "platform-oncall@acme-insure.example",
  ]

  # Dev alarms stay out of Slack on purpose: keep #claims-alerts for things that need a human now.
  slack = null
}
