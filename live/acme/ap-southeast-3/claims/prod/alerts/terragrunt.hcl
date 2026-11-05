include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "${get_repo_root()}/modules//alert-topic"
}

inputs = {
  name = "claims-alerts-prod"

  # Platform on-call + claims lead. Each address confirms the subscription once (SNS sends a link).
  email_endpoints = [
    "platform-oncall@acme-insure.example",
    "rina@acme-insure.example",
  ]

  # #claims-alerts. Placeholder IDs: the Slack workspace has to be authorized once in the
  # AWS Chatbot console (Chatbot > Slack > Configure), then copy the real team/channel IDs here.
  slack = {
    team_id    = "T0ACME"
    channel_id = "C0CLAIMSALERTS"
  }
}
