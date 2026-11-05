terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # aws_chatbot_slack_channel_configuration needs >= 5.65
      version = ">= 5.65, < 6.0"
    }
  }
}
