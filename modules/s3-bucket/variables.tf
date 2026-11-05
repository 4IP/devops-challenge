variable "name" {
  description = "Bucket name."
  type        = string
}

variable "versioning" {
  description = "Enable object versioning."
  type        = bool
  default     = false
}

variable "force_destroy" {
  description = "Allow Terraform to delete the bucket even if it contains objects. Set false for anything holding customer data."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = <<-EOT
    KMS key for SSE-KMS. Leave null for SSE-S3 (AES256). Set to "create" to have the module create
    and manage a dedicated customer-managed key for this bucket (recommended for personal data:
    access to the key is a second, auditable gate on top of the bucket policy).
  EOT
  type        = string
  default     = null
}

variable "lifecycle_rules" {
  description = "Lifecycle rules by prefix. Every field except id/prefix is optional."
  type = list(object({
    id                                 = string
    prefix                             = string
    expiration_days                    = optional(number)
    noncurrent_version_expiration_days = optional(number)
    abort_incomplete_multipart_days    = optional(number)
  }))
  default = []
}

variable "logging_target_bucket" {
  description = "Bucket that receives S3 server access logs. Leave null to disable."
  type        = string
  default     = null
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
