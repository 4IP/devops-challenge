variable "name" {
  description = "IAM role name."
  type        = string
}

variable "trusted_principal_arns" {
  description = "IAM principals (users, roles, or an account root) allowed to assume the role."
  type        = list(string)
}

variable "require_mfa" {
  description = "Require an MFA-authenticated session to assume the role."
  type        = bool
  default     = true
}

variable "max_session_duration" {
  description = "Maximum session length in seconds (1h-12h)."
  type        = number
  default     = 3600
}

variable "policy_statements" {
  description = "Inline policy statements attached to the role."
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
