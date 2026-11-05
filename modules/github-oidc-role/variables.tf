variable "name" {
  description = "IAM role name."
  type        = string
}

variable "github_repository" {
  description = "owner/repo allowed to assume the role."
  type        = string
}

variable "subjects" {
  description = <<-EOT
    GitHub OIDC subject patterns allowed, without the repo prefix. Examples:
    "pull_request" (any PR), "ref:refs/heads/main" (pushes to main), "environment:prod"
    (jobs that passed the prod environment's protection rules).
  EOT
  type        = list(string)
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. One per account; set false for every role after the first."
  type        = bool
  default     = false
}

variable "oidc_provider_arn" {
  description = "Existing provider ARN when create_oidc_provider is false."
  type        = string
  default     = null
}

variable "managed_policy_arns" {
  description = "Managed policies to attach."
  type        = list(string)
  default     = []
}

variable "policy_statements" {
  description = "Inline policy statements."
  type = list(object({
    sid       = string
    effect    = string
    actions   = list(string)
    resources = list(string)
  }))
  default = []
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
