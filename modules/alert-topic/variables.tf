variable "name" {
  description = "SNS topic name. Also used as a prefix for the Chatbot IAM role."
  type        = string
}

variable "email_endpoints" {
  description = "Email addresses subscribed to the topic. Each one has to confirm the subscription once."
  type        = list(string)
  default     = []
}

variable "slack" {
  description = <<-EOT
    Optional AWS Chatbot (Slack) delivery. The Slack workspace must be authorized once in the
    AWS Chatbot console before this can be applied; team_id and channel_id come from Slack.
  EOT
  type = object({
    team_id    = string
    channel_id = string
  })
  default = null
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
